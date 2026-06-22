// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "forge-std/Script.sol";
import "../src/agent/HiveAgentFactory.sol";

/// @title DeployAgentFactory — Deploy HiveAgentFactory
contract DeployAgentFactory is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        address treasury = 0x90fbd495c888ae010e40FD299E143FabFcf08C18; // HiveTreasury
        uint256 deploymentFee = 0.01 ether; // ~$10 worth of RITUAL

        console.log("Deploying from:", deployer);
        console.log("Chain: Ritual Testnet (1979)");
        console.log("Treasury:", treasury);
        console.log("Deployment Fee:", deploymentFee);

        vm.startBroadcast(deployerPrivateKey);

        HiveAgentFactory factory = new HiveAgentFactory(treasury, deploymentFee);
        console.log("HiveAgentFactory deployed at:", address(factory));

        vm.stopBroadcast();
    }
}
