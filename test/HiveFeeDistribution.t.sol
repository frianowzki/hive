// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/treasury/HoneyPot.sol";
import "../src/staking/HiveStaking.sol";

contract HiveFeeDistributionTest is Test {
    HoneyPot public honeypot;
    HiveStaking public staking;

    address public queen = address(this);
    address public user1 = address(0x1);
    address public user2 = address(0x2);
    address public referrer = address(0x3);
    address public feeSource = address(0x4);

    function setUp() public {
        staking = new HiveStaking();
        honeypot = new HoneyPot(queen, address(staking));

        // Fund stakers
        vm.deal(user1, 100 ether);
        vm.deal(user2, 50 ether);

        // Stake
        vm.prank(user1);
        staking.stake{value: 100 ether}(LOCK_30D);

        vm.prank(user2);
        staking.stake{value: 50 ether}(LOCK_7D);
    }

    // ═══ Fee Distribution Tests ═══

    function testFeeDistributionOnDeposit() public {
        // Send 10 ETH as fee
        vm.deal(feeSource, 10 ether);
        vm.prank(feeSource);
        honeypot.collectFee{value: 10 ether}(referrer);

        // Check distribution
        uint256 stakerShare = honeypot.pendingStakerFees();
        uint256 referrerShare = honeypot.pendingReferrerFees(referrer);
        uint256 reserveShare = honeypot.reserveBalance();

        // 60% to stakers, 25% to referrer, 15% to reserve
        assertEq(stakerShare, 6 ether);
        assertEq(referrerShare, 2.5 ether);
        assertEq(reserveShare, 1.5 ether);
    }

    function testStakerRewardProportional() public {
        // user1 has 100 staked, user2 has 50 staked
        // Total staked: 150
        // user1 should get 2/3 of staker share, user2 should get 1/3

        vm.deal(feeSource, 15 ether);
        vm.prank(feeSource);
        honeypot.collectFee{value: 15 ether}(referrer);

        uint256 user1Reward = honeypot.pendingStakerReward(user1);
        uint256 user2Reward = honeypot.pendingStakerReward(user2);

        // 60% of 15 = 9 ETH to stakers
        // user1: 9 * 100/150 = 6 ETH
        // user2: 9 * 50/150 = 3 ETH
        assertEq(user1Reward, 6 ether);
        assertEq(user2Reward, 3 ether);
    }

    function testClaimStakerReward() public {
        vm.deal(feeSource, 15 ether);
        vm.prank(feeSource);
        honeypot.collectFee{value: 15 ether}(referrer);

        uint256 balBefore = user1.balance;
        vm.prank(user1);
        honeypot.claimStakerReward();
        uint256 balAfter = user1.balance;

        assertEq(balAfter - balBefore, 6 ether);
    }

    function testClaimReferrerReward() public {
        vm.deal(feeSource, 10 ether);
        vm.prank(feeSource);
        honeypot.collectFee{value: 10 ether}(referrer);

        uint256 balBefore = referrer.balance;
        vm.prank(referrer);
        honeypot.claimReferrerReward();
        uint256 balAfter = referrer.balance;

        assertEq(balAfter - balBefore, 2.5 ether);
    }

    function testMultipleFeeCollections() public {
        // First collection
        vm.deal(feeSource, 10 ether);
        vm.prank(feeSource);
        honeypot.collectFee{value: 10 ether}(referrer);

        // Second collection
        vm.deal(feeSource, 20 ether);
        vm.prank(feeSource);
        honeypot.collectFee{value: 20 ether}(referrer);

        // Total: 30 ETH
        // Staker share: 18 ETH (60%)
        // user1: 18 * 100/150 = 12 ETH
        uint256 user1Reward = honeypot.pendingStakerReward(user1);
        assertEq(user1Reward, 12 ether);
    }

    function testZeroStakersFeesGoToReserve() public {
        // Unstake everyone
        vm.warp(block.timestamp + 31 days);
        vm.prank(user1);
        staking.unstake(100 ether);
        vm.prank(user2);
        staking.unstake(50 ether);

        // Now send fee
        vm.deal(feeSource, 10 ether);
        vm.prank(feeSource);
        honeypot.collectFee{value: 10 ether}(referrer);

        // With no stakers, staker share (60%) goes to reserve
        // Reserve = 60% + 15% = 75% of 10 = 7.5 ETH
        uint256 reserveShare = honeypot.reserveBalance();
        assertEq(reserveShare, 7.5 ether);

        // Referrer still gets 25%
        uint256 referrerShare = honeypot.pendingReferrerFees(referrer);
        assertEq(referrerShare, 2.5 ether);
    }

    // ═══ Helpers ═══

    uint256 constant LOCK_7D = 7 days;
    uint256 constant LOCK_30D = 30 days;
}
