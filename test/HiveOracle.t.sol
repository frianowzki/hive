// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/oracle/HiveOracle.sol";

contract HiveOracleTest is Test {
    HiveOracle public oracle;

    address public owner = address(this);
    address public tokenETH = address(0xA);
    address public tokenBTC = address(0xB);

    function setUp() public {
        oracle = new HiveOracle();
    }

    // ═══ Price Feed Tests ═══

    function testUpdatePrice() public {
        oracle.updatePrice(tokenETH, 1500e8, "manual");
        HiveOracle.PriceData memory data = oracle.getPriceData(tokenETH);
        assertEq(data.price, 1500e8);
        assertEq(data.source, "manual");
        assertTrue(data.valid);
    }

    function testGetPrice() public {
        oracle.updatePrice(tokenETH, 1500e8, "manual");
        uint256 price = oracle.getPrice(tokenETH);
        assertEq(price, 1500e8);
    }

    function testAddToken() public {
        oracle.addToken(tokenETH, "ETH", "ethereum", 18);
        (string memory coingeckoId, string memory symbol, , , ) = oracle.tokenConfigs(tokenETH);
        assertEq(symbol, "ETH");
        assertEq(coingeckoId, "ethereum");
    }

    function testTrackedTokens() public {
        oracle.addToken(tokenETH, "ETH", "ethereum", 18);
        oracle.addToken(tokenBTC, "BTC", "bitcoin", 8);

        address[] memory tokens = oracle.getTrackedTokens();
        assertEq(tokens.length, 2);
        assertEq(tokens[0], tokenETH);
        assertEq(tokens[1], tokenBTC);
    }

    function testBestPrice() public {
        oracle.updatePrice(tokenETH, 1500e8, "manual");
        (uint256 price, string memory source) = oracle.getBestPrice(tokenETH);
        assertEq(price, 1500e8);
        assertEq(source, "manual");
    }

    function testOnlyOwner() public {
        vm.prank(address(0xBAD));
        vm.expectRevert("Oracle: not authorized");
        oracle.updatePrice(tokenETH, 1500e8, "manual");
    }
}
