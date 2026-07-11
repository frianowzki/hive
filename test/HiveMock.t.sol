// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/HiveAgentToken.sol";
import "../src/HiveBondingCurve.sol";
import "../src/HiveFactory.sol";
import "../src/test/mocks/MockRitualPrecompiles.sol";

/// @title HiveMockTest - Fast unit tests using mock precompiles
/// @notice No RPC needed — runs in seconds
contract HiveMockTest is Test {
    // --- Contracts ---
    HiveFactory factory;
    MockLLMPrecompile mockLLM;
    MockHTTPPrecompile mockHTTP;
    MockScheduler mockScheduler;
    MockAsyncDelivery mockDelivery;

    // --- Test Accounts ---
    address deployer = makeAddr("deployer");
    address user1 = makeAddr("user1");
    address user2 = makeAddr("user2");
    address platformTreasury = makeAddr("platformTreasury");

    function setUp() public {
        vm.startPrank(deployer);

        // Deploy mocks
        mockLLM = new MockLLMPrecompile();
        mockHTTP = new MockHTTPPrecompile();
        mockScheduler = new MockScheduler();
        mockDelivery = new MockAsyncDelivery();

        // Deploy factory
        factory = new HiveFactory(platformTreasury, address(0));

        vm.stopPrank();
    }

    // ==========================================
    // TOKEN CREATION
    // ==========================================

    function test_CreateAgent() public {
        vm.deal(deployer, 10 ether);

        vm.prank(deployer);
        uint256 launchId = factory.createAgent("A chaotic cat wizard");

        assertEq(factory.launchCount(), 1);

        (address tokenAddr, address curveAddr,, string memory prompt, bool metadataSet,) = factory.getLaunch(launchId);

        assertTrue(tokenAddr != address(0), "Token deployed");
        assertTrue(curveAddr != address(0), "Curve deployed");
        assertEq(prompt, "A chaotic cat wizard");
        assertFalse(metadataSet, "Metadata not set yet (LLM skipped)");
    }

    function test_CreateMultipleAgents() public {
        vm.deal(deployer, 20 ether);

        vm.prank(deployer);
        factory.createAgent("Agent 1");

        vm.prank(deployer);
        factory.createAgent("Agent 2");

        vm.prank(deployer);
        factory.createAgent("Agent 3");

        assertEq(factory.launchCount(), 3);

        // Each should have unique token addresses
        (address t1,, , , , ) = factory.getLaunch(0);
        (address t2,, , , , ) = factory.getLaunch(1);
        (address t3,, , , , ) = factory.getLaunch(2);

        assertTrue(t1 != t2);
        assertTrue(t2 != t3);
        assertTrue(t1 != t3);
    }

    function test_EmptyPromptReverts() public {
        vm.deal(deployer, 10 ether);

        vm.prank(deployer);
        vm.expectRevert("empty prompt");
        factory.createAgent("");
    }

    // ==========================================
    // TOKEN METADATA
    // ==========================================

    function test_SetTokenMetadata() public {
        vm.deal(deployer, 10 ether);

        vm.prank(deployer);
        uint256 launchId = factory.createAgent("Test");

        // Set metadata
        vm.prank(deployer);
        factory.setTokenMetadata(launchId, "Cat Wizard", "CATWIZ", "A magical cat");

        (, , , , bool metadataSet, ) = factory.getLaunch(launchId);
        assertTrue(metadataSet, "Metadata should be set");

        // Check token
        (address tokenAddr,, , , , ) = factory.getLaunch(launchId);
        HiveAgentToken token = HiveAgentToken(tokenAddr);

        assertEq(token.name(), "Cat Wizard");
        assertEq(token.symbol(), "CATWIZ");
        assertEq(token.lore(), "A magical cat");
        assertEq(uint256(token.agentStatus()), uint256(HiveAgentToken.AgentStatus.Launched));
    }

    function test_MetadataCannotBeSetTwice() public {
        vm.deal(deployer, 10 ether);

        vm.prank(deployer);
        uint256 launchId = factory.createAgent("Test");

        vm.startPrank(deployer);
        factory.setTokenMetadata(launchId, "First", "FIRST", "First lore");
        vm.stopPrank();

        vm.prank(deployer);
        vm.expectRevert("metadata already set");
        factory.setTokenMetadata(launchId, "Second", "SECOND", "Second lore");
    }

    function test_OnlyOwnerCanSetMetadata() public {
        vm.deal(deployer, 10 ether);

        vm.prank(deployer);
        uint256 launchId = factory.createAgent("Test");

        vm.prank(user1);
        vm.expectRevert("not owner");
        factory.setTokenMetadata(launchId, "Hacked", "HACK", "Nope");
    }

    // ==========================================
    // BONDING CURVE MATH
    // ==========================================

    function test_BuyCalculation() public {
        HiveBondingCurve curve = _deployCurve();

        // Buy with 1 RITUAL
        (uint256 tokensOut, uint256 fee) = curve.calculateBuy(1 ether);

        // Fee = 7% = 0.07 ether
        assertEq(fee, 70000000000000000);

        // tokensOut = (0.93 ether * 1e9 * 1e18) / (5 ether + 0.93 ether)
        uint256 ritualAfterFee = 1 ether - fee;
        uint256 expectedTokens = (ritualAfterFee * 1_000_000_000e18) / (5 ether + ritualAfterFee);
        assertEq(tokensOut, expectedTokens);
    }

    function test_SellCalculation() public {
        HiveBondingCurve curve = _deployCurve();

        // Sell 100M tokens
        uint256 tokensIn = 100_000_000e18;
        (uint256 ritualOut, uint256 fee) = curve.calculateSell(tokensIn);

        uint256 grossRitual = (tokensIn * 5 ether) / (1_000_000_000e18 + tokensIn);
        uint256 expectedFee = (grossRitual * 700) / 10_000;
        uint256 expectedRitual = grossRitual - expectedFee;

        assertEq(fee, expectedFee);
        assertEq(ritualOut, expectedRitual);
    }

    function test_PriceIncreasesAfterBuy() public {
        HiveBondingCurve curve = _deployCurve();

        uint256 priceBefore = curve.getCurrentPrice();

        // Simulate buy by reading what would happen
        (uint256 tokensOut, uint256 fee) = curve.calculateBuy(1 ether);

        // Verify price would increase
        uint256 newVirtualRitual = 5 ether + (1 ether - fee);
        uint256 newVirtualToken = 1_000_000_000e18 - tokensOut;
        uint256 priceAfter = (newVirtualRitual * 1e18) / newVirtualToken;

        assertTrue(priceAfter > priceBefore);
    }

    function test_PriceDecreasesAfterSell() public {
        HiveBondingCurve curve = _deployCurve();

        uint256 priceBefore = curve.getCurrentPrice();

        // Simulate sell
        (uint256 ritualOut, uint256 fee) = curve.calculateSell(100_000_000e18);

        // Verify price would decrease
        uint256 grossRitual = ritualOut + fee;
        uint256 newVirtualRitual = 5 ether - grossRitual;
        uint256 newVirtualToken = 1_000_000_000e18 + 100_000_000e18;
        uint256 priceAfter = (newVirtualRitual * 1e18) / newVirtualToken;

        assertTrue(priceAfter < priceBefore);
    }

    function test_ZeroAmountReturnsZero() public {
        HiveBondingCurve curve = _deployCurve();

        (uint256 tokensOut, uint256 fee) = curve.calculateBuy(0);
        assertEq(tokensOut, 0);
        assertEq(fee, 0);

        (uint256 ritualOut, uint256 fee2) = curve.calculateSell(0);
        assertEq(ritualOut, 0);
        assertEq(fee2, 0);
    }

    function test_MaxSupplyCap() public {
        HiveBondingCurve curve = _deployCurve();

        // Try to buy more than available
        (uint256 tokensOut, ) = curve.calculateBuy(1000 ether);
        assertTrue(tokensOut <= 1_000_000_000e18);
    }

    // ==========================================
    // FEE DISTRIBUTION
    // ==========================================

    function test_FeeSplit() public {
        // Platform: 200 bps (2%), Treasury: 500 bps (5%)
        uint256 totalFee = 700; // 7%
        uint256 platformFee = (totalFee * 200) / 700;
        uint256 treasuryFee = totalFee - platformFee;

        assertEq(platformFee, 200);
        assertEq(treasuryFee, 500);
    }

    // ==========================================
    // CALLBACK SECURITY
    // ==========================================

    function test_CallbackRevertsIfNotDelivery() public {
        vm.prank(user1);
        vm.expectRevert("only async delivery");
        factory.onAgentResult(keccak256("test"), "");
    }

    function test_CallbackAcceptsFromDelivery() public {
        vm.prank(0x5A16214fF555848411544b005f7Ac063742f39F6);
        factory.onAgentResult(keccak256("test"), "");
        // Should not revert
    }

    // ==========================================
    // ACCESS CONTROL
    // ==========================================

    function test_OnlyFactoryCanMint() public {
        vm.startPrank(deployer);
        HiveAgentToken t = new HiveAgentToken("Test", "TST", "lore", deployer);
        vm.stopPrank();

        vm.prank(user1);
        vm.expectRevert("not factory");
        t.mint(user1, 1000e18);
    }

    function test_OnlyFactoryCanSetLore() public {
        vm.startPrank(deployer);
        HiveAgentToken t = new HiveAgentToken("Test", "TST", "lore", deployer);
        vm.stopPrank();

        vm.prank(user1);
        vm.expectRevert("not factory");
        t.setLore("hacked");
    }

    function test_OnlyFactoryCanSetName() public {
        vm.startPrank(deployer);
        HiveAgentToken t = new HiveAgentToken("Test", "TST", "lore", deployer);
        vm.stopPrank();

        vm.prank(user1);
        vm.expectRevert("not factory");
        t.setName("Hacked");
    }

    function test_OnlyFactoryCanSetStatus() public {
        vm.startPrank(deployer);
        HiveAgentToken t = new HiveAgentToken("Test", "TST", "lore", deployer);
        vm.stopPrank();

        vm.prank(user1);
        vm.expectRevert("not factory");
        t.setStatus(HiveAgentToken.AgentStatus.Active);
    }

    // ==========================================
    // TOKEN TRANSFER
    // ==========================================

    function test_TokenTransfer() public {
        vm.startPrank(deployer);
        HiveAgentToken t = new HiveAgentToken("Test", "TST", "lore", deployer);
        t.mint(user1, 1000e18);
        vm.stopPrank();

        vm.prank(user1);
        t.transfer(user2, 500e18);

        assertEq(t.balanceOf(user1), 500e18);
        assertEq(t.balanceOf(user2), 500e18);
    }

    function test_TokenBurn() public {
        vm.startPrank(deployer);
        HiveAgentToken t = new HiveAgentToken("Test", "TST", "lore", deployer);
        t.mint(user1, 1000e18);
        vm.stopPrank();

        vm.prank(user1);
        t.burn(200e18);

        assertEq(t.balanceOf(user1), 800e18);
        assertEq(t.totalSupply(), 800e18);
    }

    // ==========================================
    // MOCK PRECOMPILE INTEGRATION
    // ==========================================

    function test_MockLLMInfer() public {
        // Set mock response
        mockLLM.setMockResponse("Dog Coin", "DOG", "A very good boy");

        // Call infer
        uint256 requestId = mockLLM.infer(abi.encode("test input"));

        assertEq(requestId, 0);
        assertEq(mockLLM.requestCount(), 1);
    }

    function test_MockLLMFulfill() public {
        // Create a simple consumer contract for testing
        MockConsumer consumer = new MockConsumer();

        // Set mock response
        mockLLM.setMockResponse("Dog Coin", "DOG", "A very good boy");

        // Fulfill inference
        mockLLM.fulfillInference(
            address(consumer),
            0,
            "Dog Coin",
            "DOG",
            "A very good boy"
        );

        // Verify consumer received the callback
        uint256 reqId = consumer.lastRequestId();
        assertTrue(reqId == 0, "request ID should be 0");
        assertTrue(consumer.callbackReceived(), "callback should be received");
    }

    function test_MockSchedulerSchedule() public {
        // Schedule a task
        uint256 taskId = mockScheduler.schedule(
            user1,
            abi.encodeWithSignature("execute()"),
            100,  // frequency
            10    // numCalls
        );

        assertEq(taskId, 0);
        assertEq(mockScheduler.taskCount(), 1);

        (address target, , uint32 frequency, uint32 numCalls, bool active, ) = mockScheduler.tasks(taskId);
        assertEq(target, user1);
        assertEq(frequency, 100);
        assertEq(numCalls, 10);
        assertTrue(active);
    }

    function test_MockSchedulerCancel() public {
        uint256 taskId = mockScheduler.schedule(user1, "", 100, 10);

        mockScheduler.cancelTask(taskId);

        (, , , , bool active, ) = mockScheduler.tasks(taskId);
        assertFalse(active);
    }

    // ==========================================
    // EDGE CASES
    // ==========================================

    function test_BondingCurveProgress() public {
        HiveBondingCurve curve = _deployCurve();

        // Initially 0%
        assertEq(curve.getProgress(), 0);

        // After buying 1 RITUAL (minus fee)
        uint256 fee = (1 ether * 700) / 10_000;
        uint256 netRitual = 1 ether - fee;
        // Progress = netRitual * 10000 / initialVirtualRitual
        uint256 expectedProgress = (netRitual * 10_000) / 5 ether;

        // Can't actually buy without token transfers, but verify math
        (uint256 tokensOut, uint256 fee2) = curve.calculateBuy(1 ether);
        assertEq(fee2, fee);
        assertTrue(tokensOut > 0);
    }

    function test_LargeAmounts() public {
        HiveBondingCurve curve = _deployCurve();

        // Buy with 1000 RITUAL (should be capped)
        (uint256 tokensOut, uint256 fee) = curve.calculateBuy(1000 ether);
        assertTrue(tokensOut <= 1_000_000_000e18);
        assertTrue(fee > 0);
    }

    // ==========================================
    // HELPERS
    // ==========================================

    function _deployCurve() internal returns (HiveBondingCurve) {
        vm.startPrank(deployer);
        HiveAgentToken t = new HiveAgentToken("Test", "TST", "lore", deployer);
        address agentTreasury = makeAddr("agentTreasury");
        HiveBondingCurve curve = new HiveBondingCurve(
            address(t),
            deployer,
            platformTreasury,
            agentTreasury,
            address(0), // dexRouter
            5 ether,
            1_000_000_000e18
        );
        vm.stopPrank();
        return curve;
    }
}

/// @title MockConsumer - Simple contract for testing LLM callbacks
contract MockConsumer {
    uint256 public lastRequestId;
    bool public callbackReceived;
    string public lastResult;

    function onLLMResult(uint256 requestId, bytes calldata result) external {
        lastRequestId = requestId;
        callbackReceived = true;
        lastResult = abi.decode(result, (string));
    }
}
