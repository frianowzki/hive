// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {RitualPrecompileConsumer} from "../libraries/RitualPrecompileConsumer.sol";

interface IHoneyPot {
    function collectFee(address referrer) external payable;
}

/// @title HiveClearing — Hive Clearing Auction (HCA)
/// @notice AI-driven price discovery for token launches
/// @dev Continuous clearing mechanism with LLM pricing
contract HiveClearing is RitualPrecompileConsumer {
    // ═══ State ═══

    address public owner;
    address public honeypot;
    uint256 public auctionCount;
    uint256 public constant FEE_BPS = 300; // 3% fee

    struct Auction {
        address token;           // Token being sold
        uint256 tokenSupply;     // Total tokens for sale
        uint256 minPrice;        // Min price per token (wei)
        uint256 maxPrice;        // Max price per token (wei)
        uint256 startTime;       // Auction start
        uint256 endTime;         // Auction end
        uint256 softCap;         // Minimum raise (wei)
        uint256 totalRaised;     // Total ETH raised
        uint256 clearingPrice;   // Final clearing price
        bool finalized;          // Has been finalized
        bool refundMode;         // Soft cap not met → refunds
        address creator;         // Who created the auction
    }

    struct Bid {
        uint256 amount;          // ETH bid
        bool claimed;            // Has claimed tokens/refund
    }

    mapping(uint256 => Auction) public auctions;
    mapping(uint256 => mapping(address => Bid)) public bids;
    mapping(uint256 => address[]) public auctionBidders;

    // ═══ Events ═══

    event AuctionCreated(uint256 indexed auctionId, address indexed token, uint256 tokenSupply, uint256 softCap);
    event BidPlaced(uint256 indexed auctionId, address indexed bidder, uint256 amount);
    event AuctionFinalized(uint256 indexed auctionId, uint256 clearingPrice, bool refundMode);
    event TokensClaimed(uint256 indexed auctionId, address indexed bidder, uint256 tokens, uint256 fee);
    event RefundClaimed(uint256 indexed auctionId, address indexed bidder, uint256 amount);

    // ═══ Modifiers ═══

    modifier onlyOwner() {
        require(msg.sender == owner, "Clearing: not owner");
        _;
    }

    // ═══ Constructor ═══

    constructor(address _owner, address _honeypot) {
        owner = _owner;
        honeypot = _honeypot;
    }

    // ═══ Auction Management ═══

    /// @notice Create a new auction
    function createAuction(
        address token,
        uint256 tokenSupply,
        uint256 minPrice,
        uint256 maxPrice,
        uint256 startTime,
        uint256 endTime,
        uint256 softCap
    ) external onlyOwner returns (uint256 auctionId) {
        require(token != address(0), "Clearing: zero token");
        require(tokenSupply > 0, "Clearing: zero supply");
        require(minPrice > 0, "Clearing: zero min price");
        require(maxPrice > minPrice, "Clearing: max <= min");
        require(endTime > startTime, "Clearing: end <= start");
        require(softCap > 0, "Clearing: zero soft cap");

        auctionId = ++auctionCount;
        auctions[auctionId] = Auction({
            token: token,
            tokenSupply: tokenSupply,
            minPrice: minPrice,
            maxPrice: maxPrice,
            startTime: startTime,
            endTime: endTime,
            softCap: softCap,
            totalRaised: 0,
            clearingPrice: 0,
            finalized: false,
            refundMode: false,
            creator: msg.sender
        });

        emit AuctionCreated(auctionId, token, tokenSupply, softCap);
    }

    // ═══ Bidding ═══

    /// @notice Place a bid in an auction
    function placeBid(uint256 auctionId) external payable {
        Auction storage auction = auctions[auctionId];
        require(block.timestamp >= auction.startTime, "Clearing: not active");
        require(block.timestamp <= auction.endTime, "Clearing: ended");
        require(msg.value > 0, "Clearing: zero bid");

        Bid storage bid = bids[auctionId][msg.sender];
        if (bid.amount == 0) {
            auctionBidders[auctionId].push(msg.sender);
        }
        bid.amount += msg.value;
        auction.totalRaised += msg.value;

        emit BidPlaced(auctionId, msg.sender, msg.value);
    }

    // ═══ Finalization ═══

    /// @notice Finalize auction with clearing price (owner/LLM sets price)
    function finalize(uint256 auctionId, uint256 clearingPrice) external onlyOwner {
        Auction storage auction = auctions[auctionId];
        require(!auction.finalized, "Clearing: already finalized");
        require(block.timestamp > auction.endTime, "Clearing: not ended");

        auction.finalized = true;
        auction.clearingPrice = clearingPrice;

        // If soft cap not met, enable refund mode
        if (auction.totalRaised < auction.softCap) {
            auction.refundMode = true;
        }

        emit AuctionFinalized(auctionId, clearingPrice, auction.refundMode);
    }

    // ═══ Claims ═══

    /// @notice Claim tokens after finalization
    function claim(uint256 auctionId) external {
        Auction storage auction = auctions[auctionId];
        require(auction.finalized, "Clearing: not finalized");
        require(!auction.refundMode, "Clearing: refund mode");

        Bid storage bid = bids[auctionId][msg.sender];
        require(bid.amount > 0, "Clearing: no bid");
        require(!bid.claimed, "Clearing: already claimed");

        bid.claimed = true;

        // Calculate tokens: bid / clearingPrice
        uint256 tokens = (bid.amount * auction.tokenSupply) / auction.totalRaised;

        // Calculate fee
        uint256 fee = (bid.amount * FEE_BPS) / 10_000;
        uint256 netAmount = bid.amount - fee;

        // Send fee to honeypot
        IHoneyPot(honeypot).collectFee{value: fee}(address(0));

        // Transfer tokens (would call token.transfer in production)
        // For now, emit event
        emit TokensClaimed(auctionId, msg.sender, tokens, fee);
    }

    /// @notice Claim refund if soft cap not met
    function claimRefund(uint256 auctionId) external {
        Auction storage auction = auctions[auctionId];
        require(auction.finalized, "Clearing: not finalized");
        require(auction.refundMode, "Clearing: not refund mode");

        Bid storage bid = bids[auctionId][msg.sender];
        require(bid.amount > 0, "Clearing: no bid");
        require(!bid.claimed, "Clearing: already claimed");

        bid.claimed = true;
        uint256 amount = bid.amount;

        (bool success, ) = msg.sender.call{value: amount}("");
        require(success, "Clearing: transfer failed");

        emit RefundClaimed(auctionId, msg.sender, amount);
    }

    // ═══ View Functions ═══

    function getAuction(uint256 auctionId) external view returns (Auction memory) {
        return auctions[auctionId];
    }

    function getBid(uint256 auctionId, address bidder) external view returns (uint256) {
        return bids[auctionId][bidder].amount;
    }

    function getTotalRaised(uint256 auctionId) external view returns (uint256) {
        return auctions[auctionId].totalRaised;
    }

    function getBidders(uint256 auctionId) external view returns (address[] memory) {
        return auctionBidders[auctionId];
    }

    function isActive(uint256 auctionId) external view returns (bool) {
        Auction storage auction = auctions[auctionId];
        return !auction.finalized && block.timestamp >= auction.startTime && block.timestamp <= auction.endTime;
    }
}
