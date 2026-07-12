// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @title HiveTokenMeta - Store agent metadata on-chain
/// @notice Public, immutable metadata for every launched token
contract HiveTokenMeta {
    address public owner;

    struct TokenMeta {
        string json;          // full metadata JSON
        address creator;      // who set it
        uint256 updatedAt;    // last update block
    }

    mapping(address => TokenMeta) public metadata;
    mapping(address => bool) public hasMetadata;

    event MetadataSet(address indexed token, address indexed creator, uint256 updatedAt);

    constructor() {
        owner = msg.sender;
    }

    /// @notice Store metadata JSON for a token
    /// @param token Token contract address
    /// @param json Metadata JSON string (name, symbol, lore, supply, socials, logo, banner)
    function setMetadata(address token, string calldata json) external {
        require(bytes(json).length > 0, "empty json");
        require(token != address(0), "invalid token");

        // Only creator or existing creator can update
        if (hasMetadata[token]) {
            require(
                metadata[token].creator == msg.sender || msg.sender == owner,
                "not creator"
            );
        }

        metadata[token] = TokenMeta({
            json: json,
            creator: msg.sender,
            updatedAt: block.number
        });

        hasMetadata[token] = true;
        emit MetadataSet(token, msg.sender, block.number);
    }

    /// @notice Get metadata JSON for a token
    function getMetadata(address token) external view returns (
        string memory json,
        address creator,
        uint256 updatedAt
    ) {
        require(hasMetadata[token], "no metadata");
        TokenMeta storage m = metadata[token];
        return (m.json, m.creator, m.updatedAt);
    }

    /// @notice Check if token has metadata
    function exists(address token) external view returns (bool) {
        return hasMetadata[token];
    }

    receive() external payable {}
}
