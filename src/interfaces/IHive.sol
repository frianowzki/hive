// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

/// @notice Interface for staking contract
interface IStaking {
    function totalStaked() external view returns (uint256);
    function stakedAmount(address user) external view returns (uint256);
    function lockMultiplier(address user) external view returns (uint256);
    function getStakers() external view returns (address[] memory);
}

/// @notice Interface for referral contract
interface IReferral {
    function getReferrer(address user) external view returns (address);
    function referralTier(address user) external view returns (uint8);
}

/// @notice Interface for multi-sig
interface IMultiSig {
    function isOwner(address owner) external view returns (bool);
    function submitTransaction(address target, bytes calldata data) external returns (uint256);
    function confirmTransaction(uint256 txId) external;
    function executeTransaction(uint256 txId) external;
}
