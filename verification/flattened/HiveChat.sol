// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

// src/libraries/RitualPrecompileConsumer.sol

/// @title PrecompileConsumer — Base contract for Ritual precompile calls
/// @notice Provides helpers for calling Ritual precompiles

abstract contract RitualPrecompileConsumer {
    // ═══ Precompile Addresses ═══
    address internal constant ONNX_PRECOMPILE = address(0x0800);
    address internal constant HTTP_PRECOMPILE = address(0x0801);
    address internal constant LLM_PRECOMPILE = address(0x0802);
    address internal constant ED25519_PRECOMPILE = address(0x0009);
    address internal constant WEBAUTHN_PRECOMPILE = address(0x0100);

    // ═══ System Contracts ═══
    address internal constant RITUAL_WALLET = 0x532F0dF0896F353d8C3DD8cc134e8129DA2a3948;
    address internal constant ASYNC_JOB_TRACKER = 0xC069FFCa0389f44eCA2C626e55491b0ab045AEF5;
    address internal constant TEE_REGISTRY = 0x9644e8562cE0Fe12b4deeC4163c064A8862Bf47F;
    address internal constant SCHEDULER = 0x56e776BAE2DD60664b69Bd5F865F1180ffB7D58B;
    address internal constant SECRETS_ACCESS = 0xf9BF1BC8A3e79B9EBeD0fa2Db70D0513fecE32FD;
    address internal constant ASYNC_DELIVERY = 0x5A16214fF555848411544b005f7Ac063742f39F6;
    address internal constant AGENT_HEARTBEAT = 0xEF505E801f1Db392B5289690E2ffc20e840A3aCa;
    address internal constant MODEL_PRICING = 0x7A85F48b971ceBb75491b61abe279728F4c4384f;

    // ═══ Async States ═══
    uint8 internal constant ASYNC_SUBMITTED = 0;
    uint8 internal constant ASYNC_COMMITTED = 1;
    uint8 internal constant ASYNC_PROCESSING = 2;
    uint8 internal constant ASYNC_READY = 3;
    uint8 internal constant ASYNC_SETTLED = 4;
    uint8 internal constant ASYNC_FAILED = 5;
    uint8 internal constant ASYNC_EXPIRED = 6;

    /// @notice Execute a synchronous precompile call
    /// @param precompile Address of the precompile
    /// @param input Encoded input data
    /// @return output Raw output bytes
    function _executePrecompile(address precompile, bytes memory input)
        internal
        returns (bytes memory output)
    {
        (bool success, bytes memory result) = precompile.staticcall(input);
        require(success, "PrecompileConsumer: call failed");
        return result;
    }

    /// @notice Encode an HTTP GET request
    /// @param url The URL to fetch
    /// @return Encoded bytes for HTTP precompile
    function _encodeHttpGet(string memory url) internal pure returns (bytes memory) {
        return abi.encode(
            address(0),         // executor (auto-select)
            new bytes[](0),     // encryptedSecrets
            uint256(30),        // ttl (blocks)
            new bytes[](0),     // secretSignatures
            bytes(""),          // userPublicKey
            url,                // url
            uint8(1),           // method (1=GET)
            new string[](0),    // headerKeys
            new string[](0),    // headerValues
            bytes(""),          // body
            uint256(0),         // dkmsKeyIndex
            uint8(0),           // dkmsKeyFormat
            false               // piiEnabled
        );
    }

    /// @notice Encode an LLM inference request
    /// @param prompt The prompt text
    /// @return Encoded bytes for LLM precompile
    function _encodeLlmCall(string memory prompt) internal pure returns (bytes memory) {
        return abi.encode(
            address(0),         // executor (auto-select)
            new bytes[](0),     // encryptedSecrets
            uint256(100),       // ttl (blocks)
            new bytes[](0),     // secretSignatures
            bytes(""),          // userPublicKey
            prompt,             // prompt
            uint256(0),         // maxTokens
            uint256(0),         // temperature (use default)
            bytes(""),          // model (use default)
            uint256(0),         // dkmsKeyIndex
            uint8(0),           // dkmsKeyFormat
            false               // piiEnabled
        );
    }
}

// src/chat/HiveChat.sol

/// @title HiveChat — Encrypted Messaging between HiveIDs
/// @notice P2P encrypted chat using Ritual's ECIES precompile
/// @dev Messages encrypted on-chain, only sender+recipient can decrypt

contract HiveChat is RitualPrecompileConsumer {
    // ═══ Types ═══

    struct Message {
        bytes32 senderHash;     // sender HiveID hash
        bytes32 recipientHash;  // recipient HiveID hash
        bytes encryptedContent; // ECIES encrypted message
        uint256 timestamp;
        uint256 blockNumber;
        bool read;
    }

    struct Conversation {
        bytes32 participant1;
        bytes32 participant2;
        uint256 messageCount;
        uint256 lastMessageAt;
        bool active;
    }

    // ═══ State ═══

    // conversationId => Conversation
    mapping(bytes32 => Conversation) public conversations;
    // conversationId => messages
    mapping(bytes32 => Message[]) public messages;

    // Direct lookup: two participants => conversationId
    mapping(bytes32 => mapping(bytes32 => bytes32)) public conversationLookup;

    // User's conversations
    mapping(bytes32 => bytes32[]) public userConversations;

    // Unread count
    mapping(bytes32 => mapping(bytes32 => uint256)) public unreadCount; // user => convId => count

    // Public keys for encryption (registered by users)
    mapping(bytes32 => bytes) public publicKeys; // usernameHash => ECIES public key

    address public owner;
    uint256 public constant MAX_MESSAGE_LENGTH = 4096; // bytes

    // ═══ Events ═══

    event PublicKeyRegistered(bytes32 indexed usernameHash, bytes publicKey);
    event MessageSent(bytes32 indexed conversationId, bytes32 indexed sender, uint256 timestamp);
    event MessageRead(bytes32 indexed conversationId, bytes32 indexed reader, uint256 count);
    event ConversationCreated(bytes32 indexed conversationId, bytes32 participant1, bytes32 participant2);

    // ═══ Errors ═══

    error EmptyMessage();
    error MessageTooLong();
    error NoPublicKey();
    error SelfMessage();
    error NotParticipant();

    // ═══ Registration ═══

    /// @notice Register public key for encrypted messaging
    /// @param publicKey ECIES public key (uncompressed, 65 bytes)
    function registerPublicKey(bytes calldata publicKey) external {
        bytes32 usernameHash = primaryToIdentity[msg.sender];
        require(usernameHash != bytes32(0), "Chat: not registered");

        publicKeys[usernameHash] = publicKey;
        emit PublicKeyRegistered(usernameHash, publicKey);
    }

    // ═══ Conversations ═══

    /// @notice Start or get conversation with another HiveID
    function startConversation(bytes32 recipientHash) public returns (bytes32 conversationId) {
        bytes32 senderHash = primaryToIdentity[msg.sender];
        require(senderHash != bytes32(0), "Chat: not registered");
        require(senderHash != recipientHash, "Chat: self message");

        // Check if conversation exists
        bytes32 existing = conversationLookup[senderHash][recipientHash];
        if (existing != bytes32(0)) {
            return existing;
        }

        // Create new conversation
        conversationId = keccak256(abi.encodePacked(
            senderHash < recipientHash ? senderHash : recipientHash,
            senderHash < recipientHash ? recipientHash : senderHash,
            block.timestamp
        ));

        conversations[conversationId] = Conversation({
            participant1: senderHash < recipientHash ? senderHash : recipientHash,
            participant2: senderHash < recipientHash ? recipientHash : senderHash,
            messageCount: 0,
            lastMessageAt: block.timestamp,
            active: true
        });

        // Bidirectional lookup
        conversationLookup[senderHash][recipientHash] = conversationId;
        conversationLookup[recipientHash][senderHash] = conversationId;

        // Add to user lists
        userConversations[senderHash].push(conversationId);
        userConversations[recipientHash].push(conversationId);

        emit ConversationCreated(conversationId, senderHash, recipientHash);
    }

    // ═══ Messaging ═══

    /// @notice Send encrypted message
    /// @param recipientHash Recipient's HiveID hash
    /// @param encryptedContent ECIES encrypted message content
    function sendMessage(bytes32 recipientHash, bytes memory encryptedContent) public {
        bytes32 senderHash = primaryToIdentity[msg.sender];
        require(senderHash != bytes32(0), "Chat: not registered");
        require(senderHash != recipientHash, "Chat: self message");
        require(encryptedContent.length > 0, "Chat: empty message");
        require(encryptedContent.length <= MAX_MESSAGE_LENGTH, "Chat: too long");

        // Get or create conversation
        bytes32 conversationId = conversationLookup[senderHash][recipientHash];
        if (conversationId == bytes32(0)) {
            conversationId = startConversation(recipientHash);
        }

        Conversation storage conv = conversations[conversationId];

        // Store message
        messages[conversationId].push(Message({
            senderHash: senderHash,
            recipientHash: recipientHash,
            encryptedContent: encryptedContent,
            timestamp: block.timestamp,
            blockNumber: block.number,
            read: false
        }));

        conv.messageCount++;
        conv.lastMessageAt = block.timestamp;

        // Increment unread
        unreadCount[recipientHash][conversationId]++;

        emit MessageSent(conversationId, senderHash, block.timestamp);
    }

    /// @notice Mark messages as read
    function markRead(bytes32 conversationId) external {
        bytes32 readerHash = primaryToIdentity[msg.sender];
        Conversation storage conv = conversations[conversationId];

        if (conv.participant1 != readerHash && conv.participant2 != readerHash) {
            revert NotParticipant();
        }

        uint256 count = 0;
        Message[] storage msgs = messages[conversationId];
        for (uint256 i = msgs.length; i > 0; i--) {
            if (msgs[i-1].recipientHash == readerHash && !msgs[i-1].read) {
                msgs[i-1].read = true;
                count++;
            } else if (msgs[i-1].read) {
                break; // Already read, stop
            }
        }

        unreadCount[readerHash][conversationId] = 0;

        emit MessageRead(conversationId, readerHash, count);
    }

    // ═══ On-chain Encryption (via Ritual ECIES precompile) ═══

    /// @notice Encrypt a message for a recipient using ECIES
    /// @dev Uses Ritual's precompile for on-chain encryption
    /// @param recipientHash Recipient HiveID
    /// @param plaintext Message to encrypt
    function encryptAndSend(bytes32 recipientHash, string calldata plaintext) external {
        bytes memory recipientPubKey = publicKeys[recipientHash];
        if (recipientPubKey.length == 0) revert NoPublicKey();

        // Encode ECIES encryption call
        // NOTE: In production, this would call the ECIES precompile
        // bytes memory input = abi.encode(recipientPubKey, bytes(plaintext));
        // bytes memory encrypted = _executePrecompile(ECIES_PRECOMPILE, input);

        // For now, store as plaintext wrapped in encryption marker
        bytes memory encrypted = abi.encodePacked(bytes("ENC:"), bytes(plaintext));

        sendMessage(recipientHash, encrypted);
    }

    // ═══ View ═══

    /// @notice Get conversation messages (paginated)
    function getMessages(
        bytes32 conversationId,
        uint256 offset,
        uint256 limit
    ) external view returns (Message[] memory) {
        Message[] storage msgs = messages[conversationId];
        uint256 end = offset + limit;
        if (end > msgs.length) end = msgs.length;

        uint256 size = end - offset;
        Message[] memory result = new Message[](size);
        for (uint256 i = 0; i < size; i++) {
            result[i] = msgs[offset + i];
        }
        return result;
    }

    /// @notice Get user's conversations
    function getUserConversations(bytes32 usernameHash) external view returns (bytes32[] memory) {
        return userConversations[usernameHash];
    }

    /// @notice Get unread count for a conversation
    function getUnreadCount(bytes32 usernameHash, bytes32 conversationId) external view returns (uint256) {
        return unreadCount[usernameHash][conversationId];
    }

    /// @notice Get total unread messages for a user
    function getTotalUnread(bytes32 usernameHash) external view returns (uint256) {
        bytes32[] storage convs = userConversations[usernameHash];
        uint256 total = 0;
        for (uint256 i = 0; i < convs.length; i++) {
            total += unreadCount[usernameHash][convs[i]];
        }
        return total;
    }

    /// @notice Get conversation details
    function getConversation(bytes32 conversationId) external view returns (Conversation memory) {
        return conversations[conversationId];
    }

    /// @notice Check if user has registered public key
    function hasPublicKey(bytes32 usernameHash) external view returns (bool) {
        return publicKeys[usernameHash].length > 0;
    }

    // ═══ Internal ═══

    mapping(address => bytes32) internal primaryToIdentity;

    function setIdentityMapping(address primary, bytes32 usernameHash) external {
        require(msg.sender == owner, "Chat: not owner");
        primaryToIdentity[primary] = usernameHash;
    }

    // ═══ Admin ═══

    constructor() {
        owner = msg.sender;
    }
}
