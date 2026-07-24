// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "../src/HiveONNXConsumer.sol";

contract DeployONNXConsumer is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        
        vm.startBroadcast(deployerPrivateKey);
        
        // Deploy with empty model IDs (can be updated later)
        HiveONNXConsumer onnxConsumer = new HiveONNXConsumer(
            0x0000000000000000000000000000000000000000,  // bondingCurve
            "",  // riskScoringModelId
            "",  // anomalyDetectionModelId
            "",  // scamClassificationModelId
            ""   // volatilityPredictionModelId
        );
        
        vm.stopBroadcast();
        
        console.log("HiveONNXConsumer deployed at:", address(onnxConsumer));
    }
}
