// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "../src/HiveTokenMeta.sol";

/// @title DeployTokenMeta - Deploy HiveTokenMeta to Ritual Testnet
contract DeployTokenMeta is Script {
    function run() external {
        uint256 deployerKey = vm.envUint("PRIVATE_KEY");

        console.log("=== HIVE TOKEN META DEPLOY ===");

        vm.startBroadcast(deployerKey);

        HiveTokenMeta meta = new HiveTokenMeta();
        address metaAddr = address(meta);
        console.log("HiveTokenMeta deployed:", metaAddr);

        vm.stopBroadcast();

        console.log("=== DEPLOY COMPLETE ===");
        console.log("HiveTokenMeta:", metaAddr);
    }
}
