// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "../src/HiveFactory.sol";

contract DeploySimple is Script {
    function run() external {
        uint256 deployerKey = vm.envUint("PRIVATE_KEY");
        address platformTreasury = vm.envAddress("PLATFORM_TREASURY");

        vm.startBroadcast(deployerKey);

        // Deploy factory
        HiveFactory factory = new HiveFactory(platformTreasury, 0x8918Aafa24d74e8e0868fE97A77a9882874b81E0);
        console.log("Factory deployed:", address(factory));

        // Fund factory with 0.05 RITUAL for first precompile calls
        (bool funded,) = address(factory).call{value: 0.05 ether}("");
        require(funded, "Factory funding failed");
        console.log("Factory funded: 0.05 RITUAL");

        // Verify virtualRitual
        console.log("virtualRitual:", factory.virtualRitual());
        console.log("virtualToken:", factory.virtualToken());
        console.log("owner:", factory.owner());

        vm.stopBroadcast();
    }
}
