// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "../libraries/RitualPrecompileConsumer.sol";

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
