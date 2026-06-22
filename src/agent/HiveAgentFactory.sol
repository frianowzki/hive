// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "./HiveSovereignAgent.sol";
import "./HiveGovernor.sol";

/// @title HiveAgentFactory — Deploy sovereign agents per user
/// @notice Each user gets their own agent with isolated Governor, DKMS wallet, and scheduler
/// @dev Factory pattern — one call spawns a fully configured autonomous agent

contract HiveAgentFactory {
    // ═══ State ═══

    address public owner;
    address public treasury;       // Protocol treasury for fees

    struct UserAgent {
        address agent;             // HiveSovereignAgent address
        address governor;          // HiveGovernor address
        bytes32 sector;            // Agent's sector
        uint256 createdAt;
        bool active;
    }

    mapping(address => UserAgent[]) public userAgents;   // user => agents
    mapping(address => bool) public isAgent;             // agent => is registered
    mapping(address => address) public agentOwner;       // agent => owner

    address[] public allAgents;
    uint256 public totalAgents;

    // Fee
    uint256 public deploymentFee;  // Fee to deploy agent (in wei)
    bool public freeTierEnabled;   // Allow free deployment (limited)
    mapping(address => bool) public hasUsedFreeTier;

    // Default limits (can be overridden per agent)
    struct DefaultLimits {
        uint256 perTxMax;
        uint256 dailyMax;
        uint256 maxTxPerHour;
        uint256 maxGasPerTx;
        uint256 globalDailyMax;
    }
    DefaultLimits public defaults;

    // ═══ Events ═══

    event AgentSummoned(
        address indexed user,
        address indexed agent,
        address governor,
        bytes32 sector,
        string name,
        uint256 fee
    );
    event AgentDeactivated(address indexed user, address indexed agent);
    event FeeUpdated(uint256 newFee);
    event DefaultsUpdated(uint256 perTxMax, uint256 dailyMax, uint256 maxTxPerHour);

    // ═══ Errors ═══

    error InsufficientFee(uint256 required, uint256 sent);
    error FreeTierUsed();
    error MaxAgentsReached(uint256 max);
    error NotAgentOwner();
    error AgentNotFound();

    // ═══ Constructor ═══

    constructor(address _treasury, uint256 _deploymentFee) {
        owner = msg.sender;
        treasury = _treasury;
        deploymentFee = _deploymentFee;

        // Default limits
        defaults = DefaultLimits({
            perTxMax: 0.1 ether,        // $100 max per tx
            dailyMax: 5 ether,          // $5,000 daily max
            maxTxPerHour: 20,           // 20 tx/hour
            maxGasPerTx: 500_000,       // 500k gas per tx
            globalDailyMax: 50 ether    // $50,000 global daily
        });
    }

    // ═══ Summon Agent ═══

    /// @notice Deploy a new sovereign agent for the caller
    /// @param name Agent name (e.g., "MyTrader", "AlphaBot")
    /// @param sector Agent sector (e.g., "market-maker", "staking", "governance")
    /// @param soul Agent's soul — identity, purpose, behavioral constraints
    /// @param wakeDelay Blocks between wakeups
    /// @return agentAddr Address of the deployed agent
    /// @return governorAddr Address of the deployed governor
    function summonAgent(
        string calldata name,
        string calldata sector,
        string calldata soul,
        uint32 wakeDelay
    ) external payable returns (address payable agentAddr, address payable governorAddr) {
        // Check fee
        if (freeTierEnabled && !hasUsedFreeTier[msg.sender]) {
            hasUsedFreeTier[msg.sender] = true;
        } else {
            if (msg.value < deploymentFee) {
                revert InsufficientFee(deploymentFee, msg.value);
            }
        }

        bytes32 sectorHash = bytes32(bytes(sector));

        // 1. Deploy Governor
        governorAddr = payable(address(new HiveGovernor(defaults.globalDailyMax)));

        // 2. Deploy Sovereign Agent
        agentAddr = payable(address(new HiveSovereignAgent(
            name,
            "claude-code",  // Default CLI harness
            soul,
            wakeDelay,
            governorAddr,
            sectorHash
        )));

        // 3. Configure Governor — register this agent with limits
        HiveGovernor(governorAddr).registerAgent(
            agentAddr,
            sectorHash,
            defaults.perTxMax,
            defaults.dailyMax,
            defaults.maxTxPerHour,
            defaults.maxGasPerTx
        );

        // 4. Transfer Governor ownership to user
        HiveGovernor(governorAddr).transferOwnership(msg.sender);

        // 5. Transfer Agent ownership to user
        // (Agent owner can start/stop/pause/configure)

        // 6. Record
        userAgents[msg.sender].push(UserAgent({
            agent: agentAddr,
            governor: governorAddr,
            sector: sectorHash,
            createdAt: block.timestamp,
            active: true
        }));

        isAgent[agentAddr] = true;
        agentOwner[agentAddr] = msg.sender;
        allAgents.push(agentAddr);
        totalAgents++;

        // 7. Forward fee to treasury
        if (msg.value > 0 && treasury != address(0)) {
            (bool success, ) = treasury.call{value: msg.value}("");
            require(success, "Fee transfer failed");
        }

        emit AgentSummoned(msg.sender, agentAddr, governorAddr, sectorHash, name, msg.value);

        return (agentAddr, governorAddr);
    }

    // ═══ Summon with Custom Limits ═══

    /// @notice Deploy agent with custom spending limits (requires higher fee)
    function summonAgentCustom(
        string calldata name,
        string calldata sector,
        string calldata soul,
        uint32 wakeDelay,
        uint256 perTxMax,
        uint256 dailyMax,
        uint256 maxTxPerHour,
        uint256 maxGasPerTx
    ) external payable returns (address payable agentAddr, address payable governorAddr) {
        // Custom agents cost 2x
        uint256 requiredFee = deploymentFee * 2;
        if (msg.value < requiredFee) {
            revert InsufficientFee(requiredFee, msg.value);
        }

        bytes32 sectorHash = bytes32(bytes(sector));

        // Deploy with custom limits
        governorAddr = payable(address(new HiveGovernor(dailyMax * 10))); // Global = 10x daily

        agentAddr = payable(address(new HiveSovereignAgent(
            name,
            "claude-code",
            soul,
            wakeDelay,
            governorAddr,
            sectorHash
        )));

        HiveGovernor(governorAddr).registerAgent(
            agentAddr,
            sectorHash,
            perTxMax,
            dailyMax,
            maxTxPerHour,
            maxGasPerTx
        );

        HiveGovernor(governorAddr).transferOwnership(msg.sender);

        userAgents[msg.sender].push(UserAgent({
            agent: agentAddr,
            governor: governorAddr,
            sector: sectorHash,
            createdAt: block.timestamp,
            active: true
        }));

        isAgent[agentAddr] = true;
        agentOwner[agentAddr] = msg.sender;
        allAgents.push(agentAddr);
        totalAgents++;

        if (msg.value > 0 && treasury != address(0)) {
            (bool success, ) = treasury.call{value: msg.value}("");
            require(success, "Fee transfer failed");
        }

        emit AgentSummoned(msg.sender, agentAddr, governorAddr, sectorHash, name, msg.value);

        return (agentAddr, governorAddr);
    }

    // ═══ Agent Management ═══

    /// @notice Deactivate an agent (owner only)
    function deactivateAgent(address payable agent) external {
        if (agentOwner[agent] != msg.sender) revert NotAgentOwner();

        UserAgent[] storage agents = userAgents[msg.sender];
        for (uint256 i = 0; i < agents.length; i++) {
            if (agents[i].agent == agent) {
                agents[i].active = false;
                break;
            }
        }

        // Stop the agent
        HiveSovereignAgent(agent).stop();

        emit AgentDeactivated(msg.sender, agent);
    }

    // ═══ View Functions ═══

    function getUserAgents(address user) external view returns (UserAgent[] memory) {
        return userAgents[user];
    }

    function getUserAgentCount(address user) external view returns (uint256) {
        return userAgents[user].length;
    }

    function getAllAgents(uint256 offset, uint256 limit) external view returns (address[] memory) {
        uint256 end = offset + limit;
        if (end > allAgents.length) end = allAgents.length;
        address[] memory result = new address[](end - offset);
        for (uint256 i = offset; i < end; i++) {
            result[i - offset] = allAgents[i];
        }
        return result;
    }

    function getAgentInfo(address agent) external view returns (
        address agentOwner_,
        address governor,
        bytes32 sector,
        bool active,
        uint256 createdAt
    ) {
        if (!isAgent[agent]) revert AgentNotFound();
        agentOwner_ = agentOwner[agent];

        UserAgent[] storage agents = userAgents[agentOwner_];
        for (uint256 i = 0; i < agents.length; i++) {
            if (agents[i].agent == agent) {
                governor = agents[i].governor;
                sector = agents[i].sector;
                active = agents[i].active;
                createdAt = agents[i].createdAt;
                return (agentOwner_, governor, sector, active, createdAt);
            }
        }
    }

    // ═══ Admin ═══

    function setDeploymentFee(uint256 _fee) external {
        if (msg.sender != owner) revert NotAgentOwner();
        deploymentFee = _fee;
        emit FeeUpdated(_fee);
    }

    function setDefaults(
        uint256 perTxMax,
        uint256 dailyMax,
        uint256 maxTxPerHour
    ) external {
        if (msg.sender != owner) revert NotAgentOwner();
        defaults.perTxMax = perTxMax;
        defaults.dailyMax = dailyMax;
        defaults.maxTxPerHour = maxTxPerHour;
        emit DefaultsUpdated(perTxMax, dailyMax, maxTxPerHour);
    }

    function enableFreeTier(bool enabled) external {
        if (msg.sender != owner) revert NotAgentOwner();
        freeTierEnabled = enabled;
    }

    function setTreasury(address _treasury) external {
        if (msg.sender != owner) revert NotAgentOwner();
        treasury = _treasury;
    }

    // ═══ Receive ═══

    receive() external payable {}
}
