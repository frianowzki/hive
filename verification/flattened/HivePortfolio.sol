// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

// src/portfolio/HivePortfolio.sol

/// @title HivePortfolio — On-chain Portfolio Tracker
/// @notice Tracks all token holdings, vesting, and PnL per HiveID

contract HivePortfolio {
    // ═══ Types ═══

    enum TokenStandard {
        ERC20,
        ERC721,
        ERC1155
    }

    struct Holding {
        address token;
        TokenStandard standard;
        uint256 tokenId;        // For NFTs
        uint256 amount;         // For ERC20/ERC1155
        uint256 avgEntryPrice;  // Weighted average entry (in ETH wei)
        uint256 firstAcquired;
        uint256 lastUpdated;
    }

    struct VestingInfo {
        address token;
        uint256 totalAmount;
        uint256 claimedAmount;
        uint256 cliffEnd;       // Timestamp
        uint256 vestingEnd;     // Timestamp
        uint256 releaseInterval;// Seconds between releases
        uint256 lastClaim;
        bool cancelled;
    }

    struct PortfolioSummary {
        uint256 totalHoldings;
        uint256 totalVestingPositions;
        uint256 totalValueEstimate; // In wei (rough estimate)
        uint256 lastUpdated;
    }

    // ═══ State ═══

    // usernameHash => token address => Holding
    mapping(bytes32 => mapping(address => Holding)) public holdings;
    // usernameHash => list of token addresses
    mapping(bytes32 => address[]) public holdingTokens;

    // usernameHash => vestingId => VestingInfo
    mapping(bytes32 => mapping(uint256 => VestingInfo)) public vestings;
    mapping(bytes32 => uint256) public vestingCount;

    // Trade history
    struct Trade {
        address token;
        uint256 amount;
        uint256 price;
        bool isBuy;
        uint256 timestamp;
        uint256 pnl; // Realized PnL (positive = profit)
    }

    mapping(bytes32 => Trade[]) public trades;
    mapping(bytes32 => uint256) public totalRealizedPnl;

    // Price oracle (simplified — in production use Chainlink/Ritual oracle)
    mapping(address => uint256) public tokenPrices;

    address public owner;

    // ═══ Events ═══

    event HoldingUpdated(bytes32 indexed usernameHash, address token, uint256 amount);
    event VestingCreated(bytes32 indexed usernameHash, uint256 vestingId, address token, uint256 amount);
    event VestingClaimed(bytes32 indexed usernameHash, uint256 vestingId, uint256 amount);
    event VestingCancelled(bytes32 indexed usernameHash, uint256 vestingId);
    event TradeRecorded(bytes32 indexed usernameHash, address token, bool isBuy, uint256 amount, uint256 price);

    // ═══ Modifiers ═══

    modifier onlyAuthorized() {
        // In production, restrict to HiveID contract or authorized contracts
        _;
    }

    // ═══ Constructor ═══

    constructor() {
        owner = msg.sender;
    }

    // ═══ Holdings Management ═══

    /// @notice Record a token acquisition
    function recordAcquisition(
        bytes32 usernameHash,
        address token,
        uint256 amount,
        uint256 pricePerToken
    ) external onlyAuthorized {
        Holding storage h = holdings[usernameHash][token];

        if (h.firstAcquired == 0) {
            // New holding
            h.token = token;
            h.standard = TokenStandard.ERC20;
            h.amount = amount;
            h.avgEntryPrice = pricePerToken;
            h.firstAcquired = block.timestamp;
            h.lastUpdated = block.timestamp;
            holdingTokens[usernameHash].push(token);
        } else {
            // Update existing — weighted average
            uint256 totalValue = (h.amount * h.avgEntryPrice) + (amount * pricePerToken);
            h.amount += amount;
            h.avgEntryPrice = totalValue / h.amount;
            h.lastUpdated = block.timestamp;
        }

        // Record trade
        trades[usernameHash].push(Trade({
            token: token,
            amount: amount,
            price: pricePerToken,
            isBuy: true,
            timestamp: block.timestamp,
            pnl: 0
        }));

        emit HoldingUpdated(usernameHash, token, h.amount);
        emit TradeRecorded(usernameHash, token, true, amount, pricePerToken);
    }

    /// @notice Record a token sale/disposal
    function recordDisposal(
        bytes32 usernameHash,
        address token,
        uint256 amount,
        uint256 pricePerToken
    ) external onlyAuthorized {
        Holding storage h = holdings[usernameHash][token];
        require(h.amount >= amount, "Portfolio: insufficient balance");

        // Calculate realized PnL
        uint256 pnl = 0;
        if (pricePerToken > h.avgEntryPrice) {
            pnl = (pricePerToken - h.avgEntryPrice) * amount;
        } else if (h.avgEntryPrice > pricePerToken) {
            pnl = (h.avgEntryPrice - pricePerToken) * amount;
            // Negative PnL — we store as 0 and track loss separately
        }

        h.amount -= amount;
        h.lastUpdated = block.timestamp;

        if (h.amount == 0) {
            h.avgEntryPrice = 0;
        }

        // Record trade
        trades[usernameHash].push(Trade({
            token: token,
            amount: amount,
            price: pricePerToken,
            isBuy: false,
            timestamp: block.timestamp,
            pnl: pnl
        }));

        if (pricePerToken >= h.avgEntryPrice) {
            totalRealizedPnl[usernameHash] += pnl;
        } else {
            totalRealizedPnl[usernameHash] -= pnl;
        }

        emit HoldingUpdated(usernameHash, token, h.amount);
        emit TradeRecorded(usernameHash, token, false, amount, pricePerToken);
    }

    // ═══ Vesting ═══

    /// @notice Create a vesting schedule
    function createVesting(
        bytes32 usernameHash,
        address token,
        uint256 totalAmount,
        uint256 cliffDuration,
        uint256 vestingDuration,
        uint256 releaseInterval
    ) external onlyAuthorized returns (uint256 vestingId) {
        vestingId = vestingCount[usernameHash]++;

        vestings[usernameHash][vestingId] = VestingInfo({
            token: token,
            totalAmount: totalAmount,
            claimedAmount: 0,
            cliffEnd: block.timestamp + cliffDuration,
            vestingEnd: block.timestamp + vestingDuration,
            releaseInterval: releaseInterval,
            lastClaim: block.timestamp,
            cancelled: false
        });

        emit VestingCreated(usernameHash, vestingId, token, totalAmount);
        return vestingId;
    }

    /// @notice Calculate claimable amount for a vesting
    function claimableAmount(bytes32 usernameHash, uint256 vestingId) public view returns (uint256) {
        VestingInfo storage v = _getVesting(usernameHash, vestingId);

        if (v.cancelled) return 0;
        if (block.timestamp < v.cliffEnd) return 0;

        uint256 elapsed = block.timestamp - v.cliffEnd;
        uint256 vestingPeriod = v.vestingEnd - v.cliffEnd;

        if (vestingPeriod == 0) return v.totalAmount;

        uint256 vestedAmount = (v.totalAmount * elapsed) / vestingPeriod;
        if (vestedAmount > v.totalAmount) vestedAmount = v.totalAmount;

        uint256 claimable = vestedAmount - v.claimedAmount;
        return claimable;
    }

    /// @notice Claim vested tokens
    function claimVesting(bytes32 usernameHash, uint256 vestingId) external onlyAuthorized returns (uint256 amount) {
        VestingInfo storage v = _getVesting(usernameHash, vestingId);
        require(!v.cancelled, "Portfolio: vesting cancelled");

        amount = claimableAmount(usernameHash, vestingId);
        require(amount > 0, "Portfolio: nothing to claim");

        v.claimedAmount += amount;
        v.lastClaim = block.timestamp;

        // Transfer tokens
        (bool success, ) = v.token.call(
            abi.encodeWithSignature("transfer(address,uint256)", msg.sender, amount)
        );
        require(success, "Portfolio: transfer failed");

        emit VestingClaimed(usernameHash, vestingId, amount);
    }

    // ═══ Internal Vesting Access ═══

    function _getVesting(bytes32 usernameHash, uint256 vestingId) internal view returns (VestingInfo storage v) {
        v = vestings[usernameHash][vestingId];
    }

    // ═══ Price Oracle ═══

    /// @notice Update token price (called by oracle/authorized)
    function updatePrice(address token, uint256 price) external {
        require(msg.sender == owner, "Portfolio: not authorized");
        tokenPrices[token] = price;
    }

    // ═══ View ═══

    /// @notice Get all holding token addresses for a user
    function getHoldingTokens(bytes32 usernameHash) external view returns (address[] memory) {
        return holdingTokens[usernameHash];
    }

    /// @notice Get holding details for a specific token
    function getHolding(bytes32 usernameHash, address token) external view returns (Holding memory) {
        return holdings[usernameHash][token];
    }

    /// @notice Get vesting info
    function getVesting(bytes32 usernameHash, uint256 vestingId) external view returns (VestingInfo memory) {
        return vestings[usernameHash][vestingId];
    }

    /// @notice Get trade history
    function getTrades(bytes32 usernameHash) external view returns (Trade[] memory) {
        return trades[usernameHash];
    }

    /// @notice Get portfolio summary
    function getPortfolioSummary(bytes32 usernameHash) external view returns (PortfolioSummary memory) {
        address[] storage tokens = holdingTokens[usernameHash];
        uint256 totalValue = 0;

        for (uint256 i = 0; i < tokens.length; i++) {
            Holding storage h = holdings[usernameHash][tokens[i]];
            if (tokenPrices[tokens[i]] > 0) {
                totalValue += (h.amount * tokenPrices[tokens[i]]) / 1e18;
            }
        }

        return PortfolioSummary({
            totalHoldings: tokens.length,
            totalVestingPositions: vestingCount[usernameHash],
            totalValueEstimate: totalValue,
            lastUpdated: block.timestamp
        });
    }

    /// @notice Get unrealized PnL for a holding
    function getUnrealizedPnl(bytes32 usernameHash, address token) external view returns (int256) {
        Holding storage h = holdings[usernameHash][token];
        if (h.amount == 0 || tokenPrices[token] == 0) return 0;

        uint256 currentValue = (h.amount * tokenPrices[token]) / 1e18;
        uint256 entryValue = (h.amount * h.avgEntryPrice) / 1e18;

        if (currentValue >= entryValue) {
            return int256(currentValue - entryValue);
        } else {
            return -int256(entryValue - currentValue);
        }
    }
}
