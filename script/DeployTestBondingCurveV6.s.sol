// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "../src/HiveBondingCurveV6.sol";

/// @dev Deploy a test HiveBondingCurveV6 with dummy parameters
///      Use this for testing the enhanced bonding curve on Ritual testnet
contract DeployTestBondingCurveV6 is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        
        // Dummy parameters for testing
        address token = 0x0000000000000000000000000000000000000001; // Dummy token
        address factory = 0xb8E43212FfE1f3d16053a9A7f09e07e73f80412D; // Real factory
        address platformTreasury = 0x63C5341454F66a32553CE598e06861E11095d39C; // Real treasury
        address agentTreasury = 0x0000000000000000000000000000000000000002; // Dummy
        address dexRouter = 0x8918Aafa24d74e8e0868fE97A77a9882874b81E0; // Real router
        uint256 virtualRitual = 1 ether; // 1 RITUAL
        uint256 virtualToken = 1_000_000_000 * 1e18; // 1B tokens
        
        vm.startBroadcast(deployerPrivateKey);
        
        HiveBondingCurveV6 curve = new HiveBondingCurveV6(
            token,
            factory,
            platformTreasury,
            agentTreasury,
            dexRouter,
            virtualRitual,
            virtualToken,
            0.1 ether // graduationThreshold
        );
        
        vm.stopBroadcast();
        
        console.log("HiveBondingCurveV6 deployed at:", address(curve));
        console.log("  Token:", token);
        console.log("  Factory:", factory);
        console.log("  Virtual RITUAL:", virtualRitual);
        console.log("  Virtual Token:", virtualToken);
    }
}
