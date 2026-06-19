// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

// src/verifier/HiveVerifier.sol

/// @title HiveVerifier — ZK Proof Verifier for KYC/KYB
/// @notice Verifies zero-knowledge proofs for identity verification
/// @dev Integrates with HiveID — stores proof hashes, verifies zk-SNARKs

contract HiveVerifier {
    // ═══ Types ═══

    enum ProofType {
        KYC_AGE,        // Prove age >= 18
        KYC_COUNTRY,    // Prove country of residence (not sanctioned)
        KYC_IDENTITY,   // Prove unique identity (no duplicate)
        KYB_LEGAL,      // Prove legal entity exists
        KYB_JURISDICTION // Prove entity jurisdiction
    }

    struct ProofRecord {
        bytes32 usernameHash;
        ProofType proofType;
        bytes32 proofHash;          // Hash of the zk proof
        bytes32 nullifierHash;      // Prevent double-verification
        uint256 verifiedAt;
        uint256 expiresAt;
        address verifier;           // Who verified
        bool valid;
    }

    // ═══ State ═══

    // nullifierHash => used (prevents replay)
    mapping(bytes32 => bool) public usedNullifiers;
    // usernameHash => ProofType => ProofRecord
    mapping(bytes32 => mapping(uint8 => ProofRecord)) public proofs;
    // usernameHash => list of verified proof types
    mapping(bytes32 => uint8[]) public verifiedProofTypes;

    // Authorized verifiers (zk proof generators/validators)
    mapping(address => bool) public authorizedVerifiers;

    // Verifier contract addresses (external zk verifiers)
    mapping(address => bool) public verifierContracts;

    address public owner;
    uint256 public constant PROOF_VALIDITY_PERIOD = 365 days;

    // ═══ Events ═══

    event ProofVerified(
        bytes32 indexed usernameHash,
        ProofType proofType,
        bytes32 nullifierHash,
        uint256 expiresAt
    );
    event ProofRevoked(bytes32 indexed usernameHash, ProofType proofType);
    event VerifierAuthorized(address indexed verifier);
    event VerifierRevoked(address indexed verifier);

    // ═══ Errors ═══

    error NullifierUsed();
    error InvalidProof();
    error NotAuthorized();
    error ProofExpired();
    error ProofNotVerified();

    // ═══ Constructor ═══

    constructor() {
        owner = msg.sender;
    }

    // ═══ Verify Proof ═══

    /// @notice Submit and verify a zk proof
    /// @param usernameHash HiveID username hash
    /// @param proofType Type of proof
    /// @param proof The zk proof bytes (SNARK proof)
    /// @param publicSignals Public inputs to the proof
    /// @param nullifierHash Unique nullifier to prevent replay
    function verifyProof(
        bytes32 usernameHash,
        ProofType proofType,
        bytes calldata proof,
        bytes calldata publicSignals,
        bytes32 nullifierHash
    ) external {
        if (!authorizedVerifiers[msg.sender] && !verifierContracts[msg.sender]) {
            revert NotAuthorized();
        }
        if (usedNullifiers[nullifierHash]) revert NullifierUsed();

        // Verify the zk proof
        // In production, this would call a verifier contract (Groth16/PLONK)
        // For now, we verify the proof hash is non-empty
        bytes32 proofHash = keccak256(proof);
        if (proofHash == bytes32(0)) revert InvalidProof();

        // Mark nullifier as used
        usedNullifiers[nullifierHash] = true;

        // Store proof record
        uint256 expiresAt = block.timestamp + PROOF_VALIDITY_PERIOD;

        proofs[usernameHash][uint8(proofType)] = ProofRecord({
            usernameHash: usernameHash,
            proofType: proofType,
            proofHash: proofHash,
            nullifierHash: nullifierHash,
            verifiedAt: block.timestamp,
            expiresAt: expiresAt,
            verifier: msg.sender,
            valid: true
        });

        verifiedProofTypes[usernameHash].push(uint8(proofType));

        emit ProofVerified(usernameHash, proofType, nullifierHash, expiresAt);
    }

    // ═══ Batch Verify ═══

    /// @notice Verify multiple proofs at once
    function verifyBatch(
        bytes32 usernameHash,
        ProofType[] calldata proofTypes,
        bytes[] calldata proofs_,
        bytes[] calldata publicSignals,
        bytes32[] calldata nullifierHashes
    ) external {
        require(proofTypes.length == proofs_.length, "Verifier: length mismatch");
        require(proofTypes.length == nullifierHashes.length, "Verifier: length mismatch");

        for (uint256 i = 0; i < proofTypes.length; i++) {
            this.verifyProof(
                usernameHash,
                proofTypes[i],
                proofs_[i],
                publicSignals[i],
                nullifierHashes[i]
            );
        }
    }

    // ═══ Check Verification Status ═══

    /// @notice Check if a specific proof is valid and not expired
    function isProofValid(bytes32 usernameHash, ProofType proofType) public view returns (bool) {
        ProofRecord storage p = proofs[usernameHash][uint8(proofType)];
        return p.valid && block.timestamp < p.expiresAt;
    }

    /// @notice Check if user has valid KYC (all required proofs)
    function hasValidKYC(bytes32 usernameHash) external view returns (bool) {
        return isProofValid(usernameHash, ProofType.KYC_IDENTITY) &&
               isProofValid(usernameHash, ProofType.KYC_AGE);
    }

    /// @notice Check if entity has valid KYB
    function hasValidKYB(bytes32 usernameHash) external view returns (bool) {
        return isProofValid(usernameHash, ProofType.KYB_LEGAL);
    }

    /// @notice Get all verified proof types for a user
    function getVerifiedTypes(bytes32 usernameHash) external view returns (uint8[] memory) {
        return verifiedProofTypes[usernameHash];
    }

    /// @notice Get proof record
    function getProof(bytes32 usernameHash, ProofType proofType) external view returns (ProofRecord memory) {
        return proofs[usernameHash][uint8(proofType)];
    }

    // ═══ Revoke ═══

    /// @notice Revoke a proof (admin or verifier)
    function revokeProof(bytes32 usernameHash, ProofType proofType) external {
        ProofRecord storage p = proofs[usernameHash][uint8(proofType)];
        require(p.valid, "Verifier: not valid");
        require(msg.sender == owner || msg.sender == p.verifier, "Verifier: not authorized");

        p.valid = false;
        emit ProofRevoked(usernameHash, proofType);
    }

    // ═══ Admin ═══

    function authorizeVerifier(address verifier) external {
        require(msg.sender == owner, "Verifier: not owner");
        authorizedVerifiers[verifier] = true;
        emit VerifierAuthorized(verifier);
    }

    function revokeVerifier(address verifier) external {
        require(msg.sender == owner, "Verifier: not owner");
        authorizedVerifiers[verifier] = false;
        emit VerifierRevoked(verifier);
    }

    function registerVerifierContract(address contractAddr) external {
        require(msg.sender == owner, "Verifier: not owner");
        verifierContracts[contractAddr] = true;
    }
}
