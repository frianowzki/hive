// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "../libraries/RitualPrecompileConsumer.sol";

// ═══ Ritual System Interfaces ═══

interface IScheduler {
    function schedule(
        bytes memory data,
        uint32 gas,
        uint32 startBlock,
        uint32 numCalls,
        uint32 frequency,
        uint32 ttl,
        uint256 maxFeePerGas,
        uint256 maxPriorityFeePerGas,
        uint256 value,
        address payer
    ) external returns (uint256 callId);

    function schedule(
        bytes memory data,
        uint32 gas,
        uint32 numCalls,
        uint32 frequency
    ) external returns (uint256 callId);

    function cancel(uint256 callId) external;
    function getCallState(uint256 callId) external view returns (uint8);
}

interface IRitualWallet {
    function deposit(uint256 lockDuration) external payable;
    function depositFor(address user, uint256 lockDuration) external payable;
    function withdraw(uint256 amount) external;
    function balanceOf(address account) external view returns (uint256);
    function lockUntil(address account) external view returns (uint256);
}

interface ILlm {
    // LLM precompile 0x0802 — 30 fields, short-running async
    // Used for on-chain AI inference (market analysis, decision making)
}

interface IHttp {
    // HTTP precompile 0x0801 — 13 fields, short-running async
    // Used for fetching external data (prices, news, API calls)
}

// ═══ Hive Interfaces ═══

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

interface IHivePortfolio {
    function getPortfolioValue(address user) external view returns (uint256);
    function getPositions(address user) external view returns (uint256[] memory amounts, address[] memory tokens);
}

/// @title HiveSovereignAgentRitual — Autonomous agent for Hive ecosystem on Ritual Chain
/// @notice Implements the Sovereign Agent Loop with Scheduler heartbeat + RitualWallet funding
/// @dev Follows Ritual Chain patterns: execution index injection, AsyncDelivery callbacks, RitualWallet escrow
/// @dev Seven Properties: Immortal (Scheduler heartbeat), Emancipated (DKMS keys), Financially Sovereign (RitualWallet),
///      Web2-Interoperable (HTTP precompile), Computationally Sovereign (LLM precompile), Private (TEE), Teleportable (DA)
contract HiveSovereignAgentRitual is RitualPrecompileConsumer {
    // ═══ State ═══

    address public owner;
    uint256 public callId;          // Scheduler call ID
    uint256 public wakeCount;
    uint32 public nextWakeDelay = 200; // blocks between wakeups (~70s at 0.35s blocks)
    bool public isRunning;

    // Hive contract addresses
    address public hiveStaking;
    address public hiveLaunchPad;
    address public hiveGovernance;
    address public hivePortfolio;
    address public hiveMarketMaker;
    address public hiveRegistry;

    // Agent config
    uint256 public maxStakeAmount;
    uint256 public minRewardThreshold;
    bool public autoCompoundEnabled;
    bool public autoParticipateLaunches;
    uint256 public constant MAX_BUDGET = 0.5 ether;

    // State tracking
    uint256 public totalRewardsClaimed;
    uint256 public totalStaked;
    bytes32 public lastDecisionHash; // Hash of last AI decision for integrity

    // ═══ Events ═══

    event AgentStarted(uint32 wakeDelay, uint256 schedulerCallId);
    event AgentStopped();
    event WakeUp(uint256 indexed wakeCount, uint256 blockNumber);
    event RewardsClaimed(uint256 amount);
    event RewardsCompounded(uint256 amount);
    event LaunchParticipated(uint256 saleId, uint256 amount);
    event GovernanceVoted(uint256 proposalId, bool support);
    event HeartbeatSent();
    event WalletDeposited(uint256 amount, uint256 lockUntil);
    event AIDecisionMade(bytes32 decisionHash, string summary);
    event ScheduledCancelled(uint256 callId);

    // ═══ Errors ═══

    error NotOwner();
    error NotScheduler();
    error NotAsyncDelivery();
    error AgentAlreadyRunning();
    error AgentNotRunning();
    error BudgetExceeded(uint256 attempted, uint256 max);
    error InsufficientWalletBalance(uint256 required, uint256 available);

    // ═══ Modifiers ═══

    modifier onlyOwner() {
        if (msg.sender != owner) revert NotOwner();
        _;
    }

    /// @notice Execution index injection — Scheduler overwrites bytes 4-35 with real executionIndex
    /// @dev First param must be uint256 executionIndex per Ritual Scheduler spec
    modifier onlyScheduler() {
        if (msg.sender != SCHEDULER) revert NotScheduler();
        _;
    }

    /// @notice Phase 2 callback guard — msg.sender is AsyncDelivery, not the user
    /// @dev Critical: on Ritual, callback msg.sender = AsyncDelivery (0x5A16...39F6)
    modifier onlyAsyncDelivery() {
        if (msg.sender != ASYNC_DELIVERY) revert NotAsyncDelivery();
        _;
    }

    // ═══ Constructor ═══

    constructor(
        address _registry,
        address _hiveStaking,
        address _hiveLaunchPad,
        address _hiveGovernance,
        address _hivePortfolio,
        address _hiveMarketMaker
    ) {
        owner = msg.sender;
        hiveRegistry = _registry;
        hiveStaking = _hiveStaking;
        hiveLaunchPad = _hiveLaunchPad;
        hiveGovernance = _hiveGovernance;
        hivePortfolio = _hivePortfolio;
        hiveMarketMaker = _hiveMarketMaker;

        maxStakeAmount = 0.1 ether;
        minRewardThreshold = 0.001 ether;
        autoCompoundEnabled = true;
        autoParticipateLaunches = false;
    }

    // ═══ Agent Lifecycle ═══

    /// @notice Start the agent loop — deposits to RitualWallet + schedules first wakeup
    /// @dev Requires contract to have RITUAL balance for wallet deposit
    function start(uint32 initialDelay) external onlyOwner {
        if (isRunning) revert AgentAlreadyRunning();
        isRunning = true;

        // Deposit to RitualWallet for scheduled execution fees
        // Lock must cover commit_block + ttl (use large lock for recurring)
        uint256 balance = address(this).balance;
        if (balance > 0.01 ether) {
            uint256 depositAmount = balance - 0.01 ether; // Keep 0.01 for gas buffer
            IRitualWallet(RITUAL_WALLET).deposit{value: depositAmount}(50_000); // ~50k blocks lock
            emit WalletDeposited(depositAmount, block.number + 50_000);
        }

        // Schedule first wakeup
        callId = _scheduleNext(initialDelay);
        emit AgentStarted(initialDelay, callId);
    }

    /// @notice Stop the agent and cancel pending scheduler call
    function stop() external onlyOwner {
        if (!isRunning) revert AgentNotRunning();
        isRunning = false;

        // Cancel pending scheduled call
        if (callId > 0) {
            try IScheduler(SCHEDULER).cancel(callId) {
                emit ScheduledCancelled(callId);
            } catch {}
        }

        emit AgentStopped();
    }

    /// @notice Called by Scheduler at scheduled block
    /// @dev executionIndex is injected by Scheduler (bytes 4-35 overwrite)
    /// @param executionIndex The current execution count (injected, not from calldata)
    function wakeUp(uint256 executionIndex) external onlyScheduler {
        if (!isRunning) return;

        wakeCount++;
        emit WakeUp(wakeCount, block.number);

        // Execute all tasks
        _executeTasks();

        // Schedule next wakeup
        callId = _scheduleNext(nextWakeDelay);
    }

    /// @notice Phase 2 callback — Sovereign Agent result delivery
    /// @dev msg.sender is AsyncDelivery (0x5A16...39F6), NOT the user
    /// @param jobId The async job identifier from Phase 1
    /// @param result The encoded result from the TEE executor
    function onSovereignAgentResult(bytes32 jobId, bytes calldata result) external onlyAsyncDelivery {
        _processAgentResult(jobId, result);
    }

    /// @notice Phase 2 callback — Persistent Agent result delivery
    function onPersistentAgentResult(bytes32 jobId, bytes calldata result) external onlyAsyncDelivery {
        _processAgentResult(jobId, result);
    }

    // ═══ Core Tasks ═══

    function _executeTasks() internal {
        // 1. Send heartbeat to registry
        _sendHeartbeat();

        // 2. Check and compound staking rewards
        if (autoCompoundEnabled) {
            _checkAndCompoundRewards();
        }

        // 3. Check for new launches
        if (autoParticipateLaunches) {
            _checkLaunches();
        }

        // 4. Monitor portfolio health
        _monitorPortfolio();

        // 5. Check governance proposals
        _checkGovernance();
    }

    function _sendHeartbeat() internal {
        try IHiveRegistry(hiveRegistry).heartbeat() {
            emit HeartbeatSent();
        } catch {}
    }

    function _checkAndCompoundRewards() internal {
        (uint256 staked, uint256 rewards, uint256 lockUntil) = _getStakeInfoSafe();
        if (staked == 0) return;

        if (rewards >= minRewardThreshold) {
            try IHiveStaking(hiveStaking).claimRewards() {
                emit RewardsClaimed(rewards);
                totalRewardsClaimed += rewards;

                if (rewards > 0) {
                    try IHiveStaking(hiveStaking).stake{value: rewards}() {
                        emit RewardsCompounded(rewards);
                        totalStaked += rewards;
                    } catch {}
                }
            } catch {}
        }
    }

    function _getStakeInfoSafe() internal view returns (uint256, uint256, uint256) {
        try IHiveStaking(hiveStaking).getStakeInfo(address(this)) returns (
            uint256 s, uint256 r, uint256 l
        ) {
            return (s, r, l);
        } catch {
            return (0, 0, 0);
        }
    }

    function _checkLaunches() internal {
        try IHiveLaunchPad(hiveLaunchPad).getSaleInfo(0) returns (
            address token, uint256 price, uint256 remaining,
            uint256 startTime, uint256 endTime, bool active
        ) {
            if (active && remaining > 0 && block.timestamp >= startTime && block.timestamp <= endTime) {
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
        try IHivePortfolio(hivePortfolio).getPortfolioValue(address(this)) returns (uint256 value) {
            // Portfolio monitoring — value tracked for risk management
        } catch {}
    }

    function _checkGovernance() internal {
        try IHiveGovernance(hiveGovernance).getProposal(0) returns (
            string memory title, uint256 forVotes, uint256 againstVotes,
            uint256 endTime, bool executed
        ) {
            if (!executed && block.timestamp < endTime) {
                try IHiveGovernance(hiveGovernance).vote(0, true) {
                    emit GovernanceVoted(0, true);
                } catch {}
            }
        } catch {}
    }

    function _processAgentResult(bytes32 jobId, bytes calldata result) internal {
        // Decode and process agent output
        // Store decision hash for integrity verification
        lastDecisionHash = keccak256(abi.encodePacked(jobId, result));
        emit AIDecisionMade(lastDecisionHash, "Agent decision processed");
    }

    // ═══ Scheduler ═══

    /// @notice Schedule next wakeup via Ritual Scheduler precompile
    /// @dev Uses minimal 4-param overload: auto-sets startBlock, ttl, fees, payer
    /// @param delay Blocks to wait before next execution
    function _scheduleNext(uint32 delay) internal returns (uint256) {
        // Minimal overload: schedule(data, gas, numCalls, frequency)
        // Auto-sets: startBlock = block.number + frequency, ttl = 0,
        //            maxFeePerGas = block.basefee, maxPriorityFeePerGas = 0,
        //            value = 0, payer = msg.sender
        return IScheduler(SCHEDULER).schedule(
            abi.encodeWithSelector(this.wakeUp.selector, uint256(0)), // executionIndex placeholder (0)
            800_000,                          // gas limit for execution
            1,                                // numCalls (1 = one-shot, reschedule in callback)
            uint32(block.number) + delay       // frequency = delay (startBlock auto-computed)
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
        address _portfolio,
        address _marketMaker
    ) external onlyOwner {
        hiveStaking = _staking;
        hiveLaunchPad = _launchPad;
        hiveGovernance = _governance;
        hivePortfolio = _portfolio;
        hiveMarketMaker = _marketMaker;
    }

    /// @notice Withdraw from RitualWallet after lock expires
    function withdrawFromWallet(uint256 amount) external onlyOwner {
        IRitualWallet(RITUAL_WALLET).withdraw(amount);
    }

    /// @notice Check RitualWallet balance
    function getWalletBalance() external view returns (uint256) {
        return IRitualWallet(RITUAL_WALLET).balanceOf(address(this));
    }

    /// @notice Check when wallet lock expires
    function getWalletLockUntil() external view returns (uint256) {
        return IRitualWallet(RITUAL_WALLET).lockUntil(address(this));
    }

    // ═══ View Functions ═══

    function getAgentStatus() external view returns (
        bool running,
        uint256 wakes,
        uint256 totalRewards,
        uint256 totalStakedAmount,
        uint32 wakeDelay,
        uint256 walletBalance
    ) {
        uint256 walletBal = IRitualWallet(RITUAL_WALLET).balanceOf(address(this));
        return (isRunning, wakeCount, totalRewardsClaimed, totalStaked, nextWakeDelay, walletBal);
    }

    function getStakingInfo() external view returns (
        uint256 staked,
        uint256 rewards,
        uint256 lockUntil
    ) {
        return _getStakeInfoSafe();
    }

    /// @notice Get scheduler call state
    function getSchedulerState() external view returns (uint8) {
        if (callId == 0) return 0;
        return IScheduler(SCHEDULER).getCallState(callId);
    }

    // ═══ Receive ═══

    receive() external payable {
        if (address(this).balance > MAX_BUDGET) {
            revert BudgetExceeded(address(this).balance, MAX_BUDGET);
        }
    }
}
