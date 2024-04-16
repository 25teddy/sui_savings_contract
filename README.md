### Savings Plan Smart Contract

This is a smart contract written in Move language for managing a savings plan. The contract allows users to join a savings plan, increase their shares, redeem shares, create savings proposals, vote on proposals, and execute proposals based on community voting.

#### Setup

Before using the smart contract, ensure you have the following prerequisites installed:

- Ubuntu/Debian/WSL2(Ubuntu):
  ```
  sudo apt update
  sudo apt install curl git-all cmake gcc libssl-dev pkg-config libclang-dev libpq-dev build-essential -y
  ```
- MacOS (using Homebrew):
  ```
  brew install curl cmake git libpq
  ```
- Install Rust and Cargo:
  ```
  curl https://sh.rustup.rs -sSf | sh
  ```
- Install SUI:
  - Download pre-built binaries (recommended for GitHub Codespaces):
    ```
    ./download-sui-binaries.sh "v1.18.0" "devnet" "ubuntu-x86_64"
    ```
  - Or build from source:
    ```
    cargo install --locked --git https://github.com/MystenLabs/sui.git --branch devnet sui
    ```
- Install dev tools (optional, not required for GitHub Codespaces):
  ```
  cargo install --git https://github.com/move-language/move move-analyzer --branch sui-move --features "address32"
  ```
- Configure Connectivity:
  - Run a local network:
    ```
    RUST_LOG="off,sui_node=info" sui-test-validator
    ```
  - Configure connectivity to a local node:
    ```
    sui client active-address
    ```
    Follow the prompts and provide the full node URL (e.g., http://127.0.0.1:9000) and a name for the configuration (e.g., localnet).
- Create Addresses:
  ```
  sui client new-address ed25519
  ```
- Get Localnet SUI Tokens:
  - Run the HTTP request to mint SUI tokens to the active address:
    ```
    curl --location --request POST 'http://127.0.0.1:9123/gas' --header 'Content-Type: application/json' \
    --data-raw '{
        "FixedAmountRequest": {
            "recipient": "<ADDRESS>"
        }
    }'
    ```
    Replace `<ADDRESS>` with the active address obtained from `sui client active-address`.

#### Build and Publish a Smart Contract

- Build the package:
  ```
  sui move build
  ```
- Publish the package:
  ```
  sui client publish --gas-budget 100000000 --skip validation verification
  ```

#### Functions

1. `create_plan(ctx: &mut TxContext)`
   - Initializes a new savings plan.
2. `init(ctx: &mut TxContext)`
   - Initializes the contract by creating a savings plan.
3. `join_plan(plan: &mut Plan, amount: Coin<SUI>, ctx: &mut TxContext) -> AccountCap`
   - Allows a user to join the savings plan by contributing a specified amount of coins.
4. `increase_shares(plan: &mut Plan, accountCap: &mut AccountCap, amount: Coin<SUI>, _ctx: &mut TxContext)`
   - Increases the shares of a user in the savings plan by adding more coins.
5. `redeem_shares(plan: &mut Plan, accountCap: &mut AccountCap, amount: u64, ctx: &mut TxContext) -> Coin<SUI>`
   - Allows a user to redeem a specified amount of shares from the savings plan and receive coins in return.
6. `create_saving(plan: &mut Plan, accountCap: &mut AccountCap, amount: u64, recipient: address, clock: &Clock, ctx: &mut TxContext)`
   - Creates a new savings proposal within the plan, specifying the amount, recipient, and duration of the proposal.
7. `vote_saving(plan: &mut Plan, accountCap: &mut AccountCap, saving: &mut Saving, clock: &Clock, ctx: &mut TxContext)`
   - Allows a user to vote on a savings proposal within the plan.
8. `execute_saving(plan: &mut Plan, accountCap: &mut AccountCap, saving: &mut Saving, clock: &Clock, ctx: &mut TxContext) -> (bool, Coin<SUI>)`
   - Executes a savings proposal if it has received sufficient votes, distributing funds accordingly.
9. `get_account_shares(accountCap: &AccountCap) -> u64`
   - Retrieves the shares of a user in the savings plan.
10. `get_plan_total_shares(plan: &Plan) -> u64`
    - Retrieves the total shares in the savings plan.
11. `get_plan_locked_funds(plan: &Plan) -> u64`
    - Retrieves the locked funds in the savings plan.
12. `get_plan_available_funds(plan: &Plan) -> u64`
    - Retrieves the available funds in the savings plan.
13. `get_saving_votes(saving: &Saving) -> u64`
    - Retrieves the votes received by a savings proposal.
