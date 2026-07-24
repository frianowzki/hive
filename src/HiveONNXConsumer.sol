// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @title HiveONNXConsumer - On-chain ML inference via Ritual ONNX precompile
/// @notice Calls ONNX precompile (0x0800) for token risk assessment, anomaly detection, scam classification
/// @dev Synchronous execution - no async lifecycle, no RitualWallet needed
contract HiveONNXConsumer {
    // --- Ritual ONNX Precompile ---
    address public constant ONNX_PRECOMPILE = 0x0000000000000000000000000000000000000800;
    
    // --- Models (HuggingFace ONNX format) ---
    bytes public riskScoringModelId;
    bytes public anomalyDetectionModelId;
    bytes public scamClassificationModelId;
    bytes public volatilityPredictionModelId;
    
    // --- State ---
    address public owner;
    address public bondingCurve;
    
    // --- Risk Score Cache ---
    mapping(address => uint256) public lastRiskScore;
    mapping(address => uint256) public lastRiskScoreBlock;
    uint256 public constant RISK_CACHE_DURATION = 100;
    
    // --- Events ---
    event RiskScoreUpdated(address indexed token, uint256 score, uint256 blockNumber);
    event AnomalyDetected(address indexed token, bool isSuspicious, uint256 confidence);
    event ScamDetected(address indexed token, bool isScam);
    event VolatilityUpdated(address indexed token, uint256 score);
    event ModelUpdated(string modelName, bytes newModelId);
    
    // --- Errors ---
    error NotOwner();
    error NotBondingCurve();
    error ONNXCallFailed();
    error InvalidModelId();
    
    // --- Modifiers ---
    modifier onlyOwner() {
        if (msg.sender != owner) revert NotOwner();
        _;
    }
    
    modifier onlyBondingCurve() {
        if (msg.sender != bondingCurve) revert NotBondingCurve();
        _;
    }
    
    constructor(
        address bondingCurve_,
        bytes memory riskScoringModelId_,
        bytes memory anomalyDetectionModelId_,
        bytes memory scamClassificationModelId_,
        bytes memory volatilityPredictionModelId_
    ) {
        owner = msg.sender;
        bondingCurve = bondingCurve_;
        riskScoringModelId = riskScoringModelId_;
        anomalyDetectionModelId = anomalyDetectionModelId_;
        scamClassificationModelId = scamClassificationModelId_;
        volatilityPredictionModelId = volatilityPredictionModelId_;
    }
    
    // --- Core Functions ---
    
    /// @notice Get risk score for a token
    function getRiskScore(
        address token,
        uint256 buySellRatio,
        uint256 holderCount,
        uint256 topHolderPct,
        uint256 ageBlocks,
        uint256 volumeRitual,
        uint256 liquidityDepth
    ) external returns (uint256 riskScore) {
        // Check cache
        if (block.number - lastRiskScoreBlock[token] < RISK_CACHE_DURATION) {
            return lastRiskScore[token];
        }
        
        // Encode input tensor
        bytes memory tensorData = _encodeTensor(
            5,  // dtype: FLOAT32
            _createShape(1, 6),
            _createValues6(buySellRatio, holderCount, topHolderPct, ageBlocks, volumeRitual, liquidityDepth)
        );
        
        // Call ONNX precompile
        bytes memory result = _callONNX(riskScoringModelId, tensorData);
        
        // Decode output
        riskScore = _decodeFloatOutput(result);
        
        // Cache result
        lastRiskScore[token] = riskScore;
        lastRiskScoreBlock[token] = block.number;
        
        emit RiskScoreUpdated(token, riskScore, block.number);
    }
    
    /// @notice Check if token is anomalous
    function checkAnomaly(
        address token,
        uint256 volumeSpike,
        uint256 buyPressure,
        uint256 uniqueBuyers,
        uint256 tradeSizeAvg,
        uint256 timeBetweenTrades
    ) external returns (bool isSuspicious, uint256 confidence) {
        // Encode input tensor
        bytes memory tensorData = _encodeTensor(
            5,  // dtype: FLOAT32
            _createShape(1, 5),
            _createValues5(volumeSpike, buyPressure, uniqueBuyers, tradeSizeAvg, timeBetweenTrades)
        );
        
        // Call ONNX precompile
        bytes memory result = _callONNX(anomalyDetectionModelId, tensorData);
        
        // Decode output (classification returns probabilities)
        (uint256 class0, uint256 class1) = _decodeClassificationOutput(result);
        
        isSuspicious = class1 > class0;
        confidence = class1;
        
        emit AnomalyDetected(token, isSuspicious, confidence);
    }
    
    /// @notice Check if token is a scam
    function checkScam(
        address token,
        uint256 hasRenounce,
        uint256 hasHoneypot,
        uint256 maxTxPct,
        uint256 liquidityLocked,
        uint256 contractVerified,
        uint256 feePct,
        uint256 hasBlacklist,
        uint256 hasPause
    ) external returns (bool isScam) {
        // Encode input tensor
        bytes memory tensorData = _encodeTensor(
            5,  // dtype: FLOAT32
            _createShape(1, 8),
            _createValues8(hasRenounce, hasHoneypot, maxTxPct, liquidityLocked, contractVerified, feePct, hasBlacklist, hasPause)
        );
        
        // Call ONNX precompile
        bytes memory result = _callONNX(scamClassificationModelId, tensorData);
        
        // Decode output
        (uint256 class0, uint256 class1) = _decodeClassificationOutput(result);
        
        isScam = class1 > class0;
        
        emit ScamDetected(token, isScam);
    }
    
    /// @notice Get volatility score for a token
    function getVolatility(
        address token,
        uint256 priceChange1h,
        uint256 priceChange24h,
        uint256 volume1h,
        uint256 volume24h,
        uint256 tradeCount1h
    ) external returns (uint256 volatilityScore) {
        // Encode input tensor
        bytes memory tensorData = _encodeTensor(
            5,  // dtype: FLOAT32
            _createShape(1, 5),
            _createValues5(priceChange1h, priceChange24h, volume1h, volume24h, tradeCount1h)
        );
        
        // Call ONNX precompile
        bytes memory result = _callONNX(volatilityPredictionModelId, tensorData);
        
        // Decode output
        volatilityScore = _decodeFloatOutput(result);
        
        emit VolatilityUpdated(token, volatilityScore);
    }
    
    // --- Admin Functions ---
    
    /// @notice Update model ID
    function updateModel(string calldata modelName, bytes calldata newModelId) external onlyOwner {
        if (keccak256(bytes(modelName)) == keccak256("riskScoring")) {
            riskScoringModelId = newModelId;
        } else if (keccak256(bytes(modelName)) == keccak256("anomalyDetection")) {
            anomalyDetectionModelId = newModelId;
        } else if (keccak256(bytes(modelName)) == keccak256("scamClassification")) {
            scamClassificationModelId = newModelId;
        } else if (keccak256(bytes(modelName)) == keccak256("volatilityPrediction")) {
            volatilityPredictionModelId = newModelId;
        } else {
            revert InvalidModelId();
        }
        
        emit ModelUpdated(modelName, newModelId);
    }
    
    // --- Internal Functions ---
    
    /// @dev Create shape array
    function _createShape(uint16 dim0, uint16 dim1) internal pure returns (uint16[] memory) {
        uint16[] memory shape = new uint16[](2);
        shape[0] = dim0;
        shape[1] = dim1;
        return shape;
    }
    
    /// @dev Create values array (6 elements)
    function _createValues6(
        uint256 v0, uint256 v1, uint256 v2, uint256 v3, uint256 v4, uint256 v5
    ) internal pure returns (int32[] memory) {
        int32[] memory values = new int32[](6);
        values[0] = _uint256ToFloat32(v0);
        values[1] = _uint256ToFloat32(v1);
        values[2] = _uint256ToFloat32(v2);
        values[3] = _uint256ToFloat32(v3);
        values[4] = _uint256ToFloat32(v4);
        values[5] = _uint256ToFloat32(v5);
        return values;
    }
    
    /// @dev Create values array (5 elements)
    function _createValues5(
        uint256 v0, uint256 v1, uint256 v2, uint256 v3, uint256 v4
    ) internal pure returns (int32[] memory) {
        int32[] memory values = new int32[](5);
        values[0] = _uint256ToFloat32(v0);
        values[1] = _uint256ToFloat32(v1);
        values[2] = _uint256ToFloat32(v2);
        values[3] = _uint256ToFloat32(v3);
        values[4] = _uint256ToFloat32(v4);
        return values;
    }
    
    /// @dev Create values array (8 elements)
    function _createValues8(
        uint256 v0, uint256 v1, uint256 v2, uint256 v3, uint256 v4, uint256 v5, uint256 v6, uint256 v7
    ) internal pure returns (int32[] memory) {
        int32[] memory values = new int32[](8);
        values[0] = _uint256ToFloat32(v0);
        values[1] = _uint256ToFloat32(v1);
        values[2] = _uint256ToFloat32(v2);
        values[3] = _uint256ToFloat32(v3);
        values[4] = _uint256ToFloat32(v4);
        values[5] = _uint256ToFloat32(v5);
        values[6] = _uint256ToFloat32(v6);
        values[7] = _uint256ToFloat32(v7);
        return values;
    }
    
    /// @dev Call ONNX precompile
    function _callONNX(bytes memory modelId, bytes memory tensorData) internal returns (bytes memory) {
        bytes memory input = abi.encode(
            modelId,
            tensorData,
            uint8(2),  // inputArithmetic: 2 = IEEE 754 float
            uint8(0),  // inputFixedPointScale: N/A for IEEE 754
            uint8(2),  // outputArithmetic: 2 = IEEE 754 float
            uint8(0),  // outputFixedPointScale: N/A for IEEE 754
            uint8(1)   // rounding: 1 = half-even (round nearest)
        );
        
        (bool ok, bytes memory result) = ONNX_PRECOMPILE.call(input);
        if (!ok) revert ONNXCallFailed();
        
        return result;
    }
    
    /// @dev Encode RitualTensor
    function _encodeTensor(
        uint8 dtype,
        uint16[] memory shape,
        int32[] memory values
    ) internal pure returns (bytes memory) {
        return abi.encode(dtype, shape, values);
    }
    
    /// @dev Convert uint256 to float32 bit pattern (simplified)
    function _uint256ToFloat32(uint256 value) internal pure returns (int32) {
        if (value == 0) return 0;
        return int32(uint32(value));
    }
    
    /// @dev Decode ONNX float output
    function _decodeFloatOutput(bytes memory result) internal pure returns (uint256) {
        // Decode outer response envelope
        (bytes memory tensorData, , , ) = abi.decode(
            result,
            (bytes, uint8, uint8, uint8)
        );
        
        // Decode inner RitualTensor
        (, , int32[] memory values) = abi.decode(
            tensorData,
            (uint8, uint16[], int32[])
        );
        
        // Convert float32 bit pattern to uint256
        if (values.length > 0) {
            return _float32ToUint256(values[0]);
        }
        
        return 0;
    }
    
    /// @dev Decode ONNX classification output (returns class probabilities)
    function _decodeClassificationOutput(bytes memory result) internal pure returns (uint256 class0, uint256 class1) {
        // Decode outer response envelope
        (bytes memory tensorData, , , ) = abi.decode(
            result,
            (bytes, uint8, uint8, uint8)
        );
        
        // Decode inner RitualTensor
        (, , int32[] memory values) = abi.decode(
            tensorData,
            (uint8, uint16[], int32[])
        );
        
        // Classification returns probabilities for each class
        if (values.length >= 2) {
            class0 = _float32ToUint256(values[0]);
            class1 = _float32ToUint256(values[1]);
        }
    }
    
    /// @dev Convert float32 bit pattern to uint256 (simplified)
    function _float32ToUint256(int32 value) internal pure returns (uint256) {
        return uint256(uint32(value));
    }
}
