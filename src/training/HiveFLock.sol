// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {RitualPrecompileConsumer} from "../libraries/RitualPrecompileConsumer.sol";

/// @title HiveFLock — Federated Learning for Hive AI
/// @notice Training tasks, model submissions, validator voting, winner selection
/// @dev Self-improving AI via federated learning with on-chain coordination
contract HiveFLock is RitualPrecompileConsumer {
    // ═══ State ═══

    address public owner;
    uint256 public taskCount;

    struct Task {
        string name;
        string description;
        uint256 rewardPool;
        uint256 deadline;
        uint256 maxSubmissions;
        uint256 submissionCount;
        uint256 winnerIndex;
        bool finalized;
        address creator;
    }

    struct Submission {
        address trainer;
        string ipfsHash;        // Model IPFS hash
        uint256 accuracy;       // Accuracy score (basis points, 10000 = 100%)
        uint256 votes;          // Validator votes
        bool claimed;
    }

    struct Model {
        string name;
        string ipfsHash;
        string description;
        uint256 accuracy;
        uint256 version;
        address owner;
    }

    mapping(uint256 => Task) public tasks;
    mapping(uint256 => Submission[]) public submissions;
    mapping(string => Model) public models;
    string[] public modelNames;

    // ═══ Events ═══

    event TaskCreated(uint256 indexed taskId, string name, uint256 rewardPool, uint256 deadline);
    event ModelSubmitted(uint256 indexed taskId, address indexed trainer, string ipfsHash, uint256 accuracy);
    event VoteCast(uint256 indexed taskId, uint256 submissionIndex, address indexed validator);
    event TaskFinalized(uint256 indexed taskId, uint256 winnerIndex);
    event RewardClaimed(uint256 indexed taskId, address indexed trainer, uint256 amount);
    event ModelRegistered(string name, string ipfsHash);
    event ModelUpdated(string name, string ipfsHash, uint256 accuracy);

    // ═══ Modifiers ═══

    modifier onlyOwner() {
        require(msg.sender == owner, "FLock: not owner");
        _;
    }

    // ═══ Constructor ═══

    constructor(address _owner) {
        owner = _owner;
    }

    // ═══ Training Tasks ═══

    /// @notice Create a new training task
    function createTask(
        string calldata name,
        string calldata description,
        uint256 rewardPool,
        uint256 deadline,
        uint256 maxSubmissions
    ) external payable onlyOwner returns (uint256 taskId) {
        require(deadline > block.timestamp, "FLock: deadline in past");
        require(maxSubmissions > 0, "FLock: zero submissions");
        require(msg.value >= rewardPool, "FLock: insufficient reward");

        taskId = ++taskCount;
        tasks[taskId] = Task({
            name: name,
            description: description,
            rewardPool: rewardPool,
            deadline: deadline,
            maxSubmissions: maxSubmissions,
            submissionCount: 0,
            winnerIndex: 0,
            finalized: false,
            creator: msg.sender
        });

        emit TaskCreated(taskId, name, rewardPool, deadline);
    }

    /// @notice Submit a model for a task
    function submitModel(uint256 taskId, string calldata ipfsHash, uint256 accuracy) external {
        Task storage task = tasks[taskId];
        require(block.timestamp <= task.deadline, "FLock: deadline passed");
        require(task.submissionCount < task.maxSubmissions, "FLock: max submissions");
        require(accuracy <= 10000, "FLock: accuracy > 100%");

        submissions[taskId].push(Submission({
            trainer: msg.sender,
            ipfsHash: ipfsHash,
            accuracy: accuracy,
            votes: 0,
            claimed: false
        }));

        task.submissionCount++;
        emit ModelSubmitted(taskId, msg.sender, ipfsHash, accuracy);
    }

    /// @notice Vote for a submission (validator)
    function vote(uint256 taskId, uint256 submissionIndex) external {
        Task storage task = tasks[taskId];
        require(!task.finalized, "FLock: already finalized");
        require(submissionIndex < task.submissionCount, "FLock: invalid submission");

        submissions[taskId][submissionIndex].votes++;
        emit VoteCast(taskId, submissionIndex, msg.sender);
    }

    /// @notice Finalize task and select winner
    function finalize(uint256 taskId) external onlyOwner {
        Task storage task = tasks[taskId];
        require(!task.finalized, "FLock: already finalized");
        require(block.timestamp > task.deadline, "FLock: not ended");
        require(task.submissionCount > 0, "FLock: no submissions");

        // Select winner by highest accuracy (votes as tiebreaker)
        uint256 bestAccuracy = 0;
        uint256 bestVotes = 0;
        uint256 winnerIdx = 0;

        Submission[] storage subs = submissions[taskId];
        for (uint256 i = 0; i < subs.length; i++) {
            if (subs[i].accuracy > bestAccuracy ||
                (subs[i].accuracy == bestAccuracy && subs[i].votes > bestVotes)) {
                bestAccuracy = subs[i].accuracy;
                bestVotes = subs[i].votes;
                winnerIdx = i;
            }
        }

        task.finalized = true;
        task.winnerIndex = winnerIdx;

        emit TaskFinalized(taskId, winnerIdx);
    }

    // ═══ Rewards ═══

    /// @notice Claim reward (winner only)
    function claimReward(uint256 taskId) external {
        Task storage task = tasks[taskId];
        require(task.finalized, "FLock: not finalized");

        Submission storage winner = submissions[taskId][task.winnerIndex];
        require(winner.trainer == msg.sender, "FLock: not winner");
        require(!winner.claimed, "FLock: already claimed");

        winner.claimed = true;

        (bool success, ) = msg.sender.call{value: task.rewardPool}("");
        require(success, "FLock: transfer failed");

        emit RewardClaimed(taskId, msg.sender, task.rewardPool);
    }

    // ═══ Model Registry ═══

    /// @notice Register a model
    function registerModel(string calldata name, string calldata ipfsHash, string calldata description) external onlyOwner {
        models[name] = Model({
            name: name,
            ipfsHash: ipfsHash,
            description: description,
            accuracy: 0,
            version: 1,
            owner: msg.sender
        });

        modelNames.push(name);
        emit ModelRegistered(name, ipfsHash);
    }

    /// @notice Update a model
    function updateModel(string calldata name, string calldata ipfsHash, uint256 accuracy) external onlyOwner {
        Model storage model = models[name];
        require(model.version > 0, "FLock: model not found");

        model.ipfsHash = ipfsHash;
        model.accuracy = accuracy;
        model.version++;

        emit ModelUpdated(name, ipfsHash, accuracy);
    }

    // ═══ View Functions ═══

    function getTask(uint256 taskId) external view returns (Task memory) {
        return tasks[taskId];
    }

    function getSubmission(uint256 taskId, uint256 index) external view returns (Submission memory submission, uint256 votes) {
        Submission storage sub = submissions[taskId][index];
        return (sub, sub.votes);
    }

    function getSubmissionCount(uint256 taskId) external view returns (uint256 count, uint256 max) {
        Task storage task = tasks[taskId];
        return (task.submissionCount, task.maxSubmissions);
    }

    function getModel(string calldata name) external view returns (Model memory) {
        return models[name];
    }

    function getModelNames() external view returns (string[] memory) {
        return modelNames;
    }
}
