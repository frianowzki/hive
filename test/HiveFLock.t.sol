// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/flock/HiveFLock.sol";

contract HiveFLockTest is Test {
    HiveFLock flock;
    address owner = address(this);
    address brain = address(0xBBAA);
    address validator1 = address(0xA1);
    address validator2 = address(0xA2);
    address submitter1 = address(0xB1);
    address submitter2 = address(0xB2);
    address user1 = address(0xC1);

    event TaskCreated(uint256 indexed taskId, string name, HiveFLock.ModelType modelType, uint256 rewardPool);
    event TaskActivated(uint256 indexed taskId);
    event TaskCancelled(uint256 indexed taskId);
    event ModelSubmitted(uint256 indexed taskId, uint256 indexed submissionId, address submitter, bytes32 modelHash);
    event ModelValidated(uint256 indexed taskId, uint256 indexed submissionId, address validator, uint256 score);
    event WinnerSelected(uint256 indexed taskId, uint256 indexed submissionId, address submitter);
    event ModelDeployed(uint256 indexed taskId, bytes32 modelHash, uint256 timestamp);
    event ValidatorAdded(address indexed validator);
    event ValidatorRemoved(address indexed validator);
    event FlockConfigUpdated(bool enabled, string apiUrl);
    event RewardDistributed(uint256 indexed taskId, address indexed recipient, uint256 amount);

    function setUp() public {
        flock = new HiveFLock(brain);
        flock.addValidator(validator1);
        flock.addValidator(validator2);
    }

    // ═══ Constructor ═══

    function test_constructor() public {
        assertEq(flock.owner(), owner);
        assertEq(flock.brain(), brain);
        assertEq(flock.taskCount(), 0);
        assertEq(flock.validatorCount(), 2);
    }

    // ═══ FLock Configuration ═══

    function test_set_flock_config() public {
        flock.setFlockConfig("test-api-key", "https://api.flock.io/v1", true);
        assertTrue(flock.flockEnabled());
        assertEq(flock.flockApiKey(), "test-api-key");
    }

    function test_set_flock_config_emits_event() public {
        vm.expectEmit(false, false, false, true);
        emit FlockConfigUpdated(true, "https://api.flock.io/v1");
        flock.setFlockConfig("key", "https://api.flock.io/v1", true);
    }

    function test_set_flock_config_revert_not_owner() public {
        vm.prank(user1);
        vm.expectRevert("Flock: not owner");
        flock.setFlockConfig("key", "url", true);
    }

    // ═══ Validator Management ═══

    function test_add_validator() public {
        flock.addValidator(address(0xA3));
        assertTrue(flock.isValidator(address(0xA3)));
        assertEq(flock.validatorCount(), 3);
    }

    function test_add_validator_emits_event() public {
        vm.expectEmit(true, false, false, false);
        emit ValidatorAdded(address(0xA3));
        flock.addValidator(address(0xA3));
    }

    function test_add_validator_revert_not_owner() public {
        vm.prank(user1);
        vm.expectRevert("Flock: not owner");
        flock.addValidator(address(0xA3));
    }

    function test_remove_validator() public {
        flock.removeValidator(validator1);
        assertFalse(flock.isValidator(validator1));
        assertEq(flock.validatorCount(), 1);
    }

    function test_remove_validator_emits_event() public {
        vm.expectEmit(true, false, false, false);
        emit ValidatorRemoved(validator1);
        flock.removeValidator(validator1);
    }

    // ═══ Task Creation ═══

    function test_create_task() public {
        uint256 taskId = flock.createTask{value: 1 ether}(
            "ETH/USD Price Predictor", "desc", HiveFLock.ModelType.PricePrediction,
            5, 0.1 ether, block.timestamp + 7 days
        );
        assertEq(taskId, 0);
        assertEq(flock.taskCount(), 1);
        HiveFLock.TrainingTask memory task = flock.getTask(0);
        assertEq(task.name, "ETH/USD Price Predictor");
        assertEq(task.rewardPool, 1 ether);
    }

    function test_create_task_emits_event() public {
        vm.expectEmit(false, false, false, true);
        emit TaskCreated(0, "test", HiveFLock.ModelType.MarketMaking, 0);
        flock.createTask{value: 0}("test", "desc", HiveFLock.ModelType.MarketMaking, 3, 0, block.timestamp + 1 days);
    }

    function test_create_task_revert_not_owner() public {
        vm.prank(user1);
        vm.expectRevert("Flock: not owner");
        flock.createTask{value: 0}("test", "desc", HiveFLock.ModelType.PricePrediction, 3, 0, block.timestamp + 1 days);
    }

    function test_create_multiple_tasks() public {
        flock.createTask{value: 0}("T1", "d", HiveFLock.ModelType.PricePrediction, 3, 0, block.timestamp + 1 days);
        flock.createTask{value: 0}("T2", "d", HiveFLock.ModelType.MarketMaking, 5, 0, block.timestamp + 2 days);
        flock.createTask{value: 0}("T3", "d", HiveFLock.ModelType.RiskAssessment, 7, 0, block.timestamp + 3 days);
        assertEq(flock.taskCount(), 3);
    }

    // ═══ Task Management ═══

    function test_activate_task() public {
        flock.createTask{value: 0}("t", "d", HiveFLock.ModelType.PricePrediction, 3, 0, block.timestamp + 1 days);
        flock.activateTask(0);
        assertEq(uint8(flock.getTask(0).status), uint8(HiveFLock.TaskStatus.Active));
    }

    function test_activate_task_emits_event() public {
        flock.createTask{value: 0}("t", "d", HiveFLock.ModelType.PricePrediction, 3, 0, block.timestamp + 1 days);
        vm.expectEmit(true, false, false, false);
        emit TaskActivated(0);
        flock.activateTask(0);
    }

    function test_cancel_task() public {
        flock.createTask{value: 0}("t", "d", HiveFLock.ModelType.PricePrediction, 3, 0, block.timestamp + 1 days);
        flock.cancelTask(0);
        assertEq(uint8(flock.getTask(0).status), uint8(HiveFLock.TaskStatus.Cancelled));
    }

    function test_activate_task_revert_not_found() public {
        vm.expectRevert(HiveFLock.TaskNotFound.selector);
        flock.activateTask(999);
    }

    function test_activate_task_revert_not_owner() public {
        flock.createTask{value: 0}("t", "d", HiveFLock.ModelType.PricePrediction, 3, 0, block.timestamp + 1 days);
        vm.prank(user1);
        vm.expectRevert("Flock: not owner");
        flock.activateTask(0);
    }

    // ═══ Model Submission ═══

    function test_submit_model() public {
        _createAndActivateTask();
        bytes32 modelHash = keccak256(bytes("onnx-model-v1"));
        vm.deal(submitter1, 1 ether);
        vm.prank(submitter1);
        flock.submitModel{value: 0.1 ether}(0, modelHash, "ipfs://QmModel1");
        assertEq(flock.getSubmissionCount(0), 1);
        HiveFLock.ModelSubmission memory sub = flock.getSubmission(0, 0);
        assertEq(sub.submitter, submitter1);
        assertEq(sub.modelHash, modelHash);
    }

    function test_submit_model_emits_event() public {
        _createAndActivateTask();
        bytes32 modelHash = keccak256(bytes("model"));
        vm.deal(submitter1, 1 ether);
        vm.expectEmit(true, true, false, true);
        emit ModelSubmitted(0, 0, submitter1, modelHash);
        vm.prank(submitter1);
        flock.submitModel{value: 0.1 ether}(0, modelHash, "ipfs://Qm");
    }

    function test_submit_model_revert_not_active() public {
        flock.createTask{value: 0}("t", "d", HiveFLock.ModelType.PricePrediction, 3, 0, block.timestamp + 1 days);
        vm.deal(submitter1, 1 ether);
        vm.prank(submitter1);
        vm.expectRevert(HiveFLock.TaskNotActive.selector);
        flock.submitModel{value: 0.1 ether}(0, keccak256(bytes("m")), "ipfs://Qm");
    }

    function test_submit_model_revert_insufficient_stake() public {
        _createAndActivateTask();
        vm.deal(submitter1, 1 ether);
        vm.prank(submitter1);
        vm.expectRevert(HiveFLock.InsufficientStake.selector);
        flock.submitModel{value: 0.01 ether}(0, keccak256(bytes("m")), "ipfs://Qm");
    }

    function test_submit_model_revert_deadline_passed() public {
        flock.createTask{value: 0}("t", "d", HiveFLock.ModelType.PricePrediction, 3, 0, block.timestamp + 1 hours);
        flock.activateTask(0);
        vm.warp(block.timestamp + 2 hours);
        vm.deal(submitter1, 1 ether);
        vm.prank(submitter1);
        vm.expectRevert(HiveFLock.SubmissionDeadlinePassed.selector);
        flock.submitModel{value: 0.1 ether}(0, keccak256(bytes("m")), "ipfs://Qm");
    }

    function test_submit_multiple_models() public {
        _createAndActivateTask();
        vm.deal(submitter1, 1 ether);
        vm.deal(submitter2, 1 ether);
        vm.prank(submitter1);
        flock.submitModel{value: 0.1 ether}(0, keccak256(bytes("m1")), "ipfs://Qm1");
        vm.prank(submitter2);
        flock.submitModel{value: 0.2 ether}(0, keccak256(bytes("m2")), "ipfs://Qm2");
        assertEq(flock.getSubmissionCount(0), 2);
    }

    // ═══ Voting ═══

    function test_start_voting() public {
        _createAndActivateTask();
        _submitTestModel(submitter1);
        flock.startVoting(0);
        assertEq(uint8(flock.getTask(0).status), uint8(HiveFLock.TaskStatus.Voting));
    }

    function test_start_voting_revert_no_submissions() public {
        _createAndActivateTask();
        vm.expectRevert(HiveFLock.NoSubmissions.selector);
        flock.startVoting(0);
    }

    function test_start_voting_revert_not_active() public {
        flock.createTask{value: 0}("t", "d", HiveFLock.ModelType.PricePrediction, 3, 0, block.timestamp + 1 days);
        vm.expectRevert(HiveFLock.TaskNotActive.selector);
        flock.startVoting(0);
    }

    function test_validate_model() public {
        _createFullTask();
        vm.prank(validator1);
        flock.validateModel(0, 0, 8500);
        HiveFLock.ModelSubmission memory sub = flock.getSubmission(0, 0);
        assertTrue(sub.validated);
        assertEq(sub.score, 8500);
    }

    function test_validate_model_weighted_average() public {
        _createFullTask();
        vm.prank(validator1);
        flock.validateModel(0, 0, 8000);
        vm.prank(validator2);
        flock.validateModel(0, 0, 9000);
        assertEq(flock.getSubmission(0, 0).score, 8500);
    }

    function test_validate_model_emits_event() public {
        _createFullTask();
        vm.expectEmit(true, true, true, false);
        emit ModelValidated(0, 0, validator1, 8500);
        vm.prank(validator1);
        flock.validateModel(0, 0, 8500);
    }

    function test_validate_model_revert_not_validator() public {
        _createFullTask();
        vm.prank(user1);
        vm.expectRevert("Flock: not validator");
        flock.validateModel(0, 0, 8500);
    }

    function test_validate_model_revert_already_validated() public {
        _createFullTask();
        vm.startPrank(validator1);
        flock.validateModel(0, 0, 8500);
        vm.expectRevert(HiveFLock.AlreadyValidated.selector);
        flock.validateModel(0, 0, 9000);
        vm.stopPrank();
    }

    function test_validate_model_revert_not_voting() public {
        _createAndActivateTask();
        _submitTestModel(submitter1);
        vm.prank(validator1);
        vm.expectRevert(HiveFLock.TaskNotVoting.selector);
        flock.validateModel(0, 0, 8500);
    }

    function test_validate_model_revert_invalid_score() public {
        _createFullTask();
        vm.prank(validator1);
        vm.expectRevert(HiveFLock.InvalidScore.selector);
        flock.validateModel(0, 0, 10001);
    }

    // ═══ Winner Selection ═══

    function test_select_winner() public {
        // Create, activate, submit BOTH, then vote
        flock.createTask{value: 0.5 ether}("t", "d", HiveFLock.ModelType.PricePrediction, 3, 0.1 ether, block.timestamp + 7 days);
        flock.activateTask(0);

        vm.deal(submitter1, 1 ether);
        vm.prank(submitter1);
        flock.submitModel{value: 0.1 ether}(0, keccak256(bytes("model-1")), "ipfs://Qm1");

        vm.deal(submitter2, 1 ether);
        vm.prank(submitter2);
        flock.submitModel{value: 0.1 ether}(0, keccak256(bytes("model-2")), "ipfs://Qm2");

        flock.startVoting(0);

        vm.prank(validator1);
        flock.validateModel(0, 0, 8000);
        vm.prank(validator1);
        flock.validateModel(0, 1, 9500);

        uint256 winnerId = flock.selectWinner(0);
        assertEq(winnerId, 1);
        assertTrue(flock.getWinner(0).isWinner);
        assertEq(flock.getWinner(0).submitter, submitter2);
    }

    function test_select_winner_distributes_reward() public {
        _createFullTask();
        vm.prank(validator1);
        flock.validateModel(0, 0, 8500);
        uint256 balanceBefore = submitter1.balance;
        flock.selectWinner(0);
        assertEq(submitter1.balance, balanceBefore + 0.5 ether);
    }

    function test_select_winner_emits_events() public {
        _createFullTask();
        vm.prank(validator1);
        flock.validateModel(0, 0, 8500);
        vm.expectEmit(true, false, true, false);
        emit RewardDistributed(0, submitter1, 0.5 ether);
        vm.expectEmit(true, true, true, false);
        emit WinnerSelected(0, 0, submitter1);
        flock.selectWinner(0);
    }

    function test_select_winner_revert_not_voting() public {
        _createAndActivateTask();
        _submitTestModel(submitter1);
        vm.expectRevert(HiveFLock.TaskNotVoting.selector);
        flock.selectWinner(0);
    }

    function test_select_winner_revert_no_valid_submissions() public {
        _createAndActivateTask();
        _submitTestModel(submitter1);
        flock.startVoting(0);
        vm.expectRevert("Flock: no valid submissions");
        flock.selectWinner(0);
    }

    // ═══ Model Deployment ═══

    function test_deploy_model() public {
        _completeFullTask();
        flock.deployModel(0);
        assertEq(flock.deployedModels(0), keccak256(bytes("model-1")));
        assertTrue(flock.deployedAt(0) > 0);
    }

    function test_deploy_model_emits_event() public {
        _completeFullTask();
        vm.expectEmit(true, false, false, true);
        emit ModelDeployed(0, keccak256(bytes("model-1")), block.timestamp);
        flock.deployModel(0);
    }

    function test_deploy_model_revert_not_completed() public {
        _createFullTask();
        vm.expectRevert(HiveFLock.TaskNotCompleted.selector);
        flock.deployModel(0);
    }

    function test_deploy_model_revert_not_owner() public {
        _completeFullTask();
        vm.prank(user1);
        vm.expectRevert("Flock: not owner");
        flock.deployModel(0);
    }

    // ═══ View Functions ═══

    function test_get_task_submissions() public {
        _createAndActivateTask();
        vm.deal(submitter1, 1 ether);
        vm.deal(submitter2, 1 ether);
        vm.prank(submitter1);
        flock.submitModel{value: 0.1 ether}(0, keccak256(bytes("m1")), "ipfs://1");
        vm.prank(submitter2);
        flock.submitModel{value: 0.2 ether}(0, keccak256(bytes("m2")), "ipfs://2");
        HiveFLock.ModelSubmission[] memory subs = flock.getTaskSubmissions(0);
        assertEq(subs.length, 2);
    }

    function test_is_validator() public {
        assertTrue(flock.isValidator(validator1));
        assertFalse(flock.isValidator(user1));
    }

    // ═══ Full Lifecycle ═══

    function test_full_lifecycle() public {
        uint256 taskId = flock.createTask{value: 2 ether}(
            "Market Making Optimizer", "Train model", HiveFLock.ModelType.MarketMaking, 3, 0.1 ether, block.timestamp + 7 days
        );
        assertEq(taskId, 0);
        flock.activateTask(0);

        vm.deal(submitter1, 1 ether);
        vm.deal(submitter2, 1 ether);
        vm.prank(submitter1);
        flock.submitModel{value: 0.1 ether}(0, keccak256(bytes("model-a")), "ipfs://a");
        vm.prank(submitter2);
        flock.submitModel{value: 0.2 ether}(0, keccak256(bytes("model-b")), "ipfs://b");

        flock.startVoting(0);

        vm.startPrank(validator1);
        flock.validateModel(0, 0, 7500);
        flock.validateModel(0, 1, 9200);
        vm.stopPrank();

        vm.startPrank(validator2);
        flock.validateModel(0, 0, 8000);
        flock.validateModel(0, 1, 8800);
        vm.stopPrank();

        uint256 winnerId = flock.selectWinner(0);
        assertEq(winnerId, 1);
        flock.deployModel(0);

        HiveFLock.TrainingTask memory task = flock.getTask(0);
        assertEq(uint8(task.status), uint8(HiveFLock.TaskStatus.Completed));
        assertTrue(flock.deployedModels(0) != bytes32(0));
        assertTrue(flock.getWinner(0).isWinner);
    }

    // ═══ Ownership ═══

    function test_transfer_ownership() public {
        flock.transferOwnership(user1);
        assertEq(flock.owner(), user1);
    }

    function test_transfer_ownership_revert_not_owner() public {
        vm.prank(user1);
        vm.expectRevert("Flock: not owner");
        flock.transferOwnership(user1);
    }

    function test_transfer_ownership_revert_zero() public {
        vm.expectRevert("zero address");
        flock.transferOwnership(address(0));
    }

    // ═══ Helpers ═══

    function _createAndActivateTask() internal {
        flock.createTask{value: 0}("t", "d", HiveFLock.ModelType.PricePrediction, 3, 0.1 ether, block.timestamp + 7 days);
        flock.activateTask(0);
    }

    function _submitTestModel(address submitter) internal {
        vm.deal(submitter, 1 ether);
        vm.prank(submitter);
        flock.submitModel{value: 0.1 ether}(0, keccak256(bytes("model-1")), "ipfs://QmModel1");
    }

    function _createFullTask() internal {
        flock.createTask{value: 0.5 ether}("t", "d", HiveFLock.ModelType.PricePrediction, 3, 0.1 ether, block.timestamp + 7 days);
        flock.activateTask(0);
        vm.deal(submitter1, 1 ether);
        vm.prank(submitter1);
        flock.submitModel{value: 0.1 ether}(0, keccak256(bytes("model-1")), "ipfs://QmModel1");
        flock.startVoting(0);
    }

    function _completeFullTask() internal {
        _createFullTask();
        vm.prank(validator1);
        flock.validateModel(0, 0, 8500);
        flock.selectWinner(0);
    }
}
