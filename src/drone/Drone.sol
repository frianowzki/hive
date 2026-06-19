// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {RitualPrecompileConsumer} from "../libraries/RitualPrecompileConsumer.sol";

/// @title Drone — Sub-Agent Spawner
/// @notice Specialized sub-agents spawned by Queen for focused tasks

contract Drone is RitualPrecompileConsumer {
    // ═══ State ═══

    address public queen;
    string public purpose;
    uint256 public capitalAllocated;
    uint256 public spawnBlock;
    bool public active;
    bool public terminated;

    enum DroneType { Sniper, Researcher, Negotiator, Guardian }

    DroneType public droneType;

    struct DroneTask {
        string description;
        bytes data;
        address target;
        uint256 value;
        bool completed;
        bool success;
        string result;
    }

    DroneTask[] public tasks;
    uint256 public taskCount;
    uint256 public completedTasks;

    // ═══ Events ═══

    event TaskAssigned(uint256 indexed taskId, string description);
    event TaskCompleted(uint256 indexed taskId, bool success, string result);
    event DroneTerminated(uint256 capitalReturned);
    event ProfitsReturned(uint256 amount);

    // ═══ Modifiers ═══

    modifier onlyQueen() {
        require(msg.sender == queen, "Drone: not queen");
        _;
    }

    modifier whenActive() {
        require(active && !terminated, "Drone: not active");
        _;
    }

    // ═══ Constructor ═══

    constructor(
        address _queen,
        string memory _purpose,
        DroneType _droneType,
        uint256 _capital
    ) payable {
        queen = _queen;
        purpose = _purpose;
        droneType = _droneType;
        capitalAllocated = _capital;
        spawnBlock = block.number;
        active = true;
    }

    // ═══ Task Management ═══

    /// @notice Assign a task to this drone
    function assignTask(
        string calldata description,
        address target,
        bytes calldata data,
        uint256 value
    ) external onlyQueen whenActive returns (uint256 taskId) {
        taskId = taskCount++;
        tasks[taskId] = DroneTask({
            description: description,
            data: data,
            target: target,
            value: value,
            completed: false,
            success: false,
            result: ""
        });

        emit TaskAssigned(taskId, description);
    }

    /// @notice Execute assigned task
    function executeTask(uint256 taskId) external whenActive {
        require(taskId < taskCount, "Drone: invalid task");
        DroneTask storage task = tasks[taskId];
        require(!task.completed, "Drone: already completed");

        bool success = false;
        string memory result = "";

        if (task.target != address(0)) {
            (success, ) = task.target.call{value: task.value}(task.data);
            result = success ? "executed" : "failed";
        } else {
            // LLM-based task execution
            string memory prompt = string(abi.encodePacked(
                "You are a Hive drone. Type: ", _droneTypeStr(), ". ",
                "Purpose: ", purpose, ". ",
                "Task: ", task.description, ". ",
                "Execute this task. Reply with your result."
            ));

            bytes memory llmInput = _encodeLlmCall(prompt);
            (bool llmSuccess, bytes memory output) = LLM_PRECOMPILE.staticcall(llmInput);

            if (llmSuccess && output.length > 0) {
                result = abi.decode(output, (string));
                success = true;
            } else {
                result = "LLM unavailable";
            }
        }

        task.completed = true;
        task.success = success;
        task.result = result;
        completedTasks++;

        if (success) {
            capitalAllocated = address(this).balance;
        }

        emit TaskCompleted(taskId, success, result);
    }

    // ═══ Lifecycle ═══

    /// @notice Return profits to queen
    function returnProfits() external onlyQueen {
        uint256 balance = address(this).balance;
        require(balance > 0, "Drone: no balance");

        (bool success, ) = queen.call{value: balance}("");
        require(success, "Drone: transfer failed");

        emit ProfitsReturned(balance);
    }

    /// @notice Terminate drone
    function terminate() external onlyQueen {
        active = false;
        terminated = true;

        uint256 balance = address(this).balance;
        if (balance > 0) {
            (bool success, ) = queen.call{value: balance}("");
            require(success, "Drone: transfer failed");
        }

        emit DroneTerminated(balance);
    }

    // ═══ View ═══

    function getTask(uint256 taskId) external view returns (DroneTask memory) {
        require(taskId < taskCount, "Drone: invalid task");
        return tasks[taskId];
    }

    function performance() external view returns (uint256 successRate, uint256 tasksCompleted) {
        tasksCompleted = completedTasks;
        if (completedTasks == 0) {
            successRate = 0;
            return (successRate, tasksCompleted);
        }

        uint256 successes = 0;
        for (uint256 i = 0; i < taskCount; i++) {
            if (tasks[i].completed && tasks[i].success) {
                successes++;
            }
        }
        successRate = (successes * 10_000) / completedTasks;
    }

    // ═══ Internal ═══

    function _droneTypeStr() internal view returns (string memory) {
        if (droneType == DroneType.Sniper) return "Sniper";
        if (droneType == DroneType.Researcher) return "Researcher";
        if (droneType == DroneType.Negotiator) return "Negotiator";
        return "Guardian";
    }

    receive() external payable {}
}
