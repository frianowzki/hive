// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @title HiveRegistry — Agent Registry + Heartbeat
/// @notice Tracks all Hive agents, monitors liveness, enables discovery

contract HiveRegistry {
    // ═══ State ═══

    struct Agent {
        address agentAddress;
        string name;
        uint256 registeredAt;
        uint256 lastHeartbeat;
        uint256 heartbeatInterval;
        bool active;
        bool alive;
    }

    mapping(address => Agent) public agents;
    address[] public agentList;

    uint256 public constant DEFAULT_HEARTBEAT_INTERVAL = 100; // blocks
    uint256 public constant LIVENESS_THRESHOLD = 500;          // blocks before considered dead

    // ═══ Events ═══

    event AgentRegistered(address indexed agent, string name);
    event Heartbeat(address indexed agent, uint256 blockNumber);
    event AgentDeactivated(address indexed agent, string reason);
    event AgentRevived(address indexed agent);

    // ═══ Registration ═══

    /// @notice Register a new agent
    function register(string calldata name, uint256 heartbeatInterval) external {
        require(agents[agentAddress()].registeredAt == 0, "Registry: already registered");

        if (heartbeatInterval == 0) {
            heartbeatInterval = DEFAULT_HEARTBEAT_INTERVAL;
        }

        agents[msg.sender] = Agent({
            agentAddress: msg.sender,
            name: name,
            registeredAt: block.timestamp,
            lastHeartbeat: block.number,
            heartbeatInterval: heartbeatInterval,
            active: true,
            alive: true
        });

        agentList.push(msg.sender);
        emit AgentRegistered(msg.sender, name);
    }

    // ═══ Heartbeat ═══

    /// @notice Send heartbeat (call every N blocks)
    function heartbeat() external {
        require(agents[msg.sender].active, "Registry: not registered");

        agents[msg.sender].lastHeartbeat = block.number;
        agents[msg.sender].alive = true;

        emit Heartbeat(msg.sender, block.number);
    }

    /// @notice Check if agent is alive
    function isAlive(address agent) public view returns (bool) {
        Agent storage a = agents[agent];
        if (!a.active) return false;
        return (block.number - a.lastHeartbeat) < LIVENESS_THRESHOLD;
    }

    // ═══ Liveness Enforcement ═══

    /// @notice Mark agent as dead if heartbeat missed
    function checkLiveness(address agent) external {
        Agent storage a = agents[agent];
        require(a.active, "Registry: not registered");

        if (!isAlive(agent)) {
            a.alive = false;
            emit AgentDeactivated(agent, "heartbeat_missed");
        }
    }

    /// @notice Revive a dead agent (agent calls this itself)
    function revive() external {
        Agent storage a = agents[msg.sender];
        require(a.active, "Registry: not registered");
        require(!a.alive, "Registry: already alive");

        a.lastHeartbeat = block.number;
        a.alive = true;

        emit AgentRevived(msg.sender);
    }

    /// @notice Deactivate agent (self or admin)
    function deactivate(address agent) external {
        require(msg.sender == agent, "Registry: unauthorized");
        agents[agent].active = false;
        agents[agent].alive = false;
        emit AgentDeactivated(agent, "self_deactivate");
    }

    // ═══ View ═══

    function getAgent(address agent) external view returns (Agent memory) {
        return agents[agent];
    }

    function agentCount() external view returns (uint256) {
        return agentList.length;
    }

    function isRegistered(address agent) external view returns (bool) {
        return agents[agent].registeredAt > 0;
    }

    /// @notice Get blocks since last heartbeat
    function blocksSinceHeartbeat(address agent) external view returns (uint256) {
        return block.number - agents[agent].lastHeartbeat;
    }

    /// @notice Get all active agents
    function getActiveAgents() external view returns (address[] memory) {
        uint256 count = 0;
        for (uint256 i = 0; i < agentList.length; i++) {
            if (agents[agentList[i]].active && isAlive(agentList[i])) {
                count++;
            }
        }

        address[] memory active = new address[](count);
        uint256 idx = 0;
        for (uint256 i = 0; i < agentList.length; i++) {
            if (agents[agentList[i]].active && isAlive(agentList[i])) {
                active[idx++] = agentList[i];
            }
        }

        return active;
    }

    function agentAddress() internal view returns (address) {
        return address(this);
    }
}
