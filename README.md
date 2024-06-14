# Fractality ProfitSharingVault 

# Introduction

The goal is this repo is to outline the design of a vault system with the following requirements:
- Users are able to deposit and withdraw from the vault.
- Users' funds are deployed to an offchain investment strategy, eg. an exchange.
- Returns are distributed back the vault/users daily.
- Allow users to either withdraw or re-invest their profits.
- There must be safety for user's funds while they are in the contract.
- There may be supporting infrastructure to make the system work. 


# Smart Contract PseudoCode
## Inheritance
- Contract inherits from OZ AccessControl
## State Variables
- `asset`: An instance of the IERC20 interface representing the ERC20 token used for deposits and withdrawals.
- `strategy`: A struct of type `InvestmentStrategy` that contains the following fields:
 - `strategyAddress`: The address of the investment strategy. Can be a smart contract, user wallet, or exchange address.
 - `uri`: A string representing the URI of the investment strategy where users can learn more about it.
 - `name`: A string representing the name of the investment strategy.
 - `isSmartWallet`: A boolean indicating whether the strategy address is a smart wallet capable of approving token transfers. e.g: an exchange address isn't
- `halted`: A boolean flag indicating whether the contract is currently halted or not.
- `totalDeposited`: A uint256 variable storing the total amount of tokens deposited by users to be invested.
- `totalProfitPool`: A uint256 variable storing the total amount of profits available to be withdrawn or re-invested by users.
- `balances`: A mapping of user addresses to their respective deposit balances (uint256).
- `lastProfitPerTokenPaid`: A mapping of user addresses to the last used profit per token value used during `updateProfit()` (uint256). Used as a snapshotting tool.
- `unclaimedProfits`: A mapping of user addresses to their unclaimed profit balances (uint256). Updated during `updateProfit()`.
- `profitPerTokenStored`: A uint256 variable storing the current profit per token value, scaled by `PROFIT_PER_TOKEN_SCALE_FACTOR`. Always goes up, during `returnProfits()`
- `withdrawRequests`: A mapping of user addresses to their respective `WithdrawRequest` structs.
## Constants
- `PROFIT_PER_TOKEN_SCALE_FACTOR`: A uint256 constant representing the scaling factor for `profitPerTokenStored` (set to 1e18 for 18 decimal places).
- `DEFAULT_ADMIN_ROLE`: A bytes32 constant representing the role identifier for the default admin role.
- `WITHDRAW_ADMIN_ROLE`: A bytes32 constant representing the role identifier for the withdraw admin role.
- `PROFIT_DISTRO_ROLE`: A bytes32 constant representing the role identifier for the profit distribution role.
## Events
- `Deposited(address indexed user, uint256 amount)`: Emitted when a user deposits tokens, including the user's address and the deposited amount.
- `Withdrawn(address indexed user, uint256 amount)`: Emitted when a user withdraws tokens, including the user's address and the withdrawn amount.
- `Reinvested(address indexed user, uint256 amount)`: Emitted when a user reinvests their unclaimed profits, including the user's address and the reinvested amount.
- `ProfitsReturned(uint256 amount)`: Emitted when the admin distributes profit tokens to the contract, including the amount of profit tokens returned.
- `ProfitsClaimed(address indexed user, uint256 profit)`: Emitted when a user claims their unclaimed profits, including the user's address and the claimed profit amount.
- `StrategyModified(InvestmentStrategy newStrategy)`: Emitted when the investment strategy is modified by the admin, including the new strategy details.
- `HaltStatusChanged(bool newHaltStatus)`: Emitted when the halt status of the contract is changed by the admin, including the new halt status.
- `NewWithdrawRequest(address indexed user)`: Emitted when a user creates a new withdraw request, including the user's address.
- `CancelledWithdrawRequest(address indexed user)`: Emitted when a user cancels their withdraw request, including the user's address.
## Custom Errors
- `ExistingWithdrawRequest(address user)`: Thrown when a user attempts to create a new withdraw request while an active request already exists for their address.
- `CannotCancelWithdrawRequest(address user)`: Thrown when a user attempts to cancel a withdraw request that doesn't exist or is not in the `CREATED` state.
- `CannotProcessWithdrawRequest(address user, string reason)`: Thrown when a withdraw request cannot be processed due to various reasons, which is included in the reason string. Such reasons are: request doesn't exist, request isn't in `CREATED` state.
## Constructor
- Takes the following parameters:
 - `_asset`: The address of the ERC20 token contract used for deposits and withdrawals.
 - `strategyAddress`: The address of the initial investment strategy.
 - `strategyUri`: The URI string of the initial investment strategy.
 - `strategyName`: The name string of the initial investment strategy.
 - `strategyIsSmartWallet`: A boolean indicating whether the initial investment strategy address is a smart wallet that can do approves.
 - `defaultProfitDistributor`: The address to be granted the `PROFIT_DISTRO_ROLE`.
 - `defaultWithDrawAdmin`: The address to be granted the `WITHDRAW_ADMIN_ROLE`.
- Initializes the `asset` variable with the provided `_asset` address.
- Initializes the `strategy` struct with the provided strategy details.
- Grants the `DEFAULT_ADMIN_ROLE` to the contract deployer (msg.sender).
- Grants the `PROFIT_DISTRO_ROLE` to the provided `defaultProfitDistributor` address.
- Grants the `WITHDRAW_ADMIN_ROLE` to the provided `defaultWithDrawAdmin` address.
## Modifiers
- `updateProfit(address account)`:
  - Note: this modifier is called before every function call that modifies user balances or profits.
  - Updates the user's `unclaimedProfits` like so
      ```
        uint256 _newProfitSincePreviousUpdate = profitPerTokenStored -
              lastProfitPerTokenPaid[account];
          unclaimedProfits[account] += ((balances[account] * _newProfitSincePreviousUpdate) /
              PROFIT_PER_TOKEN_SCALE_FACTOR);
      ```
  - Updates the user account's `lastProfitPerTokenPaid` to the current `profitPerTokenStored` value.
- `blockIfHalted()`:
  - Checks if the `halted` flag is set to `true`.
  - If the contract is halted, the modifier reverts the transaction.
## Functions
- `changeHaltStatus(bool _newHaltStatus)`:
  - Allows changing the halt status of the contract.
  - Restricted to the `DEFAULT_ADMIN_ROLE`.
  - Requires the `_newHaltStatus` to be different to the current `halted` flag.
  - Updates the `halted` flag to the provided `_newHaltStatus` value.
  - Emits the `HaltStatusChanged` event with the new halt status.

- `deposit(uint256 amount)`:
  - Requires the contract to be not halted using the `blockIfHalted` modifier.
  - Requires the deposit `amount` to be greater than zero.
  - Updates the caller's unclaimed profits using the `updateProfit` modifier.
  - Updates the `totalDeposited` value by adding the deposited `amount`.
  - Updates the caller's balance in the `balances` mapping by adding the deposited `amount`.
  - Transfers the specified `amount` of tokens from the caller to the strategy address using `transferFrom`.
  - Emits the `Deposited` event with the caller's address and the deposited `amount`.

- `withdrawRequest(uint256 amount)`:
  - Requires the contract to be not halted using the `blockIfHalted` modifier.
  - Requires the withdraw request `amount` to be greater than zero and less than or equal to the caller's balance.
  - Retrieves the caller's current withdraw request from the `withdrawRequests` mapping.
  - Checks if the caller has no existing withdraw request or if the existing request is not in the `CREATED` state. Otherwise, reverts with the `ExistingWithdrawRequest` error.
  - If the above condition is met, creates a new `WithdrawRequest` struct with the following details:
    - `user`: The caller's address.
    - `withdrawRequestAmount`: The requested withdraw `amount`.
    - `requestCreationTime`: The current block timestamp.
    - `lastUpdateTime`: The current block timestamp.
    - `status`: `WithdrawRequestStatus.CREATED`.
  - Stores the new withdraw request in the `withdrawRequests` mapping for the caller's address.
  - Emits the `NewWithdrawRequest` event with the caller's address.

- `cancelRequest()`:
  - Retrieves the caller's current withdraw request from the `withdrawRequests` mapping.
  - Checks if the caller has an existing withdraw request and if the request is in the `CREATED` state. 
  - If the caller has no existing withdraw request or if the request is not in the `CREATED` state, reverts with the `CannotCancelWithdrawRequest` error.
  - If the above condition is met:
    - Updates the request's `status` to `WithdrawRequestStatus.CANCELLED`.
    - Updates the request's `lastUpdateTime` to the current block timestamp.
  - Emits the `CancelledWithdrawRequest` event with the caller's address.

- `processWithdraw(address user)`:
  - Restricted to the `WITHDRAW_ADMIN_ROLE`.
  - Requires the contract to be not halted using the `blockIfHalted` modifier.
  - Updates the `user`'s unclaimed profits using the `updateProfit` modifier.
  - Requires the `user` address to be a non-zero address.
  - Retrieves the `user`'s current withdraw request from the `withdrawRequests` mapping.
  - Checks if the `user` has an existing withdraw request and if the request is in the `CREATED` state.
    - If the `user` has no existing withdraw request, reverts with the `CannotProcessWithdrawRequest("non-existant request")` error
    - If the `user` has an existing withdraw request but it is not in the `CREATED` state, reverts with the `CannotProcessWithdrawRequest("request must be in created state")` error.
  - Requires the withdraw request amount to be less than or equal to the `user`'s balance.
  - Requires the withdraw request amount to be less than or equal to the contract's liquidity (balance of the asset token).
  - Updates the `user`'s balance in the `balances` mapping by subtracting the withdraw request amount.
  - Updates the `totalDeposited` value by subtracting the withdraw request amount.
  - Updates the request's `lastUpdateTime` to the current block timestamp.
  - Updates the request's `status` to `WithdrawRequestStatus.WITHDRAWN`.
  - Transfers the withdraw request amount of tokens from the contract to the `user` using `transfer`.
  - Emits the `Withdrawn` event with the `user`'s address and the withdrawn amount.
  - Note: the admin (or an automated system must transfer the tokens to the contract between the request creation and the request processing)

- `returnProfits(uint256 profitAmount,address profitSource)`:
  - Restricted to the `PROFIT_DISTRO_ROLE`.
  - Requires the contract to be not halted using the `blockIfHalted` modifier.
  - Requires totalDeposited to be greater than zero. Effectivly you cannot add profits if there are no deposits.
  - Updates the `totalProfitPool` value by adding the `profitAmount`.
  - Re-calculates the new `profitPerTokenStored` like so:
    ```
    profitPerTokenStored += ((profitAmount * PROFIT_PER_TOKEN_SCALE_FACTOR) / totalDeposited);
    ```
  - Transfers the `profitAmount` of tokens from `profitSource` to the contract using `transferFrom`.
  - Emits the `ProfitsReturned` event with the `profitAmount`.

- `claimProfits()`:
  - Requires the contract to be not halted using the `blockIfHalted` modifier.
  - Updates the caller's unclaimed profits using the `updateProfit` modifier.
  - Retrieves the caller's unclaimed profit amount from the `unclaimedProfits` mapping and stores it in a local `profit` variable.
  - Requires the `profit` amount to be greater than zero.
  - Sets the caller's unclaimed profits to zero in the `unclaimedProfits` mapping.
  - Updates the `totalProfitPool` value by subtracting the `profit` amount.
  - Transfers the `profit` amount of tokens from the contract to the caller using `transfer`.
  - Emits the `ProfitsClaimed` event with the caller's address and the claimed `profit` amount.

- `reInvestProfits()`:
  - Requires the contract to be not halted using the `blockIfHalted` modifier.
  - Updates the caller's unclaimed profits using the `updateProfit` modifier.
  - Retrieves the caller's unclaimed profit amount from the `unclaimedProfits` mapping and stores it in a local `profit` variable.
  - Requires the `profit` amount to be greater than zero.
  - Sets the caller's unclaimed profits to zero in the `unclaimedProfits` mapping.
  - Updates the `totalDeposited` value by adding the `profit` amount.
  - Updates the caller's balance in the `balances` mapping by adding the `profit` amount.
  - Transfers the `profit` amount of tokens from the contract to the strategy address using `transfer`.
  - Emits the `Reinvested` event with the caller's address and the reinvested `profit` amount.

 - `migrateStrategy(address newStrategyAddress, string memory newUri, string memory newName, bool newIsSmartWallet)`:
    - Restricted to the `DEFAULT_ADMIN_ROLE`.
    - Allows migrating to a new investment strategy.
    - Requires the `newStrategyAddress` to be a non-zero address.
    - Stores the current strategy details in a local `oldStrategy` variable.
    - Updates the `strategy` struct with the new strategy details.
    - If the old strategy is a smart wallet (`isSmartWallet` is `true`), that is - the old strategy can approve transfers:
      - Transfers the total deposited amount of tokens from the old strategy contract to the new strategy address using `transferFrom`.
      - Reverts if the token transfer fails.
    - If the old strategy is not a smart wallet:
      - Checks if the contract's balance of the asset token is greater than or equal to the sum of `totalDeposited` and `totalProfitPool` (all tokens must be in the contract).
      - Transfers the total deposited amount of tokens from the contract to the new strategy contract using `transfer`.
      - Reverts if the token transfer fails.

# Testing Approach

- There should be two types of tests to be coded in Forge. The first should be a suite of unit tests for each function. One should aim to get coverage that is as close as possible to 100%, but the most important thing to do is to cover all branches in each function, as that's another path of execution. The unit tests should use fuzzing when it makes sense (such as deposits, for example).
- The next type is even more important, which to create all the possible scenarios that the system might see in production. For example:
  - What happens when one huge deposit comes that is larger than many small deposits?
  - What happens when a long time passes and no one triggers the updateProfit() modifier, and suddenly a deposit arrives?
  - What happens when two users withdraw their funds one right after another in time?
  - What happens in the edge case of being the first or last user to either claim their profits or withdraw?
  - etc
  
  This is just a general outline, testing is its own science and project.

# Architecture Diagram

![Profit Sharing Vault Software Architecture diagram](./diagrams/fractality_architecture.png?raw=true "Profit Sharing Vault Software Architecture diagram")



# Supporting Infrastructure

- One of the requirements is for profits to be distributed every day at a specific time. This translates to calling `returnProfits` with the arguments of how much profit to return, and the source of the profits. I propose two ways to do this, one more centralized than the other.
  - Build a custom and secure server that implements an ethers.js/web3.js script to be run on a schedule
, that simply runs `returnProfits` with the total balance of the source being used, and the address of the source of funds. The source could be this signer (which would need to do an approval), or could be another wallet that has approved the transfer. The wallet in this server would have the `PROFIT_DISTRO_ROLE`.
  - Build a very simple smart contract that temporariry holds funds until they are deployed to the profit-sharing vault. This smart contract would be triggered at the exact same time by [Chainlink Automation](https://docs.chain.link/chainlink-automation), to call the vault's `returnProfits` with its token balance and address. Of course, there would also need to be an approval. In fact, this contract would not even have to hold funds if we didn't want to; the funds can come from another wallet that has approved the transfer. This contract would have the `PROFIT_DISTRO_ROLE`
- For ease of understanding what is happening, I would build a data analytics backend along with a frontend to represent several parts of the system. The system would use [The Graph](https://thegraph.com/) to pull the necessary data to display visualizations (for each vault) of:
  - The size of totalProfitPool and its growth over time.
  - The size of totalDeposited and its growth over time.
  - The current total of all active withdraw requests.
  - APR return rates. 
- The address that controls the most critial role, `DEFAULT_ADMIN_ROLE`, should be a [Gnosis Safe](https://safe.global/) with multisig. Only after N of M approvals have been reached should the gnosis safe perfom actions such as halting or migrating to a new strategy. 

# Monitoring and hygiene measures

The data mentioned above, which would be used by the "dashboard", also would power a monitoring system to alert us of several metrics/events (for each vault) such as:
- The current ratio of total withdraw request amounts to the sum of totalProfitPool+totalDeposited. We can set a threshold where alerts start to get sent.
- The number of  `Insufficient liquidity` errors users face.
- Monitoring and sending alerts for any role-related changes, because that could be related to one of the admin wallets being jeopardized.
- The average time it takes for a withdraw to be processed. If this increases too much, an alert should be sent out.
- The average time it takes for users to take out their profits.
- The ratio of users that choose to take profit out vs. reinvesting it.

Another important requirement is for users to be able to easily withdraw their funds from the strategy. However, both CEX strategies and some DeFi strategies (such as bridging from/to L2s) require some waiting. As such, one of the most important events that needs to be monitored is the `NewWithdrawRequest` event. This needs to be monitored so that the funds can be returned to the user as fast as they can. This would be going under the supporting infrastructure section, but each strategy is going to have a different way of getting funds out. Please see Further work section for more on this.

# Attack vectors 

- Access control issues:
The WITHDRAW_ADMIN_ROLE and PROFIT_DISTRO_ROLE have significant privileges. If these roles are not assigned securely or can be obtained by unintended actors, it could allow malicious profit distributions or forced withdrawals. This is the CORE risk.

- Malicious or vulnerable strategy contracts:
The contract allows the strategy to be migrated. If a malicious strategy contract is set, it could potentially drain or lock funds.

- Griefing/Spam with withdraw requests:
Malicious users could potentially spam withdraw requests.

- Use of transferFrom for strategy migration:
When migrating to a smart wallet strategy, the code assumes the old strategy will approve the transferFrom. If this doesn't occur as expected, funds could get locked. Admins need to be very careful about what the strategy is. A CEX, a defi protocol, a user controller account, etc.

- Miner manipulation / MEV:
Miners/Validators could potentially manipulate the timing of deposits, withdrawals, and profit returns to maximize their own gains at the expense of other users.

- Halting risks:
While the halt functionality can help in emergencies, it also introduces a risk if the admin keys are compromised, as a malicious actor could trap user funds.

- Reliance on token contracts:
If the asset token itself has vulnerabilities (like an inflationary mint bug), it could affect the calculations in the vault.


# Prototype
- In this repo, there is a Solidity prototype of the pseudocode/design for this system. It was developed with Foundry and you can build it using `forge build`.
- Tests for it can be added in the test folder, to be run with `forge test`. They haven't been added yet as this is not meant to be a production-level contract. It has not been audited and has not completely been gas-optimized.

# Milestones to Production & Further work

- The prototype needs to be improved, made more gas-efficient, specially the updateProfit modifier, which is called often.
- I would look into using EIP 4626 to standardize the interface of this contract, for use in defi.
- We can add extra safety checks regarding the movement of funds into the strategy, perhaps with checking if the destination is a smart contract, if it's an ERC20 receiver, etc.
- The contract needs to be fully tested, using foundry, with fuzzing and as much randomization as possible. See testing sub section.
- The way that funds go in and out of strategies needs to be standardized, by making a `IInvestmentStrategy` interface. This interface would define how to interact with the strategy and include further information on the strategy. In fact, if a strategy is for a defi protocol, it can even be expanded upon to include implementations that interact with the defi contracts.
- The contract needs to be audited.
- Key management protocols need to be created, including those with Gnosis Safe. This is more of a business process + OPSEC.
- Although the contract can work by itself, the supporting infrastructure needs to be built, primarily the automated returning of profits and the safety monitoring.
- The supporting infrastructure itself needs to be tested.  
- As mentioned in the monitoring section, something that can be worked on further in the future is creating automated systems for sending users their funds back after they make a withdrawal request. For example, if the strategy is on Binance, then we would use the Binance API to get their funds back upon listening to a `NewWithdrawRequest` event.




