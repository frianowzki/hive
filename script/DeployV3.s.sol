// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "forge-std/Script.sol";
import "../src/points/HivePoints.sol";
import "../src/launch/HiveLaunchPad.sol";
import "../src/maker/HiveMarketMaker.sol";
import "../src/registry/HiveRegistry.sol";
import "../src/strategy/Strategy.sol";
import "../src/drone/Drone.sol";
import "../src/queen/Queen.sol";
import "../src/council/HiveCouncil.sol";
import "../src/flock/HiveFLock.sol";
// EigenLayer removed — not implementable on Ritual Testnet
// import "../src/eigenlayer/HiveEigenLayer.sol";

/// @title DeployV3 — Deploy remaining 10 contracts
contract DeployV3 is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        // Already deployed addresses (from DEPLOYMENT_MANIFEST.json)
        address brain = 0x0ad0234d3EA8bd41ee571b1B317fA98d46E642B4;
        address staking = 0x93dd206181e3519c9f9CAC38aaE5d67b6009b408;
        address honeypot = 0x90fbd495c888ae010e40FD299E143FabFcf08C18; // HiveTreasury

        console.log("Deploying from:", deployer);
        console.log("Chain: Ritual Testnet (1979)");

        vm.startBroadcast(deployerPrivateKey);

        // 1. HivePoints (no args)
        HivePoints points = new HivePoints();
        console.log("HivePoints deployed at:", address(points));

        // 2. HiveLaunchPad (needs points)
        HiveLaunchPad launchPad = new HiveLaunchPad(address(points));
        console.log("HiveLaunchPad deployed at:", address(launchPad));

        // 3. HiveMarketMaker (needs points)
        HiveMarketMaker marketMaker = new HiveMarketMaker(address(points));
        console.log("HiveMarketMaker deployed at:", address(marketMaker));

        // 4. HiveRegistry (no args)
        HiveRegistry registry = new HiveRegistry();
        console.log("HiveRegistry deployed at:", address(registry));

        // 5. HiveCouncil (needs points)
        HiveCouncil council = new HiveCouncil(address(points));
        console.log("HiveCouncil deployed at:", address(council));

        // 6. Queen (needs honeypot, strategy, registry, launchPad, marketMaker, council)
        // Strategy is deployed after Queen, so pass address(0) for now
        Queen queen = new Queen(
            "HiveQueen",
            100,                    // cycleInterval (blocks)
            honeypot,               // honeypot (HiveTreasury)
            address(0),             // strategy (will wire later)
            address(registry),
            address(launchPad),
            address(marketMaker),
            address(council)
        );
        console.log("Queen deployed at:", address(queen));

        // 7. Strategy (needs queen)
        Strategy strategy = new Strategy(address(queen));
        console.log("Strategy deployed at:", address(strategy));

        // 8. HiveFLock (needs brain)
        HiveFLock flock = new HiveFLock(brain);
        console.log("HiveFLock deployed at:", address(flock));

        // EigenLayer removed — not implementable on Ritual Testnet
        // HiveEigenLayer eigenLayer = new HiveEigenLayer(staking);
        // console.log("HiveEigenLayer deployed at:", address(eigenLayer));

        // 10. Drone (needs queen, purpose, type, capital)
        // Deploying a Guardian drone as example
        Drone drone = new Drone{value: 0}(
            address(queen),
            "Guardian: threat monitoring",
            Drone.DroneType.Guardian,
            0
        );
        console.log("Drone deployed at:", address(drone));

        // Wire Queen with strategy
        queen.setDivision("strategy", address(strategy));
        console.log("Queen wired with Strategy");

        vm.stopBroadcast();

        console.log("=== DEPLOYMENT V3 COMPLETE ===");
        console.log("10 contracts deployed successfully");
    }
}
