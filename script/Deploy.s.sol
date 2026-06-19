// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "forge-std/Script.sol";
import "../src/identity/HiveID.sol";
import "../src/agent/HiveAgent.sol";
import "../src/agent/HiveBrain.sol";
import "../src/auction/HiveClearing.sol";
import "../src/reputation/HiveReputation.sol";
import "../src/multisig/HiveMultiSig.sol";
import "../src/portfolio/HivePortfolio.sol";
import "../src/referral/HiveReferral.sol";
import "../src/strategy/HiveAutoStrategy.sol";
import "../src/chat/HiveChat.sol";
import "../src/verifier/HiveVerifier.sol";
import "../src/relayer/HiveRelayer.sol";
import "../src/oracle/HiveOracle.sol";
import "../src/token/HiveToken.sol";
import "../src/factory/HiveFactory.sol";
import "../src/treasury/HiveTreasury.sol";
import "../src/governance/HiveGovernance.sol";
import "../src/staking/HiveStaking.sol";
import "../src/notification/HiveNotification.sol";

contract DeployHive is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        console.log("Deploying from:", deployer);

        vm.startBroadcast(deployerPrivateKey);

        // Phase 1: Core Infrastructure
        // HiveID requires registration fee (0 = free registration)
        HiveID hiveID = new HiveID(0);
        console.log("HiveID deployed at:", address(hiveID));

        address[] memory signers = new address[](1);
        signers[0] = deployer;
        // MultiSig requires signers, threshold, and hiveIdHash
        HiveMultiSig multiSig = new HiveMultiSig(signers, 1, bytes32(0));
        console.log("HiveMultiSig deployed at:", address(multiSig));

        HiveVerifier verifier = new HiveVerifier();
        console.log("HiveVerifier deployed at:", address(verifier));

        HiveRelayer relayer = new HiveRelayer();
        console.log("HiveRelayer deployed at:", address(relayer));

        // Phase 2: Financial Infrastructure
        HiveOracle oracle = new HiveOracle();
        console.log("HiveOracle deployed at:", address(oracle));

        HiveStaking staking = new HiveStaking();
        console.log("HiveStaking deployed at:", address(staking));

        HiveTreasury treasury = new HiveTreasury(address(multiSig));
        console.log("HiveTreasury deployed at:", address(treasury));

        HiveReputation reputation = new HiveReputation();
        console.log("HiveReputation deployed at:", address(reputation));

        HiveReferral referral = new HiveReferral();
        console.log("HiveReferral deployed at:", address(referral));

        // Phase 3: Trading Infrastructure
        HiveClearing clearing = new HiveClearing();
        console.log("HiveClearing deployed at:", address(clearing));

        HivePortfolio portfolio = new HivePortfolio();
        console.log("HivePortfolio deployed at:", address(portfolio));

        HiveAutoStrategy strategy = new HiveAutoStrategy();
        console.log("HiveAutoStrategy deployed at:", address(strategy));

        // HiveToken requires name, symbol, decimals, project, projectIdHash, tokenURI
        HiveToken token = new HiveToken("Hive Token", "HIVE", 18, deployer, bytes32(0), "");
        console.log("HiveToken deployed at:", address(token));

        // Phase 4: AI & Communication
        HiveAgent agent = new HiveAgent();
        console.log("HiveAgent deployed at:", address(agent));

        // HiveBrain requires queen address
        HiveBrain brain = new HiveBrain(address(0), address(0), address(0));
        console.log("HiveBrain deployed at:", address(brain));

        HiveChat chat = new HiveChat();
        console.log("HiveChat deployed at:", address(chat));

        // Phase 5: Governance
        HiveGovernance governance = new HiveGovernance(address(staking), address(multiSig));
        console.log("HiveGovernance deployed at:", address(governance));

        HiveNotification notification = new HiveNotification(address(hiveID));
        console.log("HiveNotification deployed at:", address(notification));

        // Phase 6: Factory
        HiveFactory factory = new HiveFactory();
        console.log("HiveFactory deployed at:", address(factory));

        // Initialize Factory
        factory.initialize(
            address(hiveID),
            address(clearing),
            address(reputation),
            address(referral),
            address(portfolio),
            address(verifier),
            address(treasury)
        );
        console.log("HiveFactory initialized");

        // Authorize Emitters
        notification.authorizeEmitter(address(clearing));
        notification.authorizeEmitter(address(governance));
        notification.authorizeEmitter(address(staking));
        notification.authorizeEmitter(address(brain));
        console.log("Notification emitters authorized");

        vm.stopBroadcast();

        console.log("=== DEPLOYMENT COMPLETE ===");
    }
}
