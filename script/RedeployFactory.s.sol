// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "forge-std/Script.sol";
import "../src/factory/HiveFactory.sol";

/// @title RedeployFactory — Redeploy HiveFactory with full module support
contract RedeployFactory is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        console.log("Redeploying HiveFactory from:", deployer);

        vm.startBroadcast(deployerPrivateKey);

        // Deploy new factory
        HiveFactory factory = new HiveFactory();
        console.log("New HiveFactory deployed at:", address(factory));

        // Initialize with Layer 1 modules
        factory.initialize(
            0x013c6D5a4fa5D50a92261C4189a8F56900408A01, // hiveID
            0xDD2A524E0Bda702ed5f9b1740Dd145Ce2de23Eb6, // verifier
            0x4cbe69CC563D548e2DA214c6c7C16fC32b69526A, // reputation
            0x5D72F3faf4ada60E1beCa310a2FA82b7B731aEbE, // oracle
            0x6fc9D8aBFa06867D5932DA9C473D46B0224041ED, // referral
            0x81E38ad29B869De5dd99bC5da1386b65Ef2Da066, // portfolio
            0xa2FCc065f174e9BE536A090DD344B9C8b8Dc513c  // relayer
        );
        console.log("Factory initialized (Layer 1)");

        // Wire extended modules (Layer 2-7)
        factory.wireExtended(
            0x8eb73b9e2dD62EcFC9C61861638C45afe003d95b, // launchPad
            0x62C8AB145AA677792b7E7d1f0Bf64000D3DC637D, // marketMaker
            0x631969799907Dc4914988298A7795783e24c20CC, // clearing
            0x8D2A42Fe7845F165264d042267a3bD8EBae83d28, // staking
            0x90fbd495c888ae010e40FD299E143FabFcf08C18, // treasury
            0x9533BD3D3baD7182EE52e054ca9c73780069AD5E, // dkms (NEW!)
            0x4DF77A4f06b792BA964B3dD751a0672cFa2bAb69, // honeyPot (NEW!)
            0x0ad0234d3EA8bd41ee571b1B317fA98d46E642B4, // brain
            0x842441aB565a3C6C8183ABB08a735B2DEA184327, // agent
            0x1b3A537D4572c1020Bc72c9f4951704966d3BEF9, // autoStrategy
            0x1b3A537D4572c1020Bc72c9f4951704966d3BEF9, // strategy (same)
            0xb0f436d799935Fbe6c7D8885E4345B588B16F5d2, // flock
            0xeadd2aB5D8f1Ead852927Dd56c34b365603c2702, // governance
            0x245590BE2E044A8a0aeB99C1bbBAAa4e68B715B3, // council
            0xd450caB1dCe65ac7bB089Cf8dA9F20f37544B1B6, // multiSig
            0x615F139dDFb2f2f486133B3a2D9F74Dd2bA785B6, // chat
            0xC031064390952259a42885219dB16F66677fbfaa, // points
            0x9a04677f219384Fe35E29E968d43e8BDC6392C42, // notification
            0xC2ec8C64A3183e3a611284d70ccb4C0dAb8eDDfd, // queen
            0x89Cff106458261b48597ee0307017504080182eE  // registry
        );
        console.log("Factory wired (Layer 2-7)");

        // Wire cross-module connections
        factory.wireAll();
        console.log("Cross-module wiring complete");

        vm.stopBroadcast();

        console.log("=== FACTORY REDEPLOY COMPLETE ===");
    }
}
