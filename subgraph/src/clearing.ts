import { BigInt, Bytes } from "@graphprotocol/graph-ts";
import {
  AuctionCreated,
  BidPlaced,
  PriceUpdated,
  AuctionSettled,
  BidRefunded,
  AuctionCancelled
} from "../generated/HiveClearing/HiveClearing";
import {
  Auction,
  Bid,
  AuctionBidder,
  PriceSnapshot
} from "../generated/schema";

export function handleAuctionCreated(event: AuctionCreated): void {
  let auction = new Auction(event.params.auctionId.toString());
  auction.auctionId = event.params.auctionId;
  auction.creator = event.params.creator;
  auction.token = event.params.token;
  auction.state = "ACTIVE";
  auction.totalBidAmount = BigInt.fromI32(0);
  auction.createdAt = event.block.timestamp;
  auction.save();
}

export function handleBidPlaced(event: BidPlaced): void {
  let bidId = event.params.auctionId.toString() + "-" + event.params.bidder.toHex() + "-" + event.block.timestamp.toString();
  let bid = new Bid(bidId);
  bid.auction = event.params.auctionId.toString();
  bid.bidder = event.params.bidder;
  bid.amount = event.params.amount;
  bid.maxPrice = event.params.maxPrice;
  bid.timestamp = event.block.timestamp;
  bid.filled = false;
  bid.refunded = false;
  bid.save();

  // Update auction total bid
  let auction = Auction.load(event.params.auctionId.toString());
  if (auction) {
    auction.totalBidAmount = auction.totalBidAmount.plus(event.params.amount);
    auction.save();
  }

  // Update or create bidder record
  let bidderId = event.params.auctionId.toString() + "-" + event.params.bidder.toHex();
  let bidder = AuctionBidder.load(bidderId);
  if (!bidder) {
    bidder = new AuctionBidder(bidderId);
    bidder.auction = event.params.auctionId.toString();
    bidder.bidder = event.params.bidder;
    bidder.totalBid = BigInt.fromI32(0);
    bidder.bidCount = BigInt.fromI32(0);
  }
  bidder.totalBid = bidder.totalBid.plus(event.params.amount);
  bidder.bidCount = bidder.bidCount.plus(BigInt.fromI32(1));
  bidder.save();
}

export function handlePriceUpdated(event: PriceUpdated): void {
  let snapshotId = event.params.auctionId.toString() + "-" + event.block.timestamp.toString();
  let snapshot = new PriceSnapshot(snapshotId);
  snapshot.auction = event.params.auctionId.toString();
  snapshot.price = event.params.newPrice;
  snapshot.blockNumber = event.block.number;
  snapshot.timestamp = event.block.timestamp;
  snapshot.save();

  // Update auction current price
  let auction = Auction.load(event.params.auctionId.toString());
  if (auction) {
    auction.currentPrice = event.params.newPrice;
    auction.aiAnalysis = event.params.aiReasoning;
    auction.save();
  }
}

export function handleAuctionSettled(event: AuctionSettled): void {
  let auction = Auction.load(event.params.auctionId.toString());
  if (auction) {
    auction.state = "SETTLED";
    auction.soldAmount = event.params.totalSold;
    auction.settledAt = event.block.timestamp;
    auction.save();
  }
}

export function handleBidRefunded(event: BidRefunded): void {
  // Mark bid as refunded
  // Note: In production, we'd need to track bid IDs more carefully
}

export function handleAuctionCancelled(event: AuctionCancelled): void {
  let auction = Auction.load(event.params.auctionId.toString());
  if (auction) {
    auction.state = "CANCELLED";
    auction.save();
  }
}
