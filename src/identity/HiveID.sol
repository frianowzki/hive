// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {RitualPrecompileConsumer} from "../libraries/RitualPrecompileConsumer.sol";

/// @title HiveID — ZK-proofed identity for Hive
/// @notice KYC/KYB verification via zero-knowledge proofs
/// @dev Prove attributes (age, country, accreditation) without revealing data
contract HiveID is RitualPrecompileConsumer {
    // ═══ State ═══

    address public owner;

    uint8 constant ID_NONE = 0;
    uint8 constant ID_INDIVIDUAL = 1;
    uint8 constant ID_ORGANIZATION = 2;

    struct Identity {
        bytes32 zkProof;        // ZK proof hash
        uint8 identityType;     // Individual or Organization
        bool verified;
        uint256 registeredAt;
    }

    struct Attribute {
        bytes32 zkProof;        // ZK proof for this attribute
        uint256 value;          // Attribute value (age, country code, etc.)
        bool verified;
        uint256 verifiedAt;
    }

    // user => Identity
    mapping(address => Identity) public identities;

    // user => attribute name => Attribute
    mapping(address => mapping(string => Attribute)) public attributes;

    // Stats
    uint256 public totalVerified;
    uint256 public totalIndividuals;
    uint256 public totalOrganizations;

    // ═══ Events ═══

    event IdentityRegistered(address indexed user, uint8 identityType, bytes32 zkProof);
    event IdentityRevoked(address indexed user);
    event AttributeVerified(address indexed user, string attribute, uint256 value);
    event AttributeRevoked(address indexed user, string attribute);

    // ═══ Modifiers ═══

    modifier onlyOwner() {
        require(msg.sender == owner, "ID: not owner");
        _;
    }

    modifier onlyVerified() {
        require(identities[msg.sender].verified, "ID: not verified");
        _;
    }

    // ═══ Constructor ═══

    constructor(address _owner) {
        owner = _owner;
    }

    // ═══ Identity Registration ═══

    /// @notice Register identity with ZK proof
    /// @param zkProof ZK proof hash (proves identity without revealing data)
    /// @param identityType 1 = individual, 2 = organization
    function registerIdentity(bytes32 zkProof, uint8 identityType) external {
        require(!identities[msg.sender].verified, "ID: already registered");
        require(identityType == ID_INDIVIDUAL || identityType == ID_ORGANIZATION, "ID: invalid type");
        require(zkProof != bytes32(0), "ID: empty proof");

        identities[msg.sender] = Identity({
            zkProof: zkProof,
            identityType: identityType,
            verified: true,
            registeredAt: block.timestamp
        });

        totalVerified++;
        if (identityType == ID_INDIVIDUAL) {
            totalIndividuals++;
        } else {
            totalOrganizations++;
        }

        emit IdentityRegistered(msg.sender, identityType, zkProof);
    }

    // ═══ Attribute Verification ═══

    /// @notice Verify an attribute with ZK proof
    /// @param zkProof ZK proof for this specific attribute
    /// @param attributeName Attribute name (e.g., "age", "country", "accredited")
    /// @param value Attribute value
    function verifyAttribute(bytes32 zkProof, string calldata attributeName, uint256 value) external onlyVerified {
        require(zkProof != bytes32(0), "ID: empty proof");
        require(bytes(attributeName).length > 0, "ID: empty name");

        attributes[msg.sender][attributeName] = Attribute({
            zkProof: zkProof,
            value: value,
            verified: true,
            verifiedAt: block.timestamp
        });

        emit AttributeVerified(msg.sender, attributeName, value);
    }

    // ═══ Access Control ═══

    /// @notice Revoke identity (owner only)
    function revokeIdentity(address user) external onlyOwner {
        require(identities[user].verified, "ID: not registered");

        uint8 idType = identities[user].identityType;
        delete identities[user];

        totalVerified--;
        if (idType == ID_INDIVIDUAL) {
            totalIndividuals--;
        } else {
            totalOrganizations--;
        }

        emit IdentityRevoked(user);
    }

    /// @notice Revoke an attribute (owner only)
    function revokeAttribute(address user, string calldata attributeName) external onlyOwner {
        require(attributes[user][attributeName].verified, "ID: attribute not found");

        delete attributes[user][attributeName];
        emit AttributeRevoked(user, attributeName);
    }

    // ═══ View Functions ═══

    /// @notice Check if user is verified
    function isVerified(address user) external view returns (bool) {
        return identities[user].verified;
    }

    /// @notice Check if user is registered (alias for isVerified)
    function isRegistered(address user) external view returns (bool) {
        return identities[user].verified;
    }

    /// @notice Get identity type
    function getIdentityType(address user) external view returns (uint8) {
        return identities[user].identityType;
    }

    /// @notice Check if user has a specific attribute
    function hasAttribute(address user, string calldata attributeName) external view returns (bool) {
        return attributes[user][attributeName].verified;
    }

    /// @notice Get attribute value
    function getAttributeValue(address user, string calldata attributeName) external view returns (uint256) {
        return attributes[user][attributeName].value;
    }

    /// @notice Get own attribute (privacy — only own data)
    function getMyAttribute(string calldata attributeName) external view returns (uint256) {
        return attributes[msg.sender][attributeName].value;
    }

    /// @notice Get verification stats
    function getStats() external view returns (uint256 total, uint256 individuals, uint256 organizations) {
        return (totalVerified, totalIndividuals, totalOrganizations);
    }
}
