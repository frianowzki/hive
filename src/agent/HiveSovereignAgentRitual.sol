// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {PrecompileConsumer} from "./utils/PrecompileConsumer.sol";
import {IScheduler} from "./interfaces/IScheduler.sol";

/// @title HiveSovereignAgent — Autonomous agent for Hive ecosystem
/// @notice Monitors portfolio, manages staking, participates in governance & launches
/// @dev Runs on Ritual Chain via Scheduler + Sovereign Agent precompile (0x080C)

interface IHiveStaking {
    function stake() external payable;
    function unstake(uint256 amount) external;
    function getStakeInfo(address user) external view returns (uint256 staked, uint256 rewards, uint256 lockUntil);
    function claimRewards() external;
}

interface IHiveRegistry {
    function register(string calldata name, uint256 interval) external;
    function heartbeat() external;
    function getAgent(address agent) external view returns (string memory name, uint256 registeredAt, uint256 lastHeartbeat, uint256 heartbeatInterval, bool active);
}

interface IHiveLaunchPad {
    function buyTokens(uint256 saleId, uint256 amount) external payable;
    function getSaleInfo(uint256 saleId) external view returns (address token, uint256 price, uint256 remaining, uint256 startTime, uint256 endTime, bool active);
}

interface IHiveGovernance {
    function vote(uint256 proposalId, bool support) external;
    function getProposal(uint256 proposalId) external view returns (string memory title, uint256 forVotes, uint256 againstVotes, uint256 endTime, bool executed);
}

interface IHiveTreasury {
    function allocate(address division, uint256 amount) external;
    function getBalance() external view returns (uint256);
}

interface IHivePortfolio {
    function getPortfolioValue(address user) external view returns (uint256);
    function getPositions(address user) external view returns (uint256[] memory amounts, address[] memory tokens);
}

contract HiveSovereignAgent is PrecompileConsumer {
    // ═══ State ═══
    
    address public owner;
    IScheduler public scheduler;
    IHiveRegistry public registry;
    
    uint256 public callId;
    uint256 public wakeCount;
    uint32 public nextWakeDelay = 200; // blocks between wakeups (~40 min)
    bool public isRunning;
    
    // Hive contract addresses
    address public hiveStaking;
    address public hiveLaunchPad;
    address public hiveGovernance;
    address public hiveTreasury;
    address public hivePortfolio;
    address public hiveMarketMaker;
    
    // Agent config
    uint256 public maxStakeAmount;
    uint256 public minRewardThreshold;
    bool public autoCompoundEnabled;
    bool public autoParticipateLaunches;
    
    // State tracking
    uint256 public lastStakeCheck;
    uint256 public lastRewardClaim;
    uint256 public totalRewardsClaimed;
    uint256 public totalStaked;
    
    // ═══ Events ═══
    
    event AgentStarted(uint32 wakeDelay);
    event AgentStopped();
    event Staked(uint256 amount);
    event Unstaked(uint256 amount);
    event RewardsClaimed(uint256 amount);
    event RewardsCompounded(uint256 amount);
    event LaunchParticipated(uint256 saleId, uint256 amount);
    event GovernanceVoted(uint256 proposalId, bool support);
    event HeartbeatSent();
    event WakeUp(uint256 wakeCount);
    event TaskExecuted(string task, bool success);
    
    // ═══ Constructor ═══
    
    constructor(
        address _scheduler,
        address _registry,
        address _hiveStaking,
        address _hiveLaunchPad,
        address _hiveGovernance,
        address _hiveTreasury,
        address _hivePortfolio,
        address _hiveMarketMaker
    ) {
        owner = msg.sender;
        scheduler = IScheduler(_scheduler);
        registry = IHiveRegistry(_registry);
        hiveStaking = _hiveStaking;
        hiveLaunchPad = _hiveLaunchPad;
        hiveGovernance = _hiveGovernance;
        hiveTreasury = _hiveTreasury;
        hivePortfolio = _hivePortfolio;
        hiveMarketMaker = _hiveMarketMaker;
        
        maxStakeAmount = 0.1 ether;
        minRewardThreshold = 0.001 ether;
        autoCompoundEnabled = true;
        autoParticipateLaunches = false;
    }
    
    // ═══ Modifiers ═══
    
    modifier onlyOwner() {
        require(msg.sender == owner, "Not owner");
        _;
    }
    
    modifier onlyScheduler() {
        require(msg.sender == address(scheduler), "Not scheduler");
        _;
    }
    
    modifier onlyAsyncDelivery() {
        require(msg.sender == ASYNC_DELIVERY, "Not async delivery");
        _;
    }
    
    // ═══ Agent Lifecycle ═══
    
    /// @notice Start the agent loop
    function start(uint32 initialDelay) external onlyOwner {
        require(!isRunning, "Already running");
        isRunning = true;
        callId = _scheduleNext(initialDelay);
        emit AgentStarted(initialDelay);
    }
    
    /// @notice Stop the agent
    function stop() external onlyOwner {
        isRunning = false;
        emit AgentStopped();
    }
    
    /// @notice Called by Scheduler at scheduled block
    function wakeUp(uint256 executionIndex) external onlyScheduler {
        if (!isRunning) return;
        
        wakeCount++;
        emit WakeUp(wakeCount);
        
        // Execute all tasks
        _executeTasks();
        
        // Schedule next wakeup
        callId = _scheduleNext(nextWakeDelay);
    }
    
    /// @notice Phase 2 callback with agent output
    function onSovereignAgentResult(bytes32 jobId, bytes calldata result) external onlyAsyncDelivery {
        // Process CLI agent output
        // Parse result, update state, make decisions
        _processAgentResult(result);
    }
    
    // ═══ Core Tasks ═══
    
    function _executeTasks() internal {
        // 1. Send heartbeat to registry
        _sendHeartbeat();
        
        // 2. Check and compound staking rewards
        if (autoCompoundEnabled) {
            _checkAndCompoundRewards();
        }
        
        // 3. Check for new launches to participate
        if (autoParticipateLaunches) {
            _checkLaunches();
        }
        
        // 4. Monitor portfolio health
        _monitorPortfolio();
        
        // 5. Check governance proposals
        _checkGovernance();
    }
    
    function _sendHeartbeat() internal {
        try registry.heartbeat() {
            emit HeartbeatSent();
        } catch {}
    }
    
    function _checkAndCompoundRewards() internal {
        try IHiveStaking(hiveStaking).getStakeInfo(address(this)) (
            uint256 staked, uint256 rewards, uint256 lockUntil
        ) {
            if (rewards >= minRewardThreshold) {
                // Claim rewards
                try IHiveStaking(hiveStaking).claimRewards() {
                    emit RewardsClaimed(rewards);
                    totalRewardsClaimed += rewards;
                    
                    // Auto-compound: stake the rewards
                    if (rewards > 0) {
                        try IHiveStaking(hiveStaking).stake{value: rewards}() {
                            emit RewardsCompounded(rewards);
                            totalStaked += rewards;
                        } catch {}
                    }
                } catch {}
            }
        } catch {}
    }
    
    function _checkLaunches() internal {
        // Check for active launches and participate if conditions met
        // This is a simplified version - in production, you'd iterate through sales
        try IHiveLaunchPad(hiveLaunchPad).getSaleInfo(0) (
            address token, uint256 price, uint256 remaining, 
            uint256 startTime, uint256 endTime, bool active
        ) {
            if (active && remaining > 0 && block.timestamp >= startTime && block.timestamp <= endTime) {
                // Participate with a small amount
                uint256 buyAmount = 0.01 ether;
                if (address(this).balance >= buyAmount + 0.01 ether) {
                    try IHiveLaunchPad(hiveLaunchPad).buyTokens{value: buyAmount}(0, buyAmount / price) {
                        emit LaunchParticipated(0, buyAmount);
                    } catch {}
                }
            }
        } catch {}
    }
    
    function _monitorPortfolio() internal {
        try IHivePortfolio(hivePortfolio).getPortfolioValue(address(this)) (uint256 value) {
            // Log portfolio value
            // In production, you'd implement risk management logic here
        } catch {}
    }
    
    function _checkGovernance() internal {
        // Check for active proposals and vote
        // This is simplified - in production, you'd check multiple proposals
        try IHiveGovernance(hiveGovernance).getProposal(0) (
            string memory title, uint256 forVotes, uint256 againstVotes, 
            uint256 endTime, bool executed
        ) {
            if (!executed && block.timestamp < endTime) {
                // Auto-vote based on some logic (e.g., always support)
                try IHiveGovernance(hiveGovernance).vote(0, true) {
                    emit GovernanceVoted(0, true);
                } catch {}
            }
        } catch {}
    }
    
    function _processAgentResult(bytes calldata result) internal {
        // Parse CLI agent output and take action
        // This is where you'd implement more sophisticated logic
    }
    
    // ═══ Scheduler ═══
    
    function _scheduleNext(uint32 delay) internal returns (uint256) {
        return scheduler.schedule(
            abi.encodeWithSelector(this.wakeUp.selector, uint256(0)),
            800_000,                          // gas
            uint32(block.number) + delay,      // startBlock
            3,                                 // retry slots
            1,                                 // frequency
            30,                                // ttl
            20 gwei, 2 gwei, 0,               // fees
            address(this)                      // payer = self
        );
    }
    
    // ═══ Admin Functions ═══
    
    function setWakeDelay(uint32 newDelay) external onlyOwner {
        nextWakeDelay = newDelay;
    }
    
    function setMaxStakeAmount(uint256 newMax) external onlyOwner {
        maxStakeAmount = newMax;
    }
    
    function setMinRewardThreshold(uint256 newThreshold) external onlyOwner {
        minRewardThreshold = newThreshold;
    }
    
    function setAutoCompound(bool enabled) external onlyOwner {
        autoCompoundEnabled = enabled;
    }
    
    function setAutoParticipateLaunches(bool enabled) external onlyOwner {
        autoParticipateLaunches = enabled;
    }
    
    function setHiveContracts(
        address _staking,
        address _launchPad,
        address _governance,
        address _treasury,
        address _portfolio,
        address _marketMaker
    ) external onlyOwner {
        hiveStaking = _staking;
        hiveLaunchPad = _launchPad;
        hiveGovernance = _governance;
        hiveTreasury = _treasury;
        hivePortfolio = _portfolio;
        hiveMarketMaker = _marketMaker;
    }
    
    // ═══ View Functions ═══
    
    function getAgentStatus() external view returns (
        bool running,
        uint256 wakes,
        uint256 totalRewards,
        uint256 totalStakedAmount,
        uint32 wakeDelay
    ) {
        return (isRunning, wakeCount, totalRewardsClaimed, totalStaked, nextWakeDelay);
    }
    
    function getStakingInfo() external view returns (
        uint256 staked,
        uint256 rewards,
        uint256 lockUntil
    ) {
        try IHiveStaking(hiveStaking).getStakeInfo(address(this)) (
            uint256 s, uint256 r, uint256 l
        ) {
            return (s, r, l);
        } catch {
            return (0, 0, 0);
        }
    }
    
    // ═══ Receive ═══
    
    receive() external payable {}
}
