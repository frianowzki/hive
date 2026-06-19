// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @title HiveRelayer — Meta-transaction relayer for Hive wallets
/// @notice Primary wallet signs, relayer submits from hive wallet
/// @dev Enables gasless transfers for users within Hive ecosystem

contract HiveRelayer {
    // ═══ Types ═══

    struct RelayRequest {
        address primaryWallet;      // Who initiated (signer)
        address hiveWallet;         // Hive wallet (actual sender)
        address to;                 // Recipient
        uint256 value;              // ETH amount
        bytes data;                 // Calldata (for ERC20 etc.)
        uint256 nonce;              // Replay protection
        uint256 deadline;           // Expiration
        bytes signature;            // Primary wallet signature
    }

    // ═══ State ═══

    mapping(address => uint256) public nonces; // primaryWallet => nonce
    mapping(bytes32 => bool) public executed;  // requestHash => executed

    address public owner;
    bool public paused;

    // Fee
    uint256 public relayFeeBps = 10; // 0.1% fee

    // ═══ Events ═══

    event RelayExecuted(
        bytes32 indexed requestHash,
        address indexed primaryWallet,
        address indexed hiveWallet,
        address to,
        uint256 value
    );
    event RelayFailed(bytes32 indexed requestHash, string reason);

    // ═══ Errors ═══

    error RelayPaused();
    error InvalidSignature();
    error Expired();
    error AlreadyExecuted();
    error NonceMismatch();
    error RelayExecutionFailed();

    // ═══ Modifiers ═══

    modifier whenNotPaused() {
        if (paused) revert RelayPaused();
        _;
    }

    // ═══ Constructor ═══

    constructor() {
        owner = msg.sender;
    }

    // ═══ Relay ═══

    /// @notice Execute a relay request
    /// @param req The relay request with signature
    function relay(RelayRequest calldata req) external whenNotPaused returns (bool) {
        // Check deadline
        if (block.timestamp > req.deadline) revert Expired();

        // Check nonce
        if (req.nonce != nonces[req.primaryWallet]) revert NonceMismatch();

        // Compute request hash
        bytes32 requestHash = keccak256(abi.encode(
            req.primaryWallet,
            req.hiveWallet,
            req.to,
            req.value,
            req.data,
            req.nonce,
            req.deadline
        ));

        // Check not already executed
        if (executed[requestHash]) revert AlreadyExecuted();

        // Verify signature from primary wallet
        bytes32 messageHash = keccak256(abi.encodePacked(
            "\x19Ethereum Signed Message:\n32",
            requestHash
        ));

        (address signer, ) = _recoverSigner(messageHash, req.signature);
        if (signer != req.primaryWallet) revert InvalidSignature();

        // Mark as executed
        executed[requestHash] = true;
        nonces[req.primaryWallet]++;

        // Execute the transfer from hive wallet
        // NOTE: In production, the relayer would have permission to execute
        // from the hive wallet. For now, we emit the event for off-chain processing.
        if (req.data.length > 0) {
            (bool success, ) = req.to.call{value: req.value}(req.data);
            if (!success) {
                emit RelayFailed(requestHash, "execution failed");
                return false;
            }
        } else {
            (bool success, ) = req.to.call{value: req.value}("");
            if (!success) {
                emit RelayFailed(requestHash, "transfer failed");
                return false;
            }
        }

        emit RelayExecuted(requestHash, req.primaryWallet, req.hiveWallet, req.to, req.value);
        return true;
    }

    // ═══ Signature Recovery ═══

    function _recoverSigner(bytes32 messageHash, bytes memory signature)
        internal
        pure
        returns (address signer, bool valid)
    {
        require(signature.length == 65, "Relayer: invalid sig length");

        bytes32 r;
        bytes32 s;
        uint8 v;

        assembly {
            r := mload(add(signature, 32))
            s := mload(add(signature, 64))
            v := byte(0, mload(add(signature, 96)))
        }

        if (v < 27) v += 27;
        require(v == 27 || v == 28, "Relayer: invalid v");

        signer = ecrecover(messageHash, v, r, s);
        valid = signer != address(0);
    }

    // ═══ Encode Helpers ═══

    /// @notice Encode an ERC20 transfer for relay
    function encodeERC20Transfer(address token, address to, uint256 amount)
        external
        pure
        returns (bytes memory)
    {
        return abi.encodeWithSignature("transfer(address,uint256)", to, amount);
    }

    /// @notice Encode an ERC20 approve for relay
    function encodeERC20Approve(address token, address spender, uint256 amount)
        external
        pure
        returns (bytes memory)
    {
        return abi.encodeWithSignature("approve(address,uint256)", spender, amount);
    }

    // ═══ View ═══

    function getNonce(address primaryWallet) external view returns (uint256) {
        return nonces[primaryWallet];
    }

    function isExecuted(bytes32 requestHash) external view returns (bool) {
        return executed[requestHash];
    }

    // ═══ Admin ═══

    function setPaused(bool _paused) external {
        require(msg.sender == owner, "Relayer: not owner");
        paused = _paused;
    }

    function setRelayFee(uint256 _bps) external {
        require(msg.sender == owner, "Relayer: not owner");
        relayFeeBps = _bps;
    }

    receive() external payable {}
}
