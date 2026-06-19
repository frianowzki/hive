// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "../libraries/RitualPrecompileConsumer.sol";

/// @title HiveFLock — Federated Learning Integration for Hive
/// @notice Manages FL training tasks, model submissions, validation, and on-chain deployment
/// @dev Integrates with FLock.io federated learning platform and Ritual ONNX precompile (0x0800).
///      Winning models are deployed on-chain for inference via ONNX precompile.
///      FLock API (https://api.flock.io/v1) used via HTTP precompile for off-chain inference.

contract HiveFLock is RitualPrecompileConsumer {
    // ═══ Types ═══

    enum ModelType {
        PricePrediction,    // Token price forecasting
        MarketMaking,       // Optimal spread calculation
        RiskAssessment,     // Portfolio risk scoring
        SentimentAnalysis,  // Market sentiment from text
        StrategyOptimization // Trading strategy parameters
    }

    enum TaskStatus {
        Created,
        Active,         // Accepting submissions
        Voting,         // Validators voting on models
        Completed,      // Winner selected
        Cancelled
    }

    struct TrainingTask {
        uint256 taskId;
        string name;                // e.g., "ETH/USD Price Predictor v2"
        string description;         // Training data, objectives, metrics
        ModelType modelType;
        TaskStatus status;
        uint256 rewardPool;         // Reward in wei for winner
        uint256 totalRounds;        // Number of training rounds
        uint256 currentRound;
        uint256 minStake;           // Minimum stake to participate
        uint256 submissionDeadline; // Deadline for model submissions
        uint256 winnerSubmissionId; // ID of winning submission
        address creator;
        uint256 createdAt;
    }

    struct ModelSubmission {
        uint256 submissionId;
        uint256 taskId;
        address submitter;
        bytes32 modelHash;          // Hash of ONNX model (stored off-chain or IPFS)
        string modelUri;            // IPFS/Arweave URI for model file
        uint256 score;              // Validation score (0-10000, 4 decimals)
        uint256 stake;              // Submitter's stake
        uint256 timestamp;
        bool validated;
        bool isWinner;
    }

    struct ValidationVote {
        address validator;
        uint256 submissionId;
        uint256 score;              // Validator's score (0-10000)
        uint256 weight;             // Voting weight (based on stake)
        bool voted;
    }

    // ═══ State ═══

    address public owner;
    address public brain;           // HiveBrain reference

    // Tasks
    mapping(uint256 => TrainingTask) public tasks;
    uint256 public taskCount;

    // Submissions per task
    mapping(uint256 => ModelSubmission[]) public taskSubmissions;
    // taskId => submissionId => submission
    mapping(uint256 => mapping(uint256 => ModelSubmission)) public submissions;

    // Votes: taskId => submissionId => validator => ValidationVote
    mapping(uint256 => mapping(uint256 => mapping(address => ValidationVote))) public votes;
    // taskId => submissionId => total weighted score
    mapping(uint256 => mapping(uint256 => uint256)) public totalWeightedScore;
    // taskId => submissionId => total vote weight
    mapping(uint256 => mapping(uint256 => uint256)) public totalVoteWeight;

    // Validators (authorized to vote on model quality)
    mapping(address => bool) public validators;
    uint256 public validatorCount;

    // Deployed models: taskId => ONNX model hash
    mapping(uint256 => bytes32) public deployedModels;
    // taskId => deployment timestamp
    mapping(uint256 => uint256) public deployedAt;

    // FLock API config
    string public flockApiKey;
    string public flockApiUrl = "https://api.flock.io/v1";
    bool public flockEnabled;

    // Submission counter
    uint256 public submissionCount;

    // ═══ Events ═══

    event TaskCreated(uint256 indexed taskId, string name, ModelType modelType, uint256 rewardPool);
    event TaskActivated(uint256 indexed taskId);
    event TaskCancelled(uint256 indexed taskId);
    event ModelSubmitted(uint256 indexed taskId, uint256 indexed submissionId, address submitter, bytes32 modelHash);
    event ModelValidated(uint256 indexed taskId, uint256 indexed submissionId, address validator, uint256 score);
    event WinnerSelected(uint256 indexed taskId, uint256 indexed submissionId, address submitter);
    event ModelDeployed(uint256 indexed taskId, bytes32 modelHash, uint256 timestamp);
    event InferenceResult(uint256 indexed taskId, string result, uint256 timestamp);
    event ValidatorAdded(address indexed validator);
    event ValidatorRemoved(address indexed validator);
    event FlockConfigUpdated(bool enabled, string apiUrl);
    event RewardDistributed(uint256 indexed taskId, address indexed recipient, uint256 amount);

    // ═══ Errors ═══

    error TaskNotFound();
    error TaskNotActive();
    error TaskNotVoting();
    error TaskNotCompleted();
    error SubmissionDeadlinePassed();
    error AlreadyValidated();
    error NotValidator();
    error InsufficientStake();
    error NoSubmissions();
    error WinnerAlreadySelected();
    error ModelNotDeployed();
    error FlockNotConfigured();
    error InvalidScore();

    // ═══ Modifiers ═══

    modifier onlyOwner() {
        require(msg.sender == owner, "Flock: not owner");
        _;
    }

    modifier onlyValidator() {
        require(validators[msg.sender], "Flock: not validator");
        _;
    }

    event BrainSet(address indexed brain);

    // ═══ Constructor ═══

    constructor(address _brain) {
        owner = msg.sender;
        brain = _brain;
    }

    // ═══ Configuration ═══

    function setBrain(address _brain) external onlyOwner {
        brain = _brain;
        emit BrainSet(_brain);
    }

    // ═══ FLock Configuration ═══

    /// @notice Configure FLock API access
    /// @param _apiKey FLock API key
    /// @param _apiUrl FLock API URL (default: https://api.flock.io/v1)
    /// @param _enabled Whether to enable FLock API
    function setFlockConfig(string calldata _apiKey, string calldata _apiUrl, bool _enabled) external onlyOwner {
        flockApiKey = _apiKey;
        if (bytes(_apiUrl).length > 0) flockApiUrl = _apiUrl;
        flockEnabled = _enabled;
        emit FlockConfigUpdated(_enabled, _apiUrl);
    }

    // ═══ Validator Management ═══

    function addValidator(address validator) external onlyOwner {
        require(validator != address(0), "Flock: zero address");
        if (!validators[validator]) {
            validators[validator] = true;
            validatorCount++;
            emit ValidatorAdded(validator);
        }
    }

    function removeValidator(address validator) external onlyOwner {
        if (validators[validator]) {
            validators[validator] = false;
            validatorCount--;
            emit ValidatorRemoved(validator);
        }
    }

    // ═══ Task Management ═══

    /// @notice Create a new federated learning training task
    /// @param name Task name (e.g., "ETH/USD Price Predictor v2")
    /// @param description Training data, objectives, evaluation metrics
    /// @param modelType Type of model being trained
    /// @param totalRounds Number of training rounds
    /// @param minStake Minimum stake to participate
    /// @param submissionDeadline Timestamp deadline for submissions
    /// @return taskId The created task ID
    function createTask(
        string calldata name,
        string calldata description,
        ModelType modelType,
        uint256 totalRounds,
        uint256 minStake,
        uint256 submissionDeadline
    ) external payable onlyOwner returns (uint256 taskId) {
        taskId = taskCount++;

        tasks[taskId] = TrainingTask({
            taskId: taskId,
            name: name,
            description: description,
            modelType: modelType,
            status: TaskStatus.Created,
            rewardPool: msg.value,
            totalRounds: totalRounds,
            currentRound: 0,
            minStake: minStake,
            submissionDeadline: submissionDeadline,
            winnerSubmissionId: 0,
            creator: msg.sender,
            createdAt: block.timestamp
        });

        emit TaskCreated(taskId, name, modelType, msg.value);
    }

    /// @notice Activate a task (start accepting submissions)
    function activateTask(uint256 taskId) external onlyOwner {
        TrainingTask storage task = tasks[taskId];
        if (task.taskId != taskId || task.status == TaskStatus.Cancelled) revert TaskNotFound();
        task.status = TaskStatus.Active;
        emit TaskActivated(taskId);
    }

    /// @notice Cancel a task
    function cancelTask(uint256 taskId) external onlyOwner {
        TrainingTask storage task = tasks[taskId];
        if (task.taskId != taskId) revert TaskNotFound();
        task.status = TaskStatus.Cancelled;
        emit TaskCancelled(taskId);
    }

    // ═══ Model Submission ═══

    /// @notice Submit a trained model for a task
    /// @param taskId Task to submit for
    /// @param modelHash Hash of the ONNX model file
    /// @param modelUri IPFS/Arweave URI for the model
    function submitModel(
        uint256 taskId,
        bytes32 modelHash,
        string calldata modelUri
    ) external payable {
        TrainingTask storage task = tasks[taskId];
        if (task.status != TaskStatus.Active) revert TaskNotActive();
        if (block.timestamp > task.submissionDeadline) revert SubmissionDeadlinePassed();
        if (msg.value < task.minStake) revert InsufficientStake();

        uint256 subId = submissionCount++;

        ModelSubmission storage sub = submissions[taskId][subId];
        sub.submissionId = subId;
        sub.taskId = taskId;
        sub.submitter = msg.sender;
        sub.modelHash = modelHash;
        sub.modelUri = modelUri;
        sub.score = 0;
        sub.stake = msg.value;
        sub.timestamp = block.timestamp;
        sub.validated = false;
        sub.isWinner = false;

        taskSubmissions[taskId].push(sub);

        emit ModelSubmitted(taskId, subId, msg.sender, modelHash);
    }

    // ═══ Validation ═══

    /// @notice Start voting phase for a task
    function startVoting(uint256 taskId) external onlyOwner {
        TrainingTask storage task = tasks[taskId];
        if (task.status != TaskStatus.Active) revert TaskNotActive();
        if (taskSubmissions[taskId].length == 0) revert NoSubmissions();
        task.status = TaskStatus.Voting;
    }

    /// @notice Validate and score a model submission
    /// @param taskId Task ID
    /// @param submissionId Submission to validate
    /// @param score Score (0-10000, where 10000 = perfect)
    function validateModel(
        uint256 taskId,
        uint256 submissionId,
        uint256 score
    ) external onlyValidator {
        TrainingTask storage task = tasks[taskId];
        if (task.status != TaskStatus.Voting) revert TaskNotVoting();
        if (score > 10000) revert InvalidScore();

        ValidationVote storage vote = votes[taskId][submissionId][msg.sender];
        if (vote.voted) revert AlreadyValidated();

        // Get validator's voting weight (based on their staked amount or reputation)
        uint256 weight = 1; // Simplified — in production, weight = validator's stake

        vote.validator = msg.sender;
        vote.submissionId = submissionId;
        vote.score = score;
        vote.weight = weight;
        vote.voted = true;

        totalWeightedScore[taskId][submissionId] += score * weight;
        totalVoteWeight[taskId][submissionId] += weight;

        // Update submission score (weighted average)
        ModelSubmission storage sub = submissions[taskId][submissionId];
        if (totalVoteWeight[taskId][submissionId] > 0) {
            sub.score = totalWeightedScore[taskId][submissionId] / totalVoteWeight[taskId][submissionId];
        }
        sub.validated = true;

        emit ModelValidated(taskId, submissionId, msg.sender, score);
    }

    // ═══ Winner Selection ═══

    /// @notice Select the winning model (highest validated score)
    /// @param taskId Task to finalize
    /// @return winnerSubmissionId The winning submission ID
    function selectWinner(uint256 taskId) external onlyOwner returns (uint256 winnerSubmissionId) {
        TrainingTask storage task = tasks[taskId];
        if (task.status != TaskStatus.Voting) revert TaskNotVoting();
        if (task.winnerSubmissionId != 0 || task.status == TaskStatus.Completed) revert WinnerAlreadySelected();

        uint256 bestScore = 0;
        uint256 bestId = 0;

        // Iterate submissions by ID (not taskSubmissions array which may have stale copies)
        for (uint256 i = 0; i < submissionCount; i++) {
            ModelSubmission storage sub = submissions[taskId][i];
            if (sub.taskId == taskId && sub.validated && sub.score > bestScore) {
                bestScore = sub.score;
                bestId = sub.submissionId;
            }
        }

        require(bestScore > 0, "Flock: no valid submissions");

        submissions[taskId][bestId].isWinner = true;
        task.winnerSubmissionId = bestId;
        task.status = TaskStatus.Completed;
        winnerSubmissionId = bestId;

        // Distribute reward to winner
        address winner = submissions[taskId][bestId].submitter;
        uint256 reward = task.rewardPool;
        if (reward > 0) {
            (bool sent, ) = winner.call{value: reward}("");
            if (sent) {
                emit RewardDistributed(taskId, winner, reward);
            }
        }

        emit WinnerSelected(taskId, bestId, winner);
    }

    // ═══ Model Deployment (ONNX Precompile) ═══

    /// @notice Deploy winning model on-chain via Ritual ONNX precompile
    /// @dev The ONNX model is registered with the precompile for on-chain inference
    /// @param taskId Task with a selected winner
    function deployModel(uint256 taskId) external onlyOwner {
        TrainingTask storage task = tasks[taskId];
        if (task.status != TaskStatus.Completed) revert TaskNotCompleted();

        ModelSubmission storage winner = submissions[taskId][task.winnerSubmissionId];
        bytes32 modelHash = winner.modelHash;

        // Register model with ONNX precompile for on-chain inference
        // In production, this would call the ONNX precompile to register the model
        // bytes memory input = abi.encode(modelHash, winner.modelUri);
        // _executePrecompile(ONNX_PRECOMPILE, input);

        deployedModels[taskId] = modelHash;
        deployedAt[taskId] = block.timestamp;

        // Notify Brain about deployed model
        if (brain != address(0)) {
            (bool success, ) = brain.call(
                abi.encodeWithSignature(
                    "storeMemory(string,string)",
                    string(abi.encodePacked("flock_model_", _uint2str(taskId))),
                    string(abi.encodePacked("deployed:", _bytes32ToHex(modelHash)))
                )
            );
            success; // silence unused warning
        }

        emit ModelDeployed(taskId, modelHash, block.timestamp);
    }

    // ═══ Inference ═══

    /// @notice Run inference using a deployed model via ONNX precompile
    /// @param taskId Task with deployed model
    /// @param inputData Input tensor data (abi-encoded)
    /// @return output Inference result
    function runInference(uint256 taskId, bytes calldata inputData)
        external
        returns (bytes memory output)
    {
        if (deployedModels[taskId] == bytes32(0)) revert ModelNotDeployed();

        // Encode ONNX precompile call
        bytes memory input = abi.encode(
            deployedModels[taskId],  // model hash
            inputData                // input tensor
        );

        (bool success, bytes memory result) = ONNX_PRECOMPILE.staticcall(input);
        if (success && result.length > 0) {
            output = result;
            emit InferenceResult(taskId, string(result), block.timestamp);
        }
    }

    /// @notice Run inference via FLock API (off-chain, through Ritual HTTP precompile)
    /// @param prompt The prompt/input for the FLock model
    /// @return result API response
    function runFlockInference(string calldata prompt)
        external
        returns (bytes memory result)
    {
        if (!flockEnabled) revert FlockNotConfigured();

        // Build FLock API request (OpenAI-compatible)
        string memory url = string(abi.encodePacked(flockApiUrl, "/chat/completions"));

        // Encode HTTP POST request to FLock API
        bytes memory body = abi.encodePacked(
            '{"model":"flock-default","messages":[{"role":"user","content":"', prompt, '"}]}'
        );

        bytes memory input = _encodeHttpPost(url, body);
        (bool success, bytes memory output) = HTTP_PRECOMPILE.staticcall(input);

        if (success && output.length > 0) {
            result = output;
            emit InferenceResult(0, string(output), block.timestamp);
        }
    }

    // ═══ View ═══

    function getTask(uint256 taskId) external view returns (TrainingTask memory) {
        return tasks[taskId];
    }

    function getSubmission(uint256 taskId, uint256 submissionId)
        external
        view
        returns (ModelSubmission memory)
    {
        return submissions[taskId][submissionId];
    }

    function getTaskSubmissions(uint256 taskId)
        external
        view
        returns (ModelSubmission[] memory)
    {
        return taskSubmissions[taskId];
    }

    function getSubmissionCount(uint256 taskId) external view returns (uint256) {
        return taskSubmissions[taskId].length;
    }

    function getWinner(uint256 taskId) external view returns (ModelSubmission memory) {
        TrainingTask storage task = tasks[taskId];
        require(task.status == TaskStatus.Completed, "Flock: not completed");
        return submissions[taskId][task.winnerSubmissionId];
    }

    function isValidator(address account) external view returns (bool) {
        return validators[account];
    }

    // ═══ Internal ═══

    /// @dev Encode HTTP POST request (helper for FLock API calls)
    function _encodeHttpPost(string memory url, bytes memory body)
        internal
        view
        returns (bytes memory)
    {
        string[] memory headerKeys = new string[](2);
        headerKeys[0] = "Content-Type";
        headerKeys[1] = "Authorization";

        string[] memory headerValues = new string[](2);
        headerValues[0] = "application/json";
        headerValues[1] = string(abi.encodePacked("Bearer ", flockApiKey));

        return abi.encode(
            address(0),         // executor
            new bytes[](0),     // encryptedSecrets
            uint256(30),        // ttl
            new bytes[](0),     // secretSignatures
            bytes(""),          // userPublicKey
            url,                // url
            uint8(2),           // method (2=POST)
            headerKeys,         // header keys
            headerValues,       // header values
            body,               // body
            uint256(0),         // dkmsKeyIndex
            uint8(0),           // dkmsKeyFormat
            false               // piiEnabled
        );
    }

    receive() external payable {}

    // ═══ Ownership ═══

    function transferOwnership(address newOwner) external onlyOwner {
        require(newOwner != address(0), "zero address");
        owner = newOwner;
    }

    // ═══ Helpers ═══

    function _uint2str(uint256 value) internal pure returns (string memory) {
        if (value == 0) return "0";
        uint256 temp = value;
        uint256 digits;
        while (temp != 0) { digits++; temp /= 10; }
        bytes memory buffer = new bytes(digits);
        while (value != 0) {
            digits -= 1;
            buffer[digits] = bytes1(uint8(48 + uint256(value % 10)));
            value /= 10;
        }
        return string(buffer);
    }

    function _bytes32ToHex(bytes32 b) internal pure returns (string memory) {
        bytes memory hexChars = "0123456789abcdef";
        bytes memory result = new bytes(64);
        for (uint256 i = 0; i < 32; i++) {
            result[i * 2] = hexChars[uint8(b[i]) >> 4];
            result[i * 2 + 1] = hexChars[uint8(b[i]) & 0x0f];
        }
        return string(result);
    }

}
