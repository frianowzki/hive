// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

/// @title SimpleSovereignAgent — Lightweight wrapper for Ritual Sovereign Agent precompile
/// @notice Calls 0x080C (Sovereign Agent) and receives results via AsyncDelivery callback
contract SimpleSovereignAgent {
    // ═══ Precompile Addresses ═══
    address constant SOVEREIGN_AGENT_PRECOMPILE = address(0x080C);
    address constant ASYNC_DELIVERY = 0x5A16214fF555848411544b005f7Ac063742f39F6;

    // ═══ State ═══
    address public owner;
    bytes public lastResult;
    bytes32 public lastJobId;
    uint256 public executionCount;
    uint256 public lastExecutionBlock;

    // ═══ Events ═══
    event AgentCalled(bytes32 indexed jobId);
    event AgentResult(bytes32 indexed jobId, bytes result);
    event FundsRescued(address indexed to, uint256 amount);

    // ═══ Modifiers ═══
    modifier onlyOwner() {
        require(msg.sender == owner, "Not owner");
        _;
    }

    // ═══ Constructor ═══
    constructor() {
        owner = msg.sender;
    }

    // ═══ Core Functions ═══

    /// @notice Call the Sovereign Agent precompile with encoded input
    /// @param agentInput ABI-encoded sovereign agent request (23-field)
    function callSovereignAgent(bytes calldata agentInput) external onlyOwner {
        (bool success, bytes memory result) = SOVEREIGN_AGENT_PRECOMPILE.staticcall(agentInput);
        if (!success) {
            if (result.length > 0) {
                assembly {
                    revert(add(result, 32), mload(result))
                }
            }
            revert("Sovereign Agent call failed");
        }

        // Decode jobId from result
        bytes32 jobId = abi.decode(result, (bytes32));
        lastJobId = jobId;
        executionCount++;
        lastExecutionBlock = block.number;

        emit AgentCalled(jobId);
    }

    /// @notice Callback from AsyncDelivery with agent result
    /// @param jobId The job ID from the original call
    /// @param result The result bytes from the TEE execution
    function onSovereignAgentResult(bytes32 jobId, bytes calldata result) external {
        require(msg.sender == ASYNC_DELIVERY, "Not AsyncDelivery");
        lastResult = result;
        lastJobId = jobId;

        emit AgentResult(jobId, result);
    }

    // ═══ View Functions ═══

    function getLastResult() external view returns (bytes memory) {
        return lastResult;
    }

    function getLastJobId() external view returns (bytes32) {
        return lastJobId;
    }

    // ═══ Admin ═══

    /// @notice Rescue native balance to owner
    function rescue() external onlyOwner {
        uint256 balance = address(this).balance;
        require(balance > 0, "No funds");
        (bool ok, ) = owner.call{value: balance}("");
        require(ok, "Transfer failed");
        emit FundsRescued(owner, balance);
    }

    // ═══ Receive ═══
    receive() external payable {}
}
