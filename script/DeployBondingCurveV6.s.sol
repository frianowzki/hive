// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "../src/HiveBondingCurveV6.sol";

contract DeployBondingCurveV6 is Script {
    function run() external {
        // Parameters (update these for your deployment)
        address token = vm.envAddress("TOKEN_ADDRESS");
        address factory = vm.envAddress("FACTORY_ADDRESS");
        address platformTreasury = vm.envAddress("PLATFORM_TREASURY");
        address agentTreasury = vm.envAddress("AGENT_TREASURY");
        address dexRouter = vm.envAddress("DEX_ROUTER");
        uint256 virtualRitual = vm.envUint("VIRTUAL_RITUAL");
        uint256 virtualToken = vm.envUint("VIRTUAL_TOKEN");
        
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        
        vm.startBroadcast(deployerPrivateKey);
        
        HiveBondingCurveV6 curve = new HiveBondingCurveV6(
            token,
            factory,
            platformTreasury,
            agentTreasury,
            dexRouter,
            virtualRitual,
            virtualToken, 0.1 ether
        );
        
        vm.stopBroadcast();
        
        console.log("HiveBondingCurveV6 deployed at:", address(curve));
    }
}
