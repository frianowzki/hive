// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "../interfaces/IEigenLayer.sol";

/// @title HiveEigenLayer — EigenLayer AVS Integration for Hive
/// @notice Registers Hive as an AVS, manages operators, handles delegation and slashing
/// @dev Integrates with EigenLayer's DelegationManager, StrategyManager, AVSDirectory, and Slasher.
///      Hive becomes an Actively Validated Service secured by restaked ETH.
///      Operators run Hive services (market making, inference, validation) and earn fees.
///      Slashing conditions enforce honest behavior.

contract HiveEigenLayer {
    // ═══ Types ═══

    enum OperatorRole {
        None,
        MarketMaker,        // Runs HiveMarketMaker
        InferenceNode,      // Runs HiveBrain inference
        Validator,          // Validates model quality (FLock)
        PriceOracle         // Runs HiveOracle price feeds
    }

    enum SlashingReason {
        None,
        FrontRunning,       // Detected front-running behavior
        FalseValidation,    // Submitted false validation scores
        Downtime,           // Operator offline beyond threshold
        DataManipulation,   // Manipulated price/inference data
        DoubleSigning       // Signed conflicting messages
    }

    struct Operator {
        address operatorAddress;
        OperatorRole role;
        uint256 registeredAt;
        uint256 totalFeesEarned;
        uint256 slashCount;
        uint256 lastHeartbeat;
        bool active;
        string metadataURI;     // Off-chain metadata (IPFS/Arweave)
    }

    struct Delegation {
        address staker;
        address operator;
        uint256 amount;
        uint256 delegatedAt;
        bool active;
    }

    struct SlashRecord {
        uint256 slashId;
        address operator;
        SlashingReason reason;
        uint256 amount;
        uint256 timestamp;
        address reporter;
        string evidence;        // Off-chain evidence URI
    }

    struct ServiceTask {
        uint256 taskId;
        OperatorRole requiredRole;
        string description;
        uint256 reward;
        uint256 deadline;
        address assignedOperator;
        bool completed;
        bool validated;
    }

    // ═══ State ═══

    address public owner;
    address public hiveStaking;         // HiveStaking contract reference

    // EigenLayer contract references
    IDelegationManager public delegationManager;
    IStrategyManager public strategyManager;
    IAVSDirectory public avsDirectory;
    ISlasher public slasher;

    // AVS registration
    bool public registeredAsAVS;
    string public avsMetadataURI;

    // Operators
    mapping(address => Operator) public operators;
    address[] public operatorList;
    uint256 public operatorCount;

    // Delegations: staker => Delegation
    mapping(address => Delegation) public delegations;
    // operator => total delegated amount
    mapping(address => uint256) public operatorDelegatedAmount;
    // operator => staker list
    mapping(address => address[]) public operatorStakers;

    // Slashing
    mapping(uint256 => SlashRecord) public slashRecords;
    uint256 public slashCount;
    uint256 public totalSlashed;

    // Service tasks
    mapping(uint256 => ServiceTask) public serviceTasks;
    uint256 public taskCount;

    // Configuration
    uint256 public minStakeForOperator;     // Minimum stake to become operator
    uint256 public heartbeatInterval;       // Max time between heartbeats
    uint256 public slashPercentage;         // Default slash percentage (basis points, 100 = 1%)
    bool public paused;

    // ═══ Events ═══

    event AVSRegistered(string metadataURI, uint256 timestamp);
    event OperatorRegistered(address indexed operator, OperatorRole role, string metadataURI);
    event OperatorDeregistered(address indexed operator, uint256 timestamp);
    event DelegationCreated(address indexed staker, address indexed operator, uint256 amount);
    event DelegationWithdrawn(address indexed staker, address indexed operator, uint256 amount);
    event OperatorSlashed(address indexed operator, SlashingReason reason, uint256 amount, address reporter);
    event HeartbeatReceived(address indexed operator, uint256 timestamp);
    event ServiceTaskCreated(uint256 indexed taskId, OperatorRole requiredRole, uint256 reward);
    event ServiceTaskAssigned(uint256 indexed taskId, address indexed operator);
    event ServiceTaskCompleted(uint256 indexed taskId, address indexed operator);
    event FeesDistributed(address indexed operator, uint256 amount);
    event ConfigUpdated(string param, uint256 value);

    // ═══ Errors ═══

    error AlreadyRegistered();
    error NotRegistered();
    error NotActive();
    error InsufficientStake();
    error OperatorNotActive();
    error InvalidRole();
    error TaskNotFound();
    error TaskNotOpen();
    error AlreadySlashed();
    error Paused();
    error NotAuthorized();

    // ═══ Modifiers ═══

    modifier whenNotPaused() {
        if (paused) revert Paused();
        _;
    }

    modifier onlyOwner() {
        require(msg.sender == owner, "EigenLayer: not owner");
        _;
    }

    modifier onlyOperator() {
        if (!operators[msg.sender].active) revert OperatorNotActive();
        _;
    }

    // ═══ Constructor ═══

    constructor(address _hiveStaking) {
        owner = msg.sender;
        hiveStaking = _hiveStaking;
        minStakeForOperator = 0.1 ether;
        heartbeatInterval = 1 hours;
        slashPercentage = 1000; // 10% default slash
    }

    // ═══ EigenLayer Configuration ═══

    /// @notice Set EigenLayer contract references
    function setEigenLayerContracts(
        address _delegationManager,
        address _strategyManager,
        address _avsDirectory,
        address _slasher
    ) external onlyOwner {
        delegationManager = IDelegationManager(_delegationManager);
        strategyManager = IStrategyManager(_strategyManager);
        avsDirectory = IAVSDirectory(_avsDirectory);
        slasher = ISlasher(_slasher);
    }

    // ═══ AVS Registration ═══

    /// @notice Register Hive as an EigenLayer AVS
    /// @param metadataURI Off-chain metadata (IPFS/Arweave) describing the AVS
    function registerAsAVS(string calldata metadataURI) external onlyOwner {
        if (registeredAsAVS) revert AlreadyRegistered();

        avsMetadataURI = metadataURI;
        registeredAsAVS = true;

        // In production, this would call avsDirectory.registerOperatorToAVS(...)
        // For now, we track registration state internally

        emit AVSRegistered(metadataURI, block.timestamp);
    }

    // ═══ Operator Management ═══

    /// @notice Register as a Hive operator
    /// @param role The operator's role (MarketMaker, InferenceNode, Validator, PriceOracle)
    /// @param metadataURI Off-chain metadata describing the operator
    function registerOperator(OperatorRole role, string calldata metadataURI)
        external
        payable
        whenNotPaused
    {
        if (operators[msg.sender].active) revert AlreadyRegistered();
        if (role == OperatorRole.None) revert InvalidRole();
        if (msg.value < minStakeForOperator) revert InsufficientStake();

        operators[msg.sender] = Operator({
            operatorAddress: msg.sender,
            role: role,
            registeredAt: block.timestamp,
            totalFeesEarned: 0,
            slashCount: 0,
            lastHeartbeat: block.timestamp,
            active: true,
            metadataURI: metadataURI
        });

        operatorList.push(msg.sender);
        operatorCount++;

        // In production, also register on EigenLayer's AVSDirectory
        // avsDirectory.registerOperatorToAVS(msg.sender, address(this), signature);

        emit OperatorRegistered(msg.sender, role, metadataURI);
    }

    /// @notice Deregister as an operator
    function deregisterOperator() external onlyOperator {
        operators[msg.sender].active = false;

        // In production, also deregister from EigenLayer
        // avsDirectory.deregisterOperatorFromAVS(msg.sender, address(this));

        emit OperatorDeregistered(msg.sender, block.timestamp);
    }

    /// @notice Operator heartbeat (proof of liveness)
    function heartbeat() external onlyOperator {
        operators[msg.sender].lastHeartbeat = block.timestamp;
        emit HeartbeatReceived(msg.sender, block.timestamp);
    }

    // ═══ Delegation (Restaking) ═══

    /// @notice Delegate restaked ETH to a Hive operator
    /// @param operator Operator address to delegate to
    /// @param amount Amount to delegate
    function delegate(address operator, uint256 amount) external whenNotPaused {
        if (!operators[operator].active) revert OperatorNotActive();
        require(amount > 0, "EigenLayer: zero amount");

        delegations[msg.sender] = Delegation({
            staker: msg.sender,
            operator: operator,
            amount: amount,
            delegatedAt: block.timestamp,
            active: true
        });

        operatorDelegatedAmount[operator] += amount;
        operatorStakers[operator].push(msg.sender);

        // In production, this would call delegationManager.delegateTo(operator, ...)

        emit DelegationCreated(msg.sender, operator, amount);
    }

    /// @notice Withdraw delegation
    function undelegate() external {
        Delegation storage del = delegations[msg.sender];
        require(del.active, "EigenLayer: not delegated");

        operatorDelegatedAmount[del.operator] -= del.amount;
        del.active = false;

        // In production, this would call delegationManager.undelegate(msg.sender)

        emit DelegationWithdrawn(msg.sender, del.operator, del.amount);
    }

    // ═══ Slashing ═══

    /// @notice Report an operator for malicious behavior
    /// @param operator Operator to slash
    /// @param reason Reason for slashing
    /// @param evidence Off-chain evidence URI (IPFS/Arweave)
    function reportOperator(
        address operator,
        SlashingReason reason,
        string calldata evidence
    ) external onlyOwner {
        if (!operators[operator].active) revert NotActive();

        uint256 slashAmount = operatorDelegatedAmount[operator] * slashPercentage / 10000;

        uint256 slashId = slashCount++;
        slashRecords[slashId] = SlashRecord({
            slashId: slashId,
            operator: operator,
            reason: reason,
            amount: slashAmount,
            timestamp: block.timestamp,
            reporter: msg.sender,
            evidence: evidence
        });

        operators[operator].slashCount++;
        totalSlashed += slashAmount;

        // In production, this would call slasher.slashOperator(operator, address(this), slashAmount)

        // Deactivate operator if slashed too many times
        if (operators[operator].slashCount >= 3) {
            operators[operator].active = false;
        }

        emit OperatorSlashed(operator, reason, slashAmount, msg.sender);
    }

    // ═══ Service Tasks ═══

    /// @notice Create a service task for operators
    /// @param requiredRole Role required to execute the task
    /// @param description Task description
    /// @param reward Reward in wei for completing the task
    /// @param deadline Task deadline
    function createServiceTask(
        OperatorRole requiredRole,
        string calldata description,
        uint256 reward,
        uint256 deadline
    ) external payable onlyOwner returns (uint256 taskId) {
        taskId = taskCount++;

        serviceTasks[taskId] = ServiceTask({
            taskId: taskId,
            requiredRole: requiredRole,
            description: description,
            reward: msg.value,
            deadline: deadline,
            assignedOperator: address(0),
            completed: false,
            validated: false
        });

        emit ServiceTaskCreated(taskId, requiredRole, msg.value);
    }

    /// @notice Assign a task to an operator
    function assignTask(uint256 taskId, address operator) external onlyOwner {
        ServiceTask storage task = serviceTasks[taskId];
        if (task.taskId != taskId) revert TaskNotFound();
        if (!operators[operator].active) revert OperatorNotActive();
        if (operators[operator].role != task.requiredRole) revert InvalidRole();

        task.assignedOperator = operator;
        emit ServiceTaskAssigned(taskId, operator);
    }

    /// @notice Mark a task as completed (called by assigned operator)
    function completeTask(uint256 taskId) external onlyOperator {
        ServiceTask storage task = serviceTasks[taskId];
        if (task.taskId != taskId) revert TaskNotFound();
        if (task.assignedOperator != msg.sender) revert NotAuthorized();
        if (block.timestamp > task.deadline) revert TaskNotOpen();

        task.completed = true;

        // Distribute reward
        if (task.reward > 0) {
            operators[msg.sender].totalFeesEarned += task.reward;
            (bool sent, ) = msg.sender.call{value: task.reward}("");
            if (sent) {
                emit FeesDistributed(msg.sender, task.reward);
            }
        }

        emit ServiceTaskCompleted(taskId, msg.sender);
    }

    // ═══ Fee Distribution ═══

    /// @notice Distribute fees to an operator
    function distributeFees(address operator) external payable onlyOwner {
        if (!operators[operator].active) revert NotActive();

        operators[operator].totalFeesEarned += msg.value;
        (bool sent, ) = operator.call{value: msg.value}("");
        if (sent) {
            emit FeesDistributed(operator, msg.value);
        }
    }

    // ═══ View ═══

    function getOperator(address operator) external view returns (Operator memory) {
        return operators[operator];
    }

    function getDelegation(address staker) external view returns (Delegation memory) {
        return delegations[staker];
    }

    function getSlashRecord(uint256 slashId) external view returns (SlashRecord memory) {
        return slashRecords[slashId];
    }

    function getServiceTask(uint256 taskId) external view returns (ServiceTask memory) {
        return serviceTasks[taskId];
    }

    function getOperatorsByRole(OperatorRole role) external view returns (address[] memory) {
        uint256 count = 0;
        for (uint256 i = 0; i < operatorList.length; i++) {
            if (operators[operatorList[i]].role == role && operators[operatorList[i]].active) {
                count++;
            }
        }

        address[] memory result = new address[](count);
        uint256 idx = 0;
        for (uint256 i = 0; i < operatorList.length; i++) {
            if (operators[operatorList[i]].role == role && operators[operatorList[i]].active) {
                result[idx++] = operatorList[i];
            }
        }
        return result;
    }

    function isOperatorActive(address operator) external view returns (bool) {
        return operators[operator].active;
    }

    function getOperatorDelegatedAmount(address operator) external view returns (uint256) {
        return operatorDelegatedAmount[operator];
    }

    // ═══ Configuration ═══

    function setMinStake(uint256 _minStake) external onlyOwner {
        minStakeForOperator = _minStake;
        emit ConfigUpdated("minStake", _minStake);
    }

    function setHeartbeatInterval(uint256 _interval) external onlyOwner {
        heartbeatInterval = _interval;
        emit ConfigUpdated("heartbeatInterval", _interval);
    }

    function setSlashPercentage(uint256 _percentage) external onlyOwner {
        require(_percentage <= 5000, "EigenLayer: max 50%");
        slashPercentage = _percentage;
        emit ConfigUpdated("slashPercentage", _percentage);
    }

    function setPaused(bool _paused) external onlyOwner {
        paused = _paused;
    }

    receive() external payable {}

    // ═══ Ownership ═══

    function transferOwnership(address newOwner) external onlyOwner {
        require(newOwner != address(0), "zero address");
        owner = newOwner;
    }
}
