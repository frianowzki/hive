// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "../libraries/RitualPrecompileConsumer.sol";
interface IScheduler {
    function schedule(bytes calldata, uint32, uint32, uint32, uint32, uint32, uint256, uint256, uint256, address) external returns (uint256);
    function cancel(uint256) external;
}

interface IRitualWallet {
    function balanceOf(address) external view returns (uint256);
    function withdraw(uint256) external;
    function lockUntil(address) external view returns (uint256);
}

/// @title HiveSovereignAgentV2 — Autonomous DeFi agent with LLM + HTTP precompiles
/// @notice Full sovereign agent with 9 features, scheduler heartbeat, and rescue function
contract HiveSovereignAgentV2 is RitualPrecompileConsumer {
    // ═══ State ═══

    address public owner;
    uint256 public callId;
    uint256 public wakeCount;
    uint32 public wakeInterval = 10000; // blocks between wakeups (~1 hour)
    bool public isRunning;

    // Task execution state
    bytes32 public lastTaskHash;
    uint256 public lastExecutionBlock;
    uint256 public totalExecutions;
    uint256 public totalErrors;

    // Feature state
    struct FeatureState {
        bool enabled;
        uint256 lastRunBlock;
        uint256 runCount;
        bytes lastResult;
    }

    mapping(string => FeatureState) public features;

    // Execution log
    struct ExecutionLog {
        uint256 blockNumber;
        string feature;
        bytes result;
        bool success;
        uint256 gasUsed;
    }

    ExecutionLog[] public executionLogs;
    uint256 public constant MAX_LOGS = 100;

    // Budget
    uint256 public constant MAX_BUDGET = 1.1 ether;

    // ═══ Events ═══

    event AgentStarted(uint32 wakeInterval, uint256 schedulerCallId);
    event AgentStopped();
    event WakeUp(uint256 indexed wakeCount, uint256 blockNumber);
    event TaskExecuted(string feature, bool success, bytes result);
    event Error(string feature, string reason);
    event FundsRescued(address indexed to, uint256 amount);

    // ═══ Errors ═══

    error NotOwner();
    error NotScheduler();
    error NotAsyncDelivery();
    error AgentAlreadyRunning();
    error AgentNotRunning();
    error BudgetExceeded(uint256 attempted, uint256 max);
    error RescueFailed();

    // ═══ Modifiers ═══

    modifier onlyOwner() {
        if (msg.sender != owner) revert NotOwner();
        _;
    }

    modifier onlyScheduler() {
        if (msg.sender != SCHEDULER) revert NotScheduler();
        _;
    }

    modifier onlyAsyncDelivery() {
        if (msg.sender != ASYNC_DELIVERY) revert NotAsyncDelivery();
        _;
    }

    // ═══ Constructor ═══

    constructor() {
        owner = msg.sender;

        // Initialize features
        features["yield_scanner"] = FeatureState(true, 0, 0, "");
        features["reward_harvester"] = FeatureState(true, 0, 0, "");
        features["portfolio_snapshot"] = FeatureState(true, 0, 0, "");
        features["gas_tracker"] = FeatureState(true, 0, 0, "");
        features["opportunity_scanner"] = FeatureState(true, 0, 0, "");
        features["rebalance_checker"] = FeatureState(true, 0, 0, "");
    }

    // ═══ Core Functions ═══

    /// @notice Start the agent with Scheduler heartbeat
    function start(uint32 interval) external onlyOwner {
        if (isRunning) revert AgentAlreadyRunning();

        wakeInterval = interval;

        // Encode wakeUp call with execution index placeholder
        bytes memory data = abi.encodeWithSelector(
            this.wakeUp.selector,
            uint256(0) // placeholder — Scheduler overwrites with real executionIndex
        );

        // Schedule with minimal overload
        callId = IScheduler(SCHEDULER).schedule(
            data,
            500000, // gas limit
            0,      // numCalls (0 = infinite)
            interval // frequency
        );

        isRunning = true;
        emit AgentStarted(interval, callId);
    }

    /// @notice Stop the agent
    function stop() external onlyOwner {
        if (!isRunning) revert AgentNotRunning();

        IScheduler(SCHEDULER).cancel(callId);
        isRunning = false;
        emit AgentStopped();
    }

    /// @notice Wake up callback from Scheduler
    /// @param executionIndex Overwritten by Scheduler with real index
    function wakeUp(uint256 executionIndex) external onlyScheduler {
        wakeCount++;
        lastExecutionBlock = block.number;

        emit WakeUp(wakeCount, block.number);

        // Execute enabled features
        _executeFeatures();
    }

    // ═══ Feature Execution ═══

    function _executeFeatures() internal {
        string[6] memory featureNames = [
            "yield_scanner",
            "reward_harvester",
            "portfolio_snapshot",
            "gas_tracker",
            "opportunity_scanner",
            "rebalance_checker"
        ];

        for (uint256 i = 0; i < featureNames.length; i++) {
            if (features[featureNames[i]].enabled) {
                _executeFeature(featureNames[i]);
            }
        }
    }

    function _executeFeature(string memory featureName) internal {
        // Build LLM prompt based on feature
        string memory prompt = _buildPrompt(featureName);

        // Call LLM precompile (async short)
        try this._callLLM(prompt) returns (bytes memory result) {
            // Update feature state
            features[featureName].lastRunBlock = block.number;
            features[featureName].runCount++;
            features[featureName].lastResult = result;

            // Log execution
            _logExecution(featureName, result, true, gasleft());

            emit TaskExecuted(featureName, true, result);
        } catch (bytes memory reason) {
            totalErrors++;
            _logExecution(featureName, reason, false, gasleft());
            emit Error(featureName, "LLM call failed");
        }
    }

    function _callLLM(string memory prompt) external returns (bytes memory) {
        // Call LLM precompile
        bytes memory input = _encodeLlmCall(prompt);
        return _executePrecompile(LLM_PRECOMPILE, input);
    }

    function _buildPrompt(string memory featureName) internal pure returns (string memory) {
        if (keccak256(bytes(featureName)) == keccak256("yield_scanner")) {
            return "Scan all DeFi pools on Ritual Chain. Report APY/APR changes. Flag drops > 5%.";
        } else if (keccak256(bytes(featureName)) == keccak256("reward_harvester")) {
            return "Check staking rewards. Calculate gas vs reward ratio. Suggest claim if reward > 10x gas.";
        } else if (keccak256(bytes(featureName)) == keccak256("portfolio_snapshot")) {
            return "Snapshot all balances. Calculate allocation percentages. Track performance.";
        } else if (keccak256(bytes(featureName)) == keccak256("gas_tracker")) {
            return "Monitor gas price. Calculate moving averages. Suggest optimal tx timing.";
        } else if (keccak256(bytes(featureName)) == keccak256("opportunity_scanner")) {
            return "Scan new contracts, tokens, pools. Detect arbitrage. Score opportunities 0-100.";
        } else if (keccak256(bytes(featureName)) == keccak256("rebalance_checker")) {
            return "Check portfolio drift. Compare to target allocation. Suggest rebalance if drift > 10%.";
        }
        return "Unknown feature";
    }

    function _logExecution(
        string memory feature,
        bytes memory result,
        bool success,
        uint256 gasRemaining
    ) internal {
        if (executionLogs.length >= MAX_LOGS) {
            // Remove oldest log
            for (uint256 i = 0; i < executionLogs.length - 1; i++) {
                executionLogs[i] = executionLogs[i + 1];
            }
            executionLogs.pop();
        }

        executionLogs.push(ExecutionLog({
            blockNumber: block.number,
            feature: feature,
            result: result,
            success: success,
            gasUsed: gasRemaining
        }));
    }

    // ═══ Async Callbacks ═══

    /// @notice Callback from AsyncDelivery for LLM results
    function onSovereignAgentResult(bytes32 jobId, bytes calldata result) external onlyAsyncDelivery {
        // Process LLM result
        totalExecutions++;
        lastTaskHash = keccak256(result);
    }

    // ═══ Admin Functions ═══

    function setFeatureEnabled(string memory featureName, bool enabled) external onlyOwner {
        features[featureName].enabled = enabled;
    }

    function setWakeInterval(uint32 newInterval) external onlyOwner {
        wakeInterval = newInterval;
        // Note: Need to restart agent to apply new interval
    }

    /// @notice Rescue native balance to owner
    function rescue() external onlyOwner {
        uint256 balance = address(this).balance;
        require(balance > 0, "No funds to rescue");

        (bool ok, ) = owner.call{value: balance}("");
        if (!ok) revert RescueFailed();

        emit FundsRescued(owner, balance);
    }

    /// @notice Withdraw from RitualWallet to contract
    function withdrawFromWallet(uint256 amount) external onlyOwner {
        IRitualWallet(RITUAL_WALLET).withdraw(amount);
    }

    // ═══ View Functions ═══

    function getWalletBalance() external view returns (uint256) {
        return IRitualWallet(RITUAL_WALLET).balanceOf(address(this));
    }

    function getWalletLockUntil() external view returns (uint256) {
        return 0; // TODO: fix
    }

    function getFeatureState(string memory featureName) external view returns (
        bool enabled,
        uint256 lastRunBlock,
        uint256 runCount,
        bytes memory lastResult
    ) {
        FeatureState storage fs = features[featureName];
        return (fs.enabled, fs.lastRunBlock, fs.runCount, fs.lastResult);
    }

    function getExecutionLogs(uint256 offset, uint256 limit) external view returns (ExecutionLog[] memory) {
        uint256 end = offset + limit;
        if (end > executionLogs.length) {
            end = executionLogs.length;
        }

        ExecutionLog[] memory logs = new ExecutionLog[](end - offset);
        for (uint256 i = offset; i < end; i++) {
            logs[i - offset] = executionLogs[i];
        }
        return logs;
    }

    function getAgentStatus() external view returns (
        bool running,
        uint256 wakes,
        uint256 executions,
        uint256 errors,
        uint256 lastBlock
    ) {
        return (isRunning, wakeCount, totalExecutions, totalErrors, lastExecutionBlock);
    }

    // ═══ Receive ═══

    receive() external payable {}
}
