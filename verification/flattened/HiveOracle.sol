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

// src/oracle/HiveOracle.sol

/// @title HiveOracle — Price feed via Ritual HTTP precompile
/// @notice Fetches real-time token prices from external APIs
/// @dev Uses Ritual HTTP precompile (0x0801) for off-chain data

contract HiveOracle is RitualPrecompileConsumer {
    // ═══ Types ═══

    struct PriceData {
        uint256 price;          // Price in USD (8 decimals)
        uint256 timestamp;      // When fetched
        uint256 confidence;     // Confidence score (0-100)
        string source;          // Data source (e.g., "coingecko")
        bool valid;
    }

    struct TokenConfig {
        string coingeckoId;     // e.g., "ethereum"
        string symbol;          // e.g., "ETH"
        uint8 decimals;         // Token decimals
        bool active;
    }

    // ═══ State ═══

    // token address => PriceData
    mapping(address => PriceData) public prices;
    // token address => config
    mapping(address => TokenConfig) public tokenConfigs;
    // token address list
    address[] public trackedTokens;

    // Staleness threshold
    uint256 public constant MAX_PRICE_AGE = 1 hours;
    uint256 public constant PRICE_DECIMALS = 8; // 8 decimal places for USD

    address public owner;
    bool public paused;

    // Request tracking
    uint256 public requestId;
    mapping(uint256 => address) public pendingRequests; // requestId => token

    // ═══ Events ═══

    event PriceUpdated(address indexed token, uint256 price, uint256 timestamp, string source);
    event TokenAdded(address indexed token, string symbol, string coingeckoId);
    event TokenRemoved(address indexed token);
    event PriceFetchRequest(uint256 indexed reqId, address indexed token);

    // ═══ Errors ═══

    error OraclePaused();
    error PriceStale();
    error TokenNotTracked();
    error FetchFailed();

    // ═══ Modifiers ═══

    modifier whenNotPaused() {
        if (paused) revert OraclePaused();
        _;
    }

    // ═══ Constructor ═══

    constructor() {
        owner = msg.sender;
    }

    // ═══ Token Management ═══

    /// @notice Add a token to track
    function addToken(
        address token,
        string calldata symbol,
        string calldata coingeckoId,
        uint8 decimals
    ) external {
        require(msg.sender == owner, "Oracle: not owner");

        tokenConfigs[token] = TokenConfig({
            coingeckoId: coingeckoId,
            symbol: symbol,
            decimals: decimals,
            active: true
        });

        trackedTokens.push(token);
        emit TokenAdded(token, symbol, coingeckoId);
    }

    /// @notice Remove a token from tracking
    function removeToken(address token) external {
        require(msg.sender == owner, "Oracle: not owner");
        tokenConfigs[token].active = false;
        emit TokenRemoved(token);
    }

    // ═══ Price Fetching ═══

    /// @notice Fetch price for a single token via Ritual HTTP precompile
    function fetchPrice(address token) external whenNotPaused returns (uint256 reqId) {
        TokenConfig storage config = tokenConfigs[token];
        if (!config.active) revert TokenNotTracked();

        reqId = requestId++;
        pendingRequests[reqId] = token;

        // Build CoinGecko API URL
        string memory url = string(
            abi.encodePacked(
                "https://api.coingecko.com/api/v3/simple/price?ids=",
                config.coingeckoId,
                "&vs_currencies=usd&precision=8"
            )
        );

        // Call Ritual HTTP precompile
        bytes memory input = _encodeHttpGet(url);
        bytes memory output = _executePrecompile(HTTP_PRECOMPILE, input);

        // Parse response (simplified — production would parse JSON)
        // For now, store a placeholder and rely on manual updates
        // The actual parsing would happen off-chain

        emit PriceFetchRequest(reqId, token);
        return reqId;
    }

    /// @notice Update price (called by authorized updater or after HTTP response)
    function updatePrice(
        address token,
        uint256 price,
        string calldata source
    ) external {
        require(msg.sender == owner || msg.sender == address(this), "Oracle: not authorized");

        prices[token] = PriceData({
            price: price,
            timestamp: block.timestamp,
            confidence: 90,
            source: source,
            valid: true
        });

        emit PriceUpdated(token, price, block.timestamp, source);
    }

    /// @notice Batch update prices
    function updatePrices(
        address[] calldata tokens,
        uint256[] calldata prices_,
        string calldata source
    ) external {
        require(msg.sender == owner, "Oracle: not authorized");
        require(tokens.length == prices_.length, "Oracle: length mismatch");

        for (uint256 i = 0; i < tokens.length; i++) {
            prices[tokens[i]] = PriceData({
                price: prices_[i],
                timestamp: block.timestamp,
                confidence: 90,
                source: source,
                valid: true
            });

            emit PriceUpdated(tokens[i], prices_[i], block.timestamp, source);
        }
    }

    // ═══ View ═══

    /// @notice Get price for a token (reverts if stale)
    function getPrice(address token) external view returns (uint256) {
        PriceData storage p = prices[token];
        if (!p.valid) revert TokenNotTracked();
        if (block.timestamp - p.timestamp > MAX_PRICE_AGE) revert PriceStale();
        return p.price;
    }

    /// @notice Get price with staleness check
    function getPriceSafe(address token) external view returns (uint256 price, bool stale) {
        PriceData storage p = prices[token];
        if (!p.valid) return (0, true);
        stale = block.timestamp - p.timestamp > MAX_PRICE_AGE;
        return (p.price, stale);
    }

    /// @notice Get full price data
    function getPriceData(address token) external view returns (PriceData memory) {
        return prices[token];
    }

    /// @notice Get all tracked tokens
    function getTrackedTokens() external view returns (address[] memory) {
        return trackedTokens;
    }

    /// @notice Convert token amount to USD
    function tokenToUSD(address token, uint256 amount) external view returns (uint256) {
        PriceData storage p = prices[token];
        if (!p.valid || block.timestamp - p.timestamp > MAX_PRICE_AGE) revert PriceStale();

        TokenConfig storage config = tokenConfigs[token];
        // amount * price / 10^decimals / 10^0 (price already in 8 decimals)
        return (amount * p.price) / (10 ** config.decimals);
    }

    /// @notice Convert USD to token amount
    function usdToToken(address token, uint256 usdAmount) external view returns (uint256) {
        PriceData storage p = prices[token];
        if (!p.valid || block.timestamp - p.timestamp > MAX_PRICE_AGE) revert PriceStale();

        TokenConfig storage config = tokenConfigs[token];
        return (usdAmount * (10 ** config.decimals)) / p.price;
    }

    // ═══ Admin ═══

    function setPaused(bool _paused) external {
        require(msg.sender == owner, "Oracle: not owner");
        paused = _paused;
    }

    receive() external payable {}
}
