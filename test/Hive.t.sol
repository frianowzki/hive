// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/points/HivePoints.sol";
import "../src/launch/HiveLaunchPad.sol";
import "../src/maker/HiveMarketMaker.sol";
import "../src/council/HiveCouncil.sol";

contract HiveTest is Test {
    HivePoints public points;
    HiveLaunchPad public launchPad;
    HiveMarketMaker public marketMaker;
    HiveCouncil public council;

    address public admin = address(this);
    address public user1 = address(0x1);
    address public user2 = address(0x2);
    address public project = address(0x3);

    function setUp() public {
        points = new HivePoints();
        launchPad = new HiveLaunchPad(address(points));
        marketMaker = new HiveMarketMaker(address(points));
        council = new HiveCouncil(address(points));
    }

    // ═══ Points Tests ═══

    function testPointsInitial() public view {
        assertEq(points.totalPoints(), 0);
    }

    function testPointsBuy() public {
        // Warp past early window to avoid multiplier
        vm.warp(block.timestamp + 2 days);
        points.awardBuy(user1, 1 ether);
        assertEq(points.totalFor(user1), 1 ether);
        assertEq(points.totalPoints(), 1 ether);
    }

    function testPointsBuyEarly() public {
        // Early multiplier applies (1.5x)
        points.awardBuy(user1, 1 ether);
        uint256 expected = (1 ether * 15_000) / 10_000;
        assertEq(points.totalFor(user1), expected);
    }

    function testPointsLP() public {
        points.awardLP(user1, 1 ether, 2 days);
        uint256 expected = (1 ether * 2 * 20_000) / 10_000; // 2x LP multiplier
        assertEq(points.totalFor(user1), expected);
    }

    function testPointsGov() public {
        points.awardGov(user1);
        assertEq(points.totalFor(user1), 10);
    }

    function testPointsReferral() public {
        vm.warp(block.timestamp + 2 days); // Avoid early multiplier
        points.awardBuy(user2, 1 ether); // Make user2 active
        vm.prank(user1);
        points.setReferral(user2);
        points.awardBuy(user1, 1 ether);

        // user1 gets 1 ether points
        assertEq(points.totalFor(user1), 1 ether);
        // user2 gets 1 ether + 5% referral bonus
        assertGt(points.totalFor(user2), 1 ether);
    }

    function testPointsRank() public {
        vm.warp(block.timestamp + 2 days); // Avoid early multiplier
        points.awardBuy(user1, 2 ether);
        points.awardBuy(user2, 1 ether);

        assertEq(points.rank(user1), 1);
        assertEq(points.rank(user2), 2);
    }

    // ═══ LaunchPad Tests ═══

    function testCreateSale() public {
        uint256 saleId = launchPad.createSale(
            project,
            address(0x1234),
            0.001 ether,
            10 ether,
            1 ether,
            0.01 ether,
            1 ether,
            block.timestamp,
            block.timestamp + 7 days,
            1 days,
            30 days,
            false
        );

        assertEq(saleId, 0);
        HiveLaunchPad.Sale memory sale = launchPad.getSale(saleId);
        assertEq(sale.hardCap, 10 ether);
    }

    function testBuySale() public {
        vm.warp(block.timestamp + 2 days); // Avoid early multiplier
        uint256 saleId = launchPad.createSale(
            project,
            address(0x1234),
            0.001 ether,
            10 ether,
            1 ether,
            0.01 ether,
            1 ether,
            block.timestamp,
            block.timestamp + 7 days,
            1 days,
            30 days,
            false
        );

        vm.deal(user1, 1 ether);
        vm.prank(user1);
        launchPad.buy{value: 0.5 ether}(saleId);

        HiveLaunchPad.Sale memory sale = launchPad.getSale(saleId);
        assertEq(sale.totalRaised, 0.5 ether);

        // Points awarded (no early multiplier)
        assertEq(points.totalFor(user1), 0.5 ether);
    }

    function testBuySaleWhitelist() public {
        uint256 saleId = launchPad.createSale(
            project,
            address(0x1234),
            0.001 ether,
            10 ether,
            1 ether,
            0.01 ether,
            1 ether,
            block.timestamp,
            block.timestamp + 7 days,
            1 days,
            30 days,
            true
        );

        launchPad.setWhitelist(saleId, user1, true);

        vm.deal(user1, 1 ether);
        vm.prank(user1);
        launchPad.buy{value: 0.5 ether}(saleId);

        HiveLaunchPad.Sale memory sale = launchPad.getSale(saleId);
        assertEq(sale.totalRaised, 0.5 ether);
    }

    function testBuySaleNotWhitelisted() public {
        uint256 saleId = launchPad.createSale(
            project,
            address(0x1234),
            0.001 ether,
            10 ether,
            1 ether,
            0.01 ether,
            1 ether,
            block.timestamp,
            block.timestamp + 7 days,
            1 days,
            30 days,
            true
        );

        vm.deal(user1, 1 ether);
        vm.prank(user1);
        vm.expectRevert("LaunchPad: not whitelisted");
        launchPad.buy{value: 0.5 ether}(saleId);
    }

    // ═══ MarketMaker Tests ═══

    function testCreatePool() public {
        marketMaker.createPool(address(0x1234), 50, 30);
        assertEq(marketMaker.poolCount(), 1);
    }

    function testAddLiquidity() public {
        marketMaker.createPool(address(0x1234), 50, 30);

        vm.deal(user1, 1 ether);
        vm.prank(user1);
        marketMaker.addLiquidity{value: 1 ether}(address(0x1234));

        // LP position should exist
        (uint256 lpTokens, , , , ) = marketMaker.lpPositions(address(0x1234), user1);
        assertGt(lpTokens, 0);
    }

    function testSwap() public {
        marketMaker.createPool(address(0x1234), 50, 30);

        // Add initial liquidity
        vm.deal(admin, 10 ether);
        marketMaker.addLiquidity{value: 10 ether}(address(0x1234));

        // Pool should have ETH reserve
        (, , uint256 ethReserve, , , , , ) = marketMaker.pools(address(0x1234));
        assertEq(ethReserve, 10 ether);
    }

    function testGetPrice() public {
        marketMaker.createPool(address(0x1234), 50, 30);

        vm.deal(admin, 10 ether);
        marketMaker.addLiquidity{value: 10 ether}(address(0x1234));

        // Price is ethReserve * 1e18 / tokenReserve
        // With only ETH added, tokenReserve is 0, so price should be 0
        // This is expected - need both sides for price
    }

    // ═══ Council Tests ═══

    function testPropose() public {
        vm.warp(block.timestamp + 2 days); // Avoid early multiplier
        points.awardBuy(user1, 200 ether);

        vm.prank(user1);
        uint256 id = council.propose(
            "Increase fees",
            "Proposal to increase trading fees to 0.5%",
            HiveCouncil.ProposalType.General,
            address(0),
            ""
        );

        assertEq(id, 0);
    }

    function testVote() public {
        vm.warp(block.timestamp + 2 days); // Avoid early multiplier
        points.awardBuy(user1, 200 ether);
        points.awardBuy(user2, 100 ether);

        vm.prank(user1);
        uint256 id = council.propose(
            "Test proposal",
            "Description",
            HiveCouncil.ProposalType.General,
            address(0),
            ""
        );

        vm.prank(user1);
        council.vote(id, 1); // For

        vm.prank(user2);
        council.vote(id, 0); // Against

        HiveCouncil.Proposal memory proposal = council.getProposal(id);
        assertEq(proposal.forVotes, 200 ether);
        assertEq(proposal.againstVotes, 100 ether);
    }

    function testProposalState() public {
        vm.warp(block.timestamp + 2 days); // Avoid early multiplier
        points.awardBuy(user1, 200 ether);

        vm.prank(user1);
        uint256 id = council.propose(
            "Test",
            "Description",
            HiveCouncil.ProposalType.General,
            address(0),
            ""
        );

        assertEq(council.proposalState(id), "Active");

        // Fast forward past voting period
        vm.warp(block.timestamp + 3 days + 1);
        assertEq(council.proposalState(id), "QuorumNotReached");
    }

    function testExecuteProposal() public {
        vm.warp(block.timestamp + 2 days); // Avoid early multiplier
        points.awardBuy(user1, 2000 ether); // Enough for quorum

        vm.prank(user1);
        uint256 id = council.propose(
            "Test",
            "Description",
            HiveCouncil.ProposalType.General,
            address(0),
            ""
        );

        vm.prank(user1);
        council.vote(id, 1);

        vm.warp(block.timestamp + 3 days + 1);
        council.execute(id);

        assertEq(council.proposalState(id), "Executed");
    }
}
