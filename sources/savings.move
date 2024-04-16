module savings_plan::contract {
    use sui::balance::{Self as BalanceModule, Balance};
    use sui::coin::{Self as CoinModule, Coin};
    use sui::object::{Self as ObjectModule, ID, UID};
    use sui::sui::SUI;
    use sui::clock::{Self as ClockModule, Clock};
    use sui::transfer;
    use sui::tx_context::{Self as TxContextModule, TxContext};
    use std::vector;
    use sui::random::random;

    // Errors
    const EWrongPlan: u64 = 9;
    const EPlanBalanceNotEnough: u64 = 10;
    const EAccountSharesNotSufficient: u64 = 11;
    const EAlreadyVoted: u64 = 12;
    const EVotingEnded: u64 = 13;
    const EVotingNotEnded: u64 = 14;
    const EInsufficientBalanceForKYC: u64 = 15;

    // Plan data
    struct Plan has key {
        id: UID,
        totalShares: Balance<SUI>,
        lockedFunds: u64,
        availableFunds: u64,
        members: u32,
        quorum: u64,
        voteTime: u64,
        minBalanceForVoting: u64,
    }

    // Saving data
    struct Saving has key, store {
        id: UID,
        planId: ID,
        amount: u64,
        recipient: address,
        votes: u64,
        voters: vector<address>,
        ends: u64,
        executed: bool,
        ended: bool,
    }

    // AccountCap for plan members
    struct AccountCap has key, store {
        id: UID,
        planId: ID,
        shares: u64
    }

    fun create_plan(ctx: &mut TxContext, min_balance_for_voting: u64) {
        // set quorum to 70;
        let quorum: u64 = 70;

        // set voteTime to 100 ticks;
        let voteTime: u64 = 100;

        // populate the plan
        let plan = Plan {
            id: ObjectModule::new(ctx),
            totalShares: BalanceModule::zero(),
            lockedFunds: 0,
            availableFunds: 0,
            members: 0,
            quorum,
            voteTime,
            minBalanceForVoting,
        };

        // allow everyone to be able to access the plan
        transfer::share_object(plan);
    }

    fun init(ctx: &mut TxContext) {
        create_plan(ctx, 1000); // Set a default minimum balance requirement for voting
    }

    public fun join_plan(plan: &mut Plan, amount: Coin<SUI>, ctx: &mut TxContext): AccountCap {
        // get the plan id
        let planId = ObjectModule::uid_to_inner(&plan.id);

        // get shares amount
        let shares = CoinModule::value(&amount);

        // add the amount to the plan total shares
        let coin_balance = CoinModule::into_balance(amount);
        BalanceModule::join(&mut plan.totalShares, coin_balance);

        // next update the available shares
        let prevAvailableFunds = &plan.availableFunds;
        plan.availableFunds = *prevAvailableFunds + shares;

        // increase the member count
        let oldCount = &plan.members;
        plan.members = *oldCount + 1;

        let accountCap = AccountCap {
            id: ObjectModule::new(ctx),
            planId,
            shares
        };

        accountCap
    }

    public fun increase_shares(plan: &mut Plan, accountCap: &mut AccountCap, amount: Coin<SUI>, _ctx: &mut TxContext) {
        // check that user passes in the right objects
        assert!(&accountCap.planId == ObjectModule::uid_as_inner(&plan.id), EWrongPlan);

        // get shares amount
        let shares = CoinModule::value(&amount);

        // add the amount to the plan total shares
        let coin_balance = CoinModule::into_balance(amount);
        BalanceModule::join(&mut plan.totalShares, coin_balance);

        // next update the available shares
        let prevAvailableFunds = &plan.availableFunds;
        plan.availableFunds = *prevAvailableFunds + shares;

        // get the old shares
        let prevShares = &accountCap.shares;
        accountCap.shares = *prevShares + shares;
    }

    public fun redeem_shares(plan: &mut Plan, accountCap: &mut AccountCap, amount: u64, ctx: &mut TxContext): Coin<SUI> {
        // check that user passes in the right objects
        assert!(&accountCap.planId == ObjectModule::uid_as_inner(&plan.id), EWrongPlan);

        // check that user has enough shares
        assert!(accountCap.shares >= amount, EAccountSharesNotSufficient);

        // check that there are available shares to complete the transaction
        assert!(plan.availableFunds >= amount, EPlanBalanceNotEnough);

        // next update the available shares
        let prevAvailableFunds = &plan.availableFunds;
        plan.availableFunds = *prevAvailableFunds - amount;

        // get the old shares
        let prevShares = &accountCap.shares;
        accountCap.shares = *prevShares - amount;

        // wrap balance with coin
        let redeemedShares = CoinModule::take(&mut plan.totalShares, amount, ctx);
        redeemedShares
    }

    public fun create_saving(
        plan: &mut Plan,
        accountCap: &mut AccountCap,
        amount: u64,
        recipient: address,
        clock: &Clock,
        ctx: &mut TxContext
    ) {
        // check that user passes in the right objects
        assert!(&accountCap.planId == ObjectModule::uid_as_inner(&plan.id), EWrongPlan);

        // check that there are available shares to complete the transaction
        assert!(plan.availableFunds >= amount, EPlanBalanceNotEnough);

        // check if the user has the minimum balance required for voting
        assert!(accountCap.shares >= plan.minBalanceForVoting, EInsufficientBalanceForKYC);

        // get the plan id
        let planId = ObjectModule::uid_to_inner(&plan.id);

        // get time
        let ends = ClockModule::timestamp_ms(clock) + plan.voteTime;

        // generate saving
        let saving = Saving {
            id: ObjectModule::new(ctx),
            planId,
            amount,
            recipient,
            votes: 0,
            voters: vector::empty(),
            ends,
            executed: false,
            ended: false,
        };

        transfer::share_object(saving);

        // next lock funds
        let prevAvailableFunds = &plan.availableFunds;
        plan.availableFunds = *prevAvailableFunds - amount;

        let prevLockedFunds = &plan.lockedFunds;
        plan.lockedFunds = *prevLockedFunds + amount;
    }

    public fun vote_saving(
        plan: &mut Plan,
        accountCap: &mut AccountCap,
        saving: &mut Saving,
        clock: &Clock,
        ctx: &mut TxContext
    ) {
        // check that user passes in the right objects
        assert!(&accountCap.planId == ObjectModule::uid_as_inner(&plan.id), EWrongPlan);
        assert!(&saving.planId == ObjectModule::uid_as_inner(&plan.id), EWrongPlan);

        // check that time for voting has not elapsed
        assert!(saving.ends > ClockModule::timestamp_ms(clock), EVotingEnded);

        // check that user has not voted;
        assert!(!vector::contains(&saving.voters, &TxContextModule::sender(ctx)), EAlreadyVoted);

        // update saving votes
        let prevVotes = &saving.votes;
        saving.votes = *prevVotes + accountCap.shares;

        vector::push_back(&mut saving.voters, TxContextModule::sender(ctx));
    }

    public fun execute_saving(
        plan: &mut Plan,
        accountCap: &mut AccountCap,
        saving: &mut Saving,
        clock: &Clock,
        ctx: &mut TxContext
    ): (bool, Coin<SUI>) {
        // check that user passes in the right objects
        assert!(&accountCap.planId == ObjectModule::uid_as_inner(&plan.id), EWrongPlan);
        assert!(&saving.planId == ObjectModule::uid_as_inner(&plan.id), EWrongPlan);

        // check that time for voting has elapsed
        assert!(saving.ends < ClockModule::timestamp_ms(clock), EVotingNotEnded);

        // calculate voting result
        let amountTotalShares = BalanceModule::value(&plan.totalShares);
        let result = (saving.votes / amountTotalShares) * 100;

        // set plan as ended
        saving.ended = true;

        // unlock funds
        plan.lockedFunds = plan.lockedFunds - saving.amount;

        if result >= plan.quorum {
            // set saving as executed
            saving.executed = true;

            // get payment coin
            let payment = CoinModule::take(&mut plan.totalShares, saving.amount, ctx);

            // return result
            (true, payment)
        } else {
            // release funds back to available funds
            plan.availableFunds = plan.availableFunds + saving.amount;

            // create empty coin
            let nullCoin = CoinModule::from_balance(BalanceModule::zero(), ctx);

            // return result
            (false, nullCoin)
        }
    }

    public fun get_account_shares(accountCap: &AccountCap): u64 {
        accountCap.shares
    }

    public fun get_plan_total_shares(plan: &Plan): u64 {
        BalanceModule::value(&plan.totalShares)
    }

    public fun get_plan_locked_funds(plan: &Plan): u64 {
        plan.lockedFunds
    }

    public fun get_plan_available_funds(plan: &Plan): u64 {
        plan.availableFunds
    }

    public fun get_saving_votes(saving: &Saving): u64 {
        saving.votes
    }
}
