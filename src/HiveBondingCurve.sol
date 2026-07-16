// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IERC20Bonding {
    function balanceOf(address) external view returns (uint256);
    function transfer(address to, uint256 amount) external returns (bool);
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
    function approve(address spender, uint256 amount) external returns (bool);
}

/// @title HiveBondingCurveV4 - Secure linear bonding curve with DEX graduation
/// @notice Virtual liquidity pool with reentrancy protection and slippage guards
/// @dev When threshold reached, auto-deploys liquidity to DEX and locks LP
contract HiveBondingCurve {
    // --- Constants ---
    uint256 public constant PRECISION = 1e18;
    uint256 public constant PLATFORM_FEE_BPS = 200; // 2%
    uint256 public constant TREASURY_FEE_BPS = 500; // 5%
    uint256 public constant TOTAL_FEE_BPS = 700;    // 7%
    uint256 public constant MAX_SUPPLY = 1_000_000_000 * 1e18; // 1B tokens
    uint256 public constant GRADUATION_THRESHOLD = 0.1 * 1e18; // 0.1 RITUAL
    address public constant LP_LOCK_ADDRESS = 0x000000000000000000000000000000000000dEaD;
    uint256 public constant RESERVE_FOR_LP = 800_000_000 * 1e18; // 80% of supply for LP

    // --- State ---
    address public token;
    address public factory;
    address public platformTreasury;
    address public agentTreasury;
    address public dexRouter;

    uint256 public virtualRitualReserve;
    uint256 public virtualTokenReserve;
    uint256 public realRitualSold;
    uint256 public realTokensSold;

    uint256 public initialVirtualRitual;
    uint256 public initialVirtualToken;

    bool public migrationReady;
    bool public isGraduated;
    address public graduationPool;

    // Reentrancy guard
    uint256 private _locked = 1;

    // --- Events ---
    event TokensPurchased(
        address indexed buyer,
        uint256 ritualIn,
        uint256 tokensOut,
        uint256 fee,
        uint256 price,
        uint256 newVirtualRitualReserve,
        uint256 newVirtualTokenReserve
    );
    event TokensSold(
        address indexed seller,
        uint256 tokensIn,
        uint256 ritualOut,
        uint256 fee,
        uint256 price,
        uint256 newVirtualRitualReserve,
        uint256 newVirtualTokenReserve
    );
    event MigrationTriggered(uint256 totalRitual, uint256 totalTokens);
    event TreasuryFunded(address indexed treasury, uint256 amount);
    event TokenGraduated(
        address indexed tokenAddress,
        address poolAddress,
        uint256 ritualAmount,
        uint256 tokenAmount
    );
    event CurveInitialized(uint256 virtualRitual, uint256 virtualToken);

    // --- Errors ---
    error InsufficientRitual();
    error InsufficientTokens();
    error SlippageExceeded(uint256 expected, uint256 actual);
    error MigrationAlreadyDone();
    error NotReadyForMigration();
    error TransferFailed();
    error GraduationFailed();
    error NotOwner();
    error ReentrancyGuard();

    // --- Modifiers ---
    modifier nonReentrant() {
        if (_locked != 1) revert ReentrancyGuard();
        _locked = 2;
        _;
        _locked = 1;
    }

    modifier onlyFactory() {
        require(msg.sender == factory, "not factory");
        _;
    }

    constructor(
        address token_,
        address factory_,
        address platformTreasury_,
        address agentTreasury_,
        address dexRouter_,
        uint256 virtualRitual_,
        uint256 virtualToken_
    ) {
        token = token_;
        factory = factory_;
        platformTreasury = platformTreasury_;
        agentTreasury = agentTreasury_;
        dexRouter = dexRouter_;
        initialVirtualRitual = virtualRitual_;
        initialVirtualToken = virtualToken_;
        virtualRitualReserve = virtualRitual_;
        virtualTokenReserve = virtualToken_;

        emit CurveInitialized(virtualRitual_, virtualToken_);
    }

    // --- Bonding Curve Math ---

    function getCurrentPrice() public view returns (uint256) {
        if (virtualTokenReserve == 0) return 0;
        return (virtualRitualReserve * PRECISION) / virtualTokenReserve;
    }

    function calculateBuy(uint256 ritualIn) public view returns (uint256 tokensOut, uint256 fee) {
        if (ritualIn == 0) return (0, 0);

        fee = (ritualIn * TOTAL_FEE_BPS) / 10_000;
        uint256 ritualAfterFee = ritualIn - fee;

        tokensOut = (ritualAfterFee * virtualTokenReserve) / (virtualRitualReserve + ritualAfterFee);

        if (tokensOut > virtualTokenReserve) {
            tokensOut = virtualTokenReserve;
        }
    }

    function calculateSell(uint256 tokensIn) public view returns (uint256 ritualOut, uint256 fee) {
        if (tokensIn == 0) return (0, 0);

        ritualOut = (tokensIn * virtualRitualReserve) / (virtualTokenReserve + tokensIn);
        fee = (ritualOut * TOTAL_FEE_BPS) / 10_000;
        ritualOut = ritualOut - fee;
    }

    // --- Buy/Sell ---

    /// @notice Buy tokens with RITUAL, with slippage protection
    /// @param ritualIn Amount of RITUAL (wei) to spend
    /// @param minTokensOut Minimum tokens to receive (slippage protection)
    function buy(uint256 ritualIn, uint256 minTokensOut) external payable nonReentrant returns (uint256 tokensOut) {
        if (migrationReady) revert MigrationAlreadyDone();
        if (msg.value < ritualIn) revert InsufficientRitual();

        uint256 fee;
        (tokensOut, fee) = calculateBuy(ritualIn);
        if (tokensOut == 0) revert InsufficientRitual();

        // Slippage protection
        if (tokensOut < minTokensOut) {
            revert SlippageExceeded(minTokensOut, tokensOut);
        }

        // Update reserves
        virtualRitualReserve += (ritualIn - fee);
        virtualTokenReserve -= tokensOut;
        realRitualSold += (ritualIn - fee);
        realTokensSold += tokensOut;

        // FIX: Transfer tokens from THIS contract (curve holds all tokens) to buyer
        (bool sent,) = token.call(
            abi.encodeWithSignature("transfer(address,uint256)", msg.sender, tokensOut)
        );
        if (!sent) revert TransferFailed();

        // Split fees
        uint256 platformFee = (fee * PLATFORM_FEE_BPS) / TOTAL_FEE_BPS;
        uint256 treasuryFee = fee - platformFee;

        if (platformFee > 0) {
            (bool sent1,) = platformTreasury.call{value: platformFee}("");
            if (!sent1) revert TransferFailed();
        }
        if (treasuryFee > 0) {
            (bool sent2,) = agentTreasury.call{value: treasuryFee}("");
            if (!sent2) revert TransferFailed();
            emit TreasuryFunded(agentTreasury, treasuryFee);
        }

        emit TokensPurchased(
            msg.sender,
            ritualIn,
            tokensOut,
            fee,
            getCurrentPrice(),
            virtualRitualReserve,
            virtualTokenReserve
        );

        // Check for graduation
        if (realRitualSold >= GRADUATION_THRESHOLD && !isGraduated) {
            _graduateToken();
        }
    }

    /// @notice Sell tokens for RITUAL, with slippage protection
    /// @param tokensIn Amount of tokens to sell
    /// @param minRitualOut Minimum RITUAL to receive (slippage protection)
    function sell(uint256 tokensIn, uint256 minRitualOut) external nonReentrant returns (uint256 ritualOut) {
        if (migrationReady) revert MigrationAlreadyDone();
        if (isGraduated) revert MigrationAlreadyDone();

        uint256 fee;
        (ritualOut, fee) = calculateSell(tokensIn);
        if (ritualOut == 0) revert InsufficientTokens();

        // Slippage protection
        if (ritualOut < minRitualOut) {
            revert SlippageExceeded(minRitualOut, ritualOut);
        }

        // Update reserves
        virtualTokenReserve += tokensIn;
        virtualRitualReserve -= (ritualOut + fee);
        realRitualSold -= ritualOut;

        // Transfer tokens from seller to this contract
        (bool sent,) = token.call(
            abi.encodeWithSignature("transferFrom(address,address,uint256)", msg.sender, address(this), tokensIn)
        );
        if (!sent) revert TransferFailed();

        // Split fees
        uint256 platformFee = (fee * PLATFORM_FEE_BPS) / TOTAL_FEE_BPS;
        uint256 treasuryFee = fee - platformFee;

        if (platformFee > 0) {
            (bool sent1,) = platformTreasury.call{value: platformFee}("");
            if (!sent1) revert TransferFailed();
        }
        if (treasuryFee > 0) {
            (bool sent2,) = agentTreasury.call{value: treasuryFee}("");
            if (!sent2) revert TransferFailed();
            emit TreasuryFunded(agentTreasury, treasuryFee);
        }

        // Send RITUAL to seller
        (bool sent3,) = msg.sender.call{value: ritualOut}("");
        if (!sent3) revert TransferFailed();

        emit TokensSold(
            msg.sender,
            tokensIn,
            ritualOut,
            fee,
            getCurrentPrice(),
            virtualRitualReserve,
            virtualTokenReserve
        );
    }

    // --- Graduation ---

    function isReadyForGraduation() public view returns (bool) {
        return realRitualSold >= GRADUATION_THRESHOLD && !isGraduated;
    }

    function getProgress() public view returns (uint256) {
        if (GRADUATION_THRESHOLD == 0) return 0;
        uint256 progress = (realRitualSold * 10_000) / GRADUATION_THRESHOLD;
        if (progress > 10_000) progress = 10_000;
        return progress;
    }

    /// @notice Internal graduation: deploy liquidity to DEX and lock LP
    /// @dev FIX: (1) curve holds tokens directly, (2) approve router for tokens,
    ///      (3) forward {value: ritualAmount} to router for addLiquidityETH
    function _graduateToken() internal {
        isGraduated = true;
        migrationReady = true;

        uint256 ritualAmount = realRitualSold;
        uint256 tokenAmount = RESERVE_FOR_LP;

        // Safety check: curve must hold enough tokens
        uint256 curveBalance = IERC20Bonding(token).balanceOf(address(this));
        if (curveBalance < tokenAmount) {
            // Fallback: use whatever tokens the curve has
            tokenAmount = curveBalance;
        }

        // 1. Approve DEX Router to spend tokens from this contract
        IERC20Bonding(token).approve(dexRouter, tokenAmount);

        // 2. Call addLiquidityETH with {value} — router needs ETH to create pair
        //    Router will: transferFrom(curve → pair, tokens) + pair.call{value}(ETH) + pair.mint(LP)
        (bool r1,) = dexRouter.call{value: ritualAmount}(
            abi.encodeWithSignature(
                "addLiquidityETH(address,uint256,uint256,uint256,address,uint256)",
                token,
                tokenAmount,
                1,           // min tokens (accept any for graduation)
                1,           // min ETH (accept any for graduation)
                LP_LOCK_ADDRESS, // send LP to dead address (locked forever)
                block.timestamp + 600
            )
        );

        if (r1) {
            graduationPool = dexRouter;
            emit TokenGraduated(token, dexRouter, ritualAmount, tokenAmount);
        } else {
            // Fallback: if DEX fails, revert graduation
            isGraduated = false;
            migrationReady = false;
            revert GraduationFailed();
        }
    }

    /// @notice Manual graduation trigger (for testing or if auto-trigger fails)
    function graduateToken() external onlyFactory {
        if (isGraduated) revert MigrationAlreadyDone();
        if (!isReadyForGraduation()) revert NotReadyForMigration();
        _graduateToken();
    }

    // --- Migration (backward compatible) ---

    function triggerMigration() external onlyFactory {
        if (migrationReady) revert MigrationAlreadyDone();
        if (!isReadyForGraduation()) revert NotReadyForMigration();
        _graduateToken();
    }

    receive() external payable {}
}
