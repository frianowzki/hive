// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

// ═══════════════════════════════════════════════════════════════
//  Ritual Sovereign Agent Harness
//  
//  Factory-backed harness for autonomous AI agents on Ritual Chain.
//  Handles scheduler lifecycle, RitualWallet funding, and async callbacks.
//
//  Matches: 0xEc87F4Cf6f1AD2fd47bfbB25b7FDAE093Fb6b097
//  Deployed via: SovereignFactory (0x9dC4C054e53bCc4Ce0A0Ff09E890A7a8e817f304)
// ═══════════════════════════════════════════════════════════════

// ═══ System Interfaces ═══

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

interface IAsyncDelivery {
    // Phase 2 callback delivery
}

// ═══ Agent Parameters Struct ═══

struct Triple {
    string a;
    string b;
    string c;
}

struct SovereignAgentParams {
    address executor;                    // 1. TEE executor address
    uint256 ttl;                         // 2. Time-to-live in blocks
    bytes userPublicKey;                 // 3. User's public key (for encryption)
    uint64 pollIntervalBlocks;           // 4. Poll interval
    uint64 maxPollBlock;                 // 5. Max poll block
    string taskIdMarker;                 // 6. Task identifier
    address deliveryTarget;              // 7. Callback target (this harness)
    bytes4 deliverySelector;             // 8. Callback function selector
    uint256 deliveryGasLimit;            // 9. Gas limit for callback
    uint256 deliveryMaxFeePerGas;        // 10. Max fee for callback
    uint256 deliveryMaxPriorityFeePerGas; // 11. Max priority fee
    uint16 cliType;                      // 12. CLI type (5=crush, 6=zeroclaw)
    string prompt;                       // 13. Agent prompt
    bytes encryptedSecrets;              // 14. ECIES encrypted secrets
    Triple convoHistory;                 // 15. Conversation history config
    Triple output;                       // 16. Output config
    Triple[] skills;                     // 17. Skills
    Triple systemPrompt;                 // 18. System prompt config
    string model;                        // 19. LLM model
    string[] tools;                      // 20. Tools
    uint16 maxTurns;                     // 21. Max turns
    uint32 maxTokens;                    // 22. Max tokens
    string rpcUrls;                      // 23. Custom RPC URLs
}

struct ScheduleConfig {
    uint32 schedulerGas;                 // Gas limit for scheduler
    uint32 frequency;                    // Blocks between executions
    uint32 schedulerTtl;                 // Scheduler TTL
    uint256 maxFeePerGas;                // Max fee per gas
    uint256 maxPriorityFeePerGas;        // Max priority fee per gas
    uint256 value;                       // Value to send
}

struct RollingConfig {
    uint32 windowNumCalls;               // Calls per window
    uint16 rolloverThresholdBps;         // Rollover threshold (basis points)
    uint16 rolloverRetryEveryCalls;      // Retry interval
}

// ═══ Harness Contract ═══

contract RitualSovereignHarness {
    // ═══ Constants ═══
    address public constant RITUAL_WALLET = 0x532F0dF0896F353d8C3DD8cc134e8129DA2a3948;
    address public constant SCHEDULER = 0x56e776BAE2DD60664b69Bd5F865F1180ffB7D58B;
    address public constant ASYNC_DELIVERY = 0x5A16214fF555848411544b005f7Ac063742f39F6;
    
    // ═══ State ═══
    address public owner;
    uint256 public callId;               // Current scheduler call ID
    bool public isConfigured;            // Whether agent is configured
    bool public isRunning;               // Whether scheduler is active
    
    // Agent config (set during configureFundAndStart)
    address public executor;
    string public prompt;
    string public model;
    uint16 public cliType;
    
    // Schedule state
    uint32 public frequency;
    uint32 public schedulerTtl;
    uint32 public windowNumCalls;
    
    // ═══ Events ═══
    event Configured(address executor, string model, uint16 cliType);
    event Started(uint256 callId, uint32 frequency);
    event Stopped();
    event Heartbeat(uint256 indexed callId, uint256 blockNumber);
    event ResultProcessed(bytes32 indexed jobId, bytes32 resultHash);
    event FundsDeposited(uint256 amount, uint256 lockDuration);
    event FundsWithdrawn(uint256 amount);
    
    // ═══ Errors ═══
    error NotOwner();
    error NotAsyncDelivery();
    error NotScheduler();
    error AlreadyConfigured();
    error NotConfigured();
    error AlreadyRunning();
    error NotRunning();
    error InvalidDeliveryTarget();
    error InsufficientBalance();
    
    // ═══ Modifiers ═══
    modifier onlyOwner() {
        if (msg.sender != owner) revert NotOwner();
        _;
    }
    
    modifier onlyAsyncDelivery() {
        if (msg.sender != ASYNC_DELIVERY) revert NotAsyncDelivery();
        _;
    }
    
    modifier onlyScheduler() {
        if (msg.sender != SCHEDULER) revert NotScheduler();
        _;
    }
    
    // ═══ Constructor ═══
    constructor() {
        owner = msg.sender;
    }
    
    // ═══ Core Functions ═══
    
    /**
     * @notice Configure, fund, and start the agent in one transaction
     * @param params Sovereign agent parameters (23 fields)
     * @param schedule Schedule configuration
     * @param rolling Rolling window configuration
     * @param lockDuration RitualWallet lock duration in blocks
     */
    function configureFundAndStart(
        SovereignAgentParams calldata params,
        ScheduleConfig calldata schedule,
        RollingConfig calldata rolling,
        uint256 lockDuration
    ) external payable onlyOwner {
        if (isConfigured) revert AlreadyConfigured();
        
        // Validate delivery target
        if (params.deliveryTarget != address(this)) {
            revert InvalidDeliveryTarget();
        }
        
        // Store config
        executor = params.executor;
        prompt = params.prompt;
        model = params.model;
        cliType = params.cliType;
        frequency = schedule.frequency;
        schedulerTtl = schedule.schedulerTtl;
        windowNumCalls = rolling.windowNumCalls;
        
        // Deposit to RitualWallet
        if (msg.value > 0) {
            IRitualWallet(RITUAL_WALLET).depositFor{value: msg.value}(
                address(this),
                lockDuration
            );
            emit FundsDeposited(msg.value, lockDuration);
        }
        
        // Mark as configured
        isConfigured = true;
        
        // Start scheduler
        _startScheduler(schedule);
        
        emit Configured(executor, model, cliType);
    }
    
    /**
     * @notice Stop the agent and cancel pending scheduler
     */
    function stop() external onlyOwner {
        if (!isRunning) revert NotRunning();
        
        // Cancel pending scheduler call
        if (callId > 0) {
            try IScheduler(SCHEDULER).cancel(callId) {} catch {}
        }
        
        isRunning = false;
        callId = 0;
        
        emit Stopped();
    }
    
    /**
     * @notice Phase 2 callback — Sovereign Agent result delivery
     * @param jobId The async job identifier
     * @param result The encoded result from TEE executor
     */
    function onSovereignAgentResult(
        bytes32 jobId,
        bytes calldata result
    ) external onlyAsyncDelivery {
        // Process the result
        bytes32 resultHash = keccak256(abi.encodePacked(jobId, result));
        emit ResultProcessed(jobId, resultHash);
        
        // Schedule next execution if running
        if (isRunning && isConfigured) {
            _reschedule();
        }
    }
    
    /**
     * @notice Wake up function called by scheduler
     * @param executionIndex Current execution count (injected by scheduler)
     */
    function wakeUp(uint256 executionIndex) external onlyScheduler {
        if (!isRunning) return;
        
        emit Heartbeat(callId, block.number);
        
        // The actual agent execution happens in the TEE
        // The scheduler triggers the precompile which handles execution
    }
    
    // ═══ Scheduler Management ═══
    
    function _startScheduler(ScheduleConfig calldata schedule) internal {
        // Encode wakeUp call
        bytes memory data = abi.encodeWithSelector(
            this.wakeUp.selector,
            uint256(0)  // executionIndex placeholder
        );
        
        // Schedule with IScheduler
        callId = IScheduler(SCHEDULER).schedule(
            data,
            schedule.schedulerGas,
            uint32(block.number) + schedule.frequency,  // startBlock
            windowNumCalls,                      // numCalls
            schedule.frequency,                  // frequency
            schedulerTtl,                        // ttl
            schedule.maxFeePerGas,
            schedule.maxPriorityFeePerGas,
            schedule.value,
            address(this)                        // payer
        );
        
        isRunning = true;
        emit Started(callId, schedule.frequency);
    }
    
    function _reschedule() internal {
        // Re-schedule for next window
        bytes memory data = abi.encodeWithSelector(
            this.wakeUp.selector,
            uint256(0)
        );
        
        callId = IScheduler(SCHEDULER).schedule(
            data,
            500000,                              // default gas
            uint32(block.number) + frequency,    // startBlock
            windowNumCalls,                      // numCalls
            frequency,                           // frequency
            schedulerTtl,                        // ttl
            block.basefee,                       // maxFeePerGas
            0,                                   // maxPriorityFeePerGas
            0,                                   // value
            address(this)                        // payer
        );
    }
    
    // ═══ Fund Management ═══
    
    /**
     * @notice Deposit additional funds to RitualWallet
     */
    function deposit(uint256 lockDuration) external payable onlyOwner {
        IRitualWallet(RITUAL_WALLET).depositFor{value: msg.value}(
            address(this),
            lockDuration
        );
        emit FundsDeposited(msg.value, lockDuration);
    }
    
    /**
     * @notice Withdraw from RitualWallet (after lock expires)
     */
    function withdraw(uint256 amount) external onlyOwner {
        IRitualWallet(RITUAL_WALLET).withdraw(amount);
        emit FundsWithdrawn(amount);
    }
    
    // ═══ View Functions ═══
    
    /**
     * @notice Get RitualWallet balance
     */
    function getWalletBalance() external view returns (uint256) {
        return IRitualWallet(RITUAL_WALLET).balanceOf(address(this));
    }
    
    /**
     * @notice Get RitualWallet lock until block
     */
    function getWalletLockUntil() external view returns (uint256) {
        return IRitualWallet(RITUAL_WALLET).lockUntil(address(this));
    }
    
    /**
     * @notice Get scheduler call state
     */
    function getSchedulerState() external view returns (uint8) {
        if (callId == 0) return 0;
        return IScheduler(SCHEDULER).getCallState(callId);
    }
    
    /**
     * @notice Get agent status
     */
    function getAgentStatus() external view returns (
        bool configured,
        bool running,
        address _executor,
        string memory _model,
        uint16 _cliType,
        uint32 _frequency,
        uint256 _callId,
        uint256 walletBalance
    ) {
        return (
            isConfigured,
            isRunning,
            executor,
            model,
            cliType,
            frequency,
            callId,
            IRitualWallet(RITUAL_WALLET).balanceOf(address(this))
        );
    }
    
    // ═══ Admin ═══
    
    /**
     * @notice Transfer ownership
     */
    function transferOwnership(address newOwner) external onlyOwner {
        owner = newOwner;
    }
    
    /**
     * @notice Accept ETH
     */
    receive() external payable {}
    
    /**
     * @notice Accept ETH with data
     */
    fallback() external payable {}
}
