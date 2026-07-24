// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/HiveAgentToken.sol";
import "../src/HiveBondingCurve.sol";
import "../src/HiveFactory.sol";

/// @title HiveForkTest - Fork tests against live Ritual Chain (1979)
/// @notice All tests use real chain state - no mocks
contract HiveForkTest is Test {
    // --- Ritual System Addresses ---
    address constant RITUAL_WALLET = 0x532F0dF0896F353d8C3DD8cc134e8129DA2a3948;
    address constant ASYNC_JOB_TRACKER = 0xC069FFCa0389f44eCA2C626e55491b0ab045AEF5;
    address constant TEE_SERVICE_REGISTRY = 0x9644e8562cE0Fe12b4deeC4163c064A8862Bf47F;
    address constant ASYNC_DELIVERY = 0x5A16214fF555848411544b005f7Ac063742f39F6;

    // --- Contracts ---
    HiveFactory factory;
    HiveAgentToken token;
    HiveBondingCurve curve;

    // --- Test Accounts ---
    address deployer = makeAddr("deployer");
    address user1 = makeAddr("user1");
    address user2 = makeAddr("user2");
    address platformTreasury = makeAddr("platformTreasury");

    function setUp() public {
        // Fork is provided via --fork-url CLI flag
        // No need for vm.createSelectFork here

        // Deploy factory
        vm.prank(deployer);
        factory = new HiveFactory(platformTreasury, address(0));
    }

    // ==========================================
    // SYSTEM CONTRACT VALIDATION
    // ==========================================

    function test_RitualWalletExists() public {
        uint256 codeSize;
        assembly {
            codeSize := extcodesize(RITUAL_WALLET)
        }
        assertTrue(codeSize > 0, "RitualWallet has no code");
        console.log("RitualWallet code size:", codeSize);
    }

    function test_AsyncJobTrackerExists() public {
        uint256 codeSize;
        assembly {
            codeSize := extcodesize(ASYNC_JOB_TRACKER)
        }
        assertTrue(codeSize > 0, "AsyncJobTracker has no code");
        console.log("AsyncJobTracker code size:", codeSize);
    }

    function test_TEEServiceRegistryExists() public {
        uint256 codeSize;
        assembly {
            codeSize := extcodesize(TEE_SERVICE_REGISTRY)
        }
        assertTrue(codeSize > 0, "TEEServiceRegistry has no code");
        console.log("TEEServiceRegistry code size:", codeSize);

        // Query LLM executors (capability = 1) - lenient on testnet
        (bool ok, bytes memory result) = TEE_SERVICE_REGISTRY.staticcall(
            abi.encodeWithSignature("getServicesByCapability(uint8,bool)", uint8(1), false)
        );
        if (ok) {
            uint256 length;
            assembly {
                length := mload(add(result, 32))
            }
            console.log("LLM executors available:", length);
        } else {
            console.log("TEE Registry query failed (testnet registration may not be active)");
        }
    }

    function test_AsyncDeliveryExists() public {
        uint256 codeSize;
        assembly {
            codeSize := extcodesize(ASYNC_DELIVERY)
        }
        assertTrue(codeSize > 0, "AsyncDelivery has no code");
        console.log("AsyncDelivery code size:", codeSize);
    }

    // ==========================================
    // HIVEFACTORY DEPLOYMENT
    // ==========================================

    function test_FactoryDeployment() public {
        assertEq(factory.owner(), deployer);
        assertEq(factory.platformTreasury(), platformTreasury);
        assertEq(factory.launchCount(), 0);
    }

    function test_FactoryHasCorrectPrecompileAddresses() public {
        assertEq(factory.SOVEREIGN_AGENT_PRECOMPILE(), 0x000000000000000000000000000000000000080C);
        assertEq(factory.ASYNC_DELIVERY(), ASYNC_DELIVERY);
        assertEq(factory.RITUAL_WALLET(), RITUAL_WALLET);
    }

    // ==========================================
    // TOKEN DEPLOYMENT (without LLM)
    // ==========================================

    function test_TokenDeployment() public {
        vm.prank(deployer);
        HiveAgentToken t = new HiveAgentToken("Test Token", "TEST", "A test lore", deployer);

        assertEq(t.name(), "Test Token");
        assertEq(t.symbol(), "TEST");
        assertEq(t.lore(), "A test lore");
        assertEq(t.factory(), deployer);
        assertEq(uint256(t.agentStatus()), uint256(HiveAgentToken.AgentStatus.Minting));
    }

    function test_TokenMint() public {
        vm.startPrank(deployer);
        HiveAgentToken t = new HiveAgentToken("Test", "TST", "lore", deployer);
        t.mint(user1, 1000e18);
        vm.stopPrank();
        assertEq(t.balanceOf(user1), 1000e18);
        assertEq(t.totalSupply(), 1000e18);
    }

    function test_TokenOnlyFactoryCanMint() public {
        vm.prank(deployer);
        HiveAgentToken t = new HiveAgentToken("Test", "TST", "lore", deployer);

        vm.prank(user1);
        vm.expectRevert("not factory");
        t.mint(user1, 1000e18);
    }

    function test_TokenSetLore() public {
        vm.startPrank(deployer);
        HiveAgentToken t = new HiveAgentToken("Test", "TST", "old lore", deployer);
        t.setLore("new lore");
        vm.stopPrank();
        assertEq(t.lore(), "new lore");
    }

    function test_TokenSetStatus() public {
        vm.startPrank(deployer);
        HiveAgentToken t = new HiveAgentToken("Test", "TST", "lore", deployer);
        t.setStatus(HiveAgentToken.AgentStatus.Launched);
        vm.stopPrank();
        assertEq(uint256(t.agentStatus()), uint256(HiveAgentToken.AgentStatus.Launched));
    }

    // ==========================================
    // BONDING CURVE MATH
    // ==========================================

    function test_BondingCurveDeployment() public {
        vm.prank(deployer);
        HiveAgentToken t = new HiveAgentToken("Test", "TST", "lore", deployer);

        vm.prank(deployer);
        HiveBondingCurve c = new HiveBondingCurve(
            address(t),
            deployer,
            platformTreasury,
            makeAddr("agentTreasury"),
            address(0), // dexRouter
            5 ether,
            1_000_000_000e18, 0.1 ether
        );

        assertEq(c.virtualRitualReserve(), 5 ether);
        assertEq(c.virtualTokenReserve(), 1_000_000_000e18);
        assertEq(c.getCurrentPrice(), 5e18 * 1e18 / 1_000_000_000e18); // 0.000000005 RITUAL per token
    }

    function test_CalculateBuy() public {
        vm.prank(deployer);
        HiveBondingCurve c = new HiveBondingCurve(
            makeAddr("token"),
            deployer,
            platformTreasury,
            makeAddr("agentTreasury"),
            address(0), // dexRouter
            5 ether,
            1_000_000_000e18, 0.1 ether
        );

        // Buy with 1 RITUAL
        (uint256 tokensOut, uint256 fee) = c.calculateBuy(1 ether);

        // Fee = 7% of 1 RITUAL = 0.07 RITUAL
        assertEq(fee, 70000000000000000); // 0.07 ether

        // tokensOut = (0.93 ether * 1e9 * 1e18) / (5 ether + 0.93 ether)
        // 0.93 ether = 930000000000000000
        uint256 ritualAfterFee = 1 ether - fee; // 930000000000000000
        uint256 expectedTokens = (ritualAfterFee * 1_000_000_000e18) / (5 ether + ritualAfterFee);
        assertEq(tokensOut, expectedTokens);

        console.log("Tokens for 1 RITUAL:", tokensOut / 1e18);
        console.log("Fee:", fee / 1e18);
    }

    function test_CalculateSell() public {
        vm.prank(deployer);
        HiveBondingCurve c = new HiveBondingCurve(
            makeAddr("token"),
            deployer,
            platformTreasury,
            makeAddr("agentTreasury"),
            address(0), // dexRouter
            5 ether,
            1_000_000_000e18, 0.1 ether
        );

        // Sell 100M tokens
        uint256 tokensIn = 100_000_000e18;
        (uint256 ritualOut, uint256 fee) = c.calculateSell(tokensIn);

        // ritualOut = (100M * 5e18) / (1e9 + 100M) - fee
        uint256 grossRitual = (tokensIn * 5 ether) / (1_000_000_000e18 + tokensIn);
        uint256 expectedFee = (grossRitual * 700) / 10_000;
        uint256 expectedRitual = grossRitual - expectedFee;

        assertEq(fee, expectedFee);
        assertEq(ritualOut, expectedRitual);

        console.log("RITUAL for 100M tokens:", ritualOut / 1e18);
        console.log("Fee:", fee / 1e18);
    }

    function test_BuyIncreasesPrice() public {
        vm.prank(deployer);
        HiveBondingCurve c = new HiveBondingCurve(
            makeAddr("token"),
            deployer,
            platformTreasury,
            makeAddr("agentTreasury"),
            address(0), // dexRouter
            5 ether,
            1_000_000_000e18, 0.1 ether
        );

        uint256 priceBefore = c.getCurrentPrice();

        // Simulate a buy by updating reserves directly (since we can't actually buy without token transfers)
        // Just test the math: after buying, price should be higher
        (uint256 tokensOut, uint256 fee) = c.calculateBuy(1 ether);

        // Simulate state change
        // virtualRitualReserve += (ritualIn - fee)
        // virtualTokenReserve -= tokensOut
        uint256 newVirtualRitual = 5 ether + (1 ether - fee);
        uint256 newVirtualToken = 1_000_000_000e18 - tokensOut;
        uint256 priceAfter = (newVirtualRitual * 1e18) / newVirtualToken;

        assertTrue(priceAfter > priceBefore, "Price should increase after buy");
        console.log("Price before:", priceBefore);
        console.log("Price after:", priceAfter);
    }

    // ==========================================
    // LLM PRECOMPILE QUERY (read-only)
    // ==========================================

    function test_QueryLLMExecutor() public {
        // Query TEEServiceRegistry for LLM executors
        (bool ok, bytes memory result) = TEE_SERVICE_REGISTRY.staticcall(
            abi.encodeWithSignature("getServicesByCapability(uint8,bool)", uint8(1), false)
        );
        if (ok) {
            uint256 length;
            assembly {
                length := mload(add(result, 32))
            }
            console.log("LLM executors found:", length);
        } else {
            console.log("LLM executor query failed (testnet registration may not be active)");
        }
    }

    function test_QueryHTTPExecutor() public {
        (bool ok, bytes memory result) = TEE_SERVICE_REGISTRY.staticcall(
            abi.encodeWithSignature("getServicesByCapability(uint8,bool)", uint8(0), false)
        );
        if (ok) {
            uint256 length;
            assembly {
                length := mload(add(result, 32))
            }
            console.log("HTTP executors found:", length);
        } else {
            console.log("HTTP executor query failed (testnet registration may not be active)");
        }
    }

    // ==========================================
    // RITUAL WALLET INTERACTION
    // ==========================================

    function test_WalletDepositAndBalance() public {
        // Deposit RITUAL to RitualWallet
        vm.deal(user1, 10 ether);

        vm.prank(user1);
        (bool ok,) = RITUAL_WALLET.call{value: 1 ether}(
            abi.encodeWithSignature("deposit(uint256)", 5000) // lock 5000 blocks
        );
        assertTrue(ok, "Deposit failed");

        // Check balance
        (bool ok2, bytes memory result) = RITUAL_WALLET.staticcall(
            abi.encodeWithSignature("balanceOf(address)", user1)
        );
        assertTrue(ok2, "Balance query failed");

        uint256 balance = abi.decode(result, (uint256));
        assertTrue(balance >= 1 ether, "Balance should be >= 1 ether");

        console.log("Wallet balance:", balance / 1e18, "RITUAL");
    }

    // ==========================================
    // INTEGRATION: FACTORY → TOKEN → CURVE
    // ==========================================

    function test_FullLaunchFlow() public {
        // Deposit RITUAL for factory deployer
        vm.deal(deployer, 10 ether);

        // Create agent (this will also attempt LLM call)
        vm.prank(deployer);
        uint256 launchId = factory.createAgent("A chaotic-good cat wizard", 0.1 ether);

        // Verify launch was created
        assertEq(factory.launchCount(), 1);

        (address tokenAddr, address curveAddr,, , string memory prompt, bool metadataSet,,) = factory.getLaunch(launchId);

        assertTrue(tokenAddr != address(0), "Token should be deployed");
        assertTrue(curveAddr != address(0), "Curve should be deployed");
        assertEq(prompt, "A chaotic-good cat wizard");

        console.log("Token deployed at:", tokenAddr);
        console.log("Curve deployed at:", curveAddr);
        console.log("Metadata set:", metadataSet);
    }

    function test_MultipleLaunches() public {
        vm.deal(deployer, 20 ether);

        vm.prank(deployer);
        uint256 id1 = factory.createAgent("A chaotic cat wizard", 0.1 ether);

        vm.prank(deployer);
        uint256 id2 = factory.createAgent("A degen frog on ETH", 0.1 ether);

        assertEq(factory.launchCount(), 2);

        (address t1,,, , , ,,) = factory.getLaunch(id1);
        (address t2,,, , , ,,) = factory.getLaunch(id2);

        assertTrue(t1 != t2, "Each launch should have unique token");
    }

    // ==========================================
    // CALLBACK AUTH TEST
    // ==========================================

    function test_CallbackRevertsIfNotDelivery() public {
        vm.prank(user1);
        vm.expectRevert("only async delivery");
        factory.onSovereignAgentResult(keccak256("test"), "");
    }

    function test_CallbackAcceptsFromDelivery() public {
        vm.prank(ASYNC_DELIVERY);
        factory.onSovereignAgentResult(keccak256("test"), "");
        // Should not revert
    }

    // ==========================================
    // EDGE CASES
    // ==========================================

    function test_EmptyPromptReverts() public {
        vm.deal(deployer, 10 ether);
        vm.prank(deployer);
        vm.expectRevert("empty prompt");
        factory.createAgent("", 0.1 ether);
    }

    function test_BondingCurveZeroAmountBuy() public {
        vm.prank(deployer);
        HiveBondingCurve c = new HiveBondingCurve(
            makeAddr("token"),
            deployer,
            platformTreasury,
            makeAddr("agentTreasury"),
            address(0), // dexRouter
            5 ether,
            1_000_000_000e18, 0.1 ether
        );

        (uint256 tokensOut, uint256 fee) = c.calculateBuy(0);
        assertEq(tokensOut, 0);
        assertEq(fee, 0);
    }

    function test_BondingCurveMaxSupplyCap() public {
        vm.prank(deployer);
        HiveBondingCurve c = new HiveBondingCurve(
            makeAddr("token"),
            deployer,
            platformTreasury,
            makeAddr("agentTreasury"),
            address(0), // dexRouter
            5 ether,
            1_000_000_000e18, 0.1 ether
        );

        // Try to buy more than available
        (uint256 tokensOut, ) = c.calculateBuy(1000 ether);
        // Should be capped at virtualTokenReserve
        assertTrue(tokensOut <= 1_000_000_000e18, "Should not exceed virtual reserve");
    }
}
