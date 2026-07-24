// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./HiveBondingCurve.sol";

/// @title HiveBondingCurveV6 - Enhanced bonding curve with dynamic fees and admin controls
/// @notice Extends V5 with risk-based dynamic fees, pause functionality, and better security
/// @dev ONNX integration ready but not active - can be enabled when ONNX precompile supports custom models
contract HiveBondingCurveV6 is HiveBondingCurve {
    // --- Dynamic Fee State ---
    uint256 public baseFeeBps = 700;  // 7% base fee
    uint256 public maxFeeBps = 1000;  // 10% max fee
    uint256 public minFeeBps = 500;   // 5% min fee
    
    // --- Pause State ---
    bool public tradingPaused;
    address public pauser;
    
    // --- Risk Assessment (simple logic) ---
    uint256 public holderThreshold = 50;      // Min holders for base fee
    uint256 public volumeThreshold = 1 ether; // Min volume for base fee
    uint256 public ageThreshold = 1000;       // Min age in blocks for base fee
    
    // --- Events ---
    event DynamicFeeApplied(uint256 riskScore, uint256 feeBps);
    event TradingPaused(address indexed token, string reason);
    event TradingUnpaused(address indexed token);
    event RiskParamsUpdated(uint256 holderThreshold, uint256 volumeThreshold, uint256 ageThreshold);
    
    // --- Errors ---
    error TradingIsPaused();
    error NotPauser();
    
    constructor(
        address token_,
        address factory_,
        address platformTreasury_,
        address agentTreasury_,
        address dexRouter_,
        uint256 virtualRitual_,
        uint256 virtualToken_,
        uint256 graduationThreshold_
    ) HiveBondingCurve(
        token_,
        factory_,
        platformTreasury_,
        agentTreasury_,
        dexRouter_,
        virtualRitual_,
        virtualToken_,
        graduationThreshold_
    ) {
        pauser = factory_;
    }
    
    // --- Override: Dynamic Fee Calculation ---
    
    /// @notice Calculate buy amount with dynamic fee based on simple risk assessment
    function calculateBuy(uint256 ritualIn) public view override returns (uint256 tokensOut, uint256 fee) {
        if (ritualIn == 0) return (0, 0);
        
        uint256 feeBps = _getDynamicFee();
        
        fee = (ritualIn * feeBps) / 10_000;
        uint256 ritualAfterFee = ritualIn - fee;
        
        tokensOut = (ritualAfterFee * virtualTokenReserve) / (virtualRitualReserve + ritualAfterFee);
        
        if (tokensOut > virtualTokenReserve) {
            tokensOut = virtualTokenReserve;
        }
    }
    
    /// @notice Calculate sell amount with dynamic fee based on simple risk assessment
    function calculateSell(uint256 tokensIn) public view override returns (uint256 ritualOut, uint256 fee) {
        if (tokensIn == 0) return (0, 0);
        
        uint256 feeBps = _getDynamicFee();
        
        ritualOut = (tokensIn * virtualRitualReserve) / (virtualTokenReserve + tokensIn);
        fee = (ritualOut * feeBps) / 10_000;
        ritualOut = ritualOut - fee;
    }
    
    // --- Override: Buy with Pause Check ---
    
    function buy(uint256 ritualIn, uint256 minTokensOut) external payable override nonReentrant returns (uint256 tokensOut) {
        if (tradingPaused) revert TradingIsPaused();
        
        if (migrationReady || migrationPending) revert MigrationAlreadyDone();
        if (msg.value < ritualIn) revert InsufficientRitual();
        
        uint256 fee;
        (tokensOut, fee) = calculateBuy(ritualIn);
        if (tokensOut == 0) revert InsufficientRitual();
        
        if (tokensOut < minTokensOut) {
            revert SlippageExceeded(minTokensOut, tokensOut);
        }
        
        virtualRitualReserve += (ritualIn - fee);
        virtualTokenReserve -= tokensOut;
        realRitualSold += (ritualIn - fee);
        realTokensSold += tokensOut;
        
        (bool sent,) = token.call(
            abi.encodeWithSignature("transfer(address,uint256)", msg.sender, tokensOut)
        );
        if (!sent) revert TransferFailed();
        
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
            msg.sender, ritualIn, tokensOut, fee, getCurrentPrice(),
            virtualRitualReserve, virtualTokenReserve
        );
        
        emit DynamicFeeApplied(_calculateRiskScore(), _getDynamicFee());
        
        // Graduation check
        if (realRitualSold >= graduationThreshold && !isGraduated && !migrationPending) {
            try this.executeGraduation() {
                // Success
            } catch (bytes memory reason) {
                migrationPending = true;
                migrationReady = true;
                emit GraduationPending(realRitualSold, realTokensSold, reason);
            }
        }
    }
    
    // --- Override: Sell with Pause Check ---
    
    function sell(uint256 tokensIn, uint256 minRitualOut) external override nonReentrant returns (uint256 ritualOut) {
        if (tradingPaused) revert TradingIsPaused();
        
        if (migrationReady || migrationPending) revert MigrationAlreadyDone();
        if (isGraduated) revert MigrationAlreadyDone();
        
        uint256 fee;
        (ritualOut, fee) = calculateSell(tokensIn);
        if (ritualOut == 0) revert InsufficientTokens();
        
        if (ritualOut < minRitualOut) {
            revert SlippageExceeded(minRitualOut, ritualOut);
        }
        
        virtualTokenReserve += tokensIn;
        virtualRitualReserve -= (ritualOut + fee);
        realRitualSold -= ritualOut;
        
        (bool sent,) = token.call(
            abi.encodeWithSignature("transferFrom(address,address,uint256)", msg.sender, address(this), tokensIn)
        );
        if (!sent) revert TransferFailed();
        
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
        
        (bool sent3,) = msg.sender.call{value: ritualOut}("");
        if (!sent3) revert TransferFailed();
        
        emit TokensSold(
            msg.sender, tokensIn, ritualOut, fee, getCurrentPrice(),
            virtualRitualReserve, virtualTokenReserve
        );
        
        emit DynamicFeeApplied(_calculateRiskScore(), _getDynamicFee());
    }
    
    // --- Admin Functions ---
    
    /// @notice Pause trading
    function pauseTrading(string calldata reason) external {
        require(msg.sender == factory || msg.sender == pauser, "not authorized");
        tradingPaused = true;
        emit TradingPaused(token, reason);
    }
    
    /// @notice Unpause trading
    function unpauseTrading() external {
        require(msg.sender == factory || msg.sender == pauser, "not authorized");
        tradingPaused = false;
        emit TradingUnpaused(token);
    }
    
    /// @notice Update risk assessment parameters
    function setRiskParams(
        uint256 holderThreshold_,
        uint256 volumeThreshold_,
        uint256 ageThreshold_
    ) external {
        require(msg.sender == factory, "not factory");
        holderThreshold = holderThreshold_;
        volumeThreshold = volumeThreshold_;
        ageThreshold = ageThreshold_;
        emit RiskParamsUpdated(holderThreshold_, volumeThreshold_, ageThreshold_);
    }
    
    /// @notice Update fee parameters
    function setFeeParams(uint256 baseFeeBps_, uint256 maxFeeBps_, uint256 minFeeBps_) external {
        require(msg.sender == factory, "not factory");
        require(baseFeeBps_ <= maxFeeBps_ && baseFeeBps_ >= minFeeBps_, "invalid fees");
        baseFeeBps = baseFeeBps_;
        maxFeeBps = maxFeeBps_;
        minFeeBps = minFeeBps_;
    }
    
    // --- Internal Functions ---
    
    /// @dev Simple risk score calculation (0-100)
    function _calculateRiskScore() internal view returns (uint256) {
        uint256 riskScore = 50; // Base risk
        
        // Age risk: newer tokens are riskier
        if (realTokensSold < ageThreshold) {
            riskScore += 20;
        }
        
        // Volume risk: lower volume = higher risk
        if (realRitualSold < volumeThreshold) {
            riskScore += 15;
        }
        
        // Concentration risk: check if too much supply sold
        uint256 supplySoldPct = (realTokensSold * 100) / virtualTokenReserve;
        if (supplySoldPct > 80) {
            riskScore += 15;
        } else if (supplySoldPct > 60) {
            riskScore += 10;
        }
        
        // Cap at 100
        if (riskScore > 100) riskScore = 100;
        
        return riskScore;
    }
    
    /// @dev Get dynamic fee based on risk score
    function _getDynamicFee() internal view returns (uint256) {
        uint256 riskScore = _calculateRiskScore();
        
        // Risk 0-50: base fee
        if (riskScore <= 50) return baseFeeBps;
        
        // Risk 50-100: linear scaling to max fee
        uint256 riskPremium = ((riskScore - 50) * (maxFeeBps - baseFeeBps)) / 50;
        uint256 dynamicFee = baseFeeBps + riskPremium;
        
        // Clamp
        if (dynamicFee < minFeeBps) return minFeeBps;
        if (dynamicFee > maxFeeBps) return maxFeeBps;
        
        return dynamicFee;
    }
}
