// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @title AutoSovereignAgent — Scheduler-compatible wrapper for recurring sovereign agent calls
contract AutoSovereignAgent {
    address constant SOVEREIGN_AGENT = address(0x080C);
    address constant ASYNC_DELIVERY = 0x5A16214fF555848411544b005f7Ac063742f39F6;
    address constant SCHEDULER = 0x56e776BAE2DD60664b69Bd5F865F1180ffB7D58B;
    address constant RITUAL_WALLET = 0x532F0dF0896F353d8C3DD8cc134e8129DA2a3948;

    address public owner;
    bytes public sovereignCalldata;
    uint256 public callId;
    bytes32 public lastJobId;
    bytes public lastResult;
    uint32 public frequency;
    bool public running;

    event SovereignAgentResultDelivered(bytes32 indexed jobId, bytes result);
    event Scheduled(uint256 indexed callId, uint32 frequency);
    event Stopped();

    modifier onlyOwner() {
        require(msg.sender == owner, "not owner");
        _;
    }

    constructor() {
        owner = msg.sender;
    }

    /// @notice Configure and start the auto-repeat loop
    /// @param _calldata The encoded callSovereignAgent(bytes) calldata
    /// @param _frequency Blocks between each call
    function start(bytes calldata _calldata, uint32 _frequency) external onlyOwner {
        sovereignCalldata = _calldata;
        frequency = _frequency;
        running = true;
        _scheduleNext();
    }

    /// @notice Called by the Scheduler on each wake
    function wakeUp(uint256) external {
        require(msg.sender == SCHEDULER, "only scheduler");
        require(running, "not running");

        // Call the sovereign agent precompile directly
        (bool ok,) = SOVEREIGN_AGENT.call(sovereignCalldata);
        if (!ok) {
            // Silently fail — scheduler will retry
        }

        // Schedule next
        _scheduleNext();
    }

    /// @notice Receive Phase 2 callback from AsyncDelivery
    function onSovereignAgentResult(bytes32 jobId, bytes calldata result) external {
        require(msg.sender == ASYNC_DELIVERY, "unauthorized");
        lastJobId = jobId;
        lastResult = result;
        emit SovereignAgentResultDelivered(jobId, result);
    }

    /// @notice Stop the auto-repeat loop
    function stop() external onlyOwner {
        running = false;
        // Cancel scheduled call if any
        if (callId != 0) {
            IScheduler(SCHEDULER).cancel(callId);
        }
        emit Stopped();
    }

    /// @notice Withdraw RITUAL from RitualWallet
    function withdrawFromWallet(uint256 amount) external onlyOwner {
        IRitualWallet(RITUAL_WALLET).withdraw(amount);
    }

    /// @notice Deposit RITUAL to RitualWallet
    function depositToWallet(uint256 lockDuration) external payable {
        IRitualWallet(RITUAL_WALLET).deposit{value: msg.value}(lockDuration);
    }

    function _scheduleNext() internal {
        callId = IScheduler(SCHEDULER).schedule(
            abi.encodeWithSelector(this.wakeUp.selector, uint256(0)), // executionIndex placeholder
            800_000,                          // gas
            1,                                // numCalls (1 = one-shot, reschedule in callback)
            uint32(block.number) + frequency   // frequency = delay (startBlock auto-computed)
        );

        emit Scheduled(callId, frequency);
    }

    receive() external payable {}
}

interface IScheduler {
    function schedule(
        bytes calldata callData,
        uint256 gasLimit,
        uint32 numCalls,
        uint32 frequency
    ) external returns (uint256);

    function cancel(uint256 callId) external;
}

interface IRitualWallet {
    function deposit(uint256 lockDuration) external payable;
    function withdraw(uint256 amount) external;
    function balanceOf(address account) external view returns (uint256);
}
