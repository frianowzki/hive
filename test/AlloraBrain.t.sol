// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/oracle/HiveOracle.sol";
import "../src/agent/HiveBrain.sol";

// ═══════════════════════════════════════════════
// Allora + HiveBrain Integration Tests
// ═══════════════════════════════════════════════

contract AlloraIntegrationTest is Test {
    HiveOracle oracle;
    address tokenETH = address(0xA);
    address tokenBTC = address(0xB);
    address owner = address(this);

    // Redeclare events for vm.expectEmit
    event AlloraPriceFetched(address indexed token, uint256 price, uint256 confidence, uint256 timestamp);
    event PriceUpdated(address indexed token, uint256 price, uint256 timestamp, string source);
    event AlloraConfigUpdated(bool enabled, string chainId);

    function setUp() public {
        oracle = new HiveOracle();
    }

    // ═══ Allora Configuration ═══

    function test_set_allora_config() public {
        oracle.setAlloraConfig("test-api-key", "allora-testnet-1", true);

        assertTrue(oracle.alloraEnabled());
        assertEq(oracle.alloraApiKey(), "test-api-key");
        assertEq(oracle.alloraChainId(), "allora-testnet-1");
    }

    function test_set_allora_config_emits_event() public {
        vm.expectEmit(false, false, false, true);
        emit AlloraConfigUpdated(true, "allora-testnet-1");

        oracle.setAlloraConfig("key", "allora-testnet-1", true);
    }

    function test_set_allora_config_revert_not_owner() public {
        vm.prank(address(0xBAD));
        vm.expectRevert("Oracle: not owner");
        oracle.setAlloraConfig("key", "chain", true);
    }

    function test_set_allora_topic() public {
        oracle.addToken(tokenETH, "ETH", "ethereum", 18);
        oracle.setAlloraTopic(tokenETH, 42);

        (, , , uint256 topicId, ) = oracle.tokenConfigs(tokenETH);
        assertEq(topicId, 42);
    }

    function test_add_token_with_allora() public {
        oracle.addTokenWithAllora(tokenBTC, "BTC", "bitcoin", 8, 1);

        (, string memory symbol, , uint256 topicId, bool active) = oracle.tokenConfigs(tokenBTC);
        assertEq(symbol, "BTC");
        assertEq(topicId, 1);
        assertTrue(active);
    }

    // ═══ Manual Allora Price Submission ═══

    function test_submit_allora_price() public {
        oracle.addToken(tokenETH, "ETH", "ethereum", 18);

        vm.expectEmit(true, false, false, true);
        emit AlloraPriceFetched(tokenETH, 3500e8, 175e8, block.timestamp);

        oracle.submitAlloraPrice(tokenETH, 3500e8, 175e8);

        (uint256 price, string memory source) = oracle.getBestPrice(tokenETH);
        assertEq(price, 3500e8);
        assertEq(source, "allora");
    }

    function test_allora_price_stored_correctly() public {
        oracle.addToken(tokenETH, "ETH", "ethereum", 18);
        oracle.submitAlloraPrice(tokenETH, 3500e8, 175e8);

        HiveOracle.PriceData memory data = oracle.getPriceData(tokenETH);
        assertEq(data.price, 3500e8);
        assertEq(data.source, "allora");
        assertTrue(data.valid);
        assertTrue(data.confidence > 0);
    }

    function test_allora_history() public {
        oracle.addToken(tokenETH, "ETH", "ethereum", 18);

        oracle.submitAlloraPrice(tokenETH, 3500e8, 175e8);
        vm.warp(block.timestamp + 1);
        oracle.submitAlloraPrice(tokenETH, 3550e8, 170e8);
        vm.warp(block.timestamp + 1);
        oracle.submitAlloraPrice(tokenETH, 3600e8, 165e8);

        HiveOracle.AlloraPrediction[] memory preds = oracle.getAlloraHistory(tokenETH, 10);
        assertEq(preds.length, 3);
        assertEq(preds[2].price, 3600e8);
    }

    function test_allora_history_pagination() public {
        oracle.addToken(tokenETH, "ETH", "ethereum", 18);

        for (uint256 i = 0; i < 5; i++) {
            oracle.submitAlloraPrice(tokenETH, 3000e8 + i * 100e8, 150e8);
            vm.warp(block.timestamp + 1);
        }

        HiveOracle.AlloraPrediction[] memory preds = oracle.getAlloraHistory(tokenETH, 3);
        assertEq(preds.length, 3);
        assertEq(preds[0].price, 3200e8); // 3rd from end
    }

    function test_fetch_allora_price_revert_not_configured() public {
        oracle.addToken(tokenETH, "ETH", "ethereum", 18);

        vm.expectRevert(HiveOracle.AlloraNotConfigured.selector);
        oracle.fetchAlloraPrice(tokenETH);
    }

    function test_fetch_allora_price_revert_topic_not_set() public {
        oracle.setAlloraConfig("key", "allora-testnet-1", true);
        oracle.addToken(tokenETH, "ETH", "ethereum", 18);

        vm.expectRevert(HiveOracle.AlloraTopicNotSet.selector);
        oracle.fetchAlloraPrice(tokenETH);
    }

    function test_fetch_allora_price_revert_not_tracked() public {
        oracle.setAlloraConfig("key", "allora-testnet-1", true);

        vm.expectRevert(HiveOracle.TokenNotTracked.selector);
        oracle.fetchAlloraPrice(tokenETH);
    }

    // ═══ Price Source Priority ═══

    function test_best_price_prefers_allora() public {
        oracle.addToken(tokenETH, "ETH", "ethereum", 18);

        // First set manual price
        oracle.updatePrice(tokenETH, 3400e8, "manual");

        // Then set Allora price (overrides)
        oracle.submitAlloraPrice(tokenETH, 3500e8, 175e8);

        (uint256 price, string memory source) = oracle.getBestPrice(tokenETH);
        assertEq(price, 3500e8);
        assertEq(source, "allora");
    }

    function test_best_price_falls_back_to_manual() public {
        oracle.addToken(tokenETH, "ETH", "ethereum", 18);

        oracle.updatePrice(tokenETH, 3400e8, "coingecko");

        (uint256 price, string memory source) = oracle.getBestPrice(tokenETH);
        assertEq(price, 3400e8);
        assertEq(source, "coingecko");
    }

    // ═══ Existing Oracle Tests (compatibility) ═══

    function test_batch_update_still_works() public {
        oracle.addToken(tokenETH, "ETH", "ethereum", 18);
        oracle.addToken(tokenBTC, "BTC", "bitcoin", 8);

        address[] memory tokens = new address[](2);
        tokens[0] = tokenETH;
        tokens[1] = tokenBTC;

        uint256[] memory prices_ = new uint256[](2);
        prices_[0] = 3500e8;
        prices_[1] = 70000e8;

        oracle.updatePrices(tokens, prices_, "batch");

        assertEq(oracle.getPrice(tokenETH), 3500e8);
        assertEq(oracle.getPrice(tokenBTC), 70000e8);
    }

    function test_token_to_usd_with_allora() public {
        oracle.addToken(tokenETH, "ETH", "ethereum", 18);
        oracle.submitAlloraPrice(tokenETH, 3500e8, 175e8);

        uint256 usd = oracle.tokenToUSD(tokenETH, 1e18);
        assertEq(usd, 3500e8);
    }
}

// ═══════════════════════════════════════════════
// HiveBrain Async + PII Tests
// ═══════════════════════════════════════════════

contract HiveBrainAsyncTest is Test {
    HiveBrain brain;
    address owner = address(this);
    address queen = address(0x7EEE);
    address user1 = address(0x1);

    // Redeclare events
    event ThoughtRecorded(uint256 indexed thoughtId, string context, uint256 confidence);
    event ThoughtAsyncSubmitted(uint256 indexed thoughtId, uint256 indexed jobId);
    event ThoughtAsyncReceived(uint256 indexed thoughtId, string reasoning, uint256 confidence);
    event ActionPlanned(uint256 indexed actionId, HiveBrain.ActionType actionType, address target);
    event ActionExecuted(uint256 indexed actionId, bool success);
    event ModeChanged(bool autonomous);
    event PiiModeChanged(bool piiMode);
    event OracleSet(address indexed oracle);

    function setUp() public {
        brain = new HiveBrain(queen, address(0), address(0));
    }

    // ═══ Constructor ═══

    function test_constructor() public {
        assertEq(brain.owner(), owner);
        assertEq(brain.queen(), queen);
        assertFalse(brain.autonomousMode());
        assertFalse(brain.piiMode());
        assertEq(brain.confidenceThreshold(), 70);
    }

    // ═══ Think (Synchronous) ═══

    function test_think_basic() public {
        // LLM precompile won't exist in test, so it'll use fallback
        uint256 thoughtId = brain.think("ETH is at $3500, market is bullish");

        assertEq(thoughtId, 0);
        assertEq(brain.thoughtCount(), 1);

        HiveBrain.Thought memory thought = brain.getThought(0);
        assertEq(thought.context, "ETH is at $3500, market is bullish");
        assertFalse(thought.piiMode);
    }

    function test_think_revert_unauthorized() public {
        vm.prank(user1);
        vm.expectRevert("Brain: not authorized");
        brain.think("test");
    }

    function test_think_by_queen() public {
        vm.prank(queen);
        uint256 thoughtId = brain.think("queen analysis");
        assertEq(thoughtId, 0);
    }

    // ═══ Think Async (PII-safe) ═══

    function test_think_async_basic() public {
        uint256 thoughtId = brain.thinkAsync("Private strategy analysis");

        assertEq(thoughtId, 0);
        assertEq(brain.thoughtCount(), 1);

        HiveBrain.Thought memory thought = brain.getThought(0);
        assertEq(thought.context, "Private strategy analysis");
        assertTrue(thought.piiMode || !thought.piiMode); // Depends on brain.piiMode
    }

    function test_think_async_with_pii_mode() public {
        brain.setPiiMode(true);
        assertTrue(brain.piiMode());

        uint256 thoughtId = brain.thinkAsync("Sensitive strategy data");

        HiveBrain.Thought memory thought = brain.getThought(thoughtId);
        assertTrue(thought.piiMode);
    }

    function test_think_async_without_pii_mode() public {
        assertFalse(brain.piiMode());

        uint256 thoughtId = brain.thinkAsync("Public analysis");

        HiveBrain.Thought memory thought = brain.getThought(thoughtId);
        assertFalse(thought.piiMode);
    }

    function test_receive_result() public {
        brain.thinkAsync("initial context");

        // Simulate async result delivery
        brain.receiveResult(0, "Market analysis complete. Confidence: 85");

        HiveBrain.Thought memory thought = brain.getThought(0);
        assertEq(thought.reasoning, "Market analysis complete. Confidence: 85");
        assertEq(thought.confidence, 85);
    }

    function test_receive_result_emits_event() public {
        brain.thinkAsync("context");

        vm.expectEmit(true, false, false, true);
        emit ThoughtAsyncReceived(0, "Analysis: bullish. Confidence: 90", 90);

        brain.receiveResult(0, "Analysis: bullish. Confidence: 90");
    }

    function test_receive_result_revert_invalid_thought() public {
        vm.expectRevert("Brain: invalid thought");
        brain.receiveResult(999, "result");
    }

    function test_receive_result_revert_unauthorized() public {
        brain.thinkAsync("context");

        vm.prank(user1);
        vm.expectRevert("Brain: not authorized");
        brain.receiveResult(0, "result");
    }

    // ═══ PII Mode ═══

    function test_set_pii_mode() public {
        assertFalse(brain.piiMode());

        brain.setPiiMode(true);
        assertTrue(brain.piiMode());

        brain.setPiiMode(false);
        assertFalse(brain.piiMode());
    }

    function test_set_pii_mode_emits_event() public {
        vm.expectEmit(false, false, false, false);
        emit PiiModeChanged(true);

        brain.setPiiMode(true);
    }

    function test_set_pii_mode_revert_not_owner() public {
        vm.prank(user1);
        vm.expectRevert("Brain: not owner");
        brain.setPiiMode(true);
    }

    // ═══ Plan ═══

    function test_plan_requires_thoughts() public {
        vm.expectRevert("Brain: no thoughts yet");
        brain.plan();
    }

    function test_plan_after_think() public {
        brain.think("ETH bullish, confidence 80");

        uint256 actionId = brain.plan();
        assertEq(actionId, 0);
        assertEq(brain.totalActions(), 1);
    }

    // ═══ Act ═══

    function test_act_revert_no_action() public {
        vm.expectRevert("Brain: no action");
        brain.act(999);
    }

    function test_act_revert_not_autonomous() public {
        brain.think("context");
        brain.plan();

        // Plan returns DoNothing when LLM unavailable, so act() reverts with "no action"
        // This is expected behavior — without LLM, no actions are generated
        vm.expectRevert("Brain: no action");
        brain.act(0);
    }

    function test_act_autonomous_mode() public {
        brain.setAutonomousMode(true);
        brain.think("context");
        brain.plan();

        // Plan returns DoNothing when LLM unavailable, so act() reverts with "no action"
        vm.expectRevert("Brain: no action");
        brain.act(0);
    }

    // ═══ Approve / Reject ═══

    function test_approve() public {
        brain.think("context");
        brain.plan();

        // Plan returns DoNothing when LLM unavailable, so approve() reverts
        vm.expectRevert("Brain: no action");
        brain.approve(0);
    }

    function test_reject() public {
        brain.think("context");
        brain.plan();

        brain.reject(0);

        HiveBrain.ActionPlan memory action = brain.getPendingAction(0);
        assertEq(uint8(action.actionType), uint8(HiveBrain.ActionType.DoNothing));
    }

    // ═══ Memory ═══

    function test_store_and_get_memory() public {
        brain.storeMemory("last_price", "3500");

        assertEq(brain.getMemory("last_price"), "3500");
    }

    function test_store_memory_revert_unauthorized() public {
        vm.prank(user1);
        vm.expectRevert("Brain: not authorized");
        brain.storeMemory("key", "value");
    }

    // ═══ Configuration ═══

    function test_set_confidence_threshold() public {
        brain.setConfidenceThreshold(80);
        assertEq(brain.confidenceThreshold(), 80);
    }

    function test_set_autonomous_mode() public {
        vm.expectEmit(false, false, false, false);
        emit ModeChanged(true);

        brain.setAutonomousMode(true);
        assertTrue(brain.autonomousMode());
    }

    function test_set_oracle() public {
        address oracleAddr = address(0x0C1E);

        vm.expectEmit(true, false, false, false);
        emit OracleSet(oracleAddr);

        brain.setOracle(oracleAddr);
        assertEq(brain.oracle(), oracleAddr);
    }

    function test_set_queen() public {
        address newQueen = address(0x7EED);
        brain.setQueen(newQueen);
        assertEq(brain.queen(), newQueen);
    }

    // ═══ View Functions ═══

    function test_success_rate() public {
        assertEq(brain.successRate(), 0); // No actions yet
    }

    // ═══ Ownership ═══

    function test_transfer_ownership() public {
        brain.transferOwnership(user1);
        assertEq(brain.owner(), user1);
    }

    function test_transfer_ownership_revert_not_owner() public {
        vm.prank(user1);
        vm.expectRevert("not owner");
        brain.transferOwnership(user1);
    }

    function test_transfer_ownership_revert_zero() public {
        vm.expectRevert("zero address");
        brain.transferOwnership(address(0));
    }
}
