// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "forge-std/Script.sol";
import "../src/agent/HiveSovereignAgentRitual.sol";

contract DeployHiveAgent is Script {
    function run() external {
        address REGISTRY = 0x89Cff106458261b48597ee0307017504080182eE;
        address STAKING = 0x8D2A42Fe7845F165264d042267a3bD8EBae83d28;
        address LAUNCHPAD = 0x8eb73b9e2dD62EcFC9C61861638C45afe003d95b;
        address GOVERNANCE = 0xeadd2aB5D8f1Ead852927Dd56c34b365603c2702;
        address PORTFOLIO = 0x81E38ad29B869De5dd99bC5da1386b65Ef2Da066;
        address MARKETMAKER = 0x62C8AB145AA677792b7E7d1f0Bf64000D3DC637D;

        vm.startBroadcast();

        HiveSovereignAgentRitual agent = new HiveSovereignAgentRitual(
            REGISTRY,
            STAKING,
            LAUNCHPAD,
            GOVERNANCE,
            PORTFOLIO,
            MARKETMAKER
        );

        vm.stopBroadcast();
    }
}
