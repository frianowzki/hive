// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "forge-std/Script.sol";
import "../src/token/HiveToken.sol";
import "../src/faucet/HiveFaucet.sol";

/// @title Deploy hiveUSD + HiveFaucet
contract DeployHiveUSD is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        console.log("Deploying from:", deployer);
        console.log("Chain: Ritual Chain (1979)");

        vm.startBroadcast(deployerPrivateKey);

        // 1. Deploy hiveUSD token
        HiveToken hiveUSD = new HiveToken(
            "hiveUSD",
            "hiveUSD",
            18,
            0x63C5341454F66a32553CE598e06861E11095d39C, // minter = Frian
            bytes32(0),
            ""
        );
        console.log("hiveUSD deployed at:", address(hiveUSD));

        // 2. Deploy HiveFaucet
        HiveFaucet faucet = new HiveFaucet(address(hiveUSD));
        console.log("HiveFaucet deployed at:", address(faucet));

        // 3. Mint 100B hiveUSD to faucet
        //    Only minter (Frian) can mint — so we'll mint from deployer
        //    Actually, minter is Frian's address, not deployer. 
        //    We need Frian to mint and transfer to faucet.
        //    For now, deploy only. Frian mints manually.

        vm.stopBroadcast();

        console.log("=== DEPLOYMENT COMPLETE ===");
        console.log("Next steps:");
        console.log("1. Frian mints 100B hiveUSD to HiveFaucet");
        console.log("2. Users call faucet.claim() for 1000 hiveUSD/day");
    }
}
