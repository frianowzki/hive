// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "forge-std/Script.sol";
import "../src/queen/Queen.sol";
import "../src/drone/Drone.sol";
import "../src/strategy/Strategy.sol";

contract DeployV2b is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);
        console.log("Deploying from:", deployer);
        vm.startBroadcast(deployerPrivateKey);

        // Queen with no pre-wired divisions (set later via setDivision)
        Queen queen = new Queen("Hive Queen", 1 days, address(0), address(0), address(0), address(0), address(0), address(0));
        console.log("Queen:", address(queen));

        Drone drone = new Drone(address(queen), "Researcher", Drone.DroneType.Researcher, 0);
        console.log("Drone:", address(drone));

        Strategy strategy = new Strategy(address(queen));
        console.log("Strategy:", address(strategy));

        // Wire queen divisions
        queen.setDivision("strategy", address(strategy));

        vm.stopBroadcast();
        console.log("=== DEPLOY V2b DONE ===");
    }
}
