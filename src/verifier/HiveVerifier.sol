// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

/// @title HiveVerifier — ZK Proof Verifier for KYC/KYB
/// @notice Verifies Groth16 zk-SNARK proofs via BN256 pairing precompile
/// @dev Uses ecPairing precompile (0x08) for on-chain proof verification

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

    struct VerifyingKey {
        uint256[2] alpha;           // G1 point
        uint256[4] beta;            // G2 point
        uint256[4] gamma;           // G2 point
        uint256[4] delta;           // G2 point
        uint256[2][] gamma_abc;     // G1 points (IC)
    }

    // ═══ State ═══

    mapping(bytes32 => bool) public usedNullifiers;
    mapping(bytes32 => mapping(uint8 => ProofRecord)) public proofs;
    mapping(bytes32 => uint8[]) public verifiedProofTypes;

    mapping(address => bool) public authorizedVerifiers;
    mapping(address => bool) public verifierContracts;

    // Proof type => verifying key
    mapping(uint8 => VerifyingKey) internal _verifyingKeys;
    mapping(uint8 => bool) public keySet;

    address public owner;
    uint256 public constant PROOF_VALIDITY_PERIOD = 365 days;

    // Test mode flag (set to true in tests, false in production)
    bool public testMode;

    // BN256 pairing precompile
    address constant EC_PAIRING = address(0x08);

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
    event VerifyingKeySet(ProofType proofType);

    // ═══ Errors ═══

    error NullifierUsed();
    error InvalidProof();
    error NotAuthorized();
    error ProofExpired();
    error ProofNotVerified();
    error VerifyingKeyNotSet();
    error ProofLengthInvalid();

    // ═══ Constructor ═══

    constructor() {
        owner = msg.sender;
    }

    // ═══ Set Verifying Key ═══

    /// @notice Set the verifying key for a proof type
    /// @dev Called once per proof type after circuit compilation
    function setVerifyingKey(
        ProofType proofType,
        uint256[2] calldata alpha,
        uint256[4] calldata beta,
        uint256[4] calldata gamma,
        uint256[4] calldata delta,
        uint256[2][] calldata gamma_abc
    ) external {
        require(msg.sender == owner, "Verifier: not owner");

        VerifyingKey storage vk = _verifyingKeys[uint8(proofType)];
        vk.alpha = alpha;
        vk.beta = beta;
        vk.gamma = gamma;
        vk.delta = delta;
        delete vk.gamma_abc;
        for (uint256 i = 0; i < gamma_abc.length; i++) {
            vk.gamma_abc.push(gamma_abc[i]);
        }

        keySet[uint8(proofType)] = true;
        emit VerifyingKeySet(proofType);
    }

    // ═══ Verify Proof ═══

    /// @notice Submit and verify a Groth16 zk proof
    /// @param usernameHash HiveID username hash
    /// @param proofType Type of proof
    /// @param proof ABI-encoded Groth16 proof (A, B, C points)
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

        // In test mode, skip Groth16 verification
        if (!testMode) {
            if (!keySet[uint8(proofType)]) revert VerifyingKeyNotSet();

            // Verify the Groth16 proof via pairing check
            bool valid = _verifyGroth16(proofType, proof, publicSignals);
            if (!valid) revert InvalidProof();
        }

        // Mark nullifier as used
        usedNullifiers[nullifierHash] = true;

        // Store proof record
        bytes32 proofHash = keccak256(proof);
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

    // ═══ Internal: Groth16 Verification ═══

    /// @dev Verify a Groth16 proof using BN256 pairing precompile
    /// Proof format: abi.encode(A_x, A_y, B_x1, B_x2, B_y1, B_y2, C_x, C_y)
    /// publicSignals: abi.encode(pubInput1, pubInput2, ...)
    function _verifyGroth16(
        ProofType proofType,
        bytes calldata proof,
        bytes calldata publicSignals
    ) internal view returns (bool) {
        // Decode proof points (A in G1, B in G2, C in G1)
        if (proof.length < 256) return false; // Minimum: 4 uint256s + padding

        (
            uint256[2] memory a,
            uint256[4] memory b,
            uint256[2] memory c
        ) = _decodeProof(proof);

        VerifyingKey storage vk = _verifyingKeys[uint8(proofType)];

        // Decode public inputs
        uint256[] memory inputs = _decodePublicSignals(publicSignals);

        // Validate inputs length matches vk.gamma_abc.length - 1
        if (inputs.length != vk.gamma_abc.length - 1) return false;

        // Compute vk_x = gamma_abc[0] + sum(inputs[i] * gamma_abc[i+1])
        uint256[2] memory vk_x = vk.gamma_abc[0];
        for (uint256 i = 0; i < inputs.length; i++) {
            uint256[2] memory product;
            // G1 scalar multiplication: inputs[i] * gamma_abc[i+1]
            product = _g1ScalarMul(vk.gamma_abc[i + 1], inputs[i]);
            // G1 addition: vk_x + product
            vk_x = _g1Add(vk_x, product);
        }

        // Pairing check: e(A, B) == e(alpha, beta) * e(vk_x, gamma) * e(C, delta)
        // Rearranged: e(-A, B) * e(alpha, beta) * e(vk_x, gamma) * e(C, delta) == 1
        // Using ecPairing precompile with 4 pairs
        return _pairingCheck(a, b, c, vk_x, vk);
    }

    function _decodeProof(bytes calldata proof)
        internal
        pure
        returns (uint256[2] memory a, uint256[4] memory b, uint256[2] memory c)
    {
        (a[0], a[1], b[0], b[1], b[2], b[3], c[0], c[1]) = abi.decode(
            proof,
            (uint256, uint256, uint256, uint256, uint256, uint256, uint256, uint256)
        );
    }

    function _decodePublicSignals(bytes calldata publicSignals)
        internal
        pure
        returns (uint256[] memory)
    {
        return abi.decode(publicSignals, (uint256[]));
    }

    /// @dev G1 point addition on BN256
    function _g1Add(uint256[2] memory p1, uint256[2] memory p2)
        internal
        view
        returns (uint256[2] memory r)
    {
        uint256[4] memory input;
        input[0] = p1[0];
        input[1] = p1[1];
        input[2] = p2[0];
        input[3] = p2[1];

        bytes memory data = abi.encodePacked(input);

        assembly {
            let success := staticcall(sub(gas(), 2000), 0x06, add(data, 0x20), mload(data), r, 0x40)
            if iszero(success) { revert(0, 0) }
        }
    }

    /// @dev G1 scalar multiplication on BN256
    function _g1ScalarMul(uint256[2] memory p, uint256 s)
        internal
        view
        returns (uint256[2] memory r)
    {
        uint256[3] memory input;
        input[0] = p[0];
        input[1] = p[1];
        input[2] = s;

        bytes memory data = abi.encodePacked(input);

        assembly {
            let success := staticcall(sub(gas(), 2000), 0x07, add(data, 0x20), mload(data), r, 0x40)
            if iszero(success) { revert(0, 0) }
        }
    }

    /// @dev BN256 pairing check using precompile 0x08
    /// @dev Check: e(-A, B) * e(alpha, beta) * e(vk_x, gamma) * e(C, delta) == 1
    function _pairingCheck(
        uint256[2] memory a,
        uint256[4] memory b,
        uint256[2] memory c,
        uint256[2] memory vk_x,
        VerifyingKey storage vk
    ) internal view returns (bool) {
        // Negate A: -A = (A.x, FIELD_SIZE - A.y)
        uint256 FIELD_SIZE = 21888242871839275222246405745257275088696311157297823662689037894645226208583;
        uint256[2] memory negA;
        negA[0] = a[0];
        negA[1] = FIELD_SIZE - (a[1] % FIELD_SIZE);

        // Build 4 pairing pairs: (-A, B), (alpha, beta), (vk_x, gamma), (C, delta)
        // Each pair: G1 (2 uint256) + G2 (4 uint256) = 6 uint256 = 192 bytes
        // Total: 4 * 192 = 768 bytes
        bytes memory input = new bytes(768);

        // Pair 1: (-A, B)
        _writeG1(input, 0, negA);
        _writeG2(input, 64, b);

        // Pair 2: (alpha, beta)
        _writeG1(input, 192, vk.alpha);
        _writeG2(input, 256, vk.beta);

        // Pair 3: (vk_x, gamma)
        _writeG1(input, 384, vk_x);
        _writeG2(input, 448, vk.gamma);

        // Pair 4: (C, delta)
        _writeG1(input, 576, c);
        _writeG2(input, 640, vk.delta);

        // Call ecPairing precompile
        uint256[1] memory result;
        assembly {
            let success := staticcall(sub(gas(), 2000), 0x08, add(input, 0x20), mload(input), result, 0x20)
            if iszero(success) { return(0, 0) }
        }

        return result[0] == 1;
    }

    function _writeG1(bytes memory data, uint256 offset, uint256[2] memory p) internal pure {
        assembly {
            mstore(add(add(data, 0x20), offset), mload(add(p, 0x00)))
            mstore(add(add(data, 0x20), add(offset, 0x20)), mload(add(p, 0x20)))
        }
    }

    function _writeG2(bytes memory data, uint256 offset, uint256[4] memory p) internal pure {
        // G2 points are stored in reverse order for the precompile
        assembly {
            mstore(add(add(data, 0x20), offset), mload(add(p, 0x20)))
            mstore(add(add(data, 0x20), add(offset, 0x20)), mload(add(p, 0x00)))
            mstore(add(add(data, 0x20), add(offset, 0x40)), mload(add(p, 0x60)))
            mstore(add(add(data, 0x20), add(offset, 0x60)), mload(add(p, 0x40)))
        }
    }

    // ═══ Batch Verify ═══

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

    function isProofValid(bytes32 usernameHash, ProofType proofType) public view returns (bool) {
        ProofRecord storage p = proofs[usernameHash][uint8(proofType)];
        return p.valid && block.timestamp < p.expiresAt;
    }

    function hasValidKYC(bytes32 usernameHash) external view returns (bool) {
        return isProofValid(usernameHash, ProofType.KYC_IDENTITY) &&
               isProofValid(usernameHash, ProofType.KYC_AGE);
    }

    function hasValidKYB(bytes32 usernameHash) external view returns (bool) {
        return isProofValid(usernameHash, ProofType.KYB_LEGAL);
    }

    function getVerifiedTypes(bytes32 usernameHash) external view returns (uint8[] memory) {
        return verifiedProofTypes[usernameHash];
    }

    function getProof(bytes32 usernameHash, ProofType proofType) external view returns (ProofRecord memory) {
        return proofs[usernameHash][uint8(proofType)];
    }

    // ═══ Revoke ═══

    function revokeProof(bytes32 usernameHash, ProofType proofType) external {
        ProofRecord storage p = proofs[usernameHash][uint8(proofType)];
        require(p.valid, "Verifier: not valid");
        require(msg.sender == owner || msg.sender == p.verifier, "Verifier: not authorized");

        p.valid = false;
        emit ProofRevoked(usernameHash, proofType);
    }

    // ═══ Admin ═══

    /// @notice Enable/disable test mode (skips Groth16 verification)
    function setTestMode(bool _testMode) external {
        require(msg.sender == owner, "Verifier: not owner");
        testMode = _testMode;
    }

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
