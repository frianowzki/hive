// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {RitualPrecompileConsumer} from "../libraries/RitualPrecompileConsumer.sol";
import {HivePoints} from "../points/HivePoints.sol";

/// @title MarketMaker — Hive Auto-LP Engine
/// @notice Provides automatic liquidity for tokens launched on Hive

contract HiveMarketMaker is RitualPrecompileConsumer {
    // ═══ State ═══

    address public admin;
    HivePoints public points;

    struct Pool {
        address token;
        uint256 tokenReserve;
        uint256 ethReserve;
        uint256 totalLpTokens;
        uint256 spreadBps;
        uint256 feeBps;
        uint256 totalVolume;
        bool active;
    }

    struct LPPosition {
        uint256 lpTokens;
        uint256 tokenAmount;
        uint256 ethAmount;
        uint256 entryBlock;
        uint256 lastReward;
    }

    mapping(address => Pool) public pools;
    mapping(address => mapping(address => LPPosition)) public lpPositions; // token => user => position
    address[] public poolList;

    uint256 public constant MIN_SPREAD_BPS = 10;   // 0.1%
    uint256 public constant MAX_SPREAD_BPS = 500;   // 5%
    uint256 public constant DEFAULT_FEE_BPS = 30;   // 0.3%

    // ═══ Events ═══

    event PoolCreated(address indexed token, uint256 spreadBps, uint256 feeBps);
    event LiquidityAdded(address indexed token, address indexed user, uint256 tokenAmount, uint256 ethAmount, uint256 lpTokens);
    event LiquidityRemoved(address indexed token, address indexed user, uint256 tokenAmount, uint256 ethAmount);
    event Swapped(address indexed token, address indexed user, bool isBuy, uint256 amountIn, uint256 amountOut, uint256 fee);
    event SpreadUpdated(address indexed token, uint256 newSpreadBps);

    // ═══ Modifiers ═══

    modifier onlyAdmin() {
        require(msg.sender == admin, "MarketMaker: not admin");
        _;
    }

    modifier poolExists(address token) {
        require(pools[token].active, "MarketMaker: pool not found");
        _;
    }

    // ═══ Constructor ═══

    constructor(address _points) {
        admin = msg.sender;
        points = HivePoints(_points);
    }

    // ═══ Pool Creation ═══

    /// @notice Create a new liquidity pool
    function createPool(
        address token,
        uint256 spreadBps,
        uint256 feeBps
    ) external onlyAdmin {
        require(spreadBps >= MIN_SPREAD_BPS && spreadBps <= MAX_SPREAD_BPS, "MarketMaker: invalid spread");
        require(feeBps > 0 && feeBps <= 100, "MarketMaker: invalid fee");

        pools[token] = Pool({
            token: token,
            tokenReserve: 0,
            ethReserve: 0,
            totalLpTokens: 0,
            spreadBps: spreadBps,
            feeBps: feeBps,
            totalVolume: 0,
            active: true
        });

        poolList.push(token);
        emit PoolCreated(token, spreadBps, feeBps);
    }

    // ═══ Liquidity ═══

    /// @notice Add liquidity to a pool
    function addLiquidity(address token) external payable poolExists(token) {
        Pool storage pool = pools[token];

        // First LP: set initial price
        if (pool.totalLpTokens == 0) {
            require(msg.value > 0, "MarketMaker: need ETH");
            // Token amount must be transferred before calling
            // For simplicity, we track by ETH value
            uint256 lpTokens = msg.value; // 1:1 for first LP
            pool.ethReserve += msg.value;
            pool.totalLpTokens += lpTokens;

            lpPositions[token][msg.sender] = LPPosition({
                lpTokens: lpTokens,
                tokenAmount: 0,
                ethAmount: msg.value,
                entryBlock: block.number,
                lastReward: block.timestamp
            });

            // Award LP points
            points.awardLP(msg.sender, msg.value, 0);

            emit LiquidityAdded(token, msg.sender, 0, msg.value, lpTokens);
        } else {
            // Subsequent LP: proportional
            uint256 ethShare = msg.value;
            uint256 tokenShare = (ethShare * pool.tokenReserve) / pool.ethReserve;
            uint256 lpTokens = (ethShare * pool.totalLpTokens) / pool.ethReserve;

            pool.ethReserve += ethShare;
            pool.tokenReserve += tokenShare;
            pool.totalLpTokens += lpTokens;

            LPPosition storage pos = lpPositions[token][msg.sender];
            pos.lpTokens += lpTokens;
            pos.ethAmount += ethShare;
            pos.tokenAmount += tokenShare;

            // Award LP points
            points.awardLP(msg.sender, ethShare, 0);

            emit LiquidityAdded(token, msg.sender, tokenShare, ethShare, lpTokens);
        }
    }

    /// @notice Remove liquidity
    function removeLiquidity(address token, uint256 lpTokens) external poolExists(token) {
        LPPosition storage pos = lpPositions[token][msg.sender];
        require(pos.lpTokens >= lpTokens, "MarketMaker: insufficient LP");

        Pool storage pool = pools[token];

        uint256 ethReturn = (lpTokens * pool.ethReserve) / pool.totalLpTokens;
        uint256 tokenReturn = (lpTokens * pool.tokenReserve) / pool.totalLpTokens;

        pos.lpTokens -= lpTokens;
        pos.ethAmount -= ethReturn;
        pos.tokenAmount -= tokenReturn;
        pool.ethReserve -= ethReturn;
        pool.tokenReserve -= tokenReturn;
        pool.totalLpTokens -= lpTokens;

        // Calculate LP duration for points
        uint256 duration = block.timestamp - pos.entryBlock;
        points.awardLP(msg.sender, ethReturn, duration);

        // Transfer ETH back
        (bool success, ) = msg.sender.call{value: ethReturn}("");
        require(success, "MarketMaker: transfer failed");

        emit LiquidityRemoved(token, msg.sender, tokenReturn, ethReturn);
    }

    // ═══ Swaps ═══

    /// @notice Swap ETH for tokens (buy)
    function buy(address token) external payable poolExists(token) {
        Pool storage pool = pools[token];
        require(pool.ethReserve > 0 && pool.tokenReserve > 0, "MarketMaker: no liquidity");

        uint256 fee = (msg.value * pool.feeBps) / 10_000;
        uint256 amountIn = msg.value - fee;

        // Constant product: x * y = k
        uint256 amountOut = (pool.tokenReserve * amountIn) /
                           (pool.ethReserve + amountIn);

        pool.ethReserve += amountIn;
        pool.tokenReserve -= amountOut;
        pool.totalVolume += msg.value;
        // fee tracked via events

        // Award points for trading
        points.awardBuy(msg.sender, msg.value);

        emit Swapped(token, msg.sender, true, msg.value, amountOut, fee);
    }

    /// @notice Swap tokens for ETH (sell)
    function sell(address token, uint256 tokenAmount) external poolExists(token) {
        Pool storage pool = pools[token];
        require(pool.ethReserve > 0 && pool.tokenReserve > 0, "MarketMaker: no liquidity");

        uint256 fee = (tokenAmount * pool.feeBps) / 10_000;
        uint256 amountIn = tokenAmount - fee;

        uint256 amountOut = (pool.ethReserve * amountIn) /
                           (pool.tokenReserve + amountIn);

        pool.tokenReserve += amountIn;
        pool.ethReserve -= amountOut;
        pool.totalVolume += amountOut;
        // fee tracked via events

        // Transfer ETH
        (bool success, ) = msg.sender.call{value: amountOut}("");
        require(success, "MarketMaker: transfer failed");

        emit Swapped(token, msg.sender, false, tokenAmount, amountOut, fee);
    }

    // ═══ Spread Management ═══

    /// @notice Update spread using LLM
    function updateSpreadAI(address token) external poolExists(token) {
        Pool storage pool = pools[token];

        string memory prompt = string(abi.encodePacked(
            "You are a market maker. Token pool stats: ",
            "Volume: ", _uint2str(pool.totalVolume), " wei. ",
            "Spread: ", _uint2str(pool.spreadBps), " bps. ",
            "Fee: ", _uint2str(pool.feeBps), " bps. ", 
            "Reserves: ", _uint2str(pool.tokenReserve), " tokens, ",
            _uint2str(pool.ethReserve), " ETH. ",
            "Current spread: ", _uint2str(pool.spreadBps), " bps. ",
            "What spread should I set? Reply with just a number in bps (10-500)."
        ));

        bytes memory llmInput = _encodeLlmCall(prompt);
        (bool success, bytes memory output) = LLM_PRECOMPILE.staticcall(llmInput);

        if (success && output.length > 0) {
            string memory response = abi.decode(output, (string));
            uint256 newSpread = _parseUint(response);
            if (newSpread >= MIN_SPREAD_BPS && newSpread <= MAX_SPREAD_BPS) {
                pool.spreadBps = newSpread;
                emit SpreadUpdated(token, newSpread);
            }
        }
    }

    /// @notice Manually update spread
    function setSpread(address token, uint256 spreadBps) external onlyAdmin poolExists(token) {
        require(spreadBps >= MIN_SPREAD_BPS && spreadBps <= MAX_SPREAD_BPS, "MarketMaker: invalid spread");
        pools[token].spreadBps = spreadBps;
        emit SpreadUpdated(token, spreadBps);
    }

    // ═══ Internal ═══

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

    function _parseUint(string memory s) internal pure returns (uint256) {
        bytes memory b = bytes(s);
        uint256 result = 0;
        for (uint256 i = 0; i < b.length; i++) {
            if (b[i] >= '0' && b[i] <= '9') {
                result = result * 10 + (uint8(b[i]) - 48);
            }
        }
        return result;
    }

    // ═══ View ═══

    function poolCount() external view returns (uint256) {
        return poolList.length;
    }

    function getPrice(address token) external view returns (uint256) {
        Pool storage pool = pools[token];
        if (pool.tokenReserve == 0) return 0;
        return (pool.ethReserve * 1e18) / pool.tokenReserve;
    }

    function getAmountOut(address token, uint256 amountIn, bool isBuy)
        external view returns (uint256 amountOut, uint256 fee)
    {
        Pool storage pool = pools[token];
        fee = (amountIn * pool.feeBps) / 10_000;
        uint256 netIn = amountIn - fee;

        if (isBuy) {
            amountOut = (pool.tokenReserve * netIn) / (pool.ethReserve + netIn);
        } else {
            amountOut = (pool.ethReserve * netIn) / (pool.tokenReserve + netIn);
        }
    }

    receive() external payable {}
}
