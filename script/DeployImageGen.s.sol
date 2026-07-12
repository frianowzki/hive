// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "../src/HiveImageGen.sol";

/// @title DeployImageGen - Deploy HiveImageGen to Ritual Testnet
contract DeployImageGen is Script {
    function run() external {
        uint256 deployerKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerKey);

        console.log("=== HIVE IMAGE GEN DEPLOY ===");
        console.log("Deployer:", deployer);

        vm.startBroadcast(deployerKey);

        HiveImageGen imageGen = new HiveImageGen();
        address imageGenAddr = address(imageGen);
        console.log("HiveImageGen deployed:", imageGenAddr);

        // Fund with 0.01 RITUAL for precompile calls
        (bool funded,) = imageGenAddr.call{value: 0.01 ether}("");
        require(funded, "Funding failed");
        console.log("Funded: 0.01 RITUAL");

        vm.stopBroadcast();

        console.log("=== DEPLOY COMPLETE ===");
        console.log("HiveImageGen:", imageGenAddr);
    }
}
