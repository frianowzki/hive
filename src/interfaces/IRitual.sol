// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @title IRitual — Ritual Chain precompile interfaces
/// @notice Addresses are from Ritual Chain mainnet/testnet

interface IRitualWallet {
    function deposit(uint256 lockDuration) external payable;
    function depositFor(address user, uint256 lockDuration) external payable;
    function withdraw(uint256 amount) external;
    function balanceOf(address account) external view returns (uint256);
    function lockUntil(address account) external view returns (uint256);
}

interface IAsyncJobTracker {
    event JobAdded(uint256 indexed jobId, address indexed sender, uint8 status);
    event Phase1Settled(uint256 indexed jobId);
    event ResultDelivered(uint256 indexed jobId);
    event JobRemoved(uint256 indexed jobId);
}

interface IAsyncDelivery {
    function deliverResult(
        uint256 jobId,
        bytes calldata result,
        bytes calldata signature
    ) external;
}

interface IAgentHeartbeat {
    function heartbeat() external;
    function isAlive(address agent) external view returns (bool);
    function lastHeartbeat(address agent) external view returns (uint256);
}
