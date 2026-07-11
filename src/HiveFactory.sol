// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./HiveAgentToken.sol";
import "./HiveBondingCurve.sol";

/// @title HiveFactory - Ritual-native memecoin launchpad
/// @notice Deploys AI agent tokens with LLM-generated metadata via Ritual precompiles
/// @dev Uses LLM precompile (0x0802) for on-chain metadata generation
contract HiveFactory {
    // --- Ritual System Contracts ---
    address public constant LLM_PRECOMPILE = 0x0000000000000000000000000000000000000802;
    address public constant ASYNC_DELIVERY = 0x5A16214fF555848411544b005f7Ac063742f39F6;
    address public constant RITUAL_WALLET = 0x532F0dF0896F353d8C3DD8cc134e8129DA2a3948;
    address public constant TEESERVICE_REGISTRY = 0x9644e8562cE0Fe12b4deeC4163c064A8862Bf47F;

    // --- State ---
    address public owner;
    address public platformTreasury;
    address public dexRouter;

    struct AgentLaunch {
        address token;
        address bondingCurve;
        address agentTreasury;
        string userPrompt;
        bool metadataSet;
        uint256 createdAt;
    }

    mapping(uint256 => AgentLaunch) public launches;
    uint256 public launchCount;

    mapping(bytes32 => bool) public pendingCallbacks;

    uint256 public virtualRitual = 5 ether;
    uint256 public virtualToken = 1_000_000_000 * 1e18;

    // --- Events ---
    event AgentCreated(
        uint256 indexed launchId,
        address indexed token,
        address indexed bondingCurve,
        string prompt
    );
    event MetadataGenerated(uint256 indexed launchId, string name, string symbol);
    event MetadataFailed(uint256 indexed launchId, string reason);

    // --- Modifiers ---
    modifier onlyOwner() {
        require(msg.sender == owner, "not owner");
        _;
    }

    modifier onlyAsyncDelivery() {
        require(msg.sender == ASYNC_DELIVERY, "only async delivery");
        _;
    }

    constructor(address platformTreasury_, address dexRouter_) {
        owner = msg.sender;
        platformTreasury = platformTreasury_;
        dexRouter = dexRouter_;
    }

    // --- Core Functions ---

    /// @notice Create a new AI agent token with LLM-generated metadata
    /// @param userPrompt Description of the token concept (e.g., "A chaotic-good cat wizard")
    /// @return launchId ID of the new launch
    function createAgent(string calldata userPrompt) external returns (uint256 launchId) {
        require(bytes(userPrompt).length > 0, "empty prompt");

        launchId = launchCount++;

        // 1. Deploy token with placeholder metadata
        string memory placeholderName = string(abi.encodePacked("Agent #", uint256(launchId)));
        HiveAgentToken token = new HiveAgentToken(
            placeholderName,
            "AGENT",
            "",
            address(this)
        );

        // 2. Deploy agent treasury
        address agentTreasury = address(new AgentTreasury(address(token)));

        // 3. Deploy bonding curve
        HiveBondingCurve curve = new HiveBondingCurve(
            address(token),
            address(this),
            platformTreasury,
            agentTreasury,
            dexRouter,
            virtualRitual,
            virtualToken
        );

        // 4. Mint tokens to factory, factory approves curve for spending
        uint256 saleTokens = virtualToken / 2; // 500M tokens for sale
        token.mint(address(this), saleTokens);
        IERC20(address(token)).approve(address(curve), saleTokens);

        // 5. Store launch
        launches[launchId] = AgentLaunch({
            token: address(token),
            bondingCurve: address(curve),
            agentTreasury: agentTreasury,
            userPrompt: userPrompt,
            metadataSet: false,
            createdAt: block.number
        });

        // 6. Mark as minting
        token.setStatus(HiveAgentToken.AgentStatus.Minting);

        emit AgentCreated(launchId, address(token), address(curve), userPrompt);

        // 7. Attempt LLM metadata generation (optional)
        // Skip if no valid executor available — token deploys with placeholder metadata
        _tryLLMLaunch(launchId, userPrompt);
    }

    /// @notice Fallback: receives LLM precompile result during fulfilled replay
    /// @dev When the builder re-executes the deferred tx with the LLM result,
    ///      the precompile output is routed here via the fallback function
    fallback() external payable {
        // Only process if this is a pending metadata callback
        if (msg.data.length < 4) return;

        // Try to decode as LLM response: (bool hasError, bytes completionData, bytes modelMetadata, string errorMessage, ...)
        // The actual decoding happens in the catch-all below
        // For now, we just accept the call - the result is in msg.data
    }

    /// @notice Callback from AsyncDelivery for long-running precompiles (future use)
    function onAgentResult(bytes32 jobId, bytes calldata result) external onlyAsyncDelivery {
        // Reserved for future agent loop integration
        delete pendingCallbacks[jobId];
    }

    // --- Internal Functions ---

    /// @notice Validate executor and attempt LLM call. Reverts silently if executor invalid.
    function _tryLLMLaunch(uint256 launchId, string calldata prompt) internal {
        // Query executor from TEEServiceRegistry
        bytes memory registryCall = abi.encodeWithSignature(
            "getServicesByCapability(uint8,bool)",
            uint8(1), // LLM capability
            false     // don't check validity (testnet may not have active registrations)
        );

        (bool regOk, bytes memory regResult) = TEESERVICE_REGISTRY.staticcall(registryCall);
        if (!regOk || regResult.length < 96) return;

        address executor = _extractFirstExecutor(regResult);
        // Validate executor is a real address (not zero, not a precompile)
        if (executor == address(0) || uint160(executor) < 0x1000) return;

        // Executor valid — attempt LLM call
        try this._triggerMetadataGeneration(launchId, prompt) {
            pendingCallbacks[keccak256(abi.encode(launchId))] = true;
        } catch {
            // LLM call failed — token still deployed with placeholder metadata
        }
    }

    function _triggerMetadataGeneration(uint256 launchId, string calldata prompt) external {
        AgentLaunch storage launch = launches[launchId];

        // Query executor from TEEServiceRegistry
        // Using inline assembly to call getServicesByCapability(1, true) for LLM
        bytes memory registryCall = abi.encodeWithSignature(
            "getServicesByCapability(uint8,bool)",
            uint8(1), // LLM capability
            true      // check validity
        );

        (bool regOk, bytes memory regResult) = TEESERVICE_REGISTRY.staticcall(registryCall);
        if (!regOk || regResult.length < 96) {
            // Fallback: use default executor or skip metadata
            return;
        }

        // Decode first executor's teeAddress from the returned struct array
        // TEEServiceContext[] -> first element -> node.teeAddress (index 1 in TEEServiceNode)
        address executor = _extractFirstExecutor(regResult);
        if (executor == address(0)) return;

        // Build LLM prompt
        string memory llmPrompt = string(abi.encodePacked(
            'Generate a memecoin token from this concept: "',
            prompt,
            '"\n\nRespond with ONLY a JSON object, no other text:\n{"name": "Token Name", "symbol": "TICKER", "lore": "One sentence description"}'
        ));

        // Encode LLM precompile call (30 fields)
        bytes memory llmInput = abi.encode(
            executor,                        // 0: executor
            new bytes[](0),                  // 1: encryptedSecrets
            300,                             // 2: ttl (300 blocks ≈ 105 seconds)
            new bytes[](0),                  // 3: secretSignatures
            hex"",                          // 4: userPublicKey (empty = no output encryption)
            string(abi.encodePacked(
                '[{"role":"user","content":"', llmPrompt, '"}]'
            )),                             // 5: messagesJson
            "zai-org/GLM-4.7-FP8",          // 6: model
            int256(0),                       // 7: frequencyPenalty
            "",                              // 8: logitBiasJson
            false,                           // 9: logprobs
            int256(4096),                    // 10: maxCompletionTokens (>=4096 for reasoning)
            "",                              // 11: metadataJson
            "",                              // 12: modalitiesJson
            uint256(1),                      // 13: n
            true,                            // 14: parallelToolCalls
            int256(0),                       // 15: presencePenalty
            "medium",                        // 16: reasoningEffort
            hex"",                          // 17: responseFormatData
            int256(-1),                      // 18: seed
            "auto",                          // 19: serviceTier
            "",                              // 20: stopJson
            false,                           // 21: stream
            int256(700),                     // 22: temperature (0.7)
            hex"",                          // 23: toolChoiceData
            hex"",                          // 24: toolsData
            int256(-1),                      // 25: topLogprobs
            int256(1000),                    // 26: topP (1.0)
            "",                              // 27: user
            false,                           // 28: piiEnabled
            ["", "", ""]                     // 29: convoHistory (empty)
        );

        // Submit to LLM precompile
        (bool ok,) = LLM_PRECOMPILE.call(llmInput);
        if (ok) {
            pendingCallbacks[keccak256(abi.encode(launchId))] = true;
        }
    }

    /// @notice Extract first executor teeAddress from TEEServiceRegistry response
    function _extractFirstExecutor(bytes memory data) internal pure returns (address) {
        // The return is TEEServiceContext[] - an array of structs
        // Each TEEServiceContext has: TEEServiceNode node, bool isValid, bytes32 workloadId
        // TEEServiceNode has: address paymentAddress, address teeAddress, ...
        // Struct array encoding: offset (32 bytes) -> length (32 bytes) -> first element
        // First element offset -> TEEServiceNode (2 words: paymentAddress, teeAddress)

        if (data.length < 128) return address(0);

        // Skip array offset (first 32 bytes)
        uint256 length;
        assembly {
            length := mload(add(data, 32))
        }
        if (length == 0) return address(0);

        // Get first element's data offset
        uint256 elemOffset;
        assembly {
            elemOffset := mload(add(data, 64)) // data[32] = offset to first element
        }

        // TEEServiceNode is a nested struct:
        // [paymentAddress (32), teeAddress (32), teeType (32), publicKey_offset (32), ...]
        // teeAddress is at elemOffset + 32 (after paymentAddress)
        if (data.length < elemOffset + 64) return address(0);

        address teeAddress;
        assembly {
            teeAddress := mload(add(add(data, 32), add(elemOffset, 32)))
        }

        return teeAddress;
    }

    /// @notice Set token metadata (called off-chain or via future callback)
    function setTokenMetadata(
        uint256 launchId,
        string calldata name,
        string calldata symbol,
        string calldata lore
    ) external onlyOwner {
        AgentLaunch storage launch = launches[launchId];
        require(launch.token != address(0), "launch not found");
        require(!launch.metadataSet, "metadata already set");

        HiveAgentToken token = HiveAgentToken(launch.token);
        token.setName(name);
        token.setSymbol(symbol);
        token.setLore(lore);
        token.setLaunchBlock(block.number);
        token.setTotalRaise(virtualRitual);

        launch.metadataSet = true;

        emit MetadataGenerated(launchId, name, symbol);
    }

    /// @notice Get launch info
    function getLaunch(uint256 launchId) external view returns (
        address token,
        address bondingCurve,
        address agentTreasury,
        string memory userPrompt,
        bool metadataSet,
        uint256 createdAt
    ) {
        AgentLaunch storage l = launches[launchId];
        return (l.token, l.bondingCurve, l.agentTreasury, l.userPrompt, l.metadataSet, l.createdAt);
    }

    receive() external payable {}
}

/// @title AgentTreasury - Per-agent treasury for future autonomous calls
contract AgentTreasury {
    address public token;
    address public factory;

    constructor(address token_) {
        token = token_;
        factory = msg.sender;
    }

    modifier onlyFactory() {
        require(msg.sender == factory, "not factory");
        _;
    }

    function withdraw(address to, uint256 amount) external onlyFactory {
        (bool sent,) = to.call{value: amount}("");
        require(sent, "transfer failed");
    }

    receive() external payable {}
}
