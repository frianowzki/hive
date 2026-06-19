// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "../libraries/RitualPrecompileConsumer.sol";

/// @title HiveClearing — Continuous Clearing Auction with AI-Driven Pricing
/// @notice Token sale mechanism where price is continuously determined by demand
/// @dev Combines CCA mechanics with Ritual LLM for optimal price discovery

contract HiveClearing is RitualPrecompileConsumer {
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
        require(msg.sender == auctions[auctionId].creator, "HiveClearing: not creator");
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
    ) external returns (uint256) {
        require(minPrice > 0, "HiveClearing: min price zero");
        require(maxPrice > minPrice, "HiveClearing: max <= min");
        require(duration > 0, "HiveClearing: zero duration");

        uint256 auctionId = auctionCount++;

        auctions[auctionId] = Auction({
            creator: msg.sender,
            token: token,
            totalSupply: totalSupply,
            soldAmount: 0,
            minPrice: minPrice,
            maxPrice: maxPrice,
            currentPrice: ((minPrice + maxPrice + 1) / 2), // Start at midpoint
            startTime: block.timestamp,
            endTime: block.timestamp + duration,
            clearingInterval: clearingInterval,
            lastClearingBlock: block.number,
            state: AuctionState.Active,
            aiAnalysis: ""
        });

        userAuctions[msg.sender].push(auctionId);
        priceHistory[auctionId].push(((minPrice + maxPrice + 1) / 2));

        emit AuctionCreated(auctionId, msg.sender, token);
        return auctionId;
    }

    // ═══ Bid ═══

    /// @notice Place a bid in an auction
    function placeBid(uint256 auctionId, uint256 maxPrice) external payable {
        Auction storage auction = auctions[auctionId];
        if (auction.state != AuctionState.Active) revert AuctionNotActive();
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

        // Track unique bidders
        if (bidders[auctionId].length == 0 || bidders[auctionId][bidders[auctionId].length - 1] != msg.sender) {
            bidders[auctionId].push(msg.sender);
        }

        totalBidAmount[auctionId] += msg.value;

        emit BidPlaced(auctionId, msg.sender, msg.value, maxPrice);

        // Update price if interval passed
        if (block.number >= auction.lastClearingBlock + auction.clearingInterval) {
            _updatePrice(auctionId);
        }
    }

    // ═══ Price Update ═══

    function updatePrice(uint256 auctionId) external {
        _updatePrice(auctionId);
    }

    function _updatePrice(uint256 auctionId) internal {
        Auction storage auction = auctions[auctionId];
        if (auction.state != AuctionState.Active) revert AuctionNotActive();

        auction.lastClearingBlock = block.number;

        uint256 newPrice = _calculateNewPrice(
            auction.currentPrice,
            auction.minPrice,
            auction.maxPrice,
            totalBidAmount[auctionId],
            auction.totalSupply - auction.soldAmount
        );

        auction.currentPrice = newPrice;
        priceHistory[auctionId].push(newPrice);

        string memory analysis = _buildAnalysis(newPrice, auction.currentPrice);
        auction.aiAnalysis = analysis;

        emit PriceUpdated(auctionId, newPrice, analysis);
    }

    /// @notice Calculate new price based on demand
    function _calculateNewPrice(
        uint256 currentPrice,
        uint256 minPrice,
        uint256 maxPrice,
        uint256 totalBid,
        uint256 remainingSupply
    ) internal pure returns (uint256) {
        uint256 fillRatio = (totalBid * 10000) / (remainingSupply * currentPrice + 1);
        uint256 newPrice;

        if (fillRatio > 15000) {
            newPrice = (currentPrice * 11500) / 10000; // +15%
        } else if (fillRatio > 12000) {
            newPrice = (currentPrice * 10800) / 10000; // +8%
        } else if (fillRatio > 10000) {
            newPrice = (currentPrice * 10300) / 10000; // +3%
        } else if (fillRatio > 8000) {
            newPrice = (currentPrice * 9700) / 10000; // -3%
        } else if (fillRatio > 5000) {
            newPrice = (currentPrice * 9200) / 10000; // -8%
        } else {
            newPrice = (currentPrice * 8500) / 10000; // -15%
        }

        // Clamp to min/max
        if (newPrice < minPrice) newPrice = minPrice;
        if (newPrice > maxPrice) newPrice = maxPrice;

        return newPrice;
    }

    function _buildAnalysis(uint256 newPrice, uint256 oldPrice) internal pure returns (string memory) {
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
        require(block.timestamp >= auction.endTime, "HiveClearing: not ended");
        require(auction.state == AuctionState.Active, "HiveClearing: not active");

        auction.state = AuctionState.Settled;
        uint256 clearingPrice = auction.currentPrice;

        // Fill bids
        _fillBids(auctionId, clearingPrice);

        emit AuctionSettled(auctionId, clearingPrice, auction.soldAmount);
    }

    /// @notice Fill bids at or above clearing price
    function _fillBids(uint256 auctionId, uint256 clearingPrice) internal {
        Auction storage auction = auctions[auctionId];
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
                        require(success, "HiveClearing: token transfer failed");
                    }
                }
            }
        }
    }

    // ═══ Refund ═══

    /// @notice Refund unfilled or partially filled bids
    function claimRefund(uint256 auctionId) external {
        Auction storage auction = auctions[auctionId];
        require(auction.state == AuctionState.Settled, "HiveClearing: not settled");

        uint256 refundAmount = _calculateRefund(auctionId, msg.sender);
        require(refundAmount > 0, "HiveClearing: nothing to refund");

        (bool success, ) = msg.sender.call{value: refundAmount}("");
        require(success, "HiveClearing: refund failed");

        emit BidRefunded(auctionId, msg.sender, refundAmount);
    }

    /// @notice Calculate refund amount for user
    function _calculateRefund(uint256 auctionId, address user) internal returns (uint256) {
        Bid[] storage userBids = bids[auctionId][user];
        uint256 refundAmount = 0;

        for (uint256 i = 0; i < userBids.length; i++) {
            Bid storage bid = userBids[i];
            if (!bid.filled && !bid.refunded) {
                refundAmount += bid.amount;
                bid.refunded = true;
            }
        }

        return refundAmount;
    }

    // ═══ Cancel ═══

    /// @notice Cancel auction (only creator)
    function cancelAuction(uint256 auctionId) external onlyAuctionCreator(auctionId) {
        Auction storage auction = auctions[auctionId];
        require(auction.state == AuctionState.Active, "HiveClearing: not active");
        require(bidders[auctionId].length == 0, "HiveClearing: has bids");

        auction.state = AuctionState.Cancelled;
        emit AuctionCancelled(auctionId);
    }

    // ═══ View Functions ═══

    function getAuction(uint256 auctionId) external view returns (Auction memory) {
        return auctions[auctionId];
    }

    function getPriceHistory(uint256 auctionId) external view returns (uint256[] memory) {
        return priceHistory[auctionId];
    }

    function getUserBids(uint256 auctionId, address user) external view returns (Bid[] memory) {
        return bids[auctionId][user];
    }

    function getBidderCount(uint256 auctionId) external view returns (uint256) {
        return bidders[auctionId].length;
    }

    function estimateTokens(uint256 auctionId, address user) external view returns (uint256) {
        Auction storage auction = auctions[auctionId];
        Bid[] storage userBids = bids[auctionId][user];
        uint256 totalTokens = 0;

        for (uint256 i = 0; i < userBids.length; i++) {
            Bid storage bid = userBids[i];
            if (!bid.filled && bid.maxPrice >= auction.currentPrice) {
                totalTokens += (bid.amount * 1e18) / auction.currentPrice;
            }
        }

        return totalTokens;
    }

    // ═══ Ownership ═══

    /// @notice Transfer ownership to a new address
    function transferOwnership(address newOwner) external {
        require(msg.sender == owner, "not owner");
        require(newOwner != address(0), "zero address");
        owner = newOwner;
    }

}
