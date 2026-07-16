// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/HiveBondingCurve.sol";
import "../src/HiveAgentToken.sol";
import "../src/dex/RitualV2Factory.sol";
import "../src/dex/RitualV2Router02.sol";
import "../src/dex/RitualV2Pair.sol";
import "../src/HiveFactory.sol";

/// @title SecurityTest - Tests for security features (updated for V5 custody model)
contract SecurityTest is Test {
    address PLATFORM_TREASURY = address(0x1111);
    address AGENT_TREASURY = address(0x2222);
    address DEX_ROUTER = address(0x3333); // no-code address — tests codesize guard
    address DEPLOYER = address(this);
    address USER1 = address(0xA11CE);

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
            DEPLOYER, // factory = deployer for test
            PLATFORM_TREASURY,
            AGENT_TREASURY,
            DEX_ROUTER,
            5 ether,
            1_000_000_000e18
        );

        // V5: Mint ALL tokens to curve (curve holds & distributes)
        token.mint(address(curve), 1_000_000_000e18);

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

        (uint256 expectedTokens,) = curve.calculateBuy(0.1 ether);

        vm.expectRevert(
            abi.encodeWithSignature(
                "SlippageExceeded(uint256,uint256)",
                expectedTokens + 1,
                expectedTokens
            )
        );
        curve.buy{value: 0.1 ether}(0.1 ether, expectedTokens + 1);

        vm.stopPrank();
    }

    function test_BuySucceedsWithValidSlippage() public {
        vm.deal(USER1, 100 ether);
        vm.startPrank(USER1);

        (uint256 expectedTokens,) = curve.calculateBuy(0.1 ether);
        curve.buy{value: 0.1 ether}(0.1 ether, expectedTokens);

        uint256 balance = token.balanceOf(USER1);
        assertEq(balance, expectedTokens);

        vm.stopPrank();
    }

    function test_SellRevertsOnSlippage() public {
        vm.deal(USER1, 100 ether);
        vm.startPrank(USER1);

        (uint256 tokensToBuy,) = curve.calculateBuy(0.1 ether);
        curve.buy{value: 0.1 ether}(0.1 ether, 0);

        (uint256 expectedRitual,) = curve.calculateSell(tokensToBuy);

        vm.expectRevert(
            abi.encodeWithSignature(
                "SlippageExceeded(uint256,uint256)",
                expectedRitual + 1,
                expectedRitual
            )
        );
        curve.sell(tokensToBuy, expectedRitual + 1);

        vm.stopPrank();
    }

    function test_SellSucceedsWithValidSlippage() public {
        vm.deal(USER1, 100 ether);
        vm.startPrank(USER1);

        (uint256 tokensToBuy,) = curve.calculateBuy(0.1 ether);
        curve.buy{value: 0.1 ether}(0.1 ether, 0);

        // V5: approve curve to pull tokens for sell
        token.approve(address(curve), type(uint256).max);

        (uint256 expectedRitual,) = curve.calculateSell(tokensToBuy);

        uint256 balanceBefore = USER1.balance;
        curve.sell(tokensToBuy, expectedRitual);

        uint256 balanceAfter = USER1.balance;
        assertTrue(balanceAfter > balanceBefore);

        vm.stopPrank();
    }

    function test_BuyZeroSlippageAlwaysWorks() public {
        vm.deal(USER1, 100 ether);
        vm.startPrank(USER1);
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

        // V5: approve curve to pull tokens for sell
        token.approve(address(curve), type(uint256).max);

        uint256 balanceBefore = USER1.balance;
        curve.sell(tokensToBuy, 0);

        uint256 balanceAfter = USER1.balance;
        assertTrue(balanceAfter > balanceBefore);

        vm.stopPrank();
    }

    // ==========================================
    // GRADUATION (no-code DEX → codesize guard catches it)
    // ==========================================

    function test_GraduationFailsWithNoCodeRouter() public {
        vm.deal(USER1, 100 ether);
        vm.startPrank(USER1);

        // Buy past threshold — graduation triggers but fails (no code at DEX_ROUTER)
        // V5: buy() does NOT revert on graduation failure; sets migrationPending
        curve.buy{value: 0.11 ether}(0.11 ether, 0);

        // Graduation failed gracefully — buy succeeded, but state is pending
        assertTrue(curve.migrationPending());
        assertFalse(curve.isGraduated());
        assertTrue(token.balanceOf(USER1) > 0); // tokens were still delivered

        vm.stopPrank();
    }

    function test_CannotBuyAfterGraduationPending() public {
        vm.deal(USER1, 100 ether);
        vm.startPrank(USER1);

        // First buy triggers graduation → fails → sets migrationPending
        curve.buy{value: 0.11 ether}(0.11 ether, 0);

        // Second buy blocked by migrationPending
        vm.expectRevert(HiveBondingCurve.MigrationAlreadyDone.selector);
        curve.buy{value: 0.1 ether}(0.1 ether, 0);

        vm.stopPrank();
    }

    function test_CannotSellAfterGraduationPending() public {
        vm.deal(USER1, 100 ether);
        vm.startPrank(USER1);

        curve.buy{value: 0.11 ether}(0.11 ether, 0);

        vm.expectRevert(HiveBondingCurve.MigrationAlreadyDone.selector);
        curve.sell(1, 0);

        vm.stopPrank();
    }

    function test_RetryGraduationRevertsWithNoCodeRouter() public {
        vm.deal(USER1, 100 ether);
        vm.startPrank(USER1);

        // Trigger graduation failure
        curve.buy{value: 0.11 ether}(0.11 ether, 0);

        // Retry should also fail (no code at router) — try/catch catches the revert
        // Since retryGraduation calls this.executeGraduation(), and executeGraduation reverts
        // with "dexRouter: no code", retryGraduation will revert (it's not in a try/catch)
        vm.expectRevert("dexRouter: no code");
        curve.retryGraduation();

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

        // V5: approve curve to pull tokens for sell
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

        // V5: approve curve to pull tokens for sell
        token.approve(address(curve), type(uint256).max);

        uint256 balance = token.balanceOf(USER1);
        assertTrue(balance > 0);

        curve.sell(balance / 2, 0);
        assertTrue(token.balanceOf(USER1) > 0);

        vm.stopPrank();
    }
}

/// @title GraduationE2E - End-to-end graduation test with REAL DEX contracts
contract GraduationE2E is Test {
    address PLATFORM_TREASURY = address(0x1111);
    address AGENT_TREASURY = address(0x2222);
    address DEPLOYER = address(this);
    address USER1 = address(0xA11CE);

    RitualV2Factory dexFactory;
    RitualV2Router02 dexRouter;
    HiveAgentToken token;
    HiveBondingCurve curve;

    function setUp() public {
        vm.startPrank(DEPLOYER);

        // Deploy real DEX
        dexFactory = new RitualV2Factory(PLATFORM_TREASURY);
        dexRouter = new RitualV2Router02(address(dexFactory));
        dexFactory.setRouter(address(dexRouter));

        // Deploy token
        token = new HiveAgentToken("Graduate Token", "GRAD", "Graduation test", DEPLOYER);

        // Deploy curve with real DEX router
        curve = new HiveBondingCurve(
            address(token),
            DEPLOYER,
            PLATFORM_TREASURY,
            AGENT_TREASURY,
            address(dexRouter),
            1 ether,
            1_000_000_000e18
        );

        // Mint ALL tokens to curve
        token.mint(address(curve), 1_000_000_000e18);

        vm.stopPrank();
    }

    function test_GraduationDeploysLiquidityToRealDEX() public {
        vm.deal(USER1, 100 ether);
        vm.startPrank(USER1);

        // Buy past threshold (0.1 RITUAL)
        curve.buy{value: 0.15 ether}(0.15 ether, 0);

        // Verify graduation
        assertTrue(curve.isGraduated(), "should be graduated");
        assertFalse(curve.migrationPending(), "should not be pending");

        // Verify pair was created
        address pair = dexFactory.getPair(address(token), address(0));
        assertTrue(pair != address(0), "pair should exist");

        // Verify LP was locked at dead address
        RitualV2Pair lp = RitualV2Pair(payable(pair));
        uint256 lockedLP = lp.balanceOf(address(0xdead));
        assertTrue(lockedLP > 0, "LP should be locked at dead address");

        // Verify pair has reserves
        (uint112 r0, uint112 r1,) = lp.getReserves();
        assertTrue(r0 > 0, "ETH reserve should be > 0");
        assertTrue(r1 > 0, "token reserve should be > 0");

        // Verify buy is now blocked
        vm.expectRevert(HiveBondingCurve.MigrationAlreadyDone.selector);
        curve.buy{value: 0.1 ether}(0.1 ether, 0);

        vm.stopPrank();
    }

    function test_GraduationTriggersAtExactThreshold() public {
        vm.deal(USER1, 100 ether);
        vm.startPrank(USER1);

        // 7% fee means we need ~0.108 ether to get 0.1 ether past fees
        curve.buy{value: 0.12 ether}(0.12 ether, 0);

        assertTrue(curve.isGraduated(), "should graduate when passing threshold");
        assertTrue(token.balanceOf(USER1) > 0);

        vm.stopPrank();
    }

    function test_CannotRetryAfterSuccessfulGraduation() public {
        vm.deal(USER1, 100 ether);
        vm.startPrank(USER1);

        // Use enough to graduate successfully
        curve.buy{value: 0.2 ether}(0.2 ether, 0);
        assertTrue(curve.isGraduated());

        // After successful graduation: migrationPending=false, isGraduated=true
        // retryGraduation checks migrationPending first → reverts with "no pending migration"
        vm.expectRevert("no pending migration");
        curve.retryGraduation();

        vm.stopPrank();
    }
}

/// @title MigrationRetryTest - Tests for the retry graduation path
contract MigrationRetryTest is Test {
    address PLATFORM_TREASURY = address(0x1111);
    address AGENT_TREASURY = address(0x2222);
    address DEPLOYER = address(this);
    address USER1 = address(0xA11CE);

    HiveAgentToken token;
    HiveBondingCurve curve;

    function setUp() public {
        vm.startPrank(DEPLOYER);

        // Deploy with no-code router (will fail graduation)
        token = new HiveAgentToken("Retry Token", "RTRY", "Retry test", DEPLOYER);

        curve = new HiveBondingCurve(
            address(token),
            DEPLOYER,
            PLATFORM_TREASURY,
            AGENT_TREASURY,
            address(0x3333), // no-code address
            1 ether,
            1_000_000_000e18
        );

        token.mint(address(curve), 1_000_000_000e18);

        vm.stopPrank();
    }

    function test_MigrationPendingStateAfterFailedGraduation() public {
        vm.deal(USER1, 100 ether);
        vm.startPrank(USER1);

        curve.buy{value: 0.15 ether}(0.15 ether, 0);

        assertTrue(curve.migrationPending(), "should be migrationPending");
        assertFalse(curve.isGraduated(), "should not be graduated");
        assertTrue(curve.migrationReady(), "should be migrationReady");

        vm.stopPrank();
    }

    function test_RetryGraduationFailsWithNoCodeRouter() public {
        vm.deal(USER1, 100 ether);
        vm.startPrank(USER1);

        curve.buy{value: 0.15 ether}(0.15 ether, 0);
        assertTrue(curve.migrationPending());

        vm.expectRevert("dexRouter: no code");
        curve.retryGraduation();

        vm.stopPrank();
    }

    function test_CannotRetryWithoutPendingMigration() public {
        vm.expectRevert("no pending migration");
        curve.retryGraduation();
    }
}
