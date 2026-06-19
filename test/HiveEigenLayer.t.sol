// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/eigenlayer/HiveEigenLayer.sol";

contract HiveEigenLayerTest is Test {
    HiveEigenLayer eigenLayer;
    address owner = address(this);
    address hiveStaking = address(0x57A1);
    address operator1 = address(0xA1);
    address operator2 = address(0xA2);
    address operator3 = address(0xA3);
    address staker1 = address(0xB1);
    address staker2 = address(0xB2);
    address user1 = address(0xC1);

    event AVSRegistered(string metadataURI, uint256 timestamp);
    event OperatorRegistered(address indexed operator, HiveEigenLayer.OperatorRole role, string metadataURI);
    event OperatorDeregistered(address indexed operator, uint256 timestamp);
    event DelegationCreated(address indexed staker, address indexed operator, uint256 amount);
    event DelegationWithdrawn(address indexed staker, address indexed operator, uint256 amount);
    event OperatorSlashed(address indexed operator, HiveEigenLayer.SlashingReason reason, uint256 amount, address reporter);
    event HeartbeatReceived(address indexed operator, uint256 timestamp);
    event ServiceTaskCreated(uint256 indexed taskId, HiveEigenLayer.OperatorRole requiredRole, uint256 reward);
    event ServiceTaskAssigned(uint256 indexed taskId, address indexed operator);
    event ServiceTaskCompleted(uint256 indexed taskId, address indexed operator);
    event FeesDistributed(address indexed operator, uint256 amount);

    function setUp() public {
        eigenLayer = new HiveEigenLayer(hiveStaking);
    }

    // ═══ Constructor ═══

    function test_constructor() public {
        assertEq(eigenLayer.owner(), owner);
        assertEq(eigenLayer.hiveStaking(), hiveStaking);
        assertEq(eigenLayer.minStakeForOperator(), 0.1 ether);
        assertEq(eigenLayer.heartbeatInterval(), 1 hours);
        assertEq(eigenLayer.slashPercentage(), 1000);
        assertFalse(eigenLayer.registeredAsAVS());
    }

    // ═══ AVS Registration ═══

    function test_register_as_avs() public {
        eigenLayer.registerAsAVS("ipfs://QmHiveAVS");

        assertTrue(eigenLayer.registeredAsAVS());
        assertEq(eigenLayer.avsMetadataURI(), "ipfs://QmHiveAVS");
    }

    function test_register_as_avs_emits_event() public {
        vm.expectEmit(false, false, false, true);
        emit AVSRegistered("ipfs://QmHiveAVS", block.timestamp);

        eigenLayer.registerAsAVS("ipfs://QmHiveAVS");
    }

    function test_register_as_avs_revert_already_registered() public {
        eigenLayer.registerAsAVS("ipfs://QmHiveAVS");

        vm.expectRevert(HiveEigenLayer.AlreadyRegistered.selector);
        eigenLayer.registerAsAVS("ipfs://QmHiveAVS2");
    }

    function test_register_as_avs_revert_not_owner() public {
        vm.prank(user1);
        vm.expectRevert("EigenLayer: not owner");
        eigenLayer.registerAsAVS("ipfs://QmHiveAVS");
    }

    // ═══ Operator Registration ═══

    function test_register_operator() public {
        vm.deal(operator1, 1 ether);

        vm.prank(operator1);
        eigenLayer.registerOperator{value: 0.1 ether}(
            HiveEigenLayer.OperatorRole.MarketMaker,
            "ipfs://QmOperator1"
        );

        assertTrue(eigenLayer.isOperatorActive(operator1));
        HiveEigenLayer.Operator memory op = eigenLayer.getOperator(operator1);
        assertEq(op.operatorAddress, operator1);
        assertEq(uint8(op.role), uint8(HiveEigenLayer.OperatorRole.MarketMaker));
        assertTrue(op.active);
    }

    function test_register_operator_emits_event() public {
        vm.deal(operator1, 1 ether);

        vm.expectEmit(true, false, false, true);
        emit OperatorRegistered(operator1, HiveEigenLayer.OperatorRole.InferenceNode, "ipfs://Qm");

        vm.prank(operator1);
        eigenLayer.registerOperator{value: 0.1 ether}(
            HiveEigenLayer.OperatorRole.InferenceNode,
            "ipfs://Qm"
        );
    }

    function test_register_operator_revert_already_registered() public {
        vm.deal(operator1, 1 ether);

        vm.startPrank(operator1);
        eigenLayer.registerOperator{value: 0.1 ether}(HiveEigenLayer.OperatorRole.MarketMaker, "ipfs://Qm");

        vm.expectRevert(HiveEigenLayer.AlreadyRegistered.selector);
        eigenLayer.registerOperator{value: 0.1 ether}(HiveEigenLayer.OperatorRole.Validator, "ipfs://Qm");
        vm.stopPrank();
    }

    function test_register_operator_revert_insufficient_stake() public {
        vm.deal(operator1, 1 ether);

        vm.prank(operator1);
        vm.expectRevert(HiveEigenLayer.InsufficientStake.selector);
        eigenLayer.registerOperator{value: 0.01 ether}(HiveEigenLayer.OperatorRole.MarketMaker, "ipfs://Qm");
    }

    function test_register_operator_revert_invalid_role() public {
        vm.deal(operator1, 1 ether);

        vm.prank(operator1);
        vm.expectRevert(HiveEigenLayer.InvalidRole.selector);
        eigenLayer.registerOperator{value: 0.1 ether}(HiveEigenLayer.OperatorRole.None, "ipfs://Qm");
    }

    function test_register_multiple_operators() public {
        vm.deal(operator1, 1 ether);
        vm.deal(operator2, 1 ether);
        vm.deal(operator3, 1 ether);

        vm.prank(operator1);
        eigenLayer.registerOperator{value: 0.1 ether}(HiveEigenLayer.OperatorRole.MarketMaker, "");
        vm.prank(operator2);
        eigenLayer.registerOperator{value: 0.2 ether}(HiveEigenLayer.OperatorRole.InferenceNode, "");
        vm.prank(operator3);
        eigenLayer.registerOperator{value: 0.3 ether}(HiveEigenLayer.OperatorRole.Validator, "");

        assertEq(eigenLayer.operatorCount(), 3);
    }

    // ═══ Operator Deregistration ═══

    function test_deregister_operator() public {
        _registerOperator(operator1, HiveEigenLayer.OperatorRole.MarketMaker);

        vm.prank(operator1);
        eigenLayer.deregisterOperator();

        assertFalse(eigenLayer.isOperatorActive(operator1));
    }

    function test_deregister_operator_emits_event() public {
        _registerOperator(operator1, HiveEigenLayer.OperatorRole.MarketMaker);

        vm.expectEmit(true, false, false, true);
        emit OperatorDeregistered(operator1, block.timestamp);

        vm.prank(operator1);
        eigenLayer.deregisterOperator();
    }

    function test_deregister_operator_revert_not_registered() public {
        vm.prank(user1);
        vm.expectRevert(HiveEigenLayer.OperatorNotActive.selector);
        eigenLayer.deregisterOperator();
    }

    // ═══ Heartbeat ═══

    function test_heartbeat() public {
        _registerOperator(operator1, HiveEigenLayer.OperatorRole.MarketMaker);

        vm.warp(block.timestamp + 30 minutes);

        vm.prank(operator1);
        eigenLayer.heartbeat();

        HiveEigenLayer.Operator memory op = eigenLayer.getOperator(operator1);
        assertEq(op.lastHeartbeat, block.timestamp);
    }

    function test_heartbeat_emits_event() public {
        _registerOperator(operator1, HiveEigenLayer.OperatorRole.MarketMaker);

        vm.expectEmit(true, false, false, true);
        emit HeartbeatReceived(operator1, block.timestamp);

        vm.prank(operator1);
        eigenLayer.heartbeat();
    }

    function test_heartbeat_revert_not_operator() public {
        vm.prank(user1);
        vm.expectRevert(HiveEigenLayer.OperatorNotActive.selector);
        eigenLayer.heartbeat();
    }

    // ═══ Delegation ═══

    function test_delegate() public {
        _registerOperator(operator1, HiveEigenLayer.OperatorRole.MarketMaker);

        vm.deal(staker1, 10 ether);

        vm.prank(staker1);
        eigenLayer.delegate(operator1, 5 ether);

        HiveEigenLayer.Delegation memory del = eigenLayer.getDelegation(staker1);
        assertEq(del.staker, staker1);
        assertEq(del.operator, operator1);
        assertEq(del.amount, 5 ether);
        assertTrue(del.active);

        assertEq(eigenLayer.getOperatorDelegatedAmount(operator1), 5 ether);
    }

    function test_delegate_emits_event() public {
        _registerOperator(operator1, HiveEigenLayer.OperatorRole.MarketMaker);

        vm.deal(staker1, 10 ether);

        vm.expectEmit(true, true, false, true);
        emit DelegationCreated(staker1, operator1, 5 ether);

        vm.prank(staker1);
        eigenLayer.delegate(operator1, 5 ether);
    }

    function test_delegate_revert_operator_not_active() public {
        vm.deal(staker1, 10 ether);

        vm.prank(staker1);
        vm.expectRevert(HiveEigenLayer.OperatorNotActive.selector);
        eigenLayer.delegate(user1, 5 ether);
    }

    function test_delegate_revert_zero_amount() public {
        _registerOperator(operator1, HiveEigenLayer.OperatorRole.MarketMaker);

        vm.prank(staker1);
        vm.expectRevert("EigenLayer: zero amount");
        eigenLayer.delegate(operator1, 0);
    }

    function test_undelegate() public {
        _registerOperator(operator1, HiveEigenLayer.OperatorRole.MarketMaker);

        vm.deal(staker1, 10 ether);
        vm.prank(staker1);
        eigenLayer.delegate(operator1, 5 ether);

        vm.prank(staker1);
        eigenLayer.undelegate();

        HiveEigenLayer.Delegation memory del = eigenLayer.getDelegation(staker1);
        assertFalse(del.active);
        assertEq(eigenLayer.getOperatorDelegatedAmount(operator1), 0);
    }

    function test_undelegate_emits_event() public {
        _registerOperator(operator1, HiveEigenLayer.OperatorRole.MarketMaker);

        vm.deal(staker1, 10 ether);
        vm.prank(staker1);
        eigenLayer.delegate(operator1, 5 ether);

        vm.expectEmit(true, true, false, true);
        emit DelegationWithdrawn(staker1, operator1, 5 ether);

        vm.prank(staker1);
        eigenLayer.undelegate();
    }

    function test_undelegate_revert_not_delegated() public {
        vm.prank(staker1);
        vm.expectRevert("EigenLayer: not delegated");
        eigenLayer.undelegate();
    }

    function test_multiple_delegations() public {
        _registerOperator(operator1, HiveEigenLayer.OperatorRole.MarketMaker);
        _registerOperator(operator2, HiveEigenLayer.OperatorRole.InferenceNode);

        vm.deal(staker1, 10 ether);
        vm.deal(staker2, 10 ether);

        vm.prank(staker1);
        eigenLayer.delegate(operator1, 3 ether);
        vm.prank(staker2);
        eigenLayer.delegate(operator2, 7 ether);

        assertEq(eigenLayer.getOperatorDelegatedAmount(operator1), 3 ether);
        assertEq(eigenLayer.getOperatorDelegatedAmount(operator2), 7 ether);
    }

    // ═══ Slashing ═══

    function test_report_operator() public {
        _registerOperator(operator1, HiveEigenLayer.OperatorRole.MarketMaker);

        vm.deal(staker1, 10 ether);
        vm.prank(staker1);
        eigenLayer.delegate(operator1, 5 ether);

        eigenLayer.reportOperator(
            operator1,
            HiveEigenLayer.SlashingReason.FrontRunning,
            "ipfs://QmEvidence"
        );

        HiveEigenLayer.Operator memory op = eigenLayer.getOperator(operator1);
        assertEq(op.slashCount, 1);

        HiveEigenLayer.SlashRecord memory record = eigenLayer.getSlashRecord(0);
        assertEq(record.operator, operator1);
        assertEq(uint8(record.reason), uint8(HiveEigenLayer.SlashingReason.FrontRunning));
        assertEq(record.amount, 5 ether * 1000 / 10000); // 10% of 5 ether = 0.5 ether
    }

    function test_report_operator_emits_event() public {
        _registerOperator(operator1, HiveEigenLayer.OperatorRole.MarketMaker);

        vm.deal(staker1, 10 ether);
        vm.prank(staker1);
        eigenLayer.delegate(operator1, 5 ether);

        uint256 expectedSlash = 5 ether * 1000 / 10000;

        vm.expectEmit(true, false, false, true);
        emit OperatorSlashed(operator1, HiveEigenLayer.SlashingReason.FrontRunning, expectedSlash, owner);

        eigenLayer.reportOperator(operator1, HiveEigenLayer.SlashingReason.FrontRunning, "ipfs://QmEvidence");
    }

    function test_report_operator_revert_not_active() public {
        vm.expectRevert(HiveEigenLayer.NotActive.selector);
        eigenLayer.reportOperator(user1, HiveEigenLayer.SlashingReason.FrontRunning, "");
    }

    function test_operator_deactivated_after_3_slashes() public {
        _registerOperator(operator1, HiveEigenLayer.OperatorRole.MarketMaker);

        // Slash 3 times
        eigenLayer.reportOperator(operator1, HiveEigenLayer.SlashingReason.FrontRunning, "");
        eigenLayer.reportOperator(operator1, HiveEigenLayer.SlashingReason.FalseValidation, "");
        eigenLayer.reportOperator(operator1, HiveEigenLayer.SlashingReason.Downtime, "");

        // Should be deactivated after 3 slashes
        assertFalse(eigenLayer.isOperatorActive(operator1));
    }

    // ═══ Service Tasks ═══

    function test_create_service_task() public {
        uint256 taskId = eigenLayer.createServiceTask{value: 1 ether}(
            HiveEigenLayer.OperatorRole.MarketMaker,
            "Execute market making strategy for ETH/USDC",
            1 ether,
            block.timestamp + 1 days
        );

        assertEq(taskId, 0);
        assertEq(eigenLayer.taskCount(), 1);

        HiveEigenLayer.ServiceTask memory task = eigenLayer.getServiceTask(0);
        assertEq(uint8(task.requiredRole), uint8(HiveEigenLayer.OperatorRole.MarketMaker));
        assertEq(task.reward, 1 ether);
        assertFalse(task.completed);
    }

    function test_create_service_task_emits_event() public {
        vm.expectEmit(true, false, false, true);
        emit ServiceTaskCreated(0, HiveEigenLayer.OperatorRole.InferenceNode, 0.5 ether);

        eigenLayer.createServiceTask{value: 0.5 ether}(
            HiveEigenLayer.OperatorRole.InferenceNode,
            "Run inference",
            0.5 ether,
            block.timestamp + 1 days
        );
    }

    function test_assign_task() public {
        _registerOperator(operator1, HiveEigenLayer.OperatorRole.MarketMaker);

        eigenLayer.createServiceTask{value: 1 ether}(
            HiveEigenLayer.OperatorRole.MarketMaker,
            "task",
            1 ether,
            block.timestamp + 1 days
        );

        eigenLayer.assignTask(0, operator1);

        HiveEigenLayer.ServiceTask memory task = eigenLayer.getServiceTask(0);
        assertEq(task.assignedOperator, operator1);
    }

    function test_assign_task_emits_event() public {
        _registerOperator(operator1, HiveEigenLayer.OperatorRole.MarketMaker);

        eigenLayer.createServiceTask{value: 0}(
            HiveEigenLayer.OperatorRole.MarketMaker,
            "task",
            0,
            block.timestamp + 1 days
        );

        vm.expectEmit(true, true, false, false);
        emit ServiceTaskAssigned(0, operator1);

        eigenLayer.assignTask(0, operator1);
    }

    function test_assign_task_revert_wrong_role() public {
        _registerOperator(operator1, HiveEigenLayer.OperatorRole.MarketMaker);

        eigenLayer.createServiceTask{value: 0}(
            HiveEigenLayer.OperatorRole.InferenceNode,
            "task",
            0,
            block.timestamp + 1 days
        );

        vm.expectRevert(HiveEigenLayer.InvalidRole.selector);
        eigenLayer.assignTask(0, operator1);
    }

    function test_assign_task_revert_not_active() public {
        eigenLayer.createServiceTask{value: 0}(
            HiveEigenLayer.OperatorRole.MarketMaker,
            "task",
            0,
            block.timestamp + 1 days
        );

        vm.expectRevert(HiveEigenLayer.OperatorNotActive.selector);
        eigenLayer.assignTask(0, user1);
    }

    function test_complete_task() public {
        _registerOperator(operator1, HiveEigenLayer.OperatorRole.MarketMaker);

        eigenLayer.createServiceTask{value: 1 ether}(
            HiveEigenLayer.OperatorRole.MarketMaker,
            "task",
            1 ether,
            block.timestamp + 1 days
        );
        eigenLayer.assignTask(0, operator1);

        vm.prank(operator1);
        eigenLayer.completeTask(0);

        HiveEigenLayer.ServiceTask memory task = eigenLayer.getServiceTask(0);
        assertTrue(task.completed);

        // Operator should have received reward
        HiveEigenLayer.Operator memory _op = eigenLayer.getOperator(operator1); assertEq(_op.totalFeesEarned, 1 ether);
    }

    function test_complete_task_emits_event() public {
        _registerOperator(operator1, HiveEigenLayer.OperatorRole.MarketMaker);

        eigenLayer.createServiceTask{value: 0.5 ether}(
            HiveEigenLayer.OperatorRole.MarketMaker,
            "task",
            0.5 ether,
            block.timestamp + 1 days
        );
        eigenLayer.assignTask(0, operator1);

        vm.expectEmit(true, false, false, true);
        emit ServiceTaskCompleted(0, operator1);

        vm.prank(operator1);
        eigenLayer.completeTask(0);
    }

    function test_complete_task_revert_not_assigned() public {
        _registerOperator(operator1, HiveEigenLayer.OperatorRole.MarketMaker);
        _registerOperator(operator2, HiveEigenLayer.OperatorRole.MarketMaker);

        eigenLayer.createServiceTask{value: 0}(
            HiveEigenLayer.OperatorRole.MarketMaker,
            "task",
            0,
            block.timestamp + 1 days
        );
        eigenLayer.assignTask(0, operator1);

        vm.prank(operator2);
        vm.expectRevert(HiveEigenLayer.NotAuthorized.selector);
        eigenLayer.completeTask(0);
    }

    function test_complete_task_revert_deadline_passed() public {
        _registerOperator(operator1, HiveEigenLayer.OperatorRole.MarketMaker);

        eigenLayer.createServiceTask{value: 0}(
            HiveEigenLayer.OperatorRole.MarketMaker,
            "task",
            0,
            block.timestamp + 1 hours
        );
        eigenLayer.assignTask(0, operator1);

        vm.warp(block.timestamp + 2 hours);

        vm.prank(operator1);
        vm.expectRevert(HiveEigenLayer.TaskNotOpen.selector);
        eigenLayer.completeTask(0);
    }

    // ═══ Fee Distribution ═══

    function test_distribute_fees() public {
        _registerOperator(operator1, HiveEigenLayer.OperatorRole.MarketMaker);

        uint256 balanceBefore = operator1.balance;
        eigenLayer.distributeFees{value: 2 ether}(operator1);

        HiveEigenLayer.Operator memory _op5 = eigenLayer.getOperator(operator1);
        assertEq(_op5.totalFeesEarned, 2 ether);
        assertEq(operator1.balance, balanceBefore + 2 ether);
    }

    function test_distribute_fees_emits_event() public {
        _registerOperator(operator1, HiveEigenLayer.OperatorRole.MarketMaker);

        vm.expectEmit(true, false, false, true);
        emit FeesDistributed(operator1, 1 ether);

        eigenLayer.distributeFees{value: 1 ether}(operator1);
    }

    function test_distribute_fees_revert_not_active() public {
        vm.expectRevert(HiveEigenLayer.NotActive.selector);
        eigenLayer.distributeFees{value: 1 ether}(user1);
    }

    // ═══ View Functions ═══

    function test_get_operators_by_role() public {
        vm.deal(operator1, 1 ether);
        vm.deal(operator2, 1 ether);
        vm.deal(operator3, 1 ether);

        vm.prank(operator1);
        eigenLayer.registerOperator{value: 0.1 ether}(HiveEigenLayer.OperatorRole.MarketMaker, "");
        vm.prank(operator2);
        eigenLayer.registerOperator{value: 0.1 ether}(HiveEigenLayer.OperatorRole.InferenceNode, "");
        vm.prank(operator3);
        eigenLayer.registerOperator{value: 0.1 ether}(HiveEigenLayer.OperatorRole.MarketMaker, "");

        address[] memory marketMakers = eigenLayer.getOperatorsByRole(HiveEigenLayer.OperatorRole.MarketMaker);
        assertEq(marketMakers.length, 2);

        address[] memory inferenceNodes = eigenLayer.getOperatorsByRole(HiveEigenLayer.OperatorRole.InferenceNode);
        assertEq(inferenceNodes.length, 1);
    }

    function test_is_operator_active() public {
        assertFalse(eigenLayer.isOperatorActive(operator1));

        _registerOperator(operator1, HiveEigenLayer.OperatorRole.MarketMaker);
        assertTrue(eigenLayer.isOperatorActive(operator1));
    }

    // ═══ Configuration ═══

    function test_set_min_stake() public {
        eigenLayer.setMinStake(1 ether);
        assertEq(eigenLayer.minStakeForOperator(), 1 ether);
    }

    function test_set_heartbeat_interval() public {
        eigenLayer.setHeartbeatInterval(2 hours);
        assertEq(eigenLayer.heartbeatInterval(), 2 hours);
    }

    function test_set_slash_percentage() public {
        eigenLayer.setSlashPercentage(2000); // 20%
        assertEq(eigenLayer.slashPercentage(), 2000);
    }

    function test_set_slash_percentage_revert_max() public {
        vm.expectRevert("EigenLayer: max 50%");
        eigenLayer.setSlashPercentage(6000); // 60% > 50% max
    }

    function test_set_paused() public {
        eigenLayer.setPaused(true);
        assertTrue(eigenLayer.paused());
    }

    function test_paused_reverts_registration() public {
        eigenLayer.setPaused(true);

        vm.deal(operator1, 1 ether);
        vm.prank(operator1);
        vm.expectRevert(HiveEigenLayer.Paused.selector);
        eigenLayer.registerOperator{value: 0.1 ether}(HiveEigenLayer.OperatorRole.MarketMaker, "");
    }

    // ═══ Full Lifecycle ═══

    function test_full_lifecycle() public {
        // 1. Register as AVS
        eigenLayer.registerAsAVS("ipfs://QmHiveAVS");

        // 2. Register operators
        vm.deal(operator1, 10 ether);
        vm.deal(operator2, 10 ether);

        vm.prank(operator1);
        eigenLayer.registerOperator{value: 1 ether}(HiveEigenLayer.OperatorRole.MarketMaker, "ipfs://QmOp1");

        vm.prank(operator2);
        eigenLayer.registerOperator{value: 1 ether}(HiveEigenLayer.OperatorRole.Validator, "ipfs://QmOp2");

        assertEq(eigenLayer.operatorCount(), 2);

        // 3. Delegation
        vm.deal(staker1, 100 ether);
        vm.prank(staker1);
        eigenLayer.delegate(operator1, 50 ether);

        assertEq(eigenLayer.getOperatorDelegatedAmount(operator1), 50 ether);

        // 4. Create and complete service task
        eigenLayer.createServiceTask{value: 5 ether}(
            HiveEigenLayer.OperatorRole.MarketMaker,
            "Market make ETH/USDC",
            5 ether,
            block.timestamp + 7 days
        );

        eigenLayer.assignTask(0, operator1);

        vm.prank(operator1);
        eigenLayer.completeTask(0);

        assertTrue(eigenLayer.getServiceTask(0).completed);
        HiveEigenLayer.Operator memory _op2 = eigenLayer.getOperator(operator1); assertEq(_op2.totalFeesEarned, 5 ether);

        // 5. Heartbeat
        vm.prank(operator1);
        eigenLayer.heartbeat();

        // 6. Slashing (operator2 reports operator1)
        // Only owner can slash
        eigenLayer.reportOperator(operator1, HiveEigenLayer.SlashingReason.FrontRunning, "ipfs://QmEvidence");

        HiveEigenLayer.Operator memory _op3 = eigenLayer.getOperator(operator1); assertEq(_op3.slashCount, 1);
        // Operator still active (only 1 slash, needs 3)
        assertTrue(eigenLayer.isOperatorActive(operator1));

        // 7. Verify final state
        assertTrue(eigenLayer.registeredAsAVS());
        assertEq(eigenLayer.operatorCount(), 2);
        assertEq(eigenLayer.slashCount(), 1);
    }

    // ═══ Ownership ═══

    function test_transfer_ownership() public {
        eigenLayer.transferOwnership(user1);
        assertEq(eigenLayer.owner(), user1);
    }

    function test_transfer_ownership_revert_not_owner() public {
        vm.prank(user1);
        vm.expectRevert("EigenLayer: not owner");
        eigenLayer.transferOwnership(user1);
    }

    function test_transfer_ownership_revert_zero() public {
        vm.expectRevert("zero address");
        eigenLayer.transferOwnership(address(0));
    }

    // ═══ Helpers ═══

    function _registerOperator(address op, HiveEigenLayer.OperatorRole role) internal {
        vm.deal(op, 10 ether);
        vm.prank(op);
        eigenLayer.registerOperator{value: 0.1 ether}(role, "ipfs://QmOperator");
    }
}
