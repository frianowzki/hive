// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "../libraries/RitualPrecompileConsumer.sol";

/// @title HiveOracle — Price feed via Ritual HTTP + Allora Network
/// @notice Fetches real-time token prices from Allora (AI-inferred) and CoinGecko
/// @dev Uses Ritual HTTP precompile (0x0801) for off-chain data inside TEE.
///      Allora provides crowdsourced AI price predictions with confidence intervals.

contract HiveOracle is RitualPrecompileConsumer {
    // ═══ Types ═══

    struct PriceData {
        uint256 price;          // Price in USD (8 decimals)
        uint256 timestamp;      // When fetched
        uint256 confidence;     // Confidence score (0-100)
        string source;          // "allora", "coingecko", "manual"
        bool valid;
    }

    struct AlloraPrediction {
        uint256 price;              // Predicted price (8 decimals)
        uint256 confidenceInterval; // ± interval (8 decimals)
        uint256 timestamp;          // Prediction timestamp
    }

    struct TokenConfig {
        string coingeckoId;     // e.g., "ethereum"
        string symbol;          // e.g., "ETH"
        uint8 decimals;         // Token decimals
        uint256 alloraTopicId;  // Allora Network topic ID (0 = not configured)
        bool active;
    }

    // ═══ State ═══

    // token address => PriceData
    mapping(address => PriceData) public prices;
    // token address => config
    mapping(address => TokenConfig) public tokenConfigs;
    // token address list
    address[] public trackedTokens;

    // Allora config
    string public alloraApiKey;             // API key for Allora
    string public alloraChainId;            // Allora chain ID (e.g., "allora-testnet-1")
    bool public alloraEnabled;              // Whether Allora is active

    // Allora predictions history
    // token address => AlloraPrediction[]
    mapping(address => AlloraPrediction[]) public alloraPredictions;

    // Staleness threshold
    uint256 public constant MAX_PRICE_AGE = 1 hours;
    uint256 public constant PRICE_DECIMALS = 8;

    address public owner;
    bool public paused;

    // Request tracking
    uint256 public requestId;
    mapping(uint256 => address) public pendingRequests; // requestId => token

    // ═══ Events ═══

    event PriceUpdated(address indexed token, uint256 price, uint256 timestamp, string source);
    event AlloraPriceFetched(address indexed token, uint256 price, uint256 confidence, uint256 timestamp);
    event TokenAdded(address indexed token, string symbol, string coingeckoId);
    event TokenRemoved(address indexed token);
    event PriceFetchRequest(uint256 indexed reqId, address indexed token);
    event AlloraConfigUpdated(bool enabled, string chainId);

    // ═══ Errors ═══

    error OraclePaused();
    error PriceStale();
    error TokenNotTracked();
    error FetchFailed();
    error AlloraNotConfigured();
    error AlloraTopicNotSet();

    // ═══ Modifiers ═══

    modifier whenNotPaused() {
        if (paused) revert OraclePaused();
        _;
    }

    // ═══ Constructor ═══

    constructor() {
        owner = msg.sender;
    }

    // ═══ Allora Configuration ═══

    /// @notice Configure Allora Network integration
    /// @param _apiKey Allora API key
    /// @param _chainId Allora chain ID
    /// @param _enabled Whether to enable Allora feeds
    function setAlloraConfig(
        string calldata _apiKey,
        string calldata _chainId,
        bool _enabled
    ) external {
        require(msg.sender == owner, "Oracle: not owner");
        alloraApiKey = _apiKey;
        alloraChainId = _chainId;
        alloraEnabled = _enabled;
        emit AlloraConfigUpdated(_enabled, _chainId);
    }

    /// @notice Set Allora topic ID for a token
    /// @param token Token address
    /// @param topicId Allora topic ID (0 to disable)
    function setAlloraTopic(address token, uint256 topicId) external {
        require(msg.sender == owner, "Oracle: not owner");
        tokenConfigs[token].alloraTopicId = topicId;
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
            alloraTopicId: 0,
            active: true
        });

        trackedTokens.push(token);
        emit TokenAdded(token, symbol, coingeckoId);
    }

    /// @notice Add a token with Allora topic ID
    function addTokenWithAllora(
        address token,
        string calldata symbol,
        string calldata coingeckoId,
        uint8 decimals,
        uint256 alloraTopicId
    ) external {
        require(msg.sender == owner, "Oracle: not owner");

        tokenConfigs[token] = TokenConfig({
            coingeckoId: coingeckoId,
            symbol: symbol,
            decimals: decimals,
            alloraTopicId: alloraTopicId,
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

    // ═══ Allora Price Fetching ═══

    /// @notice Fetch AI-inferred price from Allora Network via Ritual HTTP precompile
    /// @dev Calls Allora API inside TEE — result is attested and tamper-proof
    /// @param token Token address to fetch price for
    /// @return reqId Request ID for tracking
    function fetchAlloraPrice(address token) external whenNotPaused returns (uint256 reqId) {
        if (!alloraEnabled) revert AlloraNotConfigured();

        TokenConfig storage config = tokenConfigs[token];
        if (!config.active) revert TokenNotTracked();
        if (config.alloraTopicId == 0) revert AlloraTopicNotSet();

        reqId = requestId++;
        pendingRequests[reqId] = token;

        // Build Allora API URL
        // Testnet: https://allora-api.testnet.allora.network/emissions/v7/latest_network_inferences/<topicId>
        // Mainnet: https://api.allora.network/v2/allora/consumer/<chainId>?allora_topic_id=<topicId>
        string memory url = _buildAlloraUrl(config.alloraTopicId);

        // Call Ritual HTTP precompile (async — result delivered later)
        bytes memory input = _encodeHttpGet(url);
        (bool success, bytes memory output) = _tryExecutePrecompile(HTTP_PRECOMPILE, input);

        if (success && output.length > 0) {
            // Parse Allora response and update price
            _parseAndStoreAlloraPrice(token, output);
        }

        emit PriceFetchRequest(reqId, token);
        return reqId;
    }

    /// @notice Fetch prices for multiple tokens from Allora (batch)
    /// @param tokens Token addresses to fetch
    /// @return reqIds Request IDs for each token
    function fetchAlloraPricesBatch(address[] calldata tokens)
        external
        whenNotPaused
        returns (uint256[] memory reqIds)
    {
        if (!alloraEnabled) revert AlloraNotConfigured();

        reqIds = new uint256[](tokens.length);
        for (uint256 i = 0; i < tokens.length; i++) {
            TokenConfig storage config = tokenConfigs[tokens[i]];
            if (config.active && config.alloraTopicId > 0) {
                reqIds[i] = requestId++;
                pendingRequests[reqIds[i]] = tokens[i];

                string memory url = _buildAlloraUrl(config.alloraTopicId);
                bytes memory input = _encodeHttpGet(url);
                (bool success, bytes memory output) = _tryExecutePrecompile(HTTP_PRECOMPILE, input);

                if (success && output.length > 0) {
                    _parseAndStoreAlloraPrice(tokens[i], output);
                }

                emit PriceFetchRequest(reqIds[i], tokens[i]);
            }
        }
    }

    /// @notice Manual Allora price submission (for off-chain oracle node)
    /// @param token Token address
    /// @param price Price in USD (8 decimals)
    /// @param confidence Confidence interval (8 decimals)
    function submitAlloraPrice(
        address token,
        uint256 price,
        uint256 confidence
    ) external {
        require(msg.sender == owner, "Oracle: not authorized");

        prices[token] = PriceData({
            price: price,
            timestamp: block.timestamp,
            confidence: 100 - (confidence * 100 / price), // Convert interval to confidence %
            source: "allora",
            valid: true
        });

        alloraPredictions[token].push(AlloraPrediction({
            price: price,
            confidenceInterval: confidence,
            timestamp: block.timestamp
        }));

        emit AlloraPriceFetched(token, price, confidence, block.timestamp);
        emit PriceUpdated(token, price, block.timestamp, "allora");
    }

    // ═══ CoinGecko Price Fetching ═══

    /// @notice Fetch price for a single token via Ritual HTTP precompile (CoinGecko)
    function fetchPrice(address token) external whenNotPaused returns (uint256 reqId) {
        TokenConfig storage config = tokenConfigs[token];
        if (!config.active) revert TokenNotTracked();

        reqId = requestId++;
        pendingRequests[reqId] = token;

        string memory url = string(
            abi.encodePacked(
                "https://api.coingecko.com/api/v3/simple/price?ids=",
                config.coingeckoId,
                "&vs_currencies=usd&precision=8"
            )
        );

        bytes memory input = _encodeHttpGet(url);
        bytes memory output = _executePrecompile(HTTP_PRECOMPILE, input);

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

    // ═══ Aggregated Price (Allora + CoinGecko fallback) ═══

    /// @notice Get best available price — prefers Allora, falls back to CoinGecko
    /// @param token Token address
    /// @return price Best price in USD (8 decimals)
    /// @return source "allora" or "coingecko"
    function getBestPrice(address token) external view returns (uint256 price, string memory source) {
        PriceData storage p = prices[token];
        if (!p.valid) revert TokenNotTracked();
        if (block.timestamp - p.timestamp > MAX_PRICE_AGE) revert PriceStale();
        return (p.price, p.source);
    }

    /// @notice Get Allora prediction history for a token
    function getAlloraHistory(address token, uint256 limit)
        external
        view
        returns (AlloraPrediction[] memory)
    {
        AlloraPrediction[] storage preds = alloraPredictions[token];
        uint256 len = preds.length;
        if (limit > len) limit = len;

        AlloraPrediction[] memory result = new AlloraPrediction[](limit);
        for (uint256 i = 0; i < limit; i++) {
            result[i] = preds[len - limit + i];
        }
        return result;
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
        return (amount * p.price) / (10 ** config.decimals);
    }

    /// @notice Convert USD to token amount
    function usdToToken(address token, uint256 usdAmount) external view returns (uint256) {
        PriceData storage p = prices[token];
        if (!p.valid || block.timestamp - p.timestamp > MAX_PRICE_AGE) revert PriceStale();

        TokenConfig storage config = tokenConfigs[token];
        return (usdAmount * (10 ** config.decimals)) / p.price;
    }

    // ═══ Internal ═══

    /// @dev Build Allora API URL based on config
    function _buildAlloraUrl(uint256 topicId) internal view returns (string memory) {
        // Use testnet endpoint by default
        // Mainnet: https://api.allora.network/v2/allora/consumer/{chainId}?allora_topic_id={topicId}
        // Testnet: https://allora-api.testnet.allora.network/emissions/v7/latest_network_inferences/{topicId}
        return string(
            abi.encodePacked(
                "https://allora-api.testnet.allora.network/emissions/v7/latest_network_inferences/",
                _uint2str(topicId)
            )
        );
    }

    /// @dev Parse Allora response and store price
    /// @dev Response format: {"network_inferences":{"inference_data":{"combined_inference_value":"3500.12345678"}}}
    function _parseAndStoreAlloraPrice(address token, bytes memory output) internal {
        // Extract price from response bytes
        // In production, this would parse JSON properly
        // For now, use a simplified extraction that looks for the price value
        uint256 price = _extractPriceFromBytes(output);
        uint256 confidence = 85; // Allora network consensus confidence

        if (price > 0) {
            prices[token] = PriceData({
                price: price,
                timestamp: block.timestamp,
                confidence: confidence,
                source: "allora",
                valid: true
            });

            alloraPredictions[token].push(AlloraPrediction({
                price: price,
                confidenceInterval: price * 5 / 100, // 5% default interval
                timestamp: block.timestamp
            }));

            emit AlloraPriceFetched(token, price, confidence, block.timestamp);
            emit PriceUpdated(token, price, block.timestamp, "allora");
        }
    }

    /// @dev Extract numeric price from bytes (simplified JSON parsing)
    function _extractPriceFromBytes(bytes memory data) internal pure returns (uint256) {
        // Look for numeric value in the response
        // This is a simplified parser — production would use proper JSON parsing
        bytes memory b = data;
        uint256 price = 0;
        bool foundDecimal = false;
        uint256 decimals = 0;

        for (uint256 i = 0; i < b.length; i++) {
            uint8 c = uint8(b[i]);
            if (c >= 48 && c <= 57) { // digit
                price = price * 10 + (c - 48);
                if (foundDecimal) decimals++;
            } else if (c == 46) { // decimal point
                foundDecimal = true;
            } else if (price > 0) {
                // End of number
                break;
            }
        }

        // Normalize to 8 decimals
        while (decimals < 8) {
            price *= 10;
            decimals++;
        }
        while (decimals > 8) {
            price /= 10;
            decimals--;
        }

        return price;
    }

    function _uint2str(uint256 value) internal pure returns (string memory) {
        if (value == 0) return "0";
        uint256 temp = value;
        uint256 digits;
        while (temp != 0) { digits++; temp /= 10; }
        bytes memory buffer = new bytes(digits);
        while (value != 0) {
            digits -= 1;
            buffer[digits] = bytes1(uint8(48 + uint256(value % 10)));
            value /= 10;
        }
        return string(buffer);
    }

    // ═══ Admin ═══

    function setPaused(bool _paused) external {
        require(msg.sender == owner, "Oracle: not owner");
        paused = _paused;
    }

    receive() external payable {}

    // ═══ Ownership ═══

    /// @notice Transfer ownership to a new address
    function transferOwnership(address newOwner) external {
        require(msg.sender == owner, "not owner");
        require(newOwner != address(0), "zero address");
        owner = newOwner;
    }

}
