// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @title HiveMultiSig — Multi-signature wallet for Project/VC accounts
/// @notice Required for AccountType.Project and AccountType.Investor
/// @dev Threshold signatures with time-lock for large transactions

contract HiveMultiSig {
    // ═══ Types ═══

    enum TxType {
        Transfer,       // ETH/ERC20 transfer
        ContractCall,   // Arbitrary contract interaction
        ConfigChange,   // Change multisig settings
        TokenLaunch,    // Launch token sale
        Governance      // DAO action
    }

    struct Transaction {
        address to;
        uint256 value;
        bytes data;
        TxType txType;
        uint256 createdAt;
        uint256 executeAfter;   // Time-lock (timestamp)
        uint256 confirmations;
        bool executed;
        bool cancelled;
        string description;
    }

    // ═══ State ═══

    bytes32 public hiveIdHash;          // Bound HiveID
    address[] public signers;
    mapping(address => bool) public isSigner;
    uint256 public threshold;

    Transaction[] public transactions;
    mapping(uint256 => mapping(address => bool)) public confirmed;

    // Time-lock
    uint256 public constant TIMELOCK_DELAY = 24 hours; // 24h timelock for large tx
    uint256 public constant LARGE_TX_THRESHOLD = 10 ether;

    // ═══ Events ═══

    event TransactionSubmitted(uint256 indexed txId, address indexed proposer, TxType txType);
    event TransactionConfirmed(uint256 indexed txId, address indexed signer);
    event TransactionRevoked(uint256 indexed txId, address indexed signer);
    event TransactionExecuted(uint256 indexed txId);
    event TransactionCancelled(uint256 indexed txId);
    event SignerAdded(address indexed signer);
    event SignerRemoved(address indexed signer);
    event ThresholdUpdated(uint256 newThreshold);

    // ═══ Errors ═══

    error NotSigner();
    error AlreadyConfirmed();
    error NotConfirmed();
    error AlreadyExecuted();
    error InsufficientConfirmations();
    error TimeLockActive();
    error TransactionFailed();
    error InvalidThreshold();
    error OnlySelf(); // Only multisig itself can change config

    // ═══ Modifiers ═══

    modifier onlySigner() {
        if (!isSigner[msg.sender]) revert NotSigner();
        _;
    }

    modifier onlySelf() {
        require(msg.sender == address(this), "MultiSig: only self");
        _;
    }

    modifier txExists(uint256 txId) {
        require(txId < transactions.length, "MultiSig: tx not found");
        _;
    }

    modifier notExecuted(uint256 txId) {
        if (transactions[txId].executed) revert AlreadyExecuted();
        _;
    }

    // ═══ Constructor ═══

    /// @param _signers Initial signers
    /// @param _threshold Number of required confirmations
    /// @param _hiveIdHash Bound HiveID username hash
    constructor(address[] memory _signers, uint256 _threshold, bytes32 _hiveIdHash) {
        require(_signers.length > 0, "MultiSig: no signers");
        require(_threshold > 0 && _threshold <= _signers.length, "MultiSig: invalid threshold");

        hiveIdHash = _hiveIdHash;
        threshold = _threshold;

        for (uint256 i = 0; i < _signers.length; i++) {
            address signer = _signers[i];
            require(signer != address(0), "MultiSig: zero address");
            require(!isSigner[signer], "MultiSig: duplicate signer");

            isSigner[signer] = true;
            signers.push(signer);
        }
    }

    // ═══ Submit ═══

    /// @notice Submit a new transaction for approval
    function submitTransaction(
        address to,
        uint256 value,
        bytes calldata data,
        TxType txType,
        string calldata description
    ) external onlySigner returns (uint256 txId) {
        uint256 executeAfter = block.timestamp;

        // Time-lock for large transfers
        if (txType == TxType.Transfer && value >= LARGE_TX_THRESHOLD) {
            executeAfter = block.timestamp + TIMELOCK_DELAY;
        }

        txId = transactions.length;

        transactions.push(Transaction({
            to: to,
            value: value,
            data: data,
            txType: txType,
            createdAt: block.timestamp,
            executeAfter: executeAfter,
            confirmations: 0,
            executed: false,
            cancelled: false,
            description: description
        }));

        emit TransactionSubmitted(txId, msg.sender, txType);
        return txId;
    }

    // ═══ Confirm ═══

    /// @notice Confirm a transaction
    function confirmTransaction(uint256 txId) external onlySigner txExists(txId) notExecuted(txId) {
        if (confirmed[txId][msg.sender]) revert AlreadyConfirmed();

        confirmed[txId][msg.sender] = true;
        transactions[txId].confirmations++;

        emit TransactionConfirmed(txId, msg.sender);
    }

    /// @notice Revoke confirmation
    function revokeConfirmation(uint256 txId) external onlySigner txExists(txId) notExecuted(txId) {
        if (!confirmed[txId][msg.sender]) revert NotConfirmed();

        confirmed[txId][msg.sender] = false;
        transactions[txId].confirmations--;

        emit TransactionRevoked(txId, msg.sender);
    }

    // ═══ Execute ═══

    /// @notice Execute a confirmed transaction
    function executeTransaction(uint256 txId) external onlySigner txExists(txId) notExecuted(txId) {
        Transaction storage txn = transactions[txId];

        if (txn.confirmations < threshold) revert InsufficientConfirmations();
        if (block.timestamp < txn.executeAfter) revert TimeLockActive();

        txn.executed = true;

        (bool success, ) = txn.to.call{value: txn.value}(txn.data);
        if (!success) revert TransactionFailed();

        emit TransactionExecuted(txId);
    }

    // ═══ Cancel ═══

    /// @notice Cancel a transaction (requires threshold confirmations)
    function cancelTransaction(uint256 txId) external onlySigner txExists(txId) notExecuted(txId) {
        Transaction storage txn = transactions[txId];
        if (txn.confirmations < threshold) revert InsufficientConfirmations();

        txn.cancelled = true;
        emit TransactionCancelled(txId);
    }

    // ═══ Config Changes (only via multisig itself) ═══

    /// @notice Add a new signer (must be called via multisig)
    function addSigner(address signer) external onlySelf {
        require(signer != address(0), "MultiSig: zero address");
        require(!isSigner[signer], "MultiSig: already signer");

        isSigner[signer] = true;
        signers.push(signer);

        emit SignerAdded(signer);
    }

    /// @notice Remove a signer (must be called via multisig)
    function removeSigner(address signer) external onlySelf {
        require(isSigner[signer], "MultiSig: not signer");
        require(signers.length - 1 >= threshold, "MultiSig: below threshold");

        isSigner[signer] = false;

        // Remove from array
        for (uint256 i = 0; i < signers.length; i++) {
            if (signers[i] == signer) {
                signers[i] = signers[signers.length - 1];
                signers.pop();
                break;
            }
        }

        emit SignerRemoved(signer);
    }

    /// @notice Update threshold (must be called via multisig)
    function changeThreshold(uint256 _threshold) external onlySelf {
        if (_threshold == 0 || _threshold > signers.length) revert InvalidThreshold();
        threshold = _threshold;
        emit ThresholdUpdated(_threshold);
    }

    // ═══ Receive ═══

    receive() external payable {}

    // ═══ View ═══

    function getTransaction(uint256 txId) external view returns (Transaction memory) {
        return transactions[txId];
    }

    function getSigners() external view returns (address[] memory) {
        return signers;
    }

    function getSignerCount() external view returns (uint256) {
        return signers.length;
    }

    function getTransactionCount() external view returns (uint256) {
        return transactions.length;
    }

    function isConfirmed(uint256 txId, address signer) external view returns (bool) {
        return confirmed[txId][signer];
    }

    /// @notice Check if transaction is ready to execute
    function isReady(uint256 txId) external view returns (bool) {
        Transaction storage txn = transactions[txId];
        return !txn.executed && !txn.cancelled &&
               txn.confirmations >= threshold &&
               block.timestamp >= txn.executeAfter;
    }
}
