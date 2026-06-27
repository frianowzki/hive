// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/launch/HiveClearing.sol";
import "../src/treasury/HoneyPot.sol";
import "../src/staking/HiveStaking.sol";

contract HiveClearingTest is Test {
    HiveClearing public clearing;
    HoneyPot public honeypot;
    HiveStaking public staking;

    address public owner = address(this);
    address public project = address(0x1);
    address public buyer1 = address(0x2);
    address public buyer2 = address(0x3);
    address public buyer3 = address(0x4);

    address public token;

    function setUp() public {
        staking = new HiveStaking();
        honeypot = new HoneyPot(owner, address(staking));
        clearing = new HiveClearing(owner, address(honeypot));

        // Mock token
        token = address(0x5);

        // Fund buyers
        vm.deal(buyer1, 100 ether);
        vm.deal(buyer2, 50 ether);
        vm.deal(buyer3, 200 ether);
    }

    // ═══ Auction Lifecycle Tests ═══

    function testCreateAuction() public {
        uint256 auctionId = clearing.createAuction(
            token,
            1_000_000 ether,  // token supply
            0.01 ether,       // min price
            1 ether,          // max price
            block.timestamp + 1 days,  // start
            block.timestamp + 3 days,  // end
            10 ether          // soft cap
        );

        HiveClearing.Auction memory auction = clearing.getAuction(auctionId);
        assertEq(auction.token, token);
        assertEq(auction.tokenSupply, 1_000_000 ether);
        assertEq(auction.minPrice, 0.01 ether);
        assertEq(auction.maxPrice, 1 ether);
        assertEq(auction.softCap, 10 ether);
        assertFalse(auction.finalized);
    }

    function testPlaceBid() public {
        uint256 auctionId = _createActiveAuction();

        vm.prank(buyer1);
        clearing.placeBid{value: 5 ether}(auctionId);

        uint256 bidAmount = clearing.getBid(auctionId, buyer1);
        assertEq(bidAmount, 5 ether);
    }

    function testMultipleBids() public {
        uint256 auctionId = _createActiveAuction();

        vm.prank(buyer1);
        clearing.placeBid{value: 5 ether}(auctionId);

        vm.prank(buyer2);
        clearing.placeBid{value: 3 ether}(auctionId);

        vm.prank(buyer1);
        clearing.placeBid{value: 2 ether}(auctionId); // additional

        assertEq(clearing.getBid(auctionId, buyer1), 7 ether);
        assertEq(clearing.getBid(auctionId, buyer2), 3 ether);
        assertEq(clearing.getTotalRaised(auctionId), 10 ether);
    }

    function testBidBeforeStart() public {
        uint256 auctionId = clearing.createAuction(
            token, 1_000_000 ether, 0.01 ether, 1 ether,
            block.timestamp + 1 days, block.timestamp + 3 days, 10 ether
        );

        vm.prank(buyer1);
        vm.expectRevert("Clearing: not active");
        clearing.placeBid{value: 5 ether}(auctionId);
    }

    function testBidAfterEnd() public {
        uint256 auctionId = _createActiveAuction();

        vm.warp(block.timestamp + 4 days);

        vm.prank(buyer1);
        vm.expectRevert("Clearing: ended");
        clearing.placeBid{value: 5 ether}(auctionId);
    }

    // ═══ Finalization Tests ═══

    function testFinalizeWithSoftCapMet() public {
        uint256 auctionId = _createActiveAuction();

        // Place bids exceeding soft cap
        vm.prank(buyer1);
        clearing.placeBid{value: 5 ether}(auctionId);
        vm.prank(buyer2);
        clearing.placeBid{value: 3 ether}(auctionId);
        vm.prank(buyer3);
        clearing.placeBid{value: 7 ether}(auctionId);

        // Warp past end
        vm.warp(block.timestamp + 4 days);

        // Finalize (normally called by oracle/LLM)
        clearing.finalize(auctionId, 0.05 ether); // clearing price = 0.05 RITUAL per token

        HiveClearing.Auction memory auction = clearing.getAuction(auctionId);
        assertTrue(auction.finalized);
        assertEq(auction.clearingPrice, 0.05 ether);
    }

    function testFinalizeWithSoftCapNotMet() public {
        uint256 auctionId = _createActiveAuction();

        // Place bids below soft cap
        vm.prank(buyer1);
        clearing.placeBid{value: 3 ether}(auctionId);

        vm.warp(block.timestamp + 4 days);

        clearing.finalize(auctionId, 0.01 ether);

        HiveClearing.Auction memory auction = clearing.getAuction(auctionId);
        assertTrue(auction.finalized);
        assertTrue(auction.refundMode); // soft cap not met → refund mode
    }

    // ═══ Claim Tests ═══

    function testClaimTokens() public {
        uint256 auctionId = _createAndFinalizeAuction();

        // buyer1 bid 5 ETH at clearing price 0.05 ETH/token
        // Should get 5/0.05 = 100 tokens
        vm.prank(buyer1);
        clearing.claim(auctionId);

        // Check token balance (mock — just check event)
        // In real impl, token.transfer would be called
    }

    function testClaimRefund() public {
        uint256 auctionId = _createAndFinalizeAuctionRefund();

        uint256 balBefore = buyer1.balance;
        vm.prank(buyer1);
        clearing.claimRefund(auctionId);
        uint256 balAfter = buyer1.balance;

        assertEq(balAfter - balBefore, 5 ether); // full refund
    }

    // ═══ Fee Tests ═══

    function testFeesSentToHoneypot() public {
        uint256 auctionId = _createAndFinalizeAuction();

        uint256 honeypotBefore = address(honeypot).balance;

        // buyer1 claims
        vm.prank(buyer1);
        clearing.claim(auctionId);

        uint256 honeypotAfter = address(honeypot).balance;

        // Fee should be sent to honeypot
        // (exact amount depends on fee bps)
        assertTrue(honeypotAfter > honeypotBefore);
    }

    // ═══ Helpers ═══

    function _createActiveAuction() internal returns (uint256) {
        return clearing.createAuction(
            token, 1_000_000 ether, 0.01 ether, 1 ether,
            block.timestamp, block.timestamp + 3 days, 10 ether
        );
    }

    function _createAndFinalizeAuction() internal returns (uint256) {
        uint256 auctionId = _createActiveAuction();

        vm.prank(buyer1);
        clearing.placeBid{value: 5 ether}(auctionId);
        vm.prank(buyer2);
        clearing.placeBid{value: 3 ether}(auctionId);
        vm.prank(buyer3);
        clearing.placeBid{value: 7 ether}(auctionId);

        vm.warp(block.timestamp + 4 days);
        clearing.finalize(auctionId, 0.05 ether);

        return auctionId;
    }

    function _createAndFinalizeAuctionRefund() internal returns (uint256) {
        uint256 auctionId = _createActiveAuction();

        vm.prank(buyer1);
        clearing.placeBid{value: 5 ether}(auctionId);

        vm.warp(block.timestamp + 4 days);
        clearing.finalize(auctionId, 0.01 ether);

        return auctionId;
    }
}
