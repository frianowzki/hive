// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./RitualV2Factory.sol";
import "./RitualV2Pair.sol";

/// @title Minimal Uniswap V2-style Router for Ritual Testnet
/// @notice Supports addLiquidityETH for graduation
contract RitualV2Router02 {
    address public immutable factory;

    constructor(address _factory) {
        factory = _factory;
    }

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

        // Transfer tokens to pair
        IERC20(token).transferFrom(msg.sender, pair, amountTokenDesired);

        // Send ETH to pair
        (bool success,) = pair.call{value: msg.value}("");
        require(success, "ETH_TRANSFER_FAILED");

        // Mint LP tokens
        liquidity = RitualV2Pair(pair).mint(to);

        // Refund dust
        uint256 balanceToken = IERC20(token).balanceOf(pair);
        uint256 balanceETH = address(pair).balance;
        amountToken = balanceToken; // simplified — full implementation checks min
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

    function getAmountOut(uint256 amountIn, uint256 reserveIn, uint256 reserveOut) public pure returns (uint256) {
        require(amountIn > 0, "INSUFFICIENT_INPUT");
        require(reserveIn > 0 && reserveOut > 0, "INSUFFICIENT_LIQUIDITY");
        uint256 amountInWithFee = amountIn * 997;
        uint256 numerator = amountInWithFee * reserveOut;
        uint256 denominator = (reserveIn * 1000) + amountInWithFee;
        return numerator / denominator;
    }
}
