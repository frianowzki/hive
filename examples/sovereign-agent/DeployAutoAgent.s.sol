// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Script.sol";
import "../AutoSovereignAgent.sol";

contract DeployAutoAgent is Script {
    function run() external {
        vm.startBroadcast();
        AutoSovereignAgent agent = new AutoSovereignAgent();
        console.log("AutoSovereignAgent deployed at:", address(agent));
        vm.stopBroadcast();
    }
}
