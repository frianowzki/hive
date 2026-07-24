// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "../src/HiveONNXConsumer.sol";

contract UpdateModels is Script {
    function run() external {
        // Contract address
        address onnxConsumer = 0xfb1C8d204139D95A592Faf67276600b30a8E2632;
        
        // Model IDs
        bytes memory riskScoringModelId = "hf/frianowzki/hive-onnx-models/risk_scoring.onnx@6171ecf05ed5ffcec9056bc24ba7519b63c80829";
        bytes memory anomalyDetectionModelId = "hf/frianowzki/hive-onnx-models/anomaly_detection.onnx@4a41c6ea0d03fb66143c769ff9ea5e525f981b49";
        bytes memory scamClassificationModelId = "hf/frianowzki/hive-onnx-models/scam_classification.onnx@201dc216b4e9ac3c1afafe21d55841b68591819c";
        bytes memory volatilityPredictionModelId = "hf/frianowzki/hive-onnx-models/volatility_prediction.onnx@7965dfc446a42f62b28176c9502e0e3fb9f0b022";
        
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        
        vm.startBroadcast(deployerPrivateKey);
        
        HiveONNXConsumer consumer = HiveONNXConsumer(onnxConsumer);
        consumer.updateModel("riskScoring", riskScoringModelId);
        consumer.updateModel("anomalyDetection", anomalyDetectionModelId);
        consumer.updateModel("scamClassification", scamClassificationModelId);
        consumer.updateModel("volatilityPrediction", volatilityPredictionModelId);
        
        vm.stopBroadcast();
        
        console.log("All models updated!");
    }
}
