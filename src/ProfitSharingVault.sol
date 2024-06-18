// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {console} from "forge-std/Test.sol";
import "openzeppelin-contracts/contracts/interfaces/IERC20.sol";
import "openzeppelin-contracts/contracts/access/AccessControl.sol";

contract ProfitSharingVault is AccessControl {
    struct InvestmentStrategy {
        address strategyAddress;
        string uri;
        string name;
        bool isSmartWallet; //smart wallet = can do token approvals
    }

    enum WithdrawRequestStatus {
        CREATED,
        WITHDRAWN,
        CANCELLED
    }

    struct WithdrawRequest {
        address user;
        uint256 withdrawRequestAmount;
        uint256 requestCreationTime;
        uint256 lastUpdateTime;
        WithdrawRequestStatus status;
    }

    mapping(address => WithdrawRequest) public withdrawRequests;

    uint256 constant PROFIT_PER_TOKEN_SCALE_FACTOR = 1e18;

    IERC20 public immutable asset; //The asset that will be locked

    InvestmentStrategy public strategy;

    bool public halted;

    uint256 public totalDeposited; // Total user deposits (goes up on deposits, goes down on withdrawls)
    uint256 public totalProfitPool; // Total profit distributed by the admin
    mapping(address => uint256) public balances; //Current balance per user (does not include profit)
    mapping(address => uint256) public lastProfitPerTokenPaid; //The last "profit per token" number used for a particular user's profit distribution.
    mapping(address => uint256) public unclaimedProfits; //Current amount of unclaimed profits per user
    uint256 public profitPerTokenStored; //The total profit per token stored (the totalDeposited). Always goes up.

    event Deposited(address indexed user, uint256 amount);
    event Withdrawn(address indexed user, uint256 amount);
    event Reinvested(address indexed user, uint256 amount);
    event ProfitsReturned(uint256 amount);
    event ProfitsClaimed(address indexed user, uint256 profit);
    event StrategyModified(InvestmentStrategy newStrategy);
    event HaltStatusChanged(bool newHaltStatus);

    event NewWithdrawRequest(address indexed user);
    event CancelledWithdrawRequest(address indexed user);

    //errors
    error ExistingWithdrawRequest(address user);
    error CannotCancelWithdrawRequest(address user);
    error CannotProcessWithdrawRequest(address user, string reason);

    bytes32 public constant WITHDRAW_ADMIN_ROLE = keccak256("WITHDRAW_ADMIN_ROLE");
    bytes32 public constant PROFIT_DISTRO_ROLE = keccak256("PROFIT_DISTRO_ROLE");

    constructor(
        address _asset,
        address strategyAddress,
        string memory strategyUri,
        string memory strategyName,
        bool strategyIsSmartWallet,
        address defaultProfitDistributor,
        address defaultWithDrawAdmin
    ) {
        asset = IERC20(_asset);
        strategy = InvestmentStrategy(strategyAddress, strategyUri, strategyName, strategyIsSmartWallet);
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(PROFIT_DISTRO_ROLE, defaultProfitDistributor);
        _grantRole(WITHDRAW_ADMIN_ROLE, defaultWithDrawAdmin);
    }

    modifier updateProfit(address account) {
        //this can never underflow, because it is a subtraction of a value that always goes up, minus a previous snapshot of that value.
        uint256 _newProfitSincePreviousUpdate = profitPerTokenStored - lastProfitPerTokenPaid[account];

        unclaimedProfits[account] +=
            ((balances[account] * _newProfitSincePreviousUpdate) / PROFIT_PER_TOKEN_SCALE_FACTOR);

        lastProfitPerTokenPaid[account] = profitPerTokenStored; //set the current total profit per token as the latest for this user
        _;
    }

    modifier blockIfHalted() {
        require(!halted, "halted");
        _;
    }

    function migrateStrategy(
        address newStrategyAddress,
        string memory newUri,
        string memory newName,
        bool newIsSmartWallet
    ) public onlyRole(DEFAULT_ADMIN_ROLE) {
        require(newStrategyAddress != address(0), "ZERO_ADDRESS");
        InvestmentStrategy memory oldStrategy = strategy;
        strategy = InvestmentStrategy(newStrategyAddress, newUri, newName, newIsSmartWallet);
        if (oldStrategy.isSmartWallet) {
            require(asset.transferFrom(oldStrategy.strategyAddress, newStrategyAddress, totalDeposited), "ERC20TXERR");
        } else {
            require(
                asset.balanceOf(address(this)) >= totalDeposited + totalProfitPool, "SEND STRATEGY FUNDS TO VAULT FIRST"
            );
            require(asset.transfer(newStrategyAddress, totalDeposited), "ERC20TXERR");
        }
    }

    function changeHaltStatus(bool _newHaltStatus) public onlyRole(DEFAULT_ADMIN_ROLE) {
        require(_newHaltStatus != halted, "same halt status");
        halted = _newHaltStatus;
        emit HaltStatusChanged(_newHaltStatus);
    }

    function deposit(uint256 amount) external blockIfHalted updateProfit(msg.sender) {
        require(amount > 0, "Amount must be positive");
        totalDeposited += amount;
        balances[msg.sender] += amount;
        require(asset.transferFrom(msg.sender, strategy.strategyAddress, amount), "ERC20TXERR");
        emit Deposited(msg.sender, amount);
    }

    function withdrawRequest(uint256 amount) external blockIfHalted {
        require(amount > 0, "invalid amount");
        require(amount <= balances[msg.sender], "Insufficient user balance");
        WithdrawRequest memory currentRequest = withdrawRequests[msg.sender];

        if (currentRequest.user == address(0) || currentRequest.status != WithdrawRequestStatus.CREATED) {
            //no request ever has been made or previous request has been processed, can write fresh request
            withdrawRequests[msg.sender] =
                WithdrawRequest(msg.sender, amount, block.timestamp, block.timestamp, WithdrawRequestStatus.CREATED);
        } else {
            revert ExistingWithdrawRequest(msg.sender); //needs to be be processed or cancelled
        }
        emit NewWithdrawRequest(msg.sender);
    }

    function cancelRequest() external {
        if (
            withdrawRequests[msg.sender].user != address(0)
                && withdrawRequests[msg.sender].status == WithdrawRequestStatus.CREATED
        ) {
            withdrawRequests[msg.sender].status = WithdrawRequestStatus.CANCELLED;
            withdrawRequests[msg.sender].lastUpdateTime = block.timestamp;
        } else {
            revert CannotCancelWithdrawRequest(msg.sender);
        }
        emit CancelledWithdrawRequest(msg.sender);
    }

    function processWithdraw(address user) external blockIfHalted onlyRole(WITHDRAW_ADMIN_ROLE) updateProfit(user) {
        require(user != address(0), "invalid address");
        if (withdrawRequests[msg.sender].user == address(0)) {
            revert CannotProcessWithdrawRequest(user, "Non existant request");
        }
        if (
            withdrawRequests[msg.sender].user != address(0)
                && withdrawRequests[msg.sender].status != WithdrawRequestStatus.CREATED
        ) {
            revert CannotProcessWithdrawRequest(user, "Request must be in created state");
        }
        WithdrawRequest memory currentRequest = withdrawRequests[user];

        require(currentRequest.withdrawRequestAmount <= balances[user], "Insufficient user balance");
        require(currentRequest.withdrawRequestAmount <= asset.balanceOf(address(this)), "Insufficient liquidity");

        balances[msg.sender] -= currentRequest.withdrawRequestAmount;
        totalDeposited -= currentRequest.withdrawRequestAmount;

        withdrawRequests[msg.sender].lastUpdateTime = block.timestamp;
        withdrawRequests[msg.sender].status = WithdrawRequestStatus.WITHDRAWN;

        require(asset.transfer(user, currentRequest.withdrawRequestAmount), "ERC20TXERR");

        emit Withdrawn(user, currentRequest.withdrawRequestAmount);
    }

    function returnProfits(uint256 profitAmount, address profitSource)
        external
        blockIfHalted
        onlyRole(PROFIT_DISTRO_ROLE)
    {
        require(totalDeposited > 0, "no deposits");
        totalProfitPool += profitAmount;
        profitPerTokenStored += ((profitAmount * PROFIT_PER_TOKEN_SCALE_FACTOR) / totalDeposited); //update profit per token stored, note this needs to be scaled to avoid truncating to zero

        require(asset.transferFrom(profitSource, address(this), profitAmount), "ERC20TXERR");
        emit ProfitsReturned(profitAmount);
    }

    function claimProfits() external blockIfHalted updateProfit(msg.sender) {
        uint256 profit = unclaimedProfits[msg.sender];
        require(profit > 0, "No profit to claim");
        unclaimedProfits[msg.sender] = 0;
        totalProfitPool -= profit;
        require(asset.transfer(msg.sender, profit), "ERC20TXERR");
        // Send profits to the user here, e.g., transfer tokens
        emit ProfitsClaimed(msg.sender, profit);
    }

    function reInvestProfits() external blockIfHalted updateProfit(msg.sender) {
        uint256 profit = unclaimedProfits[msg.sender];
        require(profit > 0, "No profit to reinvest");
        unclaimedProfits[msg.sender] = 0;
        totalDeposited += profit;
        balances[msg.sender] += profit;
        totalProfitPool -= profit;
        require(asset.transfer(strategy.strategyAddress, profit), "ERC20TXERR");
        emit Reinvested(msg.sender, profit);
    }
}
