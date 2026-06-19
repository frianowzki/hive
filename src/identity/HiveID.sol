// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "../libraries/RitualPrecompileConsumer.sol";

/// @title HiveID — On-chain Identity Registry with DKMS Privacy
/// @notice Permanent username + dual-wallet binding + TEE-bound encrypted KYC
/// @dev Integrates Ritual DKMS precompile (0x0803) for deterministic key derivation.
///      Private keys never leave the TEE. KYC data encrypted via ECIES — only TEE can decrypt.

contract HiveID is RitualPrecompileConsumer {
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
        // ── Privacy Extensions (DKMS) ──
        bytes dkmsPublicKey;            // TEE-derived secp256k1 public key (65 bytes uncompressed)
        bytes encryptedKycData;         // ECIES-encrypted KYC blob (only TEE can decrypt)
        bool piiEnabled;                // PII redaction flag for on-chain settlement
    }

    // ═══ State ═══

    mapping(bytes32 => Identity) private _identities;       // usernameHash => Identity
    mapping(address => bytes32) public primaryToIdentity;   // primaryWallet => usernameHash
    mapping(address => bytes32) public hiveToIdentity;      // hiveWallet => usernameHash
    mapping(address => bool) public verifiers;              // KYC/KYB verifier contracts

    // DKMS key index counter per identity (supports key rotation)
    mapping(bytes32 => uint256) public dkmsKeyIndex;

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

    // ── Privacy Events ──
    event IdentityKeyDerived(
        bytes32 indexed usernameHash,
        uint256 keyIndex,
        bytes publicKey,
        uint256 timestamp
    );
    event KycDataStored(
        bytes32 indexed usernameHash,
        uint256 dataSize,
        bool piiEnabled,
        uint256 timestamp
    );
    event PiiModeUpdated(bytes32 indexed usernameHash, bool piiEnabled);

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
    error KeyAlreadyDerived();
    error NoDkmsKey();
    error EmptyKycData();
    error KycAlreadyStored();

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
            exists: true,
            dkmsPublicKey: "",
            encryptedKycData: "",
            piiEnabled: false
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

    // ═══ DKMS Privacy Layer ═══

    /// @notice Derive a deterministic secp256k1 key pair via Ritual DKMS precompile
    /// @dev The private key NEVER leaves the TEE. Only the public key is stored on-chain.
    ///      Key is derived from (executor, identity owner, keyIndex, secp256k1).
    ///      Supports key rotation via incrementing dkmsKeyIndex.
    /// @param usernameHash Identity to derive key for
    function deriveIdentityKey(bytes32 usernameHash)
        external
        onlyIdentityOwner(usernameHash)
    {
        Identity storage id = _identities[usernameHash];

        // Only allow if no key derived yet (use rotateIdentityKey for rotation)
        if (id.dkmsPublicKey.length > 0) {
            revert KeyAlreadyDerived();
        }

        uint256 keyIdx = dkmsKeyIndex[usernameHash];

        // Encode DKMS precompile call:
        // (executor, owner, keyIndex, keyType)
        // keyType 1 = secp256k1
        bytes memory input = abi.encode(
            address(0),             // executor (auto-select TEE)
            id.hiveWallet,          // owner (key bound to hive wallet)
            keyIdx,                 // key index
            uint8(1)                // secp256k1
        );

        bytes memory pubKey = _executePrecompile(DKMS_PRECOMPILE, input);

        id.dkmsPublicKey = pubKey;

        emit IdentityKeyDerived(usernameHash, keyIdx, pubKey, block.timestamp);
    }

    /// @notice Rotate DKMS key (derive a new key at next index)
    /// @dev Old key is preserved on-chain but TEE will use the latest index
    /// @param usernameHash Identity to rotate key for
    function rotateIdentityKey(bytes32 usernameHash)
        external
        onlyIdentityOwner(usernameHash)
        identityExists(usernameHash)
    {
        Identity storage id = _identities[usernameHash];
        uint256 newIdx = dkmsKeyIndex[usernameHash] + 1;
        dkmsKeyIndex[usernameHash] = newIdx;

        bytes memory input = abi.encode(
            address(0),             // executor
            id.hiveWallet,          // owner
            newIdx,                 // new key index
            uint8(1)                // secp256k1
        );

        bytes memory pubKey = _executePrecompile(DKMS_PRECOMPILE, input);

        id.dkmsPublicKey = pubKey;

        emit IdentityKeyDerived(usernameHash, newIdx, pubKey, block.timestamp);
    }

    /// @notice Store ECIES-encrypted KYC data on-chain
    /// @dev Data is encrypted client-side using the identity's DKMS public key.
    ///      Only the TEE can decrypt it (for verification, compliance, inference).
    ///      Set piiEnabled=true to redact this data from on-chain settlement results.
    /// @param usernameHash Identity to store KYC for
    /// @param encryptedData ECIES-encrypted KYC blob
    /// @param _piiEnabled Whether to enable PII redaction for this identity
    function storeEncryptedKyc(
        bytes32 usernameHash,
        bytes calldata encryptedData,
        bool _piiEnabled
    )
        external
        onlyIdentityOwner(usernameHash)
        identityExists(usernameHash)
    {
        if (encryptedData.length == 0) revert EmptyKycData();

        Identity storage id = _identities[usernameHash];

        // Require DKMS key first (needed for TEE to decrypt)
        if (id.dkmsPublicKey.length == 0) revert NoDkmsKey();

        id.encryptedKycData = encryptedData;
        id.piiEnabled = _piiEnabled;

        emit KycDataStored(usernameHash, encryptedData.length, _piiEnabled, block.timestamp);
    }

    /// @notice Update PII redaction flag
    /// @dev When true, Ritual precompiles will redact this identity's data from settlement
    /// @param usernameHash Identity to update
    /// @param _piiEnabled New PII mode
    function setPiiMode(bytes32 usernameHash, bool _piiEnabled)
        external
        onlyIdentityOwner(usernameHash)
        identityExists(usernameHash)
    {
        _identities[usernameHash].piiEnabled = _piiEnabled;
        emit PiiModeUpdated(usernameHash, _piiEnabled);
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

    /// @notice Check if identity has a DKMS-derived key
    function hasDkmsKey(bytes32 usernameHash) external view returns (bool) {
        return _identities[usernameHash].dkmsPublicKey.length > 0;
    }

    /// @notice Check if identity has encrypted KYC data stored
    function hasEncryptedKyc(bytes32 usernameHash) external view returns (bool) {
        return _identities[usernameHash].encryptedKycData.length > 0;
    }

    /// @notice Get the DKMS public key for an identity
    /// @return pubKey 65-byte uncompressed secp256k1 public key
    function getDkmsPublicKey(bytes32 usernameHash) external view returns (bytes memory pubKey) {
        pubKey = _identities[usernameHash].dkmsPublicKey;
        require(pubKey.length > 0, "HiveID: no DKMS key");
    }

    /// @notice Get the current DKMS key index for an identity
    function getDkmsKeyIndex(bytes32 usernameHash) external view returns (uint256) {
        return dkmsKeyIndex[usernameHash];
    }

    /// @notice Get encrypted KYC data size (not the data itself — that's only for TEE)
    function getEncryptedKycSize(bytes32 usernameHash) external view returns (uint256) {
        return _identities[usernameHash].encryptedKycData.length;
    }

    // ═══ Ownership ═══

    /// @notice Transfer ownership to a new address
    function transferOwnership(address newOwner) external onlyOwner {
        require(newOwner != address(0), "zero address");
        owner = newOwner;
    }

}
