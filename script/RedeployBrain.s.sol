// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "forge-std/Script.sol";
import "../src/agent/HiveBrain.sol";

/// @title RedeployBrain — Deploy HiveBrain with current source
contract RedeployBrain is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        // Existing addresses
        address queen = 0xC2ec8C64A3183e3a611284d70ccb4C0dAb8eDDfd;
        address oracle = 0x5D72F3faf4ada60E1beCa310a2FA82b7B731aEbE;
        address flock = 0xb0f436d799935Fbe6c7D8885E4345B588B16F5d2;

        console.log("Redeploying HiveBrain from:", deployer);

        vm.startBroadcast(deployerPrivateKey);

        HiveBrain brain = new HiveBrain(queen, oracle, flock);
        console.log("HiveBrain deployed at:", address(brain));

        vm.stopBroadcast();

        console.log("=== HIVEBRAIN REDEPLOY COMPLETE ===");
    }
}
