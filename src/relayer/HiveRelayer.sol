// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

/**
 * @title HiveRelayer
 * @notice Meta-transaction relayer for Hive
 * @dev Primary wallet signs, relayer executes from hive wallet
 * @author Hive Team
 */

contract HiveRelayer {
    // ═══════════════════════════════════════════════════════════════
    //                           STATE
    // ═══════════════════════════════════════════════════════════════

    address public owner;
    bool public paused;

    /// @notice Nonce per primary wallet (replay protection)
    mapping(address => uint256) public nonces;

    /// @notice Executed request hashes
    mapping(bytes32 => bool) public executed;

    /// @notice Relay fee (in wei)
    uint256 public relayFee = 0.001 ether;

    /// @notice Total relays executed
    uint256 public totalRelays;

    // ═══════════════════════════════════════════════════════════════
    //                          EVENTS
    // ═══════════════════════════════════════════════════════════════

    event RelayExecuted(bytes32 indexed requestHash, address indexed primaryWallet, address indexed hiveWallet, address to, uint256 value);
    event RelayFailed(bytes32 indexed requestHash, string reason);
    event FeeUpdated(uint256 oldFee, uint256 newFee);
    event Paused(address indexed by);
    event Unpaused(address indexed by);

    // ═══════════════════════════════════════════════════════════════
    //                          ERRORS
    // ═══════════════════════════════════════════════════════════════

    error Expired();
    error NonceMismatch();
    error AlreadyExecuted();
    error InvalidSignature();
    error InsufficientFee();

    // ═══════════════════════════════════════════════════════════════
    //                         MODIFIERS
    // ═══════════════════════════════════════════════════════════════

    modifier onlyOwner() {
        require(msg.sender == owner, "HiveRelayer: not owner");
        _;
    }

    modifier whenNotPaused() {
        require(!paused, "HiveRelayer: paused");
        _;
    }

    // ═══════════════════════════════════════════════════════════════
    //                       CONSTRUCTOR
    // ═══════════════════════════════════════════════════════════════

    constructor() {
        owner = msg.sender;
    }

    // ═══════════════════════════════════════════════════════════════
    //                       RELAY FUNCTIONS
    // ═══════════════════════════════════════════════════════════════

    /// @notice Execute a relay request
    /// @param primaryWallet The wallet that signed the request
    /// @param hiveWallet The hive wallet to execute from
    /// @param to Destination address
    /// @param value ETH value to send
    /// @param data Calldata
    /// @param nonce Request nonce
    /// @param deadline Request deadline
    /// @param signature ECDSA signature from primaryWallet
    function relay(
        address primaryWallet,
        address hiveWallet,
        address to,
        uint256 value,
        bytes calldata data,
        uint256 nonce,
        uint256 deadline,
        bytes calldata signature
    ) external payable whenNotPaused returns (bool) {
        // Check deadline
        if (block.timestamp > deadline) revert Expired();

        // Check nonce
        if (nonce != nonces[primaryWallet]) revert NonceMismatch();

        // Check fee
        if (msg.value < relayFee) revert InsufficientFee();

        // Compute request hash
        bytes32 requestHash = keccak256(abi.encode(
            primaryWallet,
            hiveWallet,
            to,
            value,
            data,
            nonce,
            deadline
        ));

        // Check not already executed
        if (executed[requestHash]) revert AlreadyExecuted();

        // Verify signature from primary wallet
        bytes32 messageHash = keccak256(abi.encodePacked(
            "\x19Ethereum Signed Message:\n32",
            requestHash
        ));

        address signer = _recoverSigner(messageHash, signature);
        if (signer != primaryWallet) revert InvalidSignature();

        // Mark as executed
        executed[requestHash] = true;
        nonces[primaryWallet]++;
        totalRelays++;

        // Execute the transfer
        bool success = _executeTransfer(to, value, data);
        if (!success) {
            emit RelayFailed(requestHash, "execution failed");
            return false;
        }

        emit RelayExecuted(requestHash, primaryWallet, hiveWallet, to, value);
        return true;
    }

    /// @notice Internal transfer execution
    function _executeTransfer(address to, uint256 value, bytes calldata data) internal returns (bool) {
        if (data.length > 0) {
            (bool success, ) = to.call{value: value}(data);
            return success;
        } else {
            (bool success, ) = to.call{value: value}("");
            return success;
        }
    }

    // ═══════════════════════════════════════════════════════════════
    //                    SIGNATURE RECOVERY
    // ═══════════════════════════════════════════════════════════════

    /// @notice Recover signer from signature
    function _recoverSigner(bytes32 messageHash, bytes calldata signature)
        internal
        pure
        returns (address)
    {
        require(signature.length == 65, "Relayer: invalid sig length");

        bytes32 r;
        bytes32 s;
        uint8 v;

        assembly {
            r := calldataload(signature.offset)
            s := calldataload(add(signature.offset, 32))
            v := byte(0, calldataload(add(signature.offset, 64)))
        }

        if (v < 27) v += 27;
        require(v == 27 || v == 28, "Relayer: invalid v");

        return ecrecover(messageHash, v, r, s);
    }

    // ═══════════════════════════════════════════════════════════════
    //                      ENCODE HELPERS
    // ═══════════════════════════════════════════════════════════════

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

    /// @notice Encode a contract call for relay
    function encodeCall(address target, bytes calldata data)
        external
        pure
        returns (bytes memory)
    {
        return abi.encodeWithSelector(bytes4(data[:4]), data[4:]);
    }

    // ═══════════════════════════════════════════════════════════════
    //                      VIEW FUNCTIONS
    // ═══════════════════════════════════════════════════════════════

    /// @notice Get nonce for primary wallet
    function getNonce(address primaryWallet) external view returns (uint256) {
        return nonces[primaryWallet];
    }

    /// @notice Check if request was executed
    function isExecuted(bytes32 requestHash) external view returns (bool) {
        return executed[requestHash];
    }

    // ═══════════════════════════════════════════════════════════════
    //                      ADMIN FUNCTIONS
    // ═══════════════════════════════════════════════════════════════

    /// @notice Update relay fee
    function setRelayFee(uint256 _fee) external onlyOwner {
        uint256 old = relayFee;
        relayFee = _fee;
        emit FeeUpdated(old, _fee);
    }

    /// @notice Pause relayer
    function pause() external onlyOwner {
        paused = true;
        emit Paused(msg.sender);
    }

    /// @notice Unpause relayer
    function unpause() external onlyOwner {
        paused = false;
        emit Unpaused(msg.sender);
    }

    /// @notice Transfer ownership
    function transferOwnership(address newOwner) external onlyOwner {
        require(newOwner != address(0), "HiveRelayer: zero address");
        owner = newOwner;
    }

    /// @notice Withdraw collected fees
    function withdrawFees(address to) external onlyOwner {
        require(to != address(0), "HiveRelayer: zero address");
        uint256 balance = address(this).balance;
        require(balance > 0, "HiveRelayer: no fees");
        (bool success, ) = to.call{value: balance}("");
        require(success, "HiveRelayer: transfer failed");
    }

    /// @notice Fallback to receive ETH
    receive() external payable {}
}
