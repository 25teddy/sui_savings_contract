module savings::contract {
    use sui::balance::{Self, Balance};
    use sui::coin::{Self, Coin};
    use sui::object::{Self, ID, UID};
    use sui::sui::SUI;
    use sui::clock::{Clock, timestamp_ms};
    use sui::transfer;
    use sui::tx_context::{Self, TxContext, sender};
    use sui::table::{Self, Table};

    // Errors
    const EWrongPlan: u64 = 0;
    const EPlanBalanceNotEnough: u64 = 1;
    const EAlreadyVoted: u64 = 2;
    const EVotingEnded: u64 = 3;
    const EVotingNotEnded: u64 = 4;

    // Plan data
    struct Plan has key {
        id: UID,
        lockedFunds: u64,
        availableFunds: u64,
        members: u32,
        quorum: u64,
        voteTime: u64,
    }

    // Saving data
    struct Saving has key, store {
        id: UID,
        planId: ID,
        amount: u64,
        recipient: address,
        votes: u64,
        voters: Table<address, bool>,
        ends: u64,
        executed: bool,
        ended: bool,
    }

    // AccountCap for plan members
    struct Account has key, store {
        id: UID,
        planId: ID,
        balance: Balance<SUI>,
        shares: u64,
        locked: u64
    }

    fun create_plan(ctx: &mut TxContext) {
        // set quorum to 70;
        let quorum: u64 = 70;

        // set voteTime to 100 ticks;
        let voteTime: u64 = 100;

        // populate the plan
        let plan = Plan {
            id: object::new(ctx),
            lockedFunds: 0,
            availableFunds: 0,
            members: 0,
            quorum,
            voteTime,
        };

        // allow everyone to be able to access the plan
        transfer::share_object(plan);
    }

    fun init(ctx: &mut TxContext) {
        create_plan(ctx);
    }

    public fun join_plan(plan: &mut Plan, amount: Coin<SUI>, ctx: &mut TxContext): Account {
        // get the plan id
        let planId = object::uid_to_inner(&plan.id);
        // get shares amount
        let shares = coin::value(&amount);
        // next update the available shares
        let prevAvailableFunds = &plan.availableFunds;
        plan.availableFunds = *prevAvailableFunds + shares;
        // increase the member count
        let oldCount = &plan.members;
        plan.members = *oldCount + 1;
        // create Account object 
        let account = Account {
            id: object::new(ctx),
            balance: balance::zero(),
            planId,
            shares,
            locked: 0
        };
        // add the amount to the plan total shares
        let coin_balance = coin::into_balance(amount);
        balance::join(&mut account.balance, coin_balance);

        account
    }

    public fun increase_shares(plan: &mut Plan, acc: &mut Account, amount: Coin<SUI>, _ctx: &mut TxContext) {
        // check that user passes in the right objects
        assert!(&acc.planId == object::uid_as_inner(&plan.id), EWrongPlan);
        // get shares amount
        let shares = coin::value(&amount);
        // add the amount to the plan total shares
        let coin_balance = coin::into_balance(amount);
        balance::join(&mut acc.balance, coin_balance);
        // next update the available shares
        let prevAvailableFunds = &plan.availableFunds;
        plan.availableFunds = *prevAvailableFunds + shares;
        // get the old shares
        let prevShares = &acc.shares;
        acc.shares = *prevShares + shares;
    }

    public fun redeem_shares(plan: &mut Plan, acc: &mut Account, amount: u64, ctx: &mut TxContext): Coin<SUI> {
        // check that user passes in the right objects
        assert!(&acc.planId == object::uid_as_inner(&plan.id), EWrongPlan);
        // next update the available shares
        let prevAvailableFunds = &plan.availableFunds;
        plan.availableFunds = *prevAvailableFunds - amount;
        // get the old shares
        let prevShares = &acc.shares;
        acc.shares = *prevShares - amount;
        // wrap balance with coin
        let coin_ = coin::take(&mut acc.balance, amount, ctx);
        coin_
    }

    public fun create_saving(
        plan: &mut Plan,
        acc: &mut Account,
        c: &Clock,
        amount: u64,
        recipient: address,
        ctx: &mut TxContext
    ) {
        // check that user passes in the right objects
        assert!(&acc.planId == object::uid_as_inner(&plan.id), EWrongPlan);
        // check that there are available shares to complete the transaction
        assert!(acc.shares >= amount, EPlanBalanceNotEnough);
        // get the plan id
        let planId = object::uid_to_inner(&plan.id);
        // get time
        let ends = timestamp_ms(c) + plan.voteTime;
        // generate saving
        let saving = Saving {
            id: object::new(ctx),
            planId,
            amount,
            recipient,
            votes: 0,
            voters: table::new(ctx),
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
        // locked the funds from account object. 
        acc.locked = acc.locked + amount;
    }

    public fun vote(
        plan: &mut Plan,
        acc: &mut Account,
        saving: &mut Saving,
        c: &Clock,
        ctx: &mut TxContext
    ) {
        // check that user passes in the right objects
        assert!(&acc.planId == object::uid_as_inner(&plan.id), EWrongPlan);
        assert!(&saving.planId == object::uid_as_inner(&plan.id), EWrongPlan);

        // check that time for voting has not elapsed
        assert!(saving.ends > timestamp_ms(c), EVotingEnded);

        // check that user has not voted;
        assert!(!table::contains(&saving.voters, sender(ctx)), EAlreadyVoted);

        // update saving votes
        let prevVotes = &saving.votes;
        saving.votes = *prevVotes + acc.shares;

        table::add(&mut saving.voters, tx_context::sender(ctx), true);
    }

    public fun execute_saving(
        plan: &mut Plan,
        acc: &mut Account,
        saving: &mut Saving,
        c: &Clock,
        ctx: &mut TxContext
    ): (bool, Coin<SUI>) {
        // check that user passes in the right objects
        assert!(&acc.planId == object::uid_as_inner(&plan.id), EWrongPlan);
        assert!(&saving.planId == object::uid_as_inner(&plan.id), EWrongPlan);

        // check that time for voting has elapsed
        assert!(saving.ends < timestamp_ms(c), EVotingNotEnded);

        // calculate voting result
        let amountTotalShares = plan.availableFunds;
        let result = (saving.votes / amountTotalShares) * 100;

        // set plan as ended
        saving.ended = true;

        // unlock funds
        plan.lockedFunds = plan.lockedFunds - saving.amount;
        acc.locked = acc.locked - saving.amount;

        if (result >= plan.quorum) {
            // set saving as executed
            saving.executed = true;

            // get payment coin
            let payment = coin::take(&mut acc.balance, saving.amount, ctx);

            // return result
            (true, payment)
        } else {
            // release funds back to available funds
            plan.availableFunds = plan.availableFunds + saving.amount;

            // create empty coin
            let nullCoin = coin::from_balance(balance::zero(), ctx);

            // return result
            (false, nullCoin)
        }
    }

    public fun witdraw(     
        plan: &mut Plan,
        acc: &mut Account,
        saving: &mut Saving,
        amount: u64,
        ctx: &mut TxContext
    ) : Coin<SUI> {
        assert!(&acc.planId == object::uid_as_inner(&plan.id), EWrongPlan);
        assert!((balance::value(&acc.balance) - (acc.locked + amount) > 0), EPlanBalanceNotEnough);
        let prevAvailableFunds = &plan.availableFunds;
        plan.availableFunds = *prevAvailableFunds - amount;
        // get the old shares
        let prevShares = acc.shares;
        acc.shares = prevShares - amount;
        acc.locked = acc.locked - amount;
        let coin_ = coin::take(&mut acc.balance, amount, ctx);
        coin_
    }

    public fun get_account_shares(acc: &Account): u64 {
        acc.shares
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
