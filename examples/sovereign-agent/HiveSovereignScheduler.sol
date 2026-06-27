// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

interface IRitualWallet {
    function deposit(uint256 lockDuration) external payable;
    function withdraw(uint256 amount) external;
    function balanceOf(address account) external view returns (uint256);
}

interface IScheduler {
    function schedule(
        bytes calldata data,
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
}

interface IAsyncDelivery {
    // AsyncDelivery forwards sovereign agent results
}

contract HiveSovereignScheduler {
    address constant SOVEREIGN_AGENT = address(0x080C);
    address constant ASYNC_DELIVERY = 0x5A16214fF555848411544b005f7Ac063742f39F6;
    address constant SCHEDULER = 0x56e776BAE2DD60664b69Bd5F865F1180ffB7D58B;
    address constant RITUAL_WALLET = 0x532F0dF0896F353d8C3DD8cc134e8129DA2a3948;

    address public owner;
    bytes public sovereignCalldata;
    uint256 public activeScheduleId;
    uint32 public frequency;
    bool public running;

    bytes32 public lastJobId;
    bytes public lastResult;
    uint256 public executionCount;

    event Scheduled(uint256 indexed callId, uint32 frequency, uint32 numCalls);
    event Executed(uint256 indexed executionIndex);
    event ResultDelivered(bytes32 indexed jobId);
    event Stopped();

    modifier onlyOwner() {
        require(msg.sender == owner, "not owner");
        _;
    }

    modifier onlyScheduler() {
        require(msg.sender == SCHEDULER, "only scheduler");
        _;
    }

    constructor() {
        owner = msg.sender;
    }

    /// @notice Deposit RITUAL to RitualWallet for scheduler fees
    function depositForFees(uint256 lockDuration) external payable {
        IRitualWallet(RITUAL_WALLET).deposit{value: msg.value}(lockDuration);
    }

    /// @notice Start auto-repeating sovereign agent calls
    /// @param _calldata The encoded sovereign agent request (from helpers.py)
    /// @param _frequency Blocks between each call
    /// @param numCalls Total number of calls (e.g. 5 for a window)
    function start(bytes calldata _calldata, uint32 _frequency, uint32 numCalls) external onlyOwner {
        sovereignCalldata = _calldata;
        frequency = _frequency;
        running = true;

        // Build the callback calldata
        // wakeUp(uint256 executionIndex) — Scheduler overwrites bytes 4-35
        bytes memory data = abi.encodeWithSelector(
            this.wakeUp.selector,
            uint256(0)  // placeholder — Scheduler overwrites
        );

        activeScheduleId = IScheduler(SCHEDULER).schedule(
            data,
            800_000,                            // gas
            uint32(block.number) + _frequency,  // startBlock
            numCalls,                           // numCalls
            _frequency,                         // frequency
            500,                                // ttl
            block.basefee,                      // maxFeePerGas
            0,                                  // maxPriorityFeePerGas
            0,                                  // value per call
            address(this)                       // payer (this contract)
        );

        emit Scheduled(activeScheduleId, _frequency, numCalls);
    }

    /// @notice Called by Scheduler on each wake
    function wakeUp(uint256 executionIndex) external onlyScheduler {
        if (!running) return;

        // Call sovereign agent precompile directly
        (bool ok,) = SOVEREIGN_AGENT.call(sovereignCalldata);
        executionCount++;

        emit Executed(executionIndex);
    }

    /// @notice Receive Phase 2 callback from AsyncDelivery
    function onSovereignAgentResult(bytes32 jobId, bytes calldata result) external {
        require(msg.sender == ASYNC_DELIVERY, "unauthorized");
        lastJobId = jobId;
        lastResult = result;
        emit ResultDelivered(jobId);
    }

    /// @notice Stop the auto-repeat loop
    function stop() external onlyOwner {
        running = false;
        if (activeScheduleId != 0) {
            IScheduler(SCHEDULER).cancel(activeScheduleId);
            activeScheduleId = 0;
        }
        emit Stopped();
    }

    /// @notice Withdraw RITUAL from RitualWallet
    function withdrawFromWallet(uint256 amount) external onlyOwner {
        IRitualWallet(RITUAL_WALLET).withdraw(amount);
    }

    receive() external payable {}
}
