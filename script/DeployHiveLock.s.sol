// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "forge-std/Script.sol";
import "../src/vesting/HiveLock.sol";

contract DeployHiveLock is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        console.log("Deploying HiveLock from:", deployer);

        vm.startBroadcast(deployerPrivateKey);

        HiveLock lock = new HiveLock();
        console.log("HiveLock deployed at:", address(lock));

        vm.stopBroadcast();

        console.log("=== HIVELOCK DEPLOYMENT COMPLETE ===");
    }
}
