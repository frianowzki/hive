// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./HiveAgentToken.sol";
import "./HiveBondingCurve.sol";

/// @title HiveFactory - Ritual-native memecoin launchpad
/// @notice Deploys AI agent tokens and spawns a real Sovereign Agent (0x080C) per token
/// @dev LLM metadata (0x0802) is generated client-side via HiveLLMExecutor (SPC/inline pattern) —
///      see hive-frontend/src/lib/ritual-llm.ts. This contract does NOT call the LLM precompile
///      itself; the old on-chain attempt was based on the wrong execution model (two-phase async)
///      for what is actually a short-running async (SPC) precompile, and has been removed.
contract HiveFactory {
    // --- Ritual System Contracts ---
    // NOTE: LLM_PRECOMPILE intentionally not used here — see contract-level comment above.
    address public constant SOVEREIGN_AGENT_PRECOMPILE = address(0x080C);
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
        address creator;          // NEW: the wallet that launched this token
        string userPrompt;
        bool metadataSet;
        bool agentSpawned;        // NEW: whether spawnAgent() has been called for this launch
        bytes32 sovereignJobId;   // NEW: Phase-2 job id once delivered
        uint256 createdAt;
    }

    mapping(uint256 => AgentLaunch) public launches;
    uint256 public launchCount;

    // launchId <-> agentTreasury, so the async callback (which only gets a jobId + result,
    // no launchId) can find its way back to the right launch. jobId is set from the tx hash
    // of the spawnAgent() call, matching the convention used in examples/sovereign-agent.
    mapping(bytes32 => uint256) public jobIdToLaunch;

    uint256 public virtualRitual = 1 ether;
    uint256 public virtualToken = 1_000_000_000 * 1e18;

    // --- Events ---
    event AgentCreated(
        uint256 indexed launchId,
        address indexed token,
        address indexed bondingCurve,
        string prompt
    );
    event MetadataGenerated(uint256 indexed launchId, string name, string symbol);
    event AgentSpawnRequested(uint256 indexed launchId, bytes32 indexed jobId, address consumer);
    event SovereignAgentResultDelivered(uint256 indexed launchId, bytes32 indexed jobId, bool success, bytes result);

    // --- Modifiers ---
    modifier onlyOwner() {
        require(msg.sender == owner, "not owner");
        _;
    }

    modifier onlyAsyncDelivery() {
        require(msg.sender == ASYNC_DELIVERY, "only async delivery");
        _;
    }

    modifier onlyLaunchCreator(uint256 launchId) {
        AgentLaunch storage launch = launches[launchId];
        require(launch.token != address(0), "launch not found");
        require(msg.sender == launch.creator || msg.sender == owner, "not creator");
        _;
    }

    constructor(address platformTreasury_, address dexRouter_) {
        owner = msg.sender;
        platformTreasury = platformTreasury_;
        dexRouter = dexRouter_;
    }

    // --- Core Functions ---

    /// @notice Create a new AI agent token. Metadata and the Sovereign Agent are both
    ///         set/spawned in follow-up calls by the creator (see setTokenMetadata, spawnAgent).
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

        // 5. Store launch (creator = the wallet that called createAgent)
        launches[launchId] = AgentLaunch({
            token: address(token),
            bondingCurve: address(curve),
            agentTreasury: agentTreasury,
            creator: msg.sender,
            userPrompt: userPrompt,
            metadataSet: false,
            agentSpawned: false,
            sovereignJobId: bytes32(0),
            createdAt: block.number
        });

        // 6. Mark as minting
        token.setStatus(HiveAgentToken.AgentStatus.Minting);

        emit AgentCreated(launchId, address(token), address(curve), userPrompt);
    }

    /// @notice Set token metadata. Callable by the launch creator (or platform owner),
    ///         once LLM generation (done client-side) has produced a name/symbol/lore.
    /// @dev FIX: previously `onlyOwner`-gated with no `creator` tracked anywhere, so every
    ///      launch except ones made by the factory deployer wallet reverted here permanently.
    function setTokenMetadata(
        uint256 launchId,
        string calldata name,
        string calldata symbol,
        string calldata lore
    ) external onlyLaunchCreator(launchId) {
        AgentLaunch storage launch = launches[launchId];
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

    /// @notice Spawn a real, autonomous Sovereign Agent (0x080C) as this token's on-chain mascot.
    /// @dev `sovereignRequestInput` is the 23-field ABI-encoded SovereignAgentRequest, built
    ///      OFF-CHAIN (viem + eciesjs client-side, mirroring examples/sovereign-agent/helpers.py —
    ///      ECIES encryption of secrets cannot happen in the EVM). The request's `consumer` field
    ///      MUST be set to address(this) and its `deliverySelector` field MUST be
    ///      keccak256("onSovereignAgentResult(bytes32,bytes)")[:4], or AsyncDelivery will not be
    ///      able to route the Phase 2 callback back here.
    /// @dev FUNDING: the RitualWallet backing this contract (or the launch creator's wallet,
    ///      depending on how Ritual attributes the deposit for consumer-initiated calls) must be
    ///      pre-funded before this call, or the precompile call will revert. This is the same
    ///      wallet-funding question flagged in your earlier Sovereign Agent scaffold work
    ///      (MIN_RITUAL_WALLET_WEI / the 0.3 RITUAL figure) — see chat for the open question on
    ///      who funds this per launch.
    function spawnAgent(uint256 launchId, bytes calldata sovereignRequestInput)
        external
        onlyLaunchCreator(launchId)
        returns (bytes memory)
    {
        AgentLaunch storage launch = launches[launchId];
        require(!launch.agentSpawned, "agent already spawned");

        (bool ok, bytes memory output) = SOVEREIGN_AGENT_PRECOMPILE.call(sovereignRequestInput);
        require(ok, "sovereign agent precompile call failed");

        launch.agentSpawned = true;

        emit AgentSpawnRequested(launchId, bytes32(0), address(this));
        return output;
    }

    /// @notice Link a launch to its Sovereign Agent job id, once the frontend has the real jobId.
    /// @dev IMPORTANT: do NOT pass the `sendTransaction` return hash here. Ritual defers and
    ///      replays async precompile txs, so the hash you get back from the wallet can differ
    ///      from the effective on-chain hash. Read the actual jobId from AsyncJobTracker's
    ///      commitment event (topic-indexed) instead — see ritual-agent.ts's `watchJobCommitted`.
    function linkPendingJob(uint256 launchId, bytes32 jobId) external onlyLaunchCreator(launchId) {
        AgentLaunch storage launch = launches[launchId];
        require(launch.agentSpawned, "agent not spawned yet");
        require(launch.sovereignJobId == bytes32(0), "already linked");
        launch.sovereignJobId = jobId;
        jobIdToLaunch[jobId] = launchId;
    }

    /// @notice Phase 2 callback from AsyncDelivery for the Sovereign Agent job.
    /// @dev Signature and name are load-bearing: the off-chain request encodes
    ///      keccak256("onSovereignAgentResult(bytes32,bytes)")[:4] as the delivery selector.
    ///      Do not rename or change this signature without re-deriving that selector.
    /// @dev Result decoding (bool success, string error, string text, ...) is left to the
    ///      frontend, same as the existing LLM flow — see ritual-agent.ts's `pollAgentResult`.
    ///      This keeps JSON parsing off-chain and cheap, and lets a human review the agent's
    ///      output before setTokenMetadata is called with it.
    function onSovereignAgentResult(bytes32 jobId, bytes calldata result) external onlyAsyncDelivery {
        uint256 launchId = jobIdToLaunch[jobId];
        AgentLaunch storage launch = launches[launchId];

        emit SovereignAgentResultDelivered(launchId, jobId, true, result);
    }

    /// @notice Get all launched token addresses
    function getAllAgents() external view returns (address[] memory) {
        address[] memory agents = new address[](launchCount);
        for (uint256 i = 0; i < launchCount; i++) {
            agents[i] = launches[i].token;
        }
        return agents;
    }

    /// @notice Get agent info by token address
    function getAgent(address token) external view returns (
        address token_,
        address bondingCurve,
        address agentTreasury,
        address creator,
        string memory userPrompt,
        bool metadataSet,
        bool agentSpawned,
        uint256 createdAt
    ) {
        for (uint256 i = 0; i < launchCount; i++) {
            if (launches[i].token == token) {
                AgentLaunch storage l = launches[i];
                return (l.token, l.bondingCurve, l.agentTreasury, l.creator, l.userPrompt, l.metadataSet, l.agentSpawned, l.createdAt);
            }
        }
        revert("Agent not found");
    }

    /// @notice Get launch info
    function getLaunch(uint256 launchId) external view returns (
        address token,
        address bondingCurve,
        address agentTreasury,
        address creator,
        string memory userPrompt,
        bool metadataSet,
        bool agentSpawned,
        uint256 createdAt
    ) {
        AgentLaunch storage l = launches[launchId];
        return (l.token, l.bondingCurve, l.agentTreasury, l.creator, l.userPrompt, l.metadataSet, l.agentSpawned, l.createdAt);
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
