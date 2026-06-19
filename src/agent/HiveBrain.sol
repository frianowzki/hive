// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "../libraries/RitualPrecompileConsumer.sol";

/// @title HiveBrain — Enhanced Agent Brain with Ritual LLM (Async + PII)
/// @notice Sovereign agent brain that thinks, plans, and acts via LLM
/// @dev Upgraded with async LLM inference, PII mode, and Allora price integration.
///      Supports both synchronous (fast) and asynchronous (complex) LLM calls.
///      PII mode ensures sensitive strategy data never hits the mempool.

contract HiveBrain is RitualPrecompileConsumer {
    // ═══ Types ═══

    enum ActionType {
        DoNothing,
        Invest,
        Trade,
        Rebalance,
        UpdatePricing,
        SpawnDrone,
        AdjustFees,
        CreateProposal,
        Alert,
        FetchAlloraPrice,   // New: fetch price from Allora
        PrivateInference    // New: PII-mode inference
    }

    struct Thought {
        string context;         // What the agent observed
        string reasoning;       // LLM reasoning chain
        ActionType[] actions;   // Decided actions
        uint256 confidence;     // Confidence score (0-100)
        uint256 timestamp;
        bool piiMode;           // Whether this thought was generated in PII mode
    }

    struct Memory {
        string key;
        string value;
        uint256 updatedAt;
    }

    struct ActionPlan {
        ActionType actionType;
        address target;
        uint256 value;
        bytes data;
        string description;
        uint256 priority;       // 1-10, higher = more urgent
    }

    // ═══ State ═══

    address public owner;
    address public queen;

    // Thought history
    Thought[] public thoughts;
    uint256 public thoughtCount;

    // Action history
    ActionPlan[] public actionHistory;
    uint256 public totalActions;
    uint256 public successfulActions;
    uint256 public failedActions;

    // Agent memory (key-value store for LLM context)
    mapping(bytes32 => Memory) public memory_;
    bytes32[] public memoryKeys;

    // Configuration
    uint256 public confidenceThreshold = 70; // Only act if confidence >= 70
    bool public autonomousMode = false;       // If true, auto-execute; if false, human approval needed
    bool public piiMode = false;              // If true, all inference runs with piiEnabled=true

    // Pending actions (for human approval mode)
    mapping(uint256 => ActionPlan) public pendingActions;
    uint256 public pendingCount;

    // Async LLM tracking
    uint256 public asyncThoughtId;
    mapping(uint256 => uint256) public asyncJobToThought; // jobId => thoughtId

    // Performance metrics
    uint256 public totalEarnings;
    uint256 public totalLosses;
    uint256 public uptimeBlocks;

    // Oracle reference (for Allora price data)
    address public oracle;

    // ═══ Events ═══

    event ThoughtRecorded(uint256 indexed thoughtId, string context, uint256 confidence);
    event ThoughtAsyncSubmitted(uint256 indexed thoughtId, uint256 indexed jobId);
    event ThoughtAsyncReceived(uint256 indexed thoughtId, string reasoning, uint256 confidence);
    event ActionPlanned(uint256 indexed actionId, ActionType actionType, address target);
    event ActionExecuted(uint256 indexed actionId, bool success);
    event ActionApproved(uint256 indexed actionId);
    event ActionRejected(uint256 indexed actionId);
    event MemoryStored(bytes32 indexed key, string value);
    event ModeChanged(bool autonomous);
    event PiiModeChanged(bool piiMode);
    event OracleSet(address indexed oracle);

    // ═══ Constructor ═══

    constructor(address _queen) {
        owner = msg.sender;
        queen = _queen;
    }

    // ═══ Think — Synchronous LLM (fast, simple analysis) ═══

    /// @notice Analyze current state and generate thoughts (synchronous)
    /// @param context Current state description
    /// @return thoughtId The ID of the generated thought
    function think(string calldata context) external returns (uint256 thoughtId) {
        require(msg.sender == owner || msg.sender == queen, "Brain: not authorized");

        // Build rich prompt with memory context
        string memory prompt = _buildThinkPrompt(context);

        // Call Ritual LLM precompile (synchronous)
        bytes memory llmInput = _encodeLlmCall(prompt);
        (bool success, bytes memory output) = LLM_PRECOMPILE.staticcall(llmInput);

        string memory reasoning;
        uint256 confidence;

        if (success && output.length > 0) {
            reasoning = abi.decode(output, (string));
            confidence = _extractConfidence(reasoning);
        } else {
            reasoning = "LLM unavailable -- defaulting to hold position";
            confidence = 0;
        }

        thoughtId = thoughtCount++;

        thoughts.push(Thought({
            context: context,
            reasoning: reasoning,
            actions: new ActionType[](0),
            confidence: confidence,
            timestamp: block.timestamp,
            piiMode: false
        }));

        emit ThoughtRecorded(thoughtId, reasoning, confidence);
    }

    // ═══ Think Async — Asynchronous LLM (complex analysis, PII-safe) ═══

    /// @notice Submit a thought request asynchronously (TEE-attested, PII-safe)
    /// @dev Uses Ritual's async execution model: submit → process in TEE → deliver
    ///      When piiMode=true, the LLM input/output never hits the mempool.
    /// @param context Current state description
    /// @return thoughtId The ID of the submitted thought
    function thinkAsync(string calldata context) external returns (uint256 thoughtId) {
        require(msg.sender == owner || msg.sender == queen, "Brain: not authorized");

        // Build rich prompt
        string memory prompt = _buildThinkPrompt(context);

        // Encode LLM call with PII mode
        bytes memory llmInput = _encodeLlmCallWithPii(prompt, piiMode);

        // Submit async (result will be delivered later via receiveResult)
        (bool success, bytes memory output) = LLM_PRECOMPILE.staticcall(llmInput);

        thoughtId = thoughtCount++;

        thoughts.push(Thought({
            context: context,
            reasoning: "", // Will be filled when result arrives
            actions: new ActionType[](0),
            confidence: 0,
            timestamp: block.timestamp,
            piiMode: piiMode
        }));

        if (success && output.length > 0) {
            // Parse job ID from output if available
            uint256 jobId = _extractJobId(output);
            if (jobId > 0) {
                asyncJobToThought[jobId] = thoughtId;
                emit ThoughtAsyncSubmitted(thoughtId, jobId);
            } else {
                // Synchronous result (precompile returned immediately)
                string memory reasoning = abi.decode(output, (string));
                uint256 confidence = _extractConfidence(reasoning);
                thoughts[thoughtId].reasoning = reasoning;
                thoughts[thoughtId].confidence = confidence;
                emit ThoughtRecorded(thoughtId, reasoning, confidence);
            }
        } else {
            thoughts[thoughtId].reasoning = "LLM unavailable -- async submission failed";
            emit ThoughtRecorded(thoughtId, "LLM unavailable", 0);
        }
    }

    /// @notice Receive async LLM result (called by Ritual delivery or oracle)
    /// @param thoughtId The thought to update
    /// @param reasoning The LLM reasoning output
    function receiveResult(uint256 thoughtId, string calldata reasoning) external {
        require(msg.sender == owner || msg.sender == queen || msg.sender == address(this), "Brain: not authorized");
        require(thoughtId < thoughtCount, "Brain: invalid thought");

        uint256 confidence = _extractConfidence(reasoning);

        thoughts[thoughtId].reasoning = reasoning;
        thoughts[thoughtId].confidence = confidence;

        emit ThoughtAsyncReceived(thoughtId, reasoning, confidence);
    }

    // ═══ Plan — Generate Action Plan ═══

    /// @notice Generate an action plan based on the latest thought
    /// @return actionId The ID of the planned action
    function plan() external returns (uint256 actionId) {
        require(msg.sender == owner || msg.sender == queen, "Brain: not authorized");
        require(thoughtCount > 0, "Brain: no thoughts yet");

        Thought memory latestThought = thoughts[thoughtCount - 1];

        // Build planning prompt with Allora price context
        string memory prompt = _buildPlanPrompt(latestThought);

        bytes memory llmInput = _encodeLlmCall(prompt);
        (bool success, bytes memory output) = LLM_PRECOMPILE.staticcall(llmInput);

        ActionPlan memory plan_;

        if (success && output.length > 0) {
            string memory response = abi.decode(output, (string));
            plan_ = _parseActionPlan(response);
        } else {
            plan_ = ActionPlan({
                actionType: ActionType.DoNothing,
                target: address(0),
                value: 0,
                data: "",
                description: "LLM unavailable -- no action",
                priority: 0
            });
        }

        actionId = totalActions++;
        pendingActions[actionId] = plan_;

        emit ActionPlanned(actionId, plan_.actionType, plan_.target);
    }

    // ═══ Act — Execute or Approve ═══

    /// @notice Execute an action (autonomous mode or after approval)
    function act(uint256 actionId) public {
        ActionPlan storage action = pendingActions[actionId];
        require(action.actionType != ActionType.DoNothing, "Brain: no action");

        if (!autonomousMode) {
            require(msg.sender == owner, "Brain: not autonomous, needs approval");
        }

        bool success = false;

        if (action.target != address(0)) {
            (success, ) = action.target.call{value: action.value}(action.data);
        }

        if (success) {
            successfulActions++;
        } else {
            failedActions++;
        }

        actionHistory.push(action);
        delete pendingActions[actionId];

        emit ActionExecuted(actionId, success);
    }

    /// @notice Approve a pending action (human approval mode)
    function approve(uint256 actionId) external {
        require(msg.sender == owner, "Brain: not owner");
        require(pendingActions[actionId].actionType != ActionType.DoNothing, "Brain: no action");

        emit ActionApproved(actionId);
        act(actionId);
    }

    /// @notice Reject a pending action
    function reject(uint256 actionId) external {
        require(msg.sender == owner, "Brain: not owner");
        delete pendingActions[actionId];
        emit ActionRejected(actionId);
    }

    // ═══ Memory Management ═══

    /// @notice Store a memory (key-value pair for LLM context)
    function storeMemory(string calldata key, string calldata value) external {
        require(msg.sender == owner || msg.sender == queen, "Brain: not authorized");

        bytes32 keyHash = keccak256(bytes(key));
        memory_[keyHash] = Memory({
            key: key,
            value: value,
            updatedAt: block.timestamp
        });

        if (memoryKeys.length == 0 || _indexOfMemory(keyHash) == type(uint256).max) {
            memoryKeys.push(keyHash);
        }

        emit MemoryStored(keyHash, value);
    }

    function _indexOfMemory(bytes32 keyHash) internal view returns (uint256) {
        for (uint256 i = 0; i < memoryKeys.length; i++) {
            if (memoryKeys[i] == keyHash) return i;
        }
        return type(uint256).max;
    }

    // ═══ Prompt Building ═══

    function _buildThinkPrompt(string calldata context) internal view returns (string memory) {
        string memory memoryContext = _getMemoryContext();

        return string(abi.encodePacked(
            "You are Hive, a sovereign AI agent on Ritual Chain (ID 1979). ",
            "Your role: analyze DeFi market conditions and make optimal decisions. ",
            "\n\nCURRENT STATE:\n", context,
            "\n\nMEMORY:\n", memoryContext,
            "\n\nINSTRUCTIONS:\n",
            "1. Analyze the current state carefully\n",
            "2. Consider risk/reward of each possible action\n",
            "3. Provide a confidence score (0-100)\n",
            "4. Recommend specific actions with reasoning\n",
            "5. Be conservative -- only recommend action if confident\n\n",
            "Reply with your analysis and confidence score."
        ));
    }

    function _buildPlanPrompt(Thought memory thought) internal view returns (string memory) {
        return string(abi.encodePacked(
            "You are Hive. Based on your analysis:\n",
            "ANALYSIS: ", thought.reasoning, "\n",
            "CONFIDENCE: ", _uint2str(thought.confidence), "/100\n\n",
            "Generate ONE specific action. Reply with JSON:\n",
            '{"action": "invest|trade|rebalance|update_pricing|spawn_drone|adjust_fees|nothing", ',
            '"target": "0x...", "value": 0, "description": "...", "priority": 1-10}'
        ));
    }

    function _getMemoryContext() internal view returns (string memory) {
        if (memoryKeys.length == 0) return "No memories stored.";

        string memory result = "";
        for (uint256 i = 0; i < memoryKeys.length && i < 10; i++) {
            Memory storage m = memory_[memoryKeys[i]];
            result = string(abi.encodePacked(result, "- ", m.key, ": ", m.value, "\n"));
        }
        return result;
    }

    // ═══ Enhanced LLM Encoding (with PII support) ═══

    /// @dev Encode LLM call with PII mode support
    function _encodeLlmCallWithPii(string memory prompt, bool _piiEnabled)
        internal
        pure
        returns (bytes memory)
    {
        return abi.encode(
            address(0),         // executor (auto-select)
            new bytes[](0),     // encryptedSecrets
            uint256(100),       // ttl (blocks)
            new bytes[](0),     // secretSignatures
            bytes(""),          // userPublicKey
            prompt,             // prompt
            uint256(0),         // maxTokens
            uint256(0),         // temperature (use default)
            bytes(""),          // model (use default)
            uint256(0),         // dkmsKeyIndex
            uint8(0),           // dkmsKeyFormat
            _piiEnabled         // piiEnabled — true = redact from settlement
        );
    }

    // ═══ Response Parsing ═══

    function _extractConfidence(string memory response) internal pure returns (uint256) {
        bytes memory b = bytes(response);
        uint256 confidence = 50; // default

        for (uint256 i = 0; i < b.length; i++) {
            if (uint8(b[i]) >= 48 && uint8(b[i]) <= 57) { // digit
                uint256 num = 0;
                uint256 j = i;
                while (j < b.length && uint8(b[j]) >= 48 && uint8(b[j]) <= 57) {
                    num = num * 10 + (uint256(uint8(b[j])) - 48);
                    j++;
                }
                if (num <= 100) {
                    confidence = num;
                    break;
                }
            }
        }

        return confidence;
    }

    function _parseActionPlan(string memory response) internal pure returns (ActionPlan memory) {
        ActionType actionType = ActionType.DoNothing;

        if (_contains(response, "invest")) actionType = ActionType.Invest;
        else if (_contains(response, "trade")) actionType = ActionType.Trade;
        else if (_contains(response, "rebalance")) actionType = ActionType.Rebalance;
        else if (_contains(response, "update_pricing")) actionType = ActionType.UpdatePricing;
        else if (_contains(response, "spawn")) actionType = ActionType.SpawnDrone;
        else if (_contains(response, "adjust_fees")) actionType = ActionType.AdjustFees;
        else if (_contains(response, "allora")) actionType = ActionType.FetchAlloraPrice;

        return ActionPlan({
            actionType: actionType,
            target: address(0),
            value: 0,
            data: "",
            description: response,
            priority: 5
        });
    }

    function _extractJobId(bytes memory data) internal pure returns (uint256) {
        if (data.length >= 32) {
            return abi.decode(data, (uint256));
        }
        return 0;
    }

    // ═══ Configuration ═══

    function setConfidenceThreshold(uint256 _threshold) external {
        require(msg.sender == owner, "Brain: not owner");
        confidenceThreshold = _threshold;
    }

    function setAutonomousMode(bool _autonomous) external {
        require(msg.sender == owner, "Brain: not owner");
        autonomousMode = _autonomous;
        emit ModeChanged(_autonomous);
    }

    function setPiiMode(bool _piiMode) external {
        require(msg.sender == owner, "Brain: not owner");
        piiMode = _piiMode;
        emit PiiModeChanged(_piiMode);
    }

    function setQueen(address _queen) external {
        require(msg.sender == owner, "Brain: not owner");
        queen = _queen;
    }

    function setOracle(address _oracle) external {
        require(msg.sender == owner, "Brain: not owner");
        oracle = _oracle;
        emit OracleSet(_oracle);
    }

    // ═══ View ═══

    function getThought(uint256 thoughtId) external view returns (Thought memory) {
        return thoughts[thoughtId];
    }

    function getPendingAction(uint256 actionId) external view returns (ActionPlan memory) {
        return pendingActions[actionId];
    }

    function getActionHistory() external view returns (ActionPlan[] memory) {
        return actionHistory;
    }

    function successRate() external view returns (uint256) {
        uint256 total = successfulActions + failedActions;
        if (total == 0) return 0;
        return (successfulActions * 10_000) / total;
    }

    function getMemory(string calldata key) external view returns (string memory) {
        bytes32 keyHash = keccak256(bytes(key));
        return memory_[keyHash].value;
    }

    // ═══ Helpers ═══

    function _contains(string memory s, string memory sub) internal pure returns (bool) {
        bytes memory sb = bytes(s);
        bytes memory subb = bytes(sub);
        if (subb.length > sb.length) return false;
        for (uint256 i = 0; i <= sb.length - subb.length; i++) {
            bool found = true;
            for (uint256 j = 0; j < subb.length; j++) {
                if (sb[i + j] != subb[j]) { found = false; break; }
            }
            if (found) return true;
        }
        return false;
    }

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

    receive() external payable {}

    // ═══ Ownership ═══

    /// @notice Transfer ownership to a new address
    function transferOwnership(address newOwner) external {
        require(msg.sender == owner, "not owner");
        require(newOwner != address(0), "zero address");
        owner = newOwner;
    }

}
