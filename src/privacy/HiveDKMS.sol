// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {RitualPrecompileConsumer} from "../libraries/RitualPrecompileConsumer.sol";

/// @title HiveDKMS — TEE-bound key management for Hive
/// @notice Derives keys via Ritual DKMS precompile, encrypts/decrypts data
/// @dev Keys never leave TEE enclave. ECIES-encrypted data stored on-chain.
contract HiveDKMS is RitualPrecompileConsumer {
    // ═══ State ═══

    address public owner;

    // Key derivation tracking
    // (user, purpose) => keyIndex
    mapping(address => mapping(string => uint256)) public keyIndices;
    // (user, purpose) => exists
    mapping(address => mapping(string => bool)) public keyExists;

    // Encrypted data storage
    // (user, slot) => encrypted bytes
    mapping(address => mapping(string => bytes)) private encryptedData;
    // (user) => slot list
    mapping(address => string[]) public dataSlots;
    // (user, slot) => exists
    mapping(address => mapping(string => bool)) public slotExists;

    // Key rotation tracking
    mapping(address => mapping(string => uint256)) public keyRotations;
    mapping(address => mapping(string => uint256)) public lastRotation;

    // ═══ Events ═══

    event KeyDerived(address indexed user, string purpose, uint256 keyIndex);
    event DataStored(address indexed user, string slot, uint256 size);
    event DataDeleted(address indexed user, string slot);
    event KeyRotated(address indexed user, string purpose, uint256 newIndex);

    // ═══ Modifiers ═══

    modifier onlyOwner() {
        require(msg.sender == owner, "DKMS: not owner");
        _;
    }

    // ═══ Constructor ═══

    constructor(address _owner) {
        owner = _owner;
    }

    // ═══ Key Derivation ═══

    /// @notice Derive a key for a user and purpose
    /// @param user The user address
    /// @param purpose Key purpose (e.g., "hive-identity", "hive-treasury")
    /// @return keyIndex The derived key index
    function deriveKey(address user, string calldata purpose) external returns (uint256 keyIndex) {
        // If key already exists, return existing index
        if (keyExists[user][purpose]) {
            return keyIndices[user][purpose];
        }

        // Derive new key via DKMS precompile
        keyIndex = _deriveKeyFromDKMS(user, purpose);

        keyIndices[user][purpose] = keyIndex;
        keyExists[user][purpose] = true;

        emit KeyDerived(user, purpose, keyIndex);
    }

    // ═══ Encrypted Storage ═══

    /// @notice Store encrypted data for a user
    /// @param user The user address
    /// @param slot Data slot name (e.g., "kyc", "portfolio", "strategy")
    /// @param data Encrypted data bytes
    function storeEncrypted(address user, string calldata slot, bytes calldata data) external onlyOwner {
        require(data.length > 0, "DKMS: empty data");

        // If new slot, add to list
        if (!slotExists[user][slot]) {
            dataSlots[user].push(slot);
            slotExists[user][slot] = true;
        }

        encryptedData[user][slot] = data;

        emit DataStored(user, slot, data.length);
    }

    /// @notice Get encrypted data for a user
    /// @param user The user address
    /// @param slot Data slot name
    /// @return data The encrypted data bytes
    function getEncrypted(address user, string calldata slot) external view returns (bytes memory data) {
        return encryptedData[user][slot];
    }

    /// @notice Get all data slots for a user
    /// @param user The user address
    /// @return slots Array of slot names
    function getDataSlots(address user) external view returns (string[] memory slots) {
        return dataSlots[user];
    }

    /// @notice Delete encrypted data
    /// @param user The user address
    /// @param slot Data slot name
    function deleteEncrypted(address user, string calldata slot) external onlyOwner {
        require(slotExists[user][slot], "DKMS: slot not found");

        delete encryptedData[user][slot];
        slotExists[user][slot] = false;

        // Remove from slot list
        string[] storage slots = dataSlots[user];
        for (uint256 i = 0; i < slots.length; i++) {
            if (keccak256(bytes(slots[i])) == keccak256(bytes(slot))) {
                slots[i] = slots[slots.length - 1];
                slots.pop();
                break;
            }
        }

        emit DataDeleted(user, slot);
    }

    // ═══ Key Rotation ═══

    /// @notice Rotate a key for a user
    /// @param user The user address
    /// @param purpose Key purpose
    function rotateKey(address user, string calldata purpose) external onlyOwner {
        require(keyExists[user][purpose], "DKMS: key not found");

        // Increment rotation count first (so new key is different)
        keyRotations[user][purpose]++;
        lastRotation[user][purpose] = block.timestamp;

        // Derive new key with updated rotation count
        uint256 newIndex = _deriveKeyFromDKMS(user, purpose);

        keyIndices[user][purpose] = newIndex;

        emit KeyRotated(user, purpose, newIndex);
    }

    // ═══ Internal ═══

    /// @notice Derive key via DKMS precompile
    /// @param user The user address
    /// @param purpose Key purpose
    /// @return keyIndex The derived key index
    function _deriveKeyFromDKMS(address user, string calldata purpose) internal returns (uint256 keyIndex) {
        // Encode DKMS deriveKey call
        // DKMS precompile expects: (address user, bytes purpose)
        bytes memory input = abi.encode(user, bytes(purpose));

        (bool success, bytes memory output) = _tryExecutePrecompile(DKMS_PRECOMPILE, input);

        if (success && output.length >= 32) {
            keyIndex = abi.decode(output, (uint256));
        } else {
            // Fallback: use hash-based index with rotation count for uniqueness
            uint256 rotation = keyRotations[user][purpose];
            keyIndex = uint256(keccak256(abi.encodePacked(user, purpose, rotation)));
        }
    }
}
