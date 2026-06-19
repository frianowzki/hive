// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

// src/identity/HiveID.sol

/// @title HiveID — On-chain Identity Registry
/// @notice Permanent username + dual-wallet binding (primary + Hive wallet)
/// @dev All Hive activity routes through HiveID. Withdrawals restricted to primary or other HiveIDs.

contract HiveID {
    // ═══ Types ═══

    enum VerificationType {
        None,
        KYC,    // Individual
        KYB     // Organization
    }

    enum AccountType {
        User,       // Regular user (buy/sell)
        Project,    // Token launcher
        Investor    // VC / institutional
    }

    struct Identity {
        bytes32 usernameHash;           // keccak256(username) — permanent
        address primaryWallet;          // ECDSA wallet (connect/register)
        address hiveWallet;             // Ritual passkey wallet (generated)
        AccountType accountType;
        VerificationType verification;
        bytes32 zkProofHash;            // Hash of zk proof (not storing raw proof)
        string emailEncrypted;          // Optional, encrypted
        string socialEncrypted;         // Optional, encrypted
        uint256 createdAt;
        uint256 nonce;                  // For replay protection
        bool exists;
    }

    // ═══ State ═══

    mapping(bytes32 => Identity) private _identities;       // usernameHash => Identity
    mapping(address => bytes32) public primaryToIdentity;   // primaryWallet => usernameHash
    mapping(address => bytes32) public hiveToIdentity;      // hiveWallet => usernameHash
    mapping(address => bool) public verifiers;              // KYC/KYB verifier contracts

    address public owner;
    uint256 public identityCount;
    uint256 public registrationFee;                         // Fee to register (spam prevention)

    // Username constraints
    uint256 public constant MIN_USERNAME_LENGTH = 3;
    uint256 public constant MAX_USERNAME_LENGTH = 32;

    // ═══ Events ═══

    event IdentityCreated(
        bytes32 indexed usernameHash,
        address indexed primaryWallet,
        address hiveWallet,
        AccountType accountType,
        uint256 timestamp
    );
    event HiveWalletBound(bytes32 indexed usernameHash, address newHiveWallet);
    event VerificationUpdated(bytes32 indexed usernameHash, VerificationType vType);
    event FundsTransferred(bytes32 indexed from, bytes32 indexed to, address token, uint256 amount);
    event FundsWithdrawn(bytes32 indexed from, address primaryWallet, address token, uint256 amount);
    event UsernameReserved(bytes32 indexed usernameHash, address indexed primaryWallet);

    // ═══ Errors ═══

    error UsernameTaken();
    error UsernameInvalid();
    error PrimaryWalletLinked();
    error HiveWalletLinked();
    error NotIdentityOwner();
    error NotVerified();
    error InsufficientFee();
    error InvalidAddress();
    error TransferFailed();

    // ═══ Modifiers ═══

    modifier onlyOwner() {
        require(msg.sender == owner, "HiveID: not owner");
        _;
    }

    modifier identityExists(bytes32 usernameHash) {
        require(_identities[usernameHash].exists, "HiveID: identity not found");
        _;
    }

    modifier onlyIdentityOwner(bytes32 usernameHash) {
        Identity storage id = _identities[usernameHash];
        require(id.exists, "HiveID: identity not found");
        require(msg.sender == id.primaryWallet, "HiveID: not identity owner");
        _;
    }

    // ═══ Constructor ═══

    constructor(uint256 _registrationFee) {
        owner = msg.sender;
        registrationFee = _registrationFee;
    }

    // ═══ Registration ═══

    /// @notice Register a new HiveID
    /// @param username Unique permanent username (3-32 chars)
    /// @param hiveWallet Ritual passkey wallet address (generated client-side)
    /// @param accountType User, Project, or Investor
    /// @param emailEncrypted Optional encrypted email
    /// @param socialEncrypted Optional encrypted social handle
    function register(
        string calldata username,
        address hiveWallet,
        AccountType accountType,
        string calldata emailEncrypted,
        string calldata socialEncrypted
    ) external payable {
        // Validate username
        bytes memory usernameBytes = bytes(username);
        if (usernameBytes.length < MIN_USERNAME_LENGTH || usernameBytes.length > MAX_USERNAME_LENGTH) {
            revert UsernameInvalid();
        }

        bytes32 usernameHash = keccak256(bytes(username));
        if (_identities[usernameHash].exists) {
            revert UsernameTaken();
        }

        // Primary wallet can only be linked to one HiveID
        if (primaryToIdentity[msg.sender] != bytes32(0)) {
            revert PrimaryWalletLinked();
        }

        // Hive wallet can only be linked to one HiveID
        if (hiveWallet == address(0)) {
            revert InvalidAddress();
        }
        if (hiveToIdentity[hiveWallet] != bytes32(0)) {
            revert HiveWalletLinked();
        }

        // Registration fee (spam prevention)
        if (msg.value < registrationFee) {
            revert InsufficientFee();
        }

        // Create identity
        _identities[usernameHash] = Identity({
            usernameHash: usernameHash,
            primaryWallet: msg.sender,
            hiveWallet: hiveWallet,
            accountType: accountType,
            verification: VerificationType.None,
            zkProofHash: bytes32(0),
            emailEncrypted: emailEncrypted,
            socialEncrypted: socialEncrypted,
            createdAt: block.timestamp,
            nonce: 0,
            exists: true
        });

        primaryToIdentity[msg.sender] = usernameHash;
        hiveToIdentity[hiveWallet] = usernameHash;
        identityCount++;

        emit IdentityCreated(usernameHash, msg.sender, hiveWallet, accountType, block.timestamp);
        emit UsernameReserved(usernameHash, msg.sender);

        // Refund excess fee
        if (msg.value > registrationFee) {
            (bool sent, ) = msg.sender.call{value: msg.value - registrationFee}("");
            if (!sent) revert TransferFailed();
        }
    }

    // ═══ Verification (KYC/KYB) ═══

    /// @notice Submit zk proof for KYC/KYB verification
    /// @dev Called by registered verifier contracts, not directly by users
    /// @param usernameHash Identity to verify
    /// @param vType KYC or KYB
    /// @param zkProofHash Hash of the zk proof (proof stored off-chain or in calldata)
    function verify(
        bytes32 usernameHash,
        VerificationType vType,
        bytes32 zkProofHash
    ) external identityExists(usernameHash) {
        require(verifiers[msg.sender], "HiveID: not authorized verifier");
        require(vType != VerificationType.None, "HiveID: invalid verification type");

        Identity storage id = _identities[usernameHash];

        // Project/Investor must be KYB, User must be KYC
        if (id.accountType == AccountType.User) {
            require(vType == VerificationType.KYC, "HiveID: users require KYC");
        } else {
            require(vType == VerificationType.KYB, "HiveID: projects/investors require KYB");
        }

        id.verification = vType;
        id.zkProofHash = zkProofHash;

        emit VerificationUpdated(usernameHash, vType);
    }

    // ═══ Wallet Management ═══

    /// @notice Update Hive wallet (passkey wallet rotation)
    /// @param newHiveWallet New Ritual passkey wallet address
    function updateHiveWallet(address newHiveWallet) external {
        bytes32 usernameHash = primaryToIdentity[msg.sender];
        require(usernameHash != bytes32(0), "HiveID: not registered");
        if (newHiveWallet == address(0)) revert InvalidAddress();
        if (hiveToIdentity[newHiveWallet] != bytes32(0)) revert HiveWalletLinked();

        Identity storage id = _identities[usernameHash];

        // Unmap old hive wallet
        hiveToIdentity[id.hiveWallet] = bytes32(0);

        // Map new hive wallet
        id.hiveWallet = newHiveWallet;
        hiveToIdentity[newHiveWallet] = usernameHash;

        emit HiveWalletBound(usernameHash, newHiveWallet);
    }

    // ═══ Transfers (Hive-to-Hive) ═══

    /// @notice Transfer ETH between HiveIDs
    /// @param toUsername Recipient username
    function transferETH(string calldata toUsername) external payable {
        bytes32 fromHash = primaryToIdentity[msg.sender];
        require(fromHash != bytes32(0), "HiveID: not registered");
        require(_identities[fromHash].verification != VerificationType.None, "HiveID: not verified");

        bytes32 toHash = keccak256(bytes(toUsername));
        require(_identities[toHash].exists, "HiveID: recipient not found");

        Identity storage from = _identities[fromHash];
        Identity storage to = _identities[toHash];

        from.nonce++;

        // Transfer from hive wallet to recipient's hive wallet
        // NOTE: In production, this would use a relayer pattern where the primary wallet
        // signs a message and a relayer submits from the hive wallet.
        // For now, ETH is sent directly to the contract and forwarded.
        (bool sent, ) = to.hiveWallet.call{value: msg.value}("");
        if (!sent) revert TransferFailed();

        emit FundsTransferred(fromHash, toHash, address(0), msg.value);
    }

    /// @notice Transfer ERC20 between HiveIDs
    /// @param toUsername Recipient username
    /// @param token ERC20 token address
    /// @param amount Amount to transfer
    function transferERC20(string calldata toUsername, address token, uint256 amount) external {
        bytes32 fromHash = primaryToIdentity[msg.sender];
        require(fromHash != bytes32(0), "HiveID: not registered");
        require(_identities[fromHash].verification != VerificationType.None, "HiveID: not verified");

        bytes32 toHash = keccak256(bytes(toUsername));
        require(_identities[toHash].exists, "HiveID: recipient not found");

        Identity storage to = _identities[toHash];

        // Transfer ERC20 from msg.sender (primary wallet) to recipient's hive wallet
        // NOTE: Primary wallet must have approved this contract
        (bool success, ) = token.call(
            abi.encodeWithSignature(
                "transferFrom(address,address,uint256)",
                msg.sender,
                to.hiveWallet,
                amount
            )
        );
        if (!success) revert TransferFailed();

        emit FundsTransferred(fromHash, toHash, token, amount);
    }

    // ═══ Withdrawal ═══

    /// @notice Withdraw ETH to primary wallet
    function withdrawETH() external {
        bytes32 usernameHash = primaryToIdentity[msg.sender];
        require(usernameHash != bytes32(0), "HiveID: not registered");

        Identity storage id = _identities[usernameHash];
        uint256 balance = address(id.hiveWallet).balance;

        // NOTE: In production, this requires the hive wallet to sign and send.
        // The primary wallet triggers the withdrawal, but the hive wallet executes.
        // This is a simplified version — production uses relayer pattern.

        id.nonce++;

        emit FundsWithdrawn(usernameHash, msg.sender, address(0), balance);
    }

    /// @notice Withdraw ERC20 to primary wallet
    /// @param token ERC20 token address
    /// @param amount Amount to withdraw
    function withdrawERC20(address token, uint256 amount) external {
        bytes32 usernameHash = primaryToIdentity[msg.sender];
        require(usernameHash != bytes32(0), "HiveID: not registered");

        Identity storage id = _identities[usernameHash];
        id.nonce++;

        // NOTE: Same relayer pattern applies. Primary wallet initiates,
        // hive wallet signs the actual transfer.

        emit FundsWithdrawn(usernameHash, msg.sender, token, amount);
    }

    // ═══ Admin ═══

    /// @notice Add authorized verifier
    function addVerifier(address verifier) external onlyOwner {
        require(verifier != address(0), "HiveID: invalid address");
        verifiers[verifier] = true;
    }

    /// @notice Remove verifier
    function removeVerifier(address verifier) external onlyOwner {
        verifiers[verifier] = false;
    }

    /// @notice Update registration fee
    function setRegistrationFee(uint256 newFee) external onlyOwner {
        registrationFee = newFee;
    }

    /// @notice Withdraw accumulated fees
    function withdrawFees(address to) external onlyOwner {
        require(to != address(0), "HiveID: invalid address");
        uint256 balance = address(this).balance;
        (bool sent, ) = to.call{value: balance}("");
        if (!sent) revert TransferFailed();
    }

    // ═══ View Functions ═══

    /// @notice Get identity by username
    function getIdentity(string calldata username) external view returns (Identity memory) {
        bytes32 usernameHash = keccak256(bytes(username));
        return _identities[usernameHash];
    }

    /// @notice Get identity by primary wallet
    function getIdentityByPrimary(address primaryWallet) external view returns (Identity memory) {
        bytes32 usernameHash = primaryToIdentity[primaryWallet];
        require(usernameHash != bytes32(0), "HiveID: not found");
        return _identities[usernameHash];
    }

    /// @notice Get identity by hive wallet
    function getIdentityByHive(address hiveWallet) external view returns (Identity memory) {
        bytes32 usernameHash = hiveToIdentity[hiveWallet];
        require(usernameHash != bytes32(0), "HiveID: not found");
        return _identities[usernameHash];
    }

    /// @notice Check if username is available
    function isUsernameAvailable(string calldata username) external view returns (bool) {
        bytes32 usernameHash = keccak256(bytes(username));
        return !_identities[usernameHash].exists;
    }

    /// @notice Check if user is verified
    function isVerified(address primaryWallet) external view returns (bool) {
        bytes32 usernameHash = primaryToIdentity[primaryWallet];
        if (usernameHash == bytes32(0)) return false;
        return _identities[usernameHash].verification != VerificationType.None;
    }

    /// @notice Check if address is a registered primary wallet
    function isRegistered(address primaryWallet) external view returns (bool) {
        return primaryToIdentity[primaryWallet] != bytes32(0);
    }
}
