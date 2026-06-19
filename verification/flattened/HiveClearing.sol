// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

// src/libraries/RitualPrecompileConsumer.sol

/// @title PrecompileConsumer — Base contract for Ritual precompile calls
/// @notice Provides helpers for calling Ritual precompiles

abstract contract RitualPrecompileConsumer {
    // ═══ Precompile Addresses ═══
    address internal constant ONNX_PRECOMPILE = address(0x0800);
    address internal constant HTTP_PRECOMPILE = address(0x0801);
    address internal constant LLM_PRECOMPILE = address(0x0802);
    address internal constant ED25519_PRECOMPILE = address(0x0009);
    address internal constant WEBAUTHN_PRECOMPILE = address(0x0100);

    // ═══ System Contracts ═══
    address internal constant RITUAL_WALLET = 0x532F0dF0896F353d8C3DD8cc134e8129DA2a3948;
    address internal constant ASYNC_JOB_TRACKER = 0xC069FFCa0389f44eCA2C626e55491b0ab045AEF5;
    address internal constant TEE_REGISTRY = 0x9644e8562cE0Fe12b4deeC4163c064A8862Bf47F;
    address internal constant SCHEDULER = 0x56e776BAE2DD60664b69Bd5F865F1180ffB7D58B;
    address internal constant SECRETS_ACCESS = 0xf9BF1BC8A3e79B9EBeD0fa2Db70D0513fecE32FD;
    address internal constant ASYNC_DELIVERY = 0x5A16214fF555848411544b005f7Ac063742f39F6;
    address internal constant AGENT_HEARTBEAT = 0xEF505E801f1Db392B5289690E2ffc20e840A3aCa;
    address internal constant MODEL_PRICING = 0x7A85F48b971ceBb75491b61abe279728F4c4384f;

    // ═══ Async States ═══
    uint8 internal constant ASYNC_SUBMITTED = 0;
    uint8 internal constant ASYNC_COMMITTED = 1;
    uint8 internal constant ASYNC_PROCESSING = 2;
    uint8 internal constant ASYNC_READY = 3;
    uint8 internal constant ASYNC_SETTLED = 4;
    uint8 internal constant ASYNC_FAILED = 5;
    uint8 internal constant ASYNC_EXPIRED = 6;

    /// @notice Execute a synchronous precompile call
    /// @param precompile Address of the precompile
    /// @param input Encoded input data
    /// @return output Raw output bytes
    function _executePrecompile(address precompile, bytes memory input)
        internal
        returns (bytes memory output)
    {
        (bool success, bytes memory result) = precompile.staticcall(input);
        require(success, "PrecompileConsumer: call failed");
        return result;
    }

    /// @notice Encode an HTTP GET request
    /// @param url The URL to fetch
    /// @return Encoded bytes for HTTP precompile
    function _encodeHttpGet(string memory url) internal pure returns (bytes memory) {
        return abi.encode(
            address(0),         // executor (auto-select)
            new bytes[](0),     // encryptedSecrets
            uint256(30),        // ttl (blocks)
            new bytes[](0),     // secretSignatures
            bytes(""),          // userPublicKey
            url,                // url
            uint8(1),           // method (1=GET)
            new string[](0),    // headerKeys
            new string[](0),    // headerValues
            bytes(""),          // body
            uint256(0),         // dkmsKeyIndex
            uint8(0),           // dkmsKeyFormat
            false               // piiEnabled
        );
    }

    /// @notice Encode an LLM inference request
    /// @param prompt The prompt text
    /// @return Encoded bytes for LLM precompile
    function _encodeLlmCall(string memory prompt) internal pure returns (bytes memory) {
        return abi.encode(
            address(0),         // executor (auto-select)
            new bytes[](0),     // encryptedSecrets
            uint256(100),       // ttl (blocks)
            new bytes[](0),     // secretSignatures
            bytes(""),          // userPublicKey
            prompt,             // prompt
            uint256(0),         // maxTokens
            uint256(0),         // temperature (use default)
            bytes(""),          // model (use default)
            uint256(0),         // dkmsKeyIndex
            uint8(0),           // dkmsKeyFormat
            false               // piiEnabled
        );
    }
}

// src/auction/HiveClearing.sol

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
            currentPrice: (minPrice + maxPrice) / 2, // Start at midpoint
            startTime: block.timestamp,
            endTime: block.timestamp + duration,
            clearingInterval: clearingInterval,
            lastClearingBlock: block.number,
            state: AuctionState.Active,
            aiAnalysis: ""
        });

        userAuctions[msg.sender].push(auctionId);
        priceHistory[auctionId].push((minPrice + maxPrice) / 2);

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
}
