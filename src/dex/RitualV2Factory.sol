// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./RitualV2Pair.sol";
/// @title Minimal Uniswap V2-style Factory for Ritual Testnet
contract RitualV2Factory {
    address public feeTo;
    address public router;
    mapping(address => mapping(address => address)) public getPair;
    address[] public allPairs;

    event PairCreated(address indexed token0, address indexed token1, address pair, uint256 pairIndex);

    constructor(address _feeTo) {
        feeTo = _feeTo;
    }

    function setRouter(address _router) external {
        router = _router;
    }

    function allPairsLength() external view returns (uint256) {
        return allPairs.length;
    }

    function createPair(address tokenA, address tokenB) external returns (address pair) {
        require(tokenA != tokenB, "IDENTICAL_ADDRESSES");
        (address token0, address token1) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);
        require(token0 != address(0), "ZERO_ADDRESS");
        require(getPair[token0][token1] == address(0), "PAIR_EXISTS");

        bytes memory bytecode = type(RitualV2Pair).creationCode;
        bytes32 salt = keccak256(abi.encodePacked(token0, token1));
        assembly {
            pair := create2(0, add(bytecode, 0x20), mload(bytecode), salt)
        }
        require(pair != address(0), "CREATE2_FAILED");

        // Pass router to pair so it can authorize Router calls
        RitualV2Pair(pair).initialize(token0, token1, router);
        getPair[token0][token1] = pair;
        getPair[token1][token0] = pair; // populate mapping in reverse
        allPairs.push(pair);

        emit PairCreated(token0, token1, pair, allPairs.length);
    }

    function setFeeTo(address _feeTo) external {
        feeTo = _feeTo;
    }
}
