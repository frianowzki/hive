// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

/// @title IEigenLayer — EigenLayer contract interfaces for AVS integration
/// @notice Interfaces for DelegationManager, StrategyManager, AVSDirectory, Slasher
/// @dev Based on EigenLayer contracts (github.com/Layr-Labs/eigenlayer-contracts)

interface IDelegationManager {
    /// @notice Register as an operator on EigenLayer
    function registerAsOperator(
        address initDelegationApprover,
        uint32 allocationDelay,
        string calldata metadataURI
    ) external;

    /// @notice Delegate stake to an operator
    function delegateTo(
        address operator,
        address approver,
        bytes calldata signature
    ) external;

    /// @notice Undelegate from an operator (queues withdrawal)
    function undelegate(address staker) external returns (bytes32[] memory withdrawalRoots);

    /// @notice Get operator's total delegated shares for a strategy
    function operatorShares(address operator, address strategy) external view returns (uint256);

    /// @notice Check if address is a registered operator
    function isOperator(address operator) external view returns (bool);
}

interface IStrategyManager {
    /// @notice Deposit tokens into a strategy (restaking)
    function depositIntoStrategy(
        address strategy,
        address token,
        uint256 amount
    ) external;

    /// @notice Withdraw shares from a strategy
    function withdraw(
        address strategy,
        address token,
        uint256 shares
    ) external;

    /// @notice Get staker's shares in a strategy
    function stakerStrategyShares(address staker, address strategy) external view returns (uint256);

    /// @notice Get all strategies a staker has shares in
    function getDeposits(address staker) external view returns (address[] memory);
}

interface IAVSDirectory {
    /// @notice Register an operator for an AVS (Actively Validated Service)
    function registerOperatorToAVS(
        address operator,
        address avs,
        bytes calldata operatorSignature
    ) external;

    /// @notice Deregister an operator from an AVS
    function deregisterOperatorFromAVS(address operator, address avs) external;

    /// @notice Check if operator is registered for an AVS
    function isOperator(address operator) external view returns (bool);
}

interface ISlasher {
    /// @notice Freeze an operator (prevent withdrawals)
    function freezeOperator(address operator) external;

    /// @notice Slash an operator (penalize stake)
    function slashOperator(
        address operator,
        address avs,
        uint256 amount
    ) external;

    /// @notice Check if operator is frozen
    function isFrozen(address operator) external view returns (bool);
}

interface IStrategy {
    /// @notice Get the underlying token for this strategy
    function underlyingToken() external view returns (address);

    /// @notice Get total shares
    function totalShares() external view returns (uint256);

    /// @notice Convert shares to underlying amount
    function sharesToUnderlyingView(uint256 amountShares) external view returns (uint256);

    /// @notice Convert underlying amount to shares
    function underlyingToSharesView(uint256 amountUnderlying) external view returns (uint256);
}
