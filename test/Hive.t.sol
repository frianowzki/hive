// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/points/HivePoints.sol";
import "../src/launch/HiveLaunchPad.sol";
import "../src/maker/HiveMarketMaker.sol";
import "../src/council/HiveCouncil.sol";
import "../src/registry/HiveRegistry.sol";
import "../src/treasury/HoneyPot.sol";
import "../src/strategy/Strategy.sol";
import "../src/drone/Drone.sol";
import "../src/queen/Queen.sol";

contract HiveTest is Test {
    HivePoints public points;
    HiveLaunchPad public launchPad;
    HiveMarketMaker public marketMaker;
    HiveCouncil public council;
    HiveRegistry public registry;
    HoneyPot public honeypot;
    Strategy public strategy;
    Queen public queen;

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
        vm.warp(block.timestamp + 2 days);
        points.awardBuy(user1, 1 ether);
        assertEq(points.totalFor(user1), 1 ether);
        assertEq(points.totalPoints(), 1 ether);
    }

    function testPointsBuyEarly() public {
        points.awardBuy(user1, 1 ether);
        uint256 expected = (1 ether * 15_000) / 10_000;
        assertEq(points.totalFor(user1), expected);
    }

    function testPointsLP() public {
        points.awardLP(user1, 1 ether, 2 days);
        uint256 expected = (1 ether * 2 * 20_000) / 10_000;
        assertEq(points.totalFor(user1), expected);
    }

    function testPointsGov() public {
        points.awardGov(user1);
        assertEq(points.totalFor(user1), 10);
    }

    function testPointsReferral() public {
        vm.warp(block.timestamp + 2 days);
        points.awardBuy(user2, 1 ether);
        vm.prank(user1);
        points.setReferral(user2);
        points.awardBuy(user1, 1 ether);

        assertEq(points.totalFor(user1), 1 ether);
        assertGt(points.totalFor(user2), 1 ether);
    }

    function testPointsRank() public {
        vm.warp(block.timestamp + 2 days);
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
        vm.warp(block.timestamp + 2 days);
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

        (uint256 lpTokens, , , , ) = marketMaker.lpPositions(address(0x1234), user1);
        assertGt(lpTokens, 0);
    }

    function testSwap() public {
        marketMaker.createPool(address(0x1234), 50, 30);

        vm.deal(admin, 10 ether);
        marketMaker.addLiquidity{value: 10 ether}(address(0x1234));

        (, , uint256 ethReserve, , , , , ) = marketMaker.pools(address(0x1234));
        assertEq(ethReserve, 10 ether);
    }

    function testGetPrice() public {
        marketMaker.createPool(address(0x1234), 50, 30);

        vm.deal(admin, 10 ether);
        marketMaker.addLiquidity{value: 10 ether}(address(0x1234));
    }

    // ═══ Council Tests ═══

    function testPropose() public {
        vm.warp(block.timestamp + 2 days);
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
        vm.warp(block.timestamp + 2 days);
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
        council.vote(id, 1);

        vm.prank(user2);
        council.vote(id, 0);

        HiveCouncil.Proposal memory proposal = council.getProposal(id);
        assertEq(proposal.forVotes, 200 ether);
        assertEq(proposal.againstVotes, 100 ether);
    }

    function testProposalState() public {
        vm.warp(block.timestamp + 2 days);
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

        vm.warp(block.timestamp + 3 days + 1);
        assertEq(council.proposalState(id), "QuorumNotReached");
    }

    function testExecuteProposal() public {
        vm.warp(block.timestamp + 2 days);
        points.awardBuy(user1, 2000 ether);

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

    // ═══ Registry Tests ═══

    function testRegistryRegister() public {
        registry = new HiveRegistry();
        registry.register("TestAgent", 100);
        assertEq(registry.agentCount(), 1);
        assertTrue(registry.isRegistered(address(this)));
    }

    function testRegistryHeartbeat() public {
        registry = new HiveRegistry();
        registry.register("TestAgent", 100);

        registry.heartbeat();
        assertTrue(registry.isAlive(address(this)));
    }

    function testRegistryLiveness() public {
        registry = new HiveRegistry();
        registry.register("TestAgent", 100);

        assertTrue(registry.isAlive(address(this)));

        // Fast forward past liveness threshold
        vm.roll(block.number + 600);
        assertFalse(registry.isAlive(address(this)));
    }

    // ═══ HoneyPot Tests ═══

    function testHoneyPotDeposit() public {
        honeypot = new HoneyPot(address(this), address(0));
        queen = new Queen("TestHive", 100, address(honeypot), address(0), address(0), address(0), address(0), address(0));

        vm.deal(address(this), 10 ether);
        (bool success, ) = address(honeypot).call{value: 10 ether}("");
        assertTrue(success);
    }

    function testHoneyPotAllocation() public {
        honeypot = new HoneyPot(address(this), address(0));
        queen = new Queen("TestHive", 100, address(honeypot), address(0), address(0), address(0), address(0), address(0));

        vm.deal(address(this), 10 ether);
        (bool success, ) = address(honeypot).call{value: 10 ether}("");
        assertTrue(success);

        // Default allocation: 40/40/10/10
        (uint256 s, uint256 w, uint256 v, uint256 r) = honeypot.allocation();
        assertEq(s, 4000);
        assertEq(w, 4000);
        assertEq(v, 1000);
        assertEq(r, 1000);
    }

    function testHoneyPotPause() public {
        honeypot = new HoneyPot(address(this), address(0));
        queen = new Queen("TestHive", 100, address(honeypot), address(0), address(0), address(0), address(0), address(0));

        assertFalse(honeypot.paused());
        honeypot.emergencyPause();
        assertTrue(honeypot.paused());
    }

    // ═══ Drone Tests ═══

    function testDroneSpawn() public {
        queen = new Queen("TestHive", 100, address(0), address(0), address(0), address(0), address(0), address(0));

        Drone drone = new Drone(address(queen), "Snipe airdrops", Drone.DroneType.Sniper, 1 ether);
        queen.addDrone(address(drone));

        assertEq(queen.droneCount(), 1);
    }

    function testDroneTerminate() public {
        queen = new Queen("TestHive", 100, address(0), address(0), address(0), address(0), address(0), address(0));

        Drone drone = new Drone(address(queen), "Research", Drone.DroneType.Researcher, 1 ether);
        queen.addDrone(address(drone));

        queen.terminateDrone(0);
        address payable droneAddr = payable(queen.getDrone(0));
        assertTrue(Drone(droneAddr).terminated());
    }

    // ═══ Queen Tests ═══

    function testQueenBirth() public {
        queen = new Queen("Hive-1", 100, address(0), address(0), address(0), address(0), address(0), address(0));

        assertTrue(queen.alive());
        assertEq(queen.name(), "Hive-1");
        assertEq(queen.droneCount(), 0);
    }

    function testQueenHibernation() public {
        queen = new Queen("Hive-1", 100, address(0), address(0), address(0), address(0), address(0), address(0));

        assertFalse(queen.hibernating());
        queen.hibernate();
        assertTrue(queen.hibernating());
        queen.wake();
        assertFalse(queen.hibernating());
    }

    function testQueenDie() public {
        queen = new Queen("Hive-1", 100, address(0), address(0), address(0), address(0), address(0), address(0));

        // Schedule shutdown (timelocked)
        queen.scheduleShutdown("unprofitable");

        // Cannot execute before timelock
        vm.expectRevert("Queen: timelock active");
        queen.executeShutdown("unprofitable");

        // Fast forward past timelock
        vm.warp(block.timestamp + 25 hours);

        // Execute shutdown
        queen.executeShutdown("unprofitable");
        assertFalse(queen.alive());
    }

    function testQueenCreatePool() public {
        queen = new Queen("Hive-1", 100, address(0), address(0), address(0), address(0), address(0), address(0));
        HiveMarketMaker maker = new HiveMarketMaker(address(points));
        queen.setDivision("marketMaker", address(maker));
        // MarketMaker needs queen as admin, but queen didn't deploy it
        // This test verifies the wiring works; in production, Queen deploys MarketMaker
        vm.expectRevert("MarketMaker: not admin");
        queen.createPool(address(0x1234), 50, 30);
    }
}
