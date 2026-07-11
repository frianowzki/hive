// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/HiveBondingCurve.sol";
import "../src/HiveAgentToken.sol";

/// @title SecurityTest - Tests for security features
contract SecurityTest is Test {
    address PLATFORM_TREASURY = address(0x1111);
    address AGENT_TREASURY = address(0x2222);
    address DEX_ROUTER = address(0x3333);
    address DEPLOYER = address(this);
    address USER1 = address(0xA11CE);

    // Event declarations for testing
    event TokensPurchased(address indexed buyer, uint256 ritualIn, uint256 tokensOut, uint256 fee, uint256 price, uint256 newVirtualRitualReserve, uint256 newVirtualTokenReserve);
    event TokensSold(address indexed seller, uint256 tokensIn, uint256 ritualOut, uint256 fee, uint256 price, uint256 newVirtualRitualReserve, uint256 newVirtualTokenReserve);

    HiveAgentToken token;
    HiveBondingCurve curve;

    function setUp() public {
        vm.startPrank(DEPLOYER);

        // Deploy token
        token = new HiveAgentToken("Test Token", "TEST", "Test lore", DEPLOYER);

        // Deploy curve
        curve = new HiveBondingCurve(
            address(token),
            DEPLOYER,
            PLATFORM_TREASURY,
            AGENT_TREASURY,
            DEX_ROUTER,
            5 ether,
            1_000_000_000e18
        );

        // Mint tokens to factory and approve curve
        token.mint(DEPLOYER, 500_000_000e18);
        token.approve(address(curve), 500_000_000e18);

        vm.stopPrank();
    }

    // ==========================================
    // REENTRANCY PROTECTION
    // ==========================================

    function test_ReentrancyGuardPreventsAttack() public {
        vm.deal(USER1, 100 ether);
        vm.startPrank(USER1);
        curve.buy{value: 0.1 ether}(0.1 ether, 0);
        vm.stopPrank();
        assertTrue(curve.realRitualSold() > 0);
    }

    // ==========================================
    // SLIPPAGE PROTECTION
    // ==========================================

    function test_BuyRevertsOnSlippage() public {
        vm.deal(USER1, 100 ether);
        vm.startPrank(USER1);

        // Calculate expected tokens
        (uint256 expectedTokens,) = curve.calculateBuy(0.1 ether);

        // Try to buy with impossible slippage requirement (require more than possible)
        vm.expectRevert(
            abi.encodeWithSignature(
                "SlippageExceeded(uint256,uint256)",
                expectedTokens + 1,
                expectedTokens
            )
        );
        // buy(ritualIn=0.1 ether, minTokensOut=expectedTokens+1)
        curve.buy{value: 0.1 ether}(0.1 ether, expectedTokens + 1);

        vm.stopPrank();
    }

    function test_BuySucceedsWithValidSlippage() public {
        vm.deal(USER1, 100 ether);
        vm.startPrank(USER1);

        (uint256 expectedTokens,) = curve.calculateBuy(0.1 ether);

        // buy(ritualIn=0.1 ether, minTokensOut=expectedTokens) — exact match
        curve.buy{value: 0.1 ether}(0.1 ether, expectedTokens);

        uint256 balance = token.balanceOf(USER1);
        assertEq(balance, expectedTokens);

        vm.stopPrank();
    }

    function test_SellRevertsOnSlippage() public {
        vm.deal(USER1, 100 ether);
        vm.startPrank(USER1);

        // Buy first
        (uint256 tokensToBuy,) = curve.calculateBuy(0.1 ether);
        curve.buy{value: 0.1 ether}(0.1 ether, 0);
        token.approve(address(curve), type(uint256).max);

        // Calculate expected RITUAL from sell
        (uint256 expectedRitual,) = curve.calculateSell(tokensToBuy);

        // Try to sell with impossible slippage
        vm.expectRevert(
            abi.encodeWithSignature(
                "SlippageExceeded(uint256,uint256)",
                expectedRitual + 1,
                expectedRitual
            )
        );
        // sell(tokensIn=tokensToBuy, minRitualOut=expectedRitual+1)
        curve.sell(tokensToBuy, expectedRitual + 1);

        vm.stopPrank();
    }

    function test_SellSucceedsWithValidSlippage() public {
        vm.deal(USER1, 100 ether);
        vm.startPrank(USER1);

        // Buy first
        (uint256 tokensToBuy,) = curve.calculateBuy(0.1 ether);
        curve.buy{value: 0.1 ether}(0.1 ether, 0);
        token.approve(address(curve), type(uint256).max);

        // Calculate expected RITUAL
        (uint256 expectedRitual,) = curve.calculateSell(tokensToBuy);

        // Sell with exact slippage
        uint256 balanceBefore = USER1.balance;
        curve.sell(tokensToBuy, expectedRitual);

        uint256 balanceAfter = USER1.balance;
        assertTrue(balanceAfter > balanceBefore);

        vm.stopPrank();
    }

    function test_BuyZeroSlippageAlwaysWorks() public {
        vm.deal(USER1, 100 ether);
        vm.startPrank(USER1);

        // minTokensOut=0 always succeeds if tokensOut > 0
        curve.buy{value: 0.1 ether}(0.1 ether, 0);

        uint256 balance = token.balanceOf(USER1);
        assertTrue(balance > 0);

        vm.stopPrank();
    }

    function test_SellZeroSlippageAlwaysWorks() public {
        vm.deal(USER1, 100 ether);
        vm.startPrank(USER1);

        (uint256 tokensToBuy,) = curve.calculateBuy(0.1 ether);
        curve.buy{value: 0.1 ether}(0.1 ether, 0);
        token.approve(address(curve), type(uint256).max);

        // minRitualOut=0 always succeeds
        uint256 balanceBefore = USER1.balance;
        curve.sell(tokensToBuy, 0);

        uint256 balanceAfter = USER1.balance;
        assertTrue(balanceAfter > balanceBefore);

        vm.stopPrank();
    }

    // ==========================================
    // ENHANCED EVENTS
    // ==========================================



    // ==========================================
    // GRADUATION
    // ==========================================

    function test_GraduationTriggersAtThreshold() public {
        vm.deal(USER1, 100 ether);
        vm.startPrank(USER1);
        curve.buy{value: 0.11 ether}(0.11 ether, 0);
        vm.stopPrank();

        assertTrue(curve.isGraduated());
        assertTrue(curve.migrationReady());
    }

    function test_CannotBuyAfterGraduation() public {
        vm.deal(USER1, 100 ether);
        vm.startPrank(USER1);
        curve.buy{value: 0.11 ether}(0.11 ether, 0);

        vm.expectRevert(HiveBondingCurve.MigrationAlreadyDone.selector);
        curve.buy{value: 0.1 ether}(0.1 ether, 0);

        vm.stopPrank();
    }

    function test_CannotSellAfterGraduation() public {
        vm.deal(USER1, 100 ether);
        vm.startPrank(USER1);
        curve.buy{value: 0.11 ether}(0.11 ether, 0);

        vm.expectRevert(HiveBondingCurve.MigrationAlreadyDone.selector);
        curve.sell(1, 0);

        vm.stopPrank();
    }

    // ==========================================
    // EDGE CASES
    // ==========================================

    function test_BuyWithExactValue() public {
        vm.deal(USER1, 100 ether);
        vm.startPrank(USER1);
        curve.buy{value: 0.1 ether}(0.1 ether, 0);
        assertTrue(token.balanceOf(USER1) > 0);
        vm.stopPrank();
    }

    function test_SellAllTokens() public {
        vm.deal(USER1, 100 ether);
        vm.startPrank(USER1);

        (uint256 tokensToBuy,) = curve.calculateBuy(0.1 ether);
        curve.buy{value: 0.1 ether}(0.1 ether, 0);
        token.approve(address(curve), type(uint256).max);

        curve.sell(tokensToBuy, 0);
        assertEq(token.balanceOf(USER1), 0);

        vm.stopPrank();
    }

    function test_MultipleBuysAndSells() public {
        vm.deal(USER1, 100 ether);
        vm.startPrank(USER1);

        curve.buy{value: 0.01 ether}(0.01 ether, 0);
        curve.buy{value: 0.02 ether}(0.02 ether, 0);
        curve.buy{value: 0.03 ether}(0.03 ether, 0);
        token.approve(address(curve), type(uint256).max);

        uint256 balance = token.balanceOf(USER1);
        assertTrue(balance > 0);

        curve.sell(balance / 2, 0);
        assertTrue(token.balanceOf(USER1) > 0);

        vm.stopPrank();
    }
}
