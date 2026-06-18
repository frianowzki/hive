// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {RitualPrecompileConsumer} from "../libraries/RitualPrecompileConsumer.sol";
import {HivePoints} from "../points/HivePoints.sol";

/// @title LaunchPad — Hive Token Sale Engine
/// @notice Enables projects to launch token sales with built-in vesting

contract HiveLaunchPad is RitualPrecompileConsumer {
    // ═══ State ═══

    address public admin;
    HivePoints public points;

    struct Sale {
        address project;
        address token;
        uint256 price;
        uint256 hardCap;
        uint256 softCap;
        uint256 minBuy;
        uint256 maxBuy;
        uint256 totalRaised;
        uint256 startTime;
        uint256 endTime;
        uint256 vestingCliff;
        uint256 vestingDuration;
        bool whitelistOnly;
        bool finalized;
        bool cancelled;
    }

    struct Purchase {
        uint256 amount;        // ETH spent
        uint256 tokens;        // Tokens to receive
        uint256 timestamp;     // When purchased
        uint256 claimed;       // Tokens already claimed
    }

    mapping(uint256 => Sale) public sales;
    mapping(uint256 => mapping(address => Purchase)) public purchases;
    mapping(uint256 => mapping(address => bool)) public whitelisted;

    uint256 public saleCount;
    uint256 public constant PLATFORM_FEE_BPS = 200; // 2%

    // ═══ Events ═══

    event SaleCreated(uint256 indexed saleId, address project, uint256 hardCap);
    event PurchaseMade(uint256 indexed saleId, address buyer, uint256 amount, uint256 tokens);
    event TokensClaimed(uint256 indexed saleId, address buyer, uint256 amount);
    event SaleFinalized(uint256 indexed saleId, uint256 totalRaised);
    event SaleCancelled(uint256 indexed saleId);
    event WhitelistUpdated(uint256 indexed saleId, address user, bool status);

    // ═══ Modifiers ═══

    modifier onlyAdmin() {
        require(msg.sender == admin, "LaunchPad: not admin");
        _;
    }

    modifier saleExists(uint256 saleId) {
        require(saleId < saleCount, "LaunchPad: sale not found");
        _;
    }

    // ═══ Constructor ═══

    constructor(address _points) {
        admin = msg.sender;
        points = HivePoints(_points);
    }

    // ═══ Sale Creation ═══

    /// @notice Create a new token sale
    function createSale(
        address project,
        address token,
        uint256 price,
        uint256 hardCap,
        uint256 softCap,
        uint256 minBuy,
        uint256 maxBuy,
        uint256 startTime,
        uint256 endTime,
        uint256 vestingCliff,
        uint256 vestingDuration,
        bool whitelistOnly
    ) external onlyAdmin returns (uint256 saleId) {
        require(endTime > startTime, "LaunchPad: invalid times");
        require(hardCap > softCap, "LaunchPad: hardCap > softCap");
        require(price > 0, "LaunchPad: price > 0");

        saleId = saleCount++;
        sales[saleId] = Sale({
            project: project,
            token: token,
            price: price,
            hardCap: hardCap,
            softCap: softCap,
            minBuy: minBuy,
            maxBuy: maxBuy,
            totalRaised: 0,
            startTime: startTime,
            endTime: endTime,
            vestingCliff: vestingCliff,
            vestingDuration: vestingDuration,
            whitelistOnly: whitelistOnly,
            finalized: false,
            cancelled: false
        });

        emit SaleCreated(saleId, project, hardCap);
    }

    // ═══ Purchase ═══

    /// @notice Buy tokens in a sale
    function buy(uint256 saleId) external payable saleExists(saleId) {
        Sale storage sale = sales[saleId];
        require(!sale.finalized && !sale.cancelled, "LaunchPad: sale ended");
        require(block.timestamp >= sale.startTime, "LaunchPad: not started");
        require(block.timestamp <= sale.endTime, "LaunchPad: ended");
        require(msg.value >= sale.minBuy, "LaunchPad: below min");
        require(sale.totalRaised + msg.value <= sale.hardCap, "LaunchPad: hard cap reached");

        if (sale.whitelistOnly) {
            require(whitelisted[saleId][msg.sender], "LaunchPad: not whitelisted");
        }

        // Check max buy per wallet
        require(purchases[saleId][msg.sender].amount + msg.value <= sale.maxBuy, "LaunchPad: max buy reached");

        uint256 tokens = (msg.value * 1e18) / sale.price;
        sale.totalRaised += msg.value;

        purchases[saleId][msg.sender] = Purchase({
            amount: purchases[saleId][msg.sender].amount + msg.value,
            tokens: purchases[saleId][msg.sender].tokens + tokens,
            timestamp: block.timestamp,
            claimed: purchases[saleId][msg.sender].claimed
        });

        // Award points
        points.awardBuy(msg.sender, msg.value);

        emit PurchaseMade(saleId, msg.sender, msg.value, tokens);
    }

    // ═══ Claiming ═══

    /// @notice Claim vested tokens
    function claim(uint256 saleId) external saleExists(saleId) {
        Sale storage sale = sales[saleId];
        Purchase storage purchase = purchases[saleId][msg.sender];

        require(purchase.tokens > 0, "LaunchPad: nothing to claim");

        uint256 vested = _calculateVested(
            purchase.tokens,
            purchase.timestamp,
            sale.vestingCliff,
            sale.vestingDuration
        );

        uint256 claimable = vested - purchase.claimed;
        require(claimable > 0, "LaunchPad: nothing claimable");

        purchase.claimed += claimable;

        // Transfer tokens (in production, call token.transfer)
        emit TokensClaimed(saleId, msg.sender, claimable);
    }

    /// @notice Get claimable amount
    function claimable(uint256 saleId, address user) external view returns (uint256) {
        Sale storage sale = sales[saleId];
        Purchase storage purchase = purchases[saleId][user];

        uint256 vested = _calculateVested(
            purchase.tokens,
            purchase.timestamp,
            sale.vestingCliff,
            sale.vestingDuration
        );

        return vested - purchase.claimed;
    }

    // ═══ Finalization ═══

    /// @notice Finalize a sale (after end time)
    function finalize(uint256 saleId) external onlyAdmin saleExists(saleId) {
        Sale storage sale = sales[saleId];
        require(block.timestamp > sale.endTime, "LaunchPad: sale not ended");
        require(!sale.finalized, "LaunchPad: already finalized");

        if (sale.totalRaised >= sale.softCap) {
            sale.finalized = true;
            // Transfer raised funds to project (minus platform fee)
            uint256 fee = (sale.totalRaised * PLATFORM_FEE_BPS) / 10_000;
            uint256 projectAmount = sale.totalRaised - fee;

            (bool success1, ) = sale.project.call{value: projectAmount}("");
            require(success1, "LaunchPad: transfer to project failed");

            // Fee stays in contract
            emit SaleFinalized(saleId, sale.totalRaised);
        } else {
            // Soft cap not reached — refund
            sale.cancelled = true;
            emit SaleCancelled(saleId);
        }
    }

    /// @notice Refund (if sale cancelled)
    function refund(uint256 saleId) external saleExists(saleId) {
        Sale storage sale = sales[saleId];
        require(sale.cancelled, "LaunchPad: sale not cancelled");

        Purchase storage purchase = purchases[saleId][msg.sender];
        uint256 amount = purchase.amount;
        require(amount > 0, "LaunchPad: nothing to refund");

        purchase.amount = 0;
        purchase.tokens = 0;

        (bool success, ) = msg.sender.call{value: amount}("");
        require(success, "LaunchPad: refund failed");
    }

    // ═══ Whitelist ═══

    function setWhitelist(uint256 saleId, address user, bool status) external onlyAdmin {
        whitelisted[saleId][user] = status;
        emit WhitelistUpdated(saleId, user, status);
    }

    function setWhitelistBatch(uint256 saleId, address[] calldata users, bool status) external onlyAdmin {
        for (uint256 i = 0; i < users.length; i++) {
            whitelisted[saleId][users[i]] = status;
            emit WhitelistUpdated(saleId, users[i], status);
        }
    }

    // ═══ AI Integration (Ritual) ═══

    /// @notice Analyze a project using LLM
    function analyzeProject(string calldata projectInfo) external returns (string memory) {
        string memory prompt = string(abi.encodePacked(
            "Analyze this crypto project for a token sale. ",
            "Project info: ", projectInfo, ". ",
            "Evaluate: team, tokenomics, market fit, risk. ",
            "Reply with: {score: 0-100, recommendation: APPROVE/REJECT, reasoning: ...}"
        ));

        bytes memory llmInput = _encodeLlmCall(prompt);
        (bool success, bytes memory output) = LLM_PRECOMPILE.staticcall(llmInput);

        if (success && output.length > 0) {
            return abi.decode(output, (string));
        }
        return "[LLM unavailable]";
    }

    // ═══ Internal ═══

    function _calculateVested(
        uint256 totalTokens,
        uint256 startTime,
        uint256 cliff,
        uint256 duration
    ) internal view returns (uint256) {
        if (block.timestamp < startTime + cliff) return 0;
        if (block.timestamp >= startTime + duration) return totalTokens;

        uint256 elapsed = block.timestamp - startTime - cliff;
        uint256 vestingPeriod = duration - cliff;
        return (totalTokens * elapsed) / vestingPeriod;
    }

    // ═══ View ═══

    function getSale(uint256 saleId) external view returns (Sale memory) {
        return sales[saleId];
    }

    function getPurchase(uint256 saleId, address user) external view returns (Purchase memory) {
        return purchases[saleId][user];
    }

    receive() external payable {}
}
