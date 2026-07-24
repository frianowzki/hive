// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "../src/HiveTokenLaunchFactory.sol";

contract DeployTokenLaunch is Script {
    function run() external {
        uint256 deployerKey = vm.envUint("PRIVATE_KEY");
        address platformTreasury = vm.envAddress("PLATFORM_TREASURY");
        address dexRouter = vm.envAddress("DEX_ROUTER");

        vm.startBroadcast(deployerKey);

        HiveTokenLaunchFactory factory = new HiveTokenLaunchFactory(platformTreasury, dexRouter);
        console.log("TokenLaunchFactory deployed:", address(factory));
        console.log("owner:", factory.owner());
        console.log("platformTreasury:", factory.platformTreasury());
        console.log("dexRouter:", factory.dexRouter());

        vm.stopBroadcast();
    }
}
