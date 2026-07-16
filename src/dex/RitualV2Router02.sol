// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./RitualV2Factory.sol";
import "./RitualV2Pair.sol";

/// @title Minimal Uniswap V2-style Router for Ritual Testnet
/// @notice Supports addLiquidityETH, swapExactETHForTokens, swapExactTokensForETH
contract RitualV2Router02 {
    address public immutable factory;

    // WETH-like address — we use address(0) to represent native RITUAL
    address public constant WETH = address(0);

    constructor(address _factory) {
        factory = _factory;
    }

    receive() external payable {}

    // --- Liquidity ---

    function addLiquidityETH(
        address token,
        uint256 amountTokenDesired,
        uint256 amountTokenMin,
        uint256 amountETHMin,
        address to,
        uint256 deadline
    ) external payable returns (uint256 amountToken, uint256 amountETH, uint256 liquidity) {
        require(deadline >= block.timestamp, "EXPIRED");

        // Get or create pair
        address pair = RitualV2Factory(factory).getPair(token, address(0));
        if (pair == address(0)) {
            pair = RitualV2Factory(factory).createPair(token, address(0));
        }

        // Transfer tokens from msg.sender to pair
        IERC20(token).transferFrom(msg.sender, pair, amountTokenDesired);

        // Send ETH to pair
        (bool success,) = pair.call{value: msg.value}("");
        require(success, "ETH_TRANSFER_FAILED");

        // Mint LP tokens
        liquidity = RitualV2Pair(pair).mint(to);

        // Refund dust
        uint256 balanceToken = IERC20(token).balanceOf(pair);
        uint256 balanceETH = address(pair).balance;
        amountToken = balanceToken;
        amountETH = balanceETH;

        require(amountToken >= amountTokenMin, "INSUFFICIENT_TOKEN_AMOUNT");
        require(amountETH >= amountETHMin, "INSUFFICIENT_ETH_AMOUNT");
    }

    function addLiquidity(
        address tokenA,
        address tokenB,
        uint256 amountADesired,
        uint256 amountBDesired,
        uint256 amountAMin,
        uint256 amountBMin,
        address to,
        uint256 deadline
    ) external returns (uint256 amountA, uint256 amountB, uint256 liquidity) {
        require(deadline >= block.timestamp, "EXPIRED");

        address pair = RitualV2Factory(factory).getPair(tokenA, tokenB);
        if (pair == address(0)) {
            pair = RitualV2Factory(factory).createPair(tokenA, tokenB);
        }

        IERC20(tokenA).transferFrom(msg.sender, pair, amountADesired);
        IERC20(tokenB).transferFrom(msg.sender, pair, amountBDesired);

        liquidity = RitualV2Pair(pair).mint(to);

        amountA = IERC20(tokenA).balanceOf(pair);
        amountB = IERC20(tokenB).balanceOf(pair);
        require(amountA >= amountAMin, "INSUFFICIENT_AMOUNT_A");
        require(amountB >= amountBMin, "INSUFFICIENT_AMOUNT_B");
    }

    // Remove liquidity
    function removeLiquidity(
        address tokenA,
        address tokenB,
        uint256 liquidity,
        uint256 amountAMin,
        uint256 amountBMin,
        address to,
        uint256 deadline
    ) external returns (uint256 amountA, uint256 amountB) {
        require(deadline >= block.timestamp, "EXPIRED");

        address pair = RitualV2Factory(factory).getPair(tokenA, tokenB);
        require(pair != address(0), "PAIR_NOT_FOUND");

        RitualV2Pair(pair).transferFrom(msg.sender, pair, liquidity);

        (uint256 amount0, uint256 amount1) = RitualV2Pair(pair).burn(to);

        (address token0,) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);
        (amountA, amountB) = tokenA == token0 ? (amount0, amount1) : (amount1, amount0);

        require(amountA >= amountAMin, "INSUFFICIENT_A");
        require(amountB >= amountBMin, "INSUFFICIENT_B");
    }

    // --- Swaps ---

    /// @notice Swap exact ETH for tokens (RITUAL → Token)
    function swapExactETHForTokens(
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external payable returns (uint256[] memory amounts) {
        require(deadline >= block.timestamp, "EXPIRED");
        require(path.length == 2, "INVALID_PATH");
        require(msg.value > 0, "INSUFFICIENT_ETH_AMOUNT");

        address pair = RitualV2Factory(factory).getPair(path[0], path[1]);
        require(pair != address(0), "PAIR_NOT_FOUND");

        // Calculate amounts using getAmountOut
        amounts = new uint256[](2);
        amounts[0] = msg.value;
        amounts[1] = _getAmountOut(msg.value, address(0), path[1], pair);

        require(amounts[1] >= amountOutMin, "INSUFFICIENT_OUTPUT_AMOUNT");

        // Transfer ETH to pair (path[0] is address(0) = native RITUAL)
        (bool success,) = pair.call{value: amounts[0]}("");
        require(success, "ETH_TRANSFER_FAILED");

        // Transfer tokens out of pair
        IERC20(path[1]).transferFrom(pair, to, amounts[1]);
    }

    /// @notice Swap exact tokens for ETH (Token → RITUAL)
    function swapExactTokensForETH(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external returns (uint256[] memory amounts) {
        require(deadline >= block.timestamp, "EXPIRED");
        require(path.length == 2, "INVALID_PATH");
        require(amountIn > 0, "INSUFFICIENT_INPUT_AMOUNT");

        address pair = RitualV2Factory(factory).getPair(path[0], path[1]);
        require(pair != address(0), "PAIR_NOT_FOUND");

        // Transfer tokens from msg.sender to pair
        IERC20(path[0]).transferFrom(msg.sender, pair, amountIn);

        // Calculate output
        amounts = new uint256[](2);
        amounts[0] = amountIn;
        amounts[1] = _getAmountOut(amountIn, path[0], address(0), pair);

        require(amounts[1] >= amountOutMin, "INSUFFICIENT_OUTPUT_AMOUNT");

        // Transfer ETH from pair to recipient
        (bool success,) = to.call{value: amounts[1]}("");
        require(success, "ETH_TRANSFER_FAILED");
    }

    /// @notice Swap exact tokens for tokens
    function swapExactTokensForTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external returns (uint256[] memory amounts) {
        require(deadline >= block.timestamp, "EXPIRED");
        require(path.length >= 2, "INVALID_PATH");

        amounts = new uint256[](path.length);
        amounts[0] = amountIn;

        for (uint256 i = 0; i < path.length - 1; i++) {
            address pair = RitualV2Factory(factory).getPair(path[i], path[i + 1]);
            require(pair != address(0), "PAIR_NOT_FOUND");

            IERC20(path[i]).transferFrom(msg.sender, pair, amounts[i]);
            amounts[i + 1] = _getAmountOut(amounts[i], path[i], path[i + 1], pair);
            IERC20(path[i + 1]).transferFrom(pair, i + 1 == path.length - 1 ? to : pair, amounts[i + 1]);
        }

        require(amounts[amounts.length - 1] >= amountOutMin, "INSUFFICIENT_OUTPUT_AMOUNT");
    }

    // --- View Helpers ---

    function getAmountOut(uint256 amountIn, uint256 reserveIn, uint256 reserveOut) public pure returns (uint256) {
        require(amountIn > 0, "INSUFFICIENT_INPUT");
        require(reserveIn > 0 && reserveOut > 0, "INSUFFICIENT_LIQUIDITY");
        uint256 amountInWithFee = amountIn * 997;
        uint256 numerator = amountInWithFee * reserveOut;
        uint256 denominator = (reserveIn * 1000) + amountInWithFee;
        return numerator / denominator;
    }

    function getAmountsOut(uint256 amountIn, address[] memory path) public view returns (uint256[] memory amounts) {
        require(path.length >= 2, "INVALID_PATH");
        amounts = new uint256[](path.length);
        amounts[0] = amountIn;

        for (uint256 i = 0; i < path.length - 1; i++) {
            address pair = RitualV2Factory(factory).getPair(path[i], path[i + 1]);
            require(pair != address(0), "PAIR_NOT_FOUND");

            (uint112 reserve0, uint112 reserve1,) = RitualV2Pair(pair).getReserves();
            (address token0,) = path[i] < path[i + 1] ? (path[i], path[i + 1]) : (path[i + 1], path[i]);
            uint256 reserveIn = path[i] == token0 ? reserve0 : reserve1;
            uint256 reserveOut = path[i] == token0 ? reserve1 : reserve0;
            amounts[i + 1] = getAmountOut(amounts[i], reserveIn, reserveOut);
        }
    }

    // --- Internal ---

    function _getAmountOut(uint256 amountIn, address tokenIn, address tokenOut, address pair) internal view returns (uint256) {
        (uint112 reserve0, uint112 reserve1,) = RitualV2Pair(pair).getReserves();
        (address token0,) = tokenIn < tokenOut ? (tokenIn, tokenOut) : (tokenOut, tokenIn);
        uint256 reserveIn = tokenIn == token0 ? reserve0 : reserve1;
        uint256 reserveOut = tokenIn == token0 ? reserve1 : reserve0;
        return getAmountOut(amountIn, reserveIn, reserveOut);
    }
}
