// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "../src/dex/RitualV2Factory.sol";
import "../src/dex/RitualV2Router02.sol";

/// @title DeployDEX - Deploy Ritual V2 DEX fork on Ritual Testnet
contract DeployDEX is Script {
    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address platformTreasury = vm.envAddress("PLATFORM_TREASURY");

        console.log("=== Deploying Ritual V2 DEX Fork ===");
        console.log("Chain ID:", block.chainid);

        vm.startBroadcast(deployerPrivateKey);

        // 1. Deploy Factory
        RitualV2Factory factory = new RitualV2Factory(platformTreasury);
        console.log("Factory deployed at:", address(factory));

        // 2. Deploy Router
        RitualV2Router02 router = new RitualV2Router02(address(factory));
        console.log("Router deployed at:", address(router));

        vm.stopBroadcast();

        console.log("\n=== DEX Deployment Complete ===");
        console.log("Factory:", address(factory));
        console.log("Router:", address(router));
    }
}
