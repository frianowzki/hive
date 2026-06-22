// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

/// @title HiveGovernor — Safety layer for autonomous agents
/// @notice Enforces spending limits, rate limits, whitelist, and emergency controls
/// @dev Every agent transaction must pass through this governor

contract HiveGovernor {
    // ═══ State ═══

    address public owner;
    address public pendingOwner;
    bool public paused;

    // Per-agent limits
    struct AgentLimits {
        uint256 perTxMax;        // Max value per single transaction (wei)
        uint256 dailyMax;        // Max total value per day (wei)
        uint256 dailySpent;      // Already spent today (wei)
        uint256 dailyResetTime;  // When daily counter resets
        uint256 maxTxPerHour;    // Max transactions per hour
        uint256 txThisHour;      // Transactions this hour
        uint256 hourResetTime;   // When hourly counter resets
        uint256 maxGasPerTx;     // Max gas per transaction
        bool active;             // Is this agent authorized
    }

    // Destination whitelist
    mapping(address => bool) public whitelistedDestinations;

    // Agent registry
    mapping(address => AgentLimits) public agentLimits;
    address[] public registeredAgents;

    // Sector isolation: agent => sector
    mapping(address => bytes32) public agentSector;
    mapping(bytes32 => address[]) public sectorAgents;

    // Emergency
    mapping(address => bool) public killSwitched; // Per-agent kill
    uint256 public globalDailyMax;
    uint256 public globalDailySpent;
    uint256 public globalDailyResetTime;

    // Transaction log
    struct TxRecord {
        address agent;
        address destination;
        uint256 value;
        uint256 gasUsed;
        uint256 timestamp;
        bytes32 sector;
        bool allowed;
        string reason; // Why it was allowed/denied
    }
    TxRecord[] public txHistory;
    uint256 public constant MAX_HISTORY = 1000;

    // ═══ Events ═══

    event TxApproved(address indexed agent, address indexed destination, uint256 value, bytes32 sector);
    event TxDenied(address indexed agent, address indexed destination, uint256 value, string reason);
    event AgentRegistered(address indexed agent, bytes32 sector, uint256 perTxMax, uint256 dailyMax);
    event AgentRevoked(address indexed agent);
    event DestinationWhitelisted(address indexed destination, bool status);
    event KillSwitchToggled(address indexed agent, bool status);
    event GlobalPauseToggled(bool status);
    event LimitsUpdated(address indexed agent, uint256 perTxMax, uint256 dailyMax);
    event OwnershipTransferInitiated(address indexed currentOwner, address indexed pendingOwner);
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    // ═══ Errors ═══

    error GovernorPaused();
    error AgentNotActive();
    error AgentKillSwitched();
    error DestinationNotWhitelisted();
    error PerTxLimitExceeded(uint256 requested, uint256 max);
    error DailyLimitExceeded(uint256 spent, uint256 max);
    error GlobalDailyLimitExceeded(uint256 spent, uint256 max);
    error HourlyRateLimitExceeded(uint256 count, uint256 max);
    error GasLimitExceeded(uint256 gasUsed, uint256 max);
    error NotOwner();
    error NotPendingOwner();
    error ZeroAddress();

    // ═══ Modifiers ═══

    modifier onlyOwner() {
        if (msg.sender != owner) revert NotOwner();
        _;
    }

    modifier whenNotPaused() {
        if (paused) revert GovernorPaused();
        _;
    }

    // ═══ Constructor ═══

    constructor(uint256 _globalDailyMax) {
        owner = msg.sender;
        globalDailyMax = _globalDailyMax;
        globalDailyResetTime = block.timestamp + 1 days;
    }

    // ═══ Agent Management ═══

    /// @notice Register a new agent with spending limits
    function registerAgent(
        address agent,
        bytes32 sector,
        uint256 perTxMax,
        uint256 dailyMax,
        uint256 maxTxPerHour,
        uint256 maxGasPerTx
    ) external onlyOwner {
        if (agent == address(0)) revert ZeroAddress();

        agentLimits[agent] = AgentLimits({
            perTxMax: perTxMax,
            dailyMax: dailyMax,
            dailySpent: 0,
            dailyResetTime: block.timestamp + 1 days,
            maxTxPerHour: maxTxPerHour,
            txThisHour: 0,
            hourResetTime: block.timestamp + 1 hours,
            maxGasPerTx: maxGasPerTx,
            active: true
        });

        agentSector[agent] = sector;
        sectorAgents[sector].push(agent);
        registeredAgents.push(agent);

        emit AgentRegistered(agent, sector, perTxMax, dailyMax);
    }

    /// @notice Revoke an agent's authorization
    function revokeAgent(address agent) external onlyOwner {
        agentLimits[agent].active = false;
        emit AgentRevoked(agent);
    }

    /// @notice Update agent limits
    function updateLimits(
        address agent,
        uint256 perTxMax,
        uint256 dailyMax
    ) external onlyOwner {
        agentLimits[agent].perTxMax = perTxMax;
        agentLimits[agent].dailyMax = dailyMax;
        emit LimitsUpdated(agent, perTxMax, dailyMax);
    }

    // ═══ Destination Whitelist ═══

    /// @notice Add/remove destination from whitelist
    function setWhitelisted(address destination, bool status) external onlyOwner {
        if (destination == address(0)) revert ZeroAddress();
        whitelistedDestinations[destination] = status;
        emit DestinationWhitelisted(destination, status);
    }

    /// @notice Batch set whitelisted destinations
    function setWhitelistedBatch(address[] calldata destinations, bool status) external onlyOwner {
        for (uint256 i = 0; i < destinations.length; i++) {
            whitelistedDestinations[destinations[i]] = status;
            emit DestinationWhitelisted(destinations[i], status);
        }
    }

    // ═══ Core: Validate Transaction ═══

    /// @notice Validate and record a transaction. Call this BEFORE executing.
    /// @param destination Where the funds are going
    /// @param value Amount in wei
    /// @return allowed Whether the transaction is allowed
    /// @return reason Why it was allowed/denied
    function validateTx(
        address destination,
        uint256 value,
        uint256 gasUsed
    ) external whenNotPaused returns (bool allowed, string memory reason) {
        address agent = msg.sender;
        AgentLimits storage limits = agentLimits[agent];

        // Check agent is active
        if (!limits.active) {
            emit TxDenied(agent, destination, value, "agent not active");
            return (false, "agent not active");
        }

        // Check kill switch
        if (killSwitched[agent]) {
            emit TxDenied(agent, destination, value, "kill switch active");
            return (false, "kill switch active");
        }

        // Check destination whitelist
        if (!whitelistedDestinations[destination]) {
            emit TxDenied(agent, destination, value, "destination not whitelisted");
            return (false, "destination not whitelisted");
        }

        // Reset daily counter if needed
        if (block.timestamp >= limits.dailyResetTime) {
            limits.dailySpent = 0;
            limits.dailyResetTime = block.timestamp + 1 days;
        }

        // Reset hourly counter if needed
        if (block.timestamp >= limits.hourResetTime) {
            limits.txThisHour = 0;
            limits.hourResetTime = block.timestamp + 1 hours;
        }

        // Reset global daily counter if needed
        if (block.timestamp >= globalDailyResetTime) {
            globalDailySpent = 0;
            globalDailyResetTime = block.timestamp + 1 days;
        }

        // Check per-tx limit
        if (value > limits.perTxMax) {
            emit TxDenied(agent, destination, value, "per-tx limit exceeded");
            return (false, "per-tx limit exceeded");
        }

        // Check daily limit
        if (limits.dailySpent + value > limits.dailyMax) {
            emit TxDenied(agent, destination, value, "daily limit exceeded");
            return (false, "daily limit exceeded");
        }

        // Check global daily limit
        if (globalDailySpent + value > globalDailyMax) {
            emit TxDenied(agent, destination, value, "global daily limit exceeded");
            return (false, "global daily limit exceeded");
        }

        // Check hourly rate limit
        if (limits.txThisHour >= limits.maxTxPerHour) {
            emit TxDenied(agent, destination, value, "hourly rate limit exceeded");
            return (false, "hourly rate limit exceeded");
        }

        // Check gas limit
        if (gasUsed > limits.maxGasPerTx) {
            emit TxDenied(agent, destination, value, "gas limit exceeded");
            return (false, "gas limit exceeded");
        }

        // All checks passed — record the transaction
        limits.dailySpent += value;
        limits.txThisHour++;
        globalDailySpent += value;

        bytes32 sector = agentSector[agent];

        // Store in history (cap at MAX_HISTORY)
        if (txHistory.length < MAX_HISTORY) {
            txHistory.push(TxRecord({
                agent: agent,
                destination: destination,
                value: value,
                gasUsed: gasUsed,
                timestamp: block.timestamp,
                sector: sector,
                allowed: true,
                reason: "approved"
            }));
        }

        emit TxApproved(agent, destination, value, sector);
        return (true, "approved");
    }

    // ═══ Emergency Controls ═══

    /// @notice Toggle kill switch for a specific agent
    function toggleKillSwitch(address agent) external onlyOwner {
        killSwitched[agent] = !killSwitched[agent];
        emit KillSwitchToggled(agent, killSwitched[agent]);
    }

    /// @notice Emergency pause ALL agents
    function emergencyPause() external onlyOwner {
        paused = true;
        emit GlobalPauseToggled(true);
    }

    /// @notice Unpause
    function unpause() external onlyOwner {
        paused = false;
        emit GlobalPauseToggled(false);
    }

    /// @notice Emergency withdraw all funds from a compromised agent
    function emergencyWithdraw(address token, address to) external onlyOwner {
        if (to == address(0)) revert ZeroAddress();
        uint256 balance;
        if (token == address(0)) {
            balance = address(this).balance;
            (bool success, ) = to.call{value: balance}("");
            require(success, "ETH transfer failed");
        } else {
            balance = IERC20(token).balanceOf(address(this));
            IERC20(token).transfer(to, balance);
        }
    }

    // ═══ View Functions ═══

    function getAgentCount() external view returns (uint256) {
        return registeredAgents.length;
    }

    function getTxHistoryCount() external view returns (uint256) {
        return txHistory.length;
    }

    function getRecentTxs(uint256 count) external view returns (TxRecord[] memory) {
        uint256 len = txHistory.length;
        uint256 start = len > count ? len - count : 0;
        TxRecord[] memory result = new TxRecord[](len - start);
        for (uint256 i = start; i < len; i++) {
            result[i - start] = txHistory[i];
        }
        return result;
    }

    function getDailySpent(address agent) external view returns (uint256) {
        AgentLimits storage limits = agentLimits[agent];
        if (block.timestamp >= limits.dailyResetTime) return 0;
        return limits.dailySpent;
    }

    // ═══ Ownership ═══

    function transferOwnership(address newOwner) external onlyOwner {
        if (newOwner == address(0)) revert ZeroAddress();
        pendingOwner = newOwner;
        emit OwnershipTransferInitiated(owner, newOwner);
    }

    function acceptOwnership() external {
        if (msg.sender != pendingOwner) revert NotPendingOwner();
        emit OwnershipTransferred(owner, pendingOwner);
        owner = pendingOwner;
        pendingOwner = address(0);
    }

    // ═══ Receive ═══

    receive() external payable {}
}

interface IERC20 {
    function balanceOf(address) external view returns (uint256);
    function transfer(address, uint256) external returns (bool);
}
