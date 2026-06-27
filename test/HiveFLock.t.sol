// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/training/HiveFLock.sol";

contract HiveFLockTest is Test {
    HiveFLock public flock;

    address public owner = address(this);
    address public trainer1 = address(0x1);
    address public trainer2 = address(0x2);
    address public validator = address(0x3);

    function setUp() public {
        flock = new HiveFLock(owner);
    }

    // ═══ Training Task Tests ═══

    function testCreateTask() public {
        uint256 taskId = flock.createTask{value: 100 ether}(
            "Price Prediction Model",
            "Predict ETH price 1h ahead",
            100 ether,           // reward pool
            block.timestamp + 7 days,  // deadline
            3                    // max submissions
        );

        HiveFLock.Task memory task = flock.getTask(taskId);
        assertEq(task.name, "Price Prediction Model");
        assertEq(task.rewardPool, 100 ether);
        assertEq(task.maxSubmissions, 3);
        assertFalse(task.finalized);
    }

    function testSubmitModel() public {
        uint256 taskId = _createActiveTask();

        vm.prank(trainer1);
        flock.submitModel(taskId, "QmModelHash1", 8500); // 85% accuracy

        vm.prank(trainer2);
        flock.submitModel(taskId, "QmModelHash2", 9200); // 92% accuracy

        (uint256 count, ) = flock.getSubmissionCount(taskId);
        assertEq(count, 2);
    }

    function testVote() public {
        uint256 taskId = _createActiveTask();

        vm.prank(trainer1);
        flock.submitModel(taskId, "QmModelHash1", 8500);

        vm.prank(validator);
        flock.vote(taskId, 0); // vote for submission 0

        (, uint256 votes) = flock.getSubmission(taskId, 0);
        assertEq(votes, 1);
    }

    function testFinalize() public {
        uint256 taskId = _createActiveTask();

        vm.prank(trainer1);
        flock.submitModel(taskId, "QmModelHash1", 8500);

        vm.prank(trainer2);
        flock.submitModel(taskId, "QmModelHash2", 9200);

        // Warp past deadline
        vm.warp(block.timestamp + 8 days);

        flock.finalize(taskId);

        HiveFLock.Task memory task = flock.getTask(taskId);
        assertTrue(task.finalized);
        assertEq(task.winnerIndex, 1); // higher accuracy wins
    }

    // ═══ Reward Tests ═══

    function testClaimReward() public {
        uint256 taskId = _createAndFinalizeTask();

        uint256 balBefore = trainer2.balance;
        vm.prank(trainer2);
        flock.claimReward(taskId);
        uint256 balAfter = trainer2.balance;

        assertEq(balAfter - balBefore, 100 ether); // winner gets full pool
    }

    // ═══ Model Registry Tests ═══

    function testRegisterModel() public {
        flock.registerModel("ETH-Predictor-v1", "QmModelHash", "Price prediction");
        HiveFLock.Model memory model = flock.getModel("ETH-Predictor-v1");
        assertEq(model.name, "ETH-Predictor-v1");
        assertEq(model.ipfsHash, "QmModelHash");
    }

    function testUpdateModel() public {
        flock.registerModel("ETH-Predictor-v1", "QmModelHash", "Price prediction");
        flock.updateModel("ETH-Predictor-v1", "QmNewHash", 9500);

        HiveFLock.Model memory model = flock.getModel("ETH-Predictor-v1");
        assertEq(model.ipfsHash, "QmNewHash");
        assertEq(model.accuracy, 9500);
    }

    // ═══ Helpers ═══

    function _createActiveTask() internal returns (uint256) {
        return flock.createTask{value: 100 ether}(
            "Test Task", "Description", 100 ether,
            block.timestamp + 7 days, 3
        );
    }

    function _createAndFinalizeTask() internal returns (uint256) {
        uint256 taskId = _createActiveTask();

        vm.prank(trainer1);
        flock.submitModel(taskId, "QmModelHash1", 8500);

        vm.prank(trainer2);
        flock.submitModel(taskId, "QmModelHash2", 9200);

        vm.warp(block.timestamp + 8 days);
        flock.finalize(taskId);

        return taskId;
    }
}
