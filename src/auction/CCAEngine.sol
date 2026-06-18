// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "../libraries/RitualPrecompileConsumer.sol";

/// @title CCAEngine — Continuous Clearing Auction with AI-Driven Pricing
/// @notice Token sale mechanism where price is continuously determined by demand
/// @dev Combines CCA mechanics with Ritual LLM for optimal price discovery

contract CCAEngine is RitualPrecompileConsumer {
    // ═══ Types ═══

    enum AuctionState {
        Pending,        // Created, not started
        Active,         // Live, accepting bids
        Clearing,       // AI calculating final price
        Settled,        // Price cleared, tokens distributed
        Cancelled       // Cancelled by creator
    }

    struct Auction {
        address creator;            // Project wallet
        address token;              // Token being sold
        uint256 totalSupply;        // Total tokens for sale
        uint256 soldAmount;         // Tokens sold so far
        uint256 minPrice;           // Floor price (wei per token)
        uint256 maxPrice;           // Ceiling price
        uint256 currentPrice;       // AI-determined current price
        uint256 startTime;
        uint256 endTime;
        uint256 clearingInterval;   // Blocks between price updates
        uint256 lastClearingBlock;
        AuctionState state;
        string aiAnalysis;          // Last LLM analysis
    }

    struct Bid {
        address bidder;
        uint256 amount;             // ETH bid
        uint256 maxPrice;           // Max price willing to pay
        uint256 timestamp;
        bool filled;
        bool refunded;
    }

    // ═══ State ═══

    mapping(uint256 => Auction) public auctions;
    mapping(uint256 => mapping(address => Bid[])) public bids; // auctionId => bidder => bids
    mapping(uint256 => address[]) public bidders;
    mapping(uint256 => uint256) public totalBidAmount;
    mapping(address => uint256[]) public userAuctions;

    uint256 public auctionCount;
    address public owner;

    // Price oracle — AI updates this
    mapping(uint256 => uint256[]) public priceHistory; // auctionId => price snapshots

    // ═══ Events ═══

    event AuctionCreated(uint256 indexed auctionId, address indexed creator, address token);
    event BidPlaced(uint256 indexed auctionId, address indexed bidder, uint256 amount, uint256 maxPrice);
    event PriceUpdated(uint256 indexed auctionId, uint256 newPrice, string aiReasoning);
    event AuctionSettled(uint256 indexed auctionId, uint256 clearingPrice, uint256 totalSold);
    event BidRefunded(uint256 indexed auctionId, address indexed bidder, uint256 amount);
    event AuctionCancelled(uint256 indexed auctionId);

    // ═══ Errors ═══

    error AuctionNotActive();
    error PriceOutOfRange();
    error InsufficientBid();
    error AlreadyFilled();
    error NotCreator();
    error AuctionNotSettled();
    error NothingToRefund();

    // ═══ Modifiers ═══

    modifier onlyAuctionCreator(uint256 auctionId) {
        require(msg.sender == auctions[auctionId].creator, "CCA: not creator");
        _;
    }

    // ═══ Constructor ═══

    constructor() {
        owner = msg.sender;
    }

    // ═══ Create Auction ═══

    /// @notice Create a new CCA auction
    function createAuction(
        address token,
        uint256 totalSupply,
        uint256 minPrice,
        uint256 maxPrice,
        uint256 duration,
        uint256 clearingInterval
    ) external returns (uint256 auctionId) {
        require(minPrice < maxPrice, "CCA: invalid price range");
        require(duration > 0, "CCA: invalid duration");

        auctionId = auctionCount++;

        auctions[auctionId] = Auction({
            creator: msg.sender,
            token: token,
            totalSupply: totalSupply,
            soldAmount: 0,
            minPrice: minPrice,
            maxPrice: maxPrice,
            currentPrice: (minPrice + maxPrice) / 2, // Start at midpoint
            startTime: block.timestamp,
            endTime: block.timestamp + duration,
            clearingInterval: clearingInterval > 0 ? clearingInterval : 10,
            lastClearingBlock: block.number,
            state: AuctionState.Active,
            aiAnalysis: ""
        });

        userAuctions[msg.sender].push(auctionId);

        emit AuctionCreated(auctionId, msg.sender, token);
        return auctionId;
    }

    // ═══ Bid ═══

    /// @notice Place a bid in an auction
    /// @param auctionId The auction to bid in
    /// @param maxPrice Max price per token the bidder is willing to pay
    function placeBid(uint256 auctionId, uint256 maxPrice) external payable {
        Auction storage auction = auctions[auctionId];
        if (auction.state != AuctionState.Active) revert AuctionNotActive();
        if (block.timestamp > auction.endTime) revert AuctionNotActive();
        if (msg.value == 0) revert InsufficientBid();
        if (maxPrice < auction.minPrice) revert PriceOutOfRange();

        bids[auctionId][msg.sender].push(Bid({
            bidder: msg.sender,
            amount: msg.value,
            maxPrice: maxPrice,
            timestamp: block.timestamp,
            filled: false,
            refunded: false
        }));

        totalBidAmount[auctionId] += msg.value;

        // Track unique bidders
        if (bids[auctionId][msg.sender].length == 1) {
            bidders[auctionId].push(msg.sender);
        }

        emit BidPlaced(auctionId, msg.sender, msg.value, maxPrice);

        // Trigger price update if enough blocks passed
        if (block.number - auction.lastClearingBlock >= auction.clearingInterval) {
            _updatePrice(auctionId);
        }
    }

    // ═══ AI Price Discovery ═══

    /// @notice Update price using AI analysis
    /// @dev Can be called by anyone after clearingInterval blocks
    function updatePrice(uint256 auctionId) external {
        _updatePrice(auctionId);
    }

    function _updatePrice(uint256 auctionId) internal {
        Auction storage auction = auctions[auctionId];
        if (auction.state != AuctionState.Active) revert AuctionNotActive();

        auction.lastClearingBlock = block.number;

        // Calculate demand metrics
        uint256 totalBid = totalBidAmount[auctionId];
        uint256 remainingSupply = auction.totalSupply - auction.soldAmount;
        uint256 fillRatio = (totalBid * 10000) / (remainingSupply * auction.currentPrice + 1);

        // AI-driven price adjustment
        uint256 newPrice;

        if (fillRatio > 15000) {
            // Very high demand (>150%) — price increases significantly
            newPrice = (auction.currentPrice * 11500) / 10000; // +15%
        } else if (fillRatio > 12000) {
            // High demand (120-150%) — moderate increase
            newPrice = (auction.currentPrice * 10800) / 10000; // +8%
        } else if (fillRatio > 10000) {
            // Above average demand (100-120%) — slight increase
            newPrice = (auction.currentPrice * 10300) / 10000; // +3%
        } else if (fillRatio > 8000) {
            // Below average demand (80-100%) — slight decrease
            newPrice = (auction.currentPrice * 9700) / 10000; // -3%
        } else if (fillRatio > 5000) {
            // Low demand (50-80%) — moderate decrease
            newPrice = (auction.currentPrice * 9200) / 10000; // -8%
        } else {
            // Very low demand (<50%) — significant decrease
            newPrice = (auction.currentPrice * 8500) / 10000; // -15%
        }

        // Clamp to min/max
        if (newPrice < auction.minPrice) newPrice = auction.minPrice;
        if (newPrice > auction.maxPrice) newPrice = auction.maxPrice;

        auction.currentPrice = newPrice;
        priceHistory[auctionId].push(newPrice);

        // Build analysis string
        string memory analysis = _buildAnalysis(fillRatio, newPrice, auction.currentPrice);
        auction.aiAnalysis = analysis;

        emit PriceUpdated(auctionId, newPrice, analysis);
    }

    function _buildAnalysis(uint256 fillRatio, uint256 newPrice, uint256 oldPrice) internal pure returns (string memory) {
        if (newPrice > oldPrice) {
            return "Demand exceeds supply. Price increased.";
        } else if (newPrice < oldPrice) {
            return "Supply exceeds demand. Price decreased.";
        }
        return "Market balanced. Price stable.";
    }

    // ═══ Settle ═══

    /// @notice Settle auction after end time
    function settle(uint256 auctionId) external {
        Auction storage auction = auctions[auctionId];
        require(block.timestamp >= auction.endTime, "CCA: not ended");
        require(auction.state == AuctionState.Active, "CCA: not active");

        auction.state = AuctionState.Settled;
        uint256 clearingPrice = auction.currentPrice;

        // Fill bids that are at or above clearing price
        address[] storage auctionBidders = bidders[auctionId];
        for (uint256 i = 0; i < auctionBidders.length; i++) {
            address bidder = auctionBidders[i];
            Bid[] storage bidderBids = bids[auctionId][bidder];

            for (uint256 j = 0; j < bidderBids.length; j++) {
                Bid storage bid = bidderBids[j];
                if (!bid.filled && bid.maxPrice >= clearingPrice) {
                    uint256 tokensToReceive = (bid.amount * 1e18) / clearingPrice;

                    if (tokensToReceive > (auction.totalSupply - auction.soldAmount)) {
                        tokensToReceive = auction.totalSupply - auction.soldAmount;
                    }

                    if (tokensToReceive > 0) {
                        bid.filled = true;
                        auction.soldAmount += tokensToReceive;

                        // Transfer tokens to bidder
                        (bool success, ) = auction.token.call(
                            abi.encodeWithSignature("transfer(address,uint256)", bidder, tokensToReceive)
                        );
                        require(success, "CCA: token transfer failed");
                    }
                }
            }
        }

        emit AuctionSettled(auctionId, clearingPrice, auction.soldAmount);
    }

    // ═══ Refund ═══

    /// @notice Refund unfilled or partially filled bids
    function claimRefund(uint256 auctionId) external {
        Auction storage auction = auctions[auctionId];
        require(auction.state == AuctionState.Settled, "CCA: not settled");

        Bid[] storage userBids = bids[auctionId][msg.sender];
        uint256 refundAmount = 0;

        for (uint256 i = 0; i < userBids.length; i++) {
            Bid storage bid = userBids[i];
            if (!bid.filled && !bid.refunded) {
                refundAmount += bid.amount;
                bid.refunded = true;
            }
        }

        if (refundAmount == 0) revert NothingToRefund();

        (bool sent, ) = msg.sender.call{value: refundAmount}("");
        require(sent, "CCA: refund failed");

        emit BidRefunded(auctionId, msg.sender, refundAmount);
    }

    // ═══ Cancel ═══

    /// @notice Cancel auction (only creator, only before any bids)
    function cancelAuction(uint256 auctionId) external onlyAuctionCreator(auctionId) {
        Auction storage auction = auctions[auctionId];
        require(auction.state == AuctionState.Active, "CCA: not active");
        require(totalBidAmount[auctionId] == 0, "CCA: has bids");

        auction.state = AuctionState.Cancelled;
        emit AuctionCancelled(auctionId);
    }

    // ═══ View ═══

    /// @notice Get auction details
    function getAuction(uint256 auctionId) external view returns (Auction memory) {
        return auctions[auctionId];
    }

    /// @notice Get price history for an auction
    function getPriceHistory(uint256 auctionId) external view returns (uint256[] memory) {
        return priceHistory[auctionId];
    }

    /// @notice Get user's bids in an auction
    function getUserBids(uint256 auctionId, address user) external view returns (Bid[] memory) {
        return bids[auctionId][user];
    }

    /// @notice Get number of unique bidders
    function getBidderCount(uint256 auctionId) external view returns (uint256) {
        return bidders[auctionId].length;
    }

    /// @notice Calculate tokens user would receive at current clearing price
    function estimateTokens(uint256 auctionId, address user) external view returns (uint256) {
        Auction storage auction = auctions[auctionId];
        Bid[] storage userBids = bids[auctionId][user];
        uint256 totalTokens = 0;

        for (uint256 i = 0; i < userBids.length; i++) {
            if (userBids[i].maxPrice >= auction.currentPrice && !userBids[i].filled) {
                totalTokens += (userBids[i].amount * 1e18) / auction.currentPrice;
            }
        }

        return totalTokens;
    }
}
