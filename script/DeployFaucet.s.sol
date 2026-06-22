// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "forge-std/Script.sol";
import "../src/faucet/HiveFaucet.sol";

/// @title DeployFaucet — Deploy updated HiveFaucet (25000 hiveUSD)
contract DeployFaucet is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);
        address hiveUSD = 0x60601e48038E32dBCd9A9667c589bf6D39A32fb5;

        console.log("Deploying from:", deployer);
        console.log("Chain: Ritual Testnet (1979)");

        vm.startBroadcast(deployerPrivateKey);

        HiveFaucet faucet = new HiveFaucet(hiveUSD);
        console.log("HiveFaucet deployed at:", address(faucet));

        vm.stopBroadcast();
    }
}
