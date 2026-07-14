// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./HiveAgentToken.sol";
import "./HiveBondingCurve.sol";

/// @title HiveFactory - Ritual-native memecoin launchpad
/// @notice Deploys AI agent tokens with LLM-generated metadata + Sovereign Agent spawning
/// @dev LLM via HiveLLMExecutor (SPC/short-running). Agent via 0x080C (long-running async).
contract HiveFactory {
    // --- Ritual System Contracts ---
    address public constant SOVEREIGN_AGENT = address(0x080C);
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
        address creator;          // ← NEW: who created this launch
        string userPrompt;
        bool metadataSet;
        bytes32 pendingJobId;     // ← NEW: async agent job
        uint256 createdAt;
    }

    struct AgentResult {
        bool success;
        string errorMessage;
        string responseText;
        uint256 receivedAt;
    }

    mapping(uint256 => AgentLaunch) public launches;
    uint256 public launchCount;

    mapping(bytes32 => uint256) public jobToLaunch;      // jobId → launchId
    mapping(uint256 => AgentResult) public agentResults;  // launchId → result

    uint256 public virtualRitual = 1 ether;
    uint256 public virtualToken = 1_000_000_000 * 1e18;

    // --- Events ---
    event AgentCreated(
        uint256 indexed launchId,
        address indexed token,
        address indexed bondingCurve,
        address creator,
        string prompt
    );
    event MetadataGenerated(uint256 indexed launchId, string name, string symbol);
    event AgentSpawned(uint256 indexed launchId, bytes32 indexed jobId);
    event AgentResultReceived(uint256 indexed launchId, bytes32 indexed jobId, bool success);

    // --- Modifiers ---
    modifier onlyOwner() {
        require(msg.sender == owner, "not owner");
        _;
    }

    modifier onlyAsyncDelivery() {
        require(msg.sender == ASYNC_DELIVERY, "only async delivery");
        _;
    }

    modifier onlyCreatorOrOwner(uint256 launchId) {
        AgentLaunch storage l = launches[launchId];
        require(
            msg.sender == l.creator || msg.sender == owner,
            "not creator or owner"
        );
        _;
    }

    constructor(address platformTreasury_, address dexRouter_) {
        owner = msg.sender;
        platformTreasury = platformTreasury_;
        dexRouter = dexRouter_;
    }

    // --- Core Functions ---

    /// @notice Create a new AI agent token with bonding curve
    /// @param userPrompt Description of the token concept
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

        // 5. Store launch (with creator)
        launches[launchId] = AgentLaunch({
            token: address(token),
            bondingCurve: address(curve),
            agentTreasury: agentTreasury,
            creator: msg.sender,        // ← FIXED: record who created
            userPrompt: userPrompt,
            metadataSet: false,
            pendingJobId: bytes32(0),
            createdAt: block.number
        });

        // 6. Mark as minting
        token.setStatus(HiveAgentToken.AgentStatus.Minting);

        emit AgentCreated(launchId, address(token), address(curve), msg.sender, userPrompt);
    }

    /// @notice Set token metadata (callable by creator OR owner)
    /// @dev Fixed: old version was onlyOwner, silently reverted for non-deployer creators
    function setTokenMetadata(
        uint256 launchId,
        string calldata name,
        string calldata symbol,
        string calldata lore
    ) external onlyCreatorOrOwner(launchId) {
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

    /// @notice Spawn a Sovereign Agent for a launched token
    /// @param launchId ID of the launch to attach an agent to
    /// @param sovereignRequestInput ABI-encoded 23-field SovereignAgentRequest
    /// @dev Caller must have funded RitualWallet beforehand. Request is built client-side
    ///      (ECIES encryption can't happen in EVM) and forwarded to precompile.
    function spawnAgent(
        uint256 launchId,
        bytes calldata sovereignRequestInput
    ) external onlyCreatorOrOwner(launchId) returns (bytes32 jobId) {
        AgentLaunch storage launch = launches[launchId];
        require(launch.token != address(0), "launch not found");
        require(launch.pendingJobId == bytes32(0), "agent already spawned");

        // Forward request to Sovereign Agent precompile (0x080C)
        (bool ok, bytes memory output) = SOVEREIGN_AGENT.call(sovereignRequestInput);
        require(ok, "sovereign precompile call failed");

        // Extract jobId from output (first 32 bytes)
        require(output.length >= 32, "invalid precompile output");
        assembly {
            jobId := mload(add(output, 32))
        }

        launch.pendingJobId = jobId;
        jobToLaunch[jobId] = launchId;

        emit AgentSpawned(launchId, jobId);
    }

    /// @notice Callback from AsyncDelivery when agent job is committed on-chain
    /// @dev Ritual's AsyncDelivery delivers Phase 2 results here
    function onSovereignAgentResult(
        bytes32 jobId,
        bytes calldata result
    ) external onlyAsyncDelivery {
        uint256 launchId = jobToLaunch[jobId];
        require(launchId != 0, "unknown job");

        // Store raw result — decoding happens off-chain in ritual-agent.ts
        // Result ABI: (bool success, string error, string text, (string,string,string), (string,string,string), (string,string,string)[])
        bool success = false;
        string memory errorMessage = "";
        string memory responseText = "";

        if (result.length >= 96) {
            // Best-effort decode of the outer tuple
            try abi.decode(result, (bool, string, string, (string,string,string), (string,string,string), (string,string,string)[]))(
                bool s, string memory e, string memory t,
                (string,string,string), (string,string,string), (string,string,string)[]
            ) {
                success = s;
                errorMessage = e;
                responseText = t;
            } catch {
                // If decode fails, store raw hex for off-chain parsing
                success = false;
                errorMessage = "decode failed — parse raw result off-chain";
            }
        }

        agentResults[launchId] = AgentResult({
            success: success,
            errorMessage: errorMessage,
            responseText: responseText,
            receivedAt: block.timestamp
        });

        delete jobToLaunch[jobId];

        emit AgentResultReceived(launchId, jobId, success);
    }

    /// @notice Link a pending job ID to a launch (for jobs submitted externally)
    function linkPendingJob(uint256 launchId, bytes32 jobId) external onlyCreatorOrOwner(launchId) {
        AgentLaunch storage launch = launches[launchId];
        require(launch.token != address(0), "launch not found");
        require(launch.pendingJobId == bytes32(0), "job already linked");

        launch.pendingJobId = jobId;
        jobToLaunch[jobId] = launchId;
    }

    // --- View Functions ---

    function getLaunch(uint256 launchId) external view returns (
        address token,
        address bondingCurve,
        address agentTreasury,
        address creator,
        string memory userPrompt,
        bool metadataSet,
        bytes32 pendingJobId,
        uint256 createdAt
    ) {
        AgentLaunch storage l = launches[launchId];
        return (
            l.token, l.bondingCurve, l.agentTreasury, l.creator,
            l.userPrompt, l.metadataSet, l.pendingJobId, l.createdAt
        );
    }

    function getAgentResult(uint256 launchId) external view returns (
        bool success,
        string memory errorMessage,
        string memory responseText,
        uint256 receivedAt
    ) {
        AgentResult storage r = agentResults[launchId];
        return (r.success, r.errorMessage, r.responseText, r.receivedAt);
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
