// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "forge-std/Test.sol";
import "../src/agent/HiveAgentFactory.sol";

contract HiveAgentFactoryTest is Test {
    HiveAgentFactory factory;

    address owner = address(0x1);
    address treasury = address(0x2);
    address user1 = address(0xA1);
    address user2 = address(0xA2);

    function setUp() public { vm.deal(address(this), 100 ether);
        vm.deal(user1, 10 ether);
        vm.deal(user2, 10 ether);
        vm.prank(owner);
        factory = new HiveAgentFactory(treasury, 0.01 ether);
    }

    function test_summonAgent_basic() public {
        vm.prank(user1);
        (address agent, address governor) = factory.summonAgent{value: 0.01 ether}(
            "MyTrader",
            "market-maker",
            "You are a conservative trader. Max 5% per trade.",
            50
        );

        assertTrue(agent != address(0));
        assertTrue(governor != address(0));
        assertEq(factory.totalAgents(), 1);
        assertEq(factory.getUserAgentCount(user1), 1);
    }

    function test_summonAgent_insufficientFee() public {
        vm.prank(user1);
        vm.expectRevert();
        factory.summonAgent{value: 0.001 ether}(
            "CheapBot",
            "market-maker",
            "soul",
            50
        );
    }

    function test_summonAgent_freeTier() public {
        vm.prank(owner);
        factory.enableFreeTier(true);

        vm.prank(user1);
        (address agent, ) = factory.summonAgent{value: 0}(
            "FreeBot",
            "test",
            "soul",
            50
        );

        assertTrue(agent != address(0));

        // Second attempt should fail (free tier used)
        vm.prank(user1);
        vm.expectRevert();
        factory.summonAgent{value: 0}(
            "FreeBot2",
            "test",
            "soul",
            50
        );
    }

    function test_summonAgent_multipleUsers() public {
        vm.prank(user1);
        factory.summonAgent{value: 0.01 ether}("Bot1", "maker", "soul1", 50);

        vm.prank(user2);
        factory.summonAgent{value: 0.01 ether}("Bot2", "staking", "soul2", 100);

        assertEq(factory.totalAgents(), 2);
        assertEq(factory.getUserAgentCount(user1), 1);
        assertEq(factory.getUserAgentCount(user2), 1);
    }

    function test_summonAgent_customLimits() public {
        vm.prank(user1);
        (address agent, address governor) = factory.summonAgentCustom{value: 0.02 ether}(
            "ProBot",
            "market-maker",
            "soul",
            30,
            1 ether,    // perTxMax
            100 ether,  // dailyMax
            100,        // maxTxPerHour
            1000000     // maxGasPerTx
        );

        assertTrue(agent != address(0));
        assertTrue(governor != address(0));
    }

    function test_deactivateAgent() public {
        vm.prank(user1);
        (address agent, ) = factory.summonAgent{value: 0.01 ether}("Bot", "maker", "soul", 50);

        vm.prank(user1);
        factory.deactivateAgent(payable(agent));

        (, , , bool active, ) = factory.getAgentInfo(agent);
        assertFalse(active);
    }

    function test_deactivateAgent_notOwner() public {
        vm.prank(user1);
        (address agent, ) = factory.summonAgent{value: 0.01 ether}("Bot", "maker", "soul", 50);

        vm.prank(user2);
        vm.expectRevert(HiveAgentFactory.NotAgentOwner.selector);
        factory.deactivateAgent(payable(agent));
    }

    function test_feeForwardedToTreasury() public {
        uint256 treasuryBefore = treasury.balance;

        vm.prank(user1);
        factory.summonAgent{value: 0.01 ether}("Bot", "maker", "soul", 50);

        assertEq(treasury.balance, treasuryBefore + 0.01 ether);
    }

    function test_getAllAgents() public {
        vm.prank(user1);
        factory.summonAgent{value: 0.01 ether}("Bot1", "maker", "soul", 50);

        vm.prank(user2);
        factory.summonAgent{value: 0.01 ether}("Bot2", "staking", "soul", 100);

        address[] memory agents = factory.getAllAgents(0, 10);
        assertEq(agents.length, 2);
    }

    function test_getUserAgents() public {
        vm.startPrank(user1);
        factory.summonAgent{value: 0.01 ether}("Bot1", "maker", "soul", 50);
        factory.summonAgent{value: 0.01 ether}("Bot2", "staking", "soul", 100);
        vm.stopPrank();

        HiveAgentFactory.UserAgent[] memory agents = factory.getUserAgents(user1);
        assertEq(agents.length, 2);
        assertTrue(agents[0].active);
        assertTrue(agents[1].active);
    }

    function test_updateDefaults() public {
        vm.prank(owner);
        factory.setDefaults(0.5 ether, 50 ether, 50);

        // New agents should use new defaults
        vm.prank(user1);
        (address agent, address governor) = factory.summonAgent{value: 0.01 ether}(
            "Bot", "maker", "soul", 50
        );

        // Verify governor was created (defaults applied internally)
        assertTrue(governor != address(0));
    }
}
