// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "../src/HiveFactory.sol";

/// @title DeployHive - Deploy HiveFactory to Ritual Chain (1979)
contract DeployHive is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address platformTreasury = vm.envAddress("PLATFORM_TREASURY");

        vm.startBroadcast(deployerPrivateKey);

        HiveFactory factory = new HiveFactory(platformTreasury, 0x8918Aafa24d74e8e0868fE97A77a9882874b81E0);

        console.log("HiveFactory deployed to:", address(factory));
        console.log("Owner:", vm.addr(deployerPrivateKey));
        console.log("Platform Treasury:", platformTreasury);

        vm.stopBroadcast();
    }
}
