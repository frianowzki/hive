// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "../libraries/RitualPrecompileConsumer.sol";

/// @title IScheduler — Interface for Ritual Scheduler precompile
interface IScheduler {
    function schedule(
        bytes calldata callData,
        uint256 gasLimit,
        uint32 startBlock,
        uint32 retrySlots,
        uint32 frequency,
        uint32 ttl,
        uint256 maxFeePerGas,
        uint256 minFeePerGas,
        uint256 priorityFee,
        address payer
    ) external returns (uint256);

    function cancel(uint256 callId) external;
}

/// @title HiveSovereignAgent — Autonomous agent on Ritual Chain
/// @notice Implements the Sovereign Agent Loop with Governor safety layer
/// @dev Agent wakes up periodically, analyzes market, executes trades, schedules next wakeup

contract HiveSovereignAgent is RitualPrecompileConsumer {
    // ═══ State ═══

    struct AgentConfig {
        string name;           // e.g., "Queen", "Drone-α", "Scout"
        string cliType;        // CLI harness type (e.g., "claude-code", "zeroclaw")
        string soul;           // Identity, purpose, behavioral constraints
        uint32 wakeDelay;      // Blocks between wakeups
        bool isRunning;        // Is the agent loop active
        uint256 wakeCount;     // How many times agent has woken up
        uint256 lastWakeBlock; // Last wakeup block
        bytes32 sector;        // Which sector this agent belongs to
    }

    struct TradeDecision {
        address token;
        uint256 amount;
        uint256 price;
        bool isBuy;
        uint256 confidence;    // 0-100
        string reason;
    }

    AgentConfig public config;
    address public governor;   // HiveGovernor address
    address public owner;
    uint256 public callId;     // Scheduler call ID
    bool public paused;

    // Trade history
    TradeDecision[] public tradeHistory;
    uint256 public totalTrades;
    uint256 public successfulTrades;

    // State hash for integrity verification
    bytes32 public lastStateHash;
    string public lastDARef;   // Last DA reference (IPFS CID)

    // ═══ Events ═══

    event AgentStarted(string name, uint32 wakeDelay);
    event AgentStopped(string name);
    event AgentWokeUp(uint256 indexed wakeCount, uint256 blockNumber);
    event TradeExecuted(address indexed token, uint256 amount, bool isBuy, string reason);
    event StatePersisted(bytes32 stateHash, string daRef);
    event AgentRevived(string daRef);
    event GovernorSet(address indexed governor);

    // ═══ Errors ═══

    error NotScheduler();
    error NotGovernor();
    error NotOwner();
    error NotAsyncDelivery();
    error AgentNotRunning();
    error GovernorNotSet();
    error LowConfidence(uint256 confidence, uint256 minRequired);
    error GovernorDenied(string reason);

    // ═══ Modifiers ═══

    modifier onlyOwner() {
        if (msg.sender != owner) revert NotOwner();
        _;
    }

    modifier whenNotPaused() {
        require(!paused, "Agent paused");
        _;
    }

    // ═══ Constructor ═══

    constructor(
        string memory _name,
        string memory _cliType,
        string memory _soul,
        uint32 _wakeDelay,
        address _governor,
        bytes32 _sector
    ) {
        owner = msg.sender;
        governor = _governor;
        config = AgentConfig({
            name: _name,
            cliType: _cliType,
            soul: _soul,
            wakeDelay: _wakeDelay,
            isRunning: false,
            wakeCount: 0,
            lastWakeBlock: 0,
            sector: _sector
        });
    }

    // ═══ Agent Lifecycle ═══

    /// @notice Start the sovereign agent loop
    function start() external onlyOwner whenNotPaused {
        if (governor == address(0)) revert GovernorNotSet();
        config.isRunning = true;
        callId = _scheduleNext(config.wakeDelay);
        emit AgentStarted(config.name, config.wakeDelay);
    }

    /// @notice Stop the agent loop
    function stop() external onlyOwner {
        config.isRunning = false;
        if (callId > 0) {
            IScheduler(SCHEDULER).cancel(callId);
        }
        emit AgentStopped(config.name);
    }

    /// @notice Pause without canceling scheduler (for emergency)
    function pause() external onlyOwner {
        paused = true;
    }

    function unpause() external onlyOwner {
        paused = false;
    }

    // ═══ Sovereign Agent Loop ═══

    /// @notice Called by Scheduler at the scheduled block
    /// @dev This is the heartbeat — agent wakes up, thinks, acts, sleeps
    function wakeUp(uint256 executionIndex) external whenNotPaused {
        if (msg.sender != SCHEDULER) revert NotScheduler();
        if (!config.isRunning) return;

        config.wakeCount++;
        config.lastWakeBlock = block.number;

        emit AgentWokeUp(config.wakeCount, block.number);

        // 1. Fetch market data via HTTP precompile
        // 2. Run LLM inference for decision
        // 3. Validate with Governor
        // 4. Execute if approved
        // 5. Persist state to DA
        // 6. Schedule next wakeup
        _executeAgentLogic();

        callId = _scheduleNext(config.wakeDelay);
    }

    /// @notice Phase 2 callback with agent output from TEE
    /// @dev Called by AsyncDelivery after Sovereign Agent execution completes
    function onSovereignAgentResult(bytes32 jobId, bytes calldata result) external {
        if (msg.sender != ASYNC_DELIVERY) revert NotAsyncDelivery();

        // Parse the result from the TEE agent
        // result contains: trade decisions, analysis, updated state
        _processAgentResult(result);
    }

    // ═══ Internal: Agent Logic ═══

    function _executeAgentLogic() internal {
        // Encode the Sovereign Agent request (23-field ABI)
        bytes memory agentInput = _encodeSovereignAgentInput();

        // Execute via precompile 0x080C
        _tryExecutePrecompile(SOVEREIGN_AGENT_PRECOMPILE, agentInput);
    }

    function _encodeSovereignAgentInput() internal view returns (bytes memory) {
        // Sovereign Agent 23-field encoding
        // Key fields: cliType (11), prompt (12), tools (19)
        return abi.encode(
            address(this),           // 0: executor
            new bytes[](0),          // 1: encryptedSecrets
            uint256(100),            // 2: ttl (blocks)
            new bytes[](0),          // 3: secretSignatures
            bytes32(0),              // 4: userPublicKey
            uint64(block.number + 50), // 5: maxSpawnBlock
            config.cliType,          // 11: cliType
            _buildPrompt(),          // 12: prompt
            _buildToolsList(),       // 19: tools
            config.soul              // soul reference
        );
    }

    function _buildPrompt() internal view returns (string memory) {
        return string(abi.encodePacked(
            "You are ", config.name, ", an AI market maker agent on Hive/Ritual Chain.\n",
            "Sector: ", _bytes32ToString(config.sector), "\n",
            "Current block: ", _uint2str(block.number), "\n",
            "Wake count: ", _uint2str(config.wakeCount), "\n",
            "Analyze market conditions and make trading decisions.\n",
            "Return structured JSON with trade decisions."
        ));
    }

    function _buildToolsList() internal pure returns (string[] memory) {
        string[] memory tools = new string[](4);
        tools[0] = "http_fetch";      // 0x0801
        tools[1] = "llm_inference";   // 0x0802
        tools[2] = "token_swap";      // HiveMarketMaker
        tools[3] = "state_persist";   // DA storage
        return tools;
    }

    function _processAgentResult(bytes calldata result) internal {
        // Decode trade decisions from TEE output
        // Validate each decision with Governor
        // Execute approved trades
        // Persist state to DA

        // For now, emit event for monitoring
        emit TradeExecuted(address(0), 0, false, "result processed");
    }

    // ═══ Governor Integration ═══

    /// @notice Execute a trade through the Governor
    /// @dev Called internally after LLM decides on a trade
    function _executeTradeThroughGovernor(
        address destination,
        uint256 value,
        bytes calldata data
    ) internal returns (bool success) {
        if (governor == address(0)) revert GovernorNotSet();

        // Ask Governor to validate
        (bool allowed, string memory reason) = IHiveGovernor(governor).validateTx(
            destination,
            value,
            gasleft()
        );

        if (!allowed) {
            revert GovernorDenied(reason);
        }

        // Execute the trade
        (success, ) = destination.call{value: value, gas: 500_000}(data);
        if (success) {
            successfulTrades++;
        }
        totalTrades++;

        return success;
    }

    // ═══ State Persistence ═══

    /// @notice Persist agent state to DA (IPFS/Pinata)
    function persistState(string calldata daRef) external onlyOwner {
        // Hash current state
        lastStateHash = keccak256(abi.encode(
            config.name,
            config.wakeCount,
            config.lastWakeBlock,
            totalTrades,
            successfulTrades,
            block.timestamp
        ));
        lastDARef = daRef;

        emit StatePersisted(lastStateHash, daRef);
    }

    /// @notice Revive agent from DA reference
    function revive(string calldata daRef) external onlyOwner {
        lastDARef = daRef;
        config.isRunning = true;
        callId = _scheduleNext(config.wakeDelay);
        emit AgentRevived(daRef);
    }

    // ═══ Admin ═══

    function setGovernor(address _governor) external onlyOwner {
        governor = _governor;
        emit GovernorSet(_governor);
    }

    function updateWakeDelay(uint32 newDelay) external onlyOwner {
        config.wakeDelay = newDelay;
    }

    // ═══ Scheduler ═══

    function _scheduleNext(uint32 delay) internal returns (uint256) {
        return IScheduler(SCHEDULER).schedule(
            abi.encodeWithSelector(this.wakeUp.selector, uint256(0)),
            800_000,                          // gas
            uint32(block.number) + delay,     // startBlock
            3,                                // retry slots
            1,                                // frequency
            30,                               // ttl
            20 gwei, 2 gwei, 0,              // fees
            address(this)                     // payer = self
        );
    }

    // ═══ View ═══

    function getAgentInfo() external view returns (
        string memory name,
        string memory cliType,
        bool isRunning,
        uint256 wakeCount,
        uint256 lastWakeBlock,
        uint256 totalTrades,
        uint256 successfulTrades,
        bytes32 sector
    ) {
        return (
            config.name,
            config.cliType,
            config.isRunning,
            config.wakeCount,
            config.lastWakeBlock,
            totalTrades,
            successfulTrades,
            config.sector
        );
    }

    function getTradeHistory(uint256 count) external view returns (TradeDecision[] memory) {
        uint256 len = tradeHistory.length;
        uint256 start = len > count ? len - count : 0;
        TradeDecision[] memory result = new TradeDecision[](len - start);
        for (uint256 i = start; i < len; i++) {
            result[i - start] = tradeHistory[i];
        }
        return result;
    }

    // ═══ Utility ═══

    function _uint2str(uint256 value) internal pure returns (string memory) {
        if (value == 0) return "0";
        uint256 temp = value;
        uint256 digits;
        while (temp != 0) {
            digits++;
            temp /= 10;
        }
        bytes memory buffer = new bytes(digits);
        while (value != 0) {
            digits -= 1;
            buffer[digits] = bytes1(uint8(48 + uint256(value % 10)));
            value /= 10;
        }
        return string(buffer);
    }

    function _bytes32ToString(bytes32 b) internal pure returns (string memory) {
        bytes memory result = new bytes(32);
        uint256 len = 0;
        for (uint256 i = 0; i < 32; i++) {
            if (b[i] == 0) break;
            result[i] = b[i];
            len++;
        }
        return string(abi.encodePacked(result));
    }

    // ═══ Receive ═══

    receive() external payable {}
}

/// @notice Interface for HiveGovernor
interface IHiveGovernor {
    function validateTx(
        address destination,
        uint256 value,
        uint256 gasUsed
    ) external returns (bool allowed, string memory reason);
}
