// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "forge-std/Script.sol";
import "../src/privacy/HiveDKMS.sol";
import "../src/treasury/HoneyPot.sol";

/// @title DeployRemaining — Deploy HiveDKMS + HoneyPot to Ritual Testnet
contract DeployRemaining is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        // Already deployed addresses
        address queen = 0xC2ec8C64A3183e3a611284d70ccb4C0dAb8eDDfd;
        address staking = 0x8D2A42Fe7845F165264d042267a3bD8EBae83d28;
        address factory = 0x0241cfB0a6620f57988C75Cd06dA2914b21463c6;

        console.log("Deploying from:", deployer);
        console.log("Chain: Ritual Testnet (1979)");

        vm.startBroadcast(deployerPrivateKey);

        // 1. HiveDKMS — TEE-bound key management
        HiveDKMS dkms = new HiveDKMS(deployer);
        console.log("HiveDKMS deployed at:", address(dkms));

        // 2. HoneyPot — Fee economy (60% stakers / 25% referrers / 15% reserve)
        HoneyPot honeyPot = new HoneyPot(queen, staking);
        console.log("HoneyPot deployed at:", address(honeyPot));

        vm.stopBroadcast();

        console.log("=== DEPLOY REMAINING COMPLETE ===");
        console.log("Next: wire via HiveFactory.updateModule()");
    }
}
