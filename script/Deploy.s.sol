// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "forge-std/Script.sol";
import "../src/identity/HiveID.sol";
import "../src/agent/HiveAgent.sol";
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
import "../src/brain/HiveBrain.sol";
import "../src/treasury/HiveTreasury.sol";
import "../src/governance/HiveGovernance.sol";
import "../src/staking/HiveStaking.sol";
import "../src/notification/HiveNotification.sol";

/**
 * @title DeployHive
 * @notice Deploy all Hive contracts to Ritual Testnet
 * @dev Run with: forge script script/Deploy.s.sol --rpc-url ritual_testnet --broadcast --verify
 */
contract DeployHive is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        vm.startBroadcast(deployerPrivateKey);

        // ═══ Phase 1: Core Infrastructure ═══

        // 1. HiveID — On-chain identity
        HiveID hiveID = new HiveID();
        console.log("HiveID deployed at:", address(hiveID));

        // 2. HiveMultiSig — Multi-sig wallet
        address[] memory signers = new address[](1);
        signers[0] = deployer;
        HiveMultiSig multiSig = new HiveMultiSig(signers, 1);
        console.log("HiveMultiSig deployed at:", address(multiSig));

        // 3. HiveVerifier — ZK proof verifier
        HiveVerifier verifier = new HiveVerifier();
        console.log("HiveVerifier deployed at:", address(verifier));

        // 4. HiveRelayer — Meta-tx relayer
        HiveRelayer relayer = new HiveRelayer();
        console.log("HiveRelayer deployed at:", address(relayer));

        // ═══ Phase 2: Financial Infrastructure ═══

        // 5. HiveOracle — Price feeds
        HiveOracle oracle = new HiveOracle();
        console.log("HiveOracle deployed at:", address(oracle));

        // 6. HiveStaking — Staking
        HiveStaking staking = new HiveStaking();
        console.log("HiveStaking deployed at:", address(staking));

        // 7. HiveTreasury — Fee collector
        HiveTreasury treasury = new HiveTreasury(address(multiSig));
        console.log("HiveTreasury deployed at:", address(treasury));

        // 8. HiveReputation — Scoring
        HiveReputation reputation = new HiveReputation();
        console.log("HiveReputation deployed at:", address(reputation));

        // 9. HiveReferral — Referral engine
        HiveReferral referral = new HiveReferral();
        console.log("HiveReferral deployed at:", address(referral));

        // ═══ Phase 3: Trading Infrastructure ═══

        // 10. HiveClearing — CCA auction
        HiveClearing clearing = new HiveClearing();
        console.log("HiveClearing deployed at:", address(clearing));

        // 11. HivePortfolio — Portfolio management
        HivePortfolio portfolio = new HivePortfolio();
        console.log("HivePortfolio deployed at:", address(portfolio));

        // 12. HiveAutoStrategy — DCA/TP/SL
        HiveAutoStrategy strategy = new HiveAutoStrategy();
        console.log("HiveAutoStrategy deployed at:", address(strategy));

        // 13. HiveToken — ERC20 standard
        HiveToken token = new HiveToken("Hive Token", "HIVE", deployer);
        console.log("HiveToken deployed at:", address(token));

        // ═══ Phase 4: AI & Communication ═══

        // 14. HiveAgent — AI Agent Gateway
        HiveAgent agent = new HiveAgent();
        console.log("HiveAgent deployed at:", address(agent));

        // 15. HiveBrain — Enhanced agent brain
        HiveBrain brain = new HiveBrain();
        console.log("HiveBrain deployed at:", address(brain));

        // 16. HiveChat — Encrypted messaging
        HiveChat chat = new HiveChat();
        console.log("HiveChat deployed at:", address(chat));

        // ═══ Phase 5: Governance ═══

        // 17. HiveGovernance — DAO voting
        HiveGovernance governance = new HiveGovernance(address(staking), address(multiSig));
        console.log("HiveGovernance deployed at:", address(governance));

        // 18. HiveNotification — Event notifications
        HiveNotification notification = new HiveNotification(address(hiveID));
        console.log("HiveNotification deployed at:", address(notification));

        // ═══ Phase 6: Factory (Master Wiring) ═══

        // 19. HiveFactory — Master wiring
        HiveFactory factory = new HiveFactory();
        console.log("HiveFactory deployed at:", address(factory));

        // ═══ Initialize Factory ═══
        factory.initialize(
            address(hiveID),
            address(clearing),
            address(reputation),
            address(referral),
            address(portfolio),
            address(verifier),
            address(treasury),
            address(multiSig)
        );
        console.log("HiveFactory initialized");

        // ═══ Authorize Emitters ═══
        notification.authorizeEmitter(address(clearing));
        notification.authorizeEmitter(address(governance));
        notification.authorizeEmitter(address(staking));
        notification.authorizeEmitter(address(brain));
        console.log("Notification emitters authorized");

        vm.stopBroadcast();

        // ═══ Output Summary ═══
        console.log("\n═══════════════════════════════════════════");
        console.log("HIVE DEPLOYMENT COMPLETE — Ritual Testnet");
        console.log("═══════════════════════════════════════════");
        console.log("HiveID:", address(hiveID));
        console.log("HiveMultiSig:", address(multiSig));
        console.log("HiveVerifier:", address(verifier));
        console.log("HiveRelayer:", address(relayer));
        console.log("HiveOracle:", address(oracle));
        console.log("HiveStaking:", address(staking));
        console.log("HiveTreasury:", address(treasury));
        console.log("HiveReputation:", address(reputation));
        console.log("HiveReferral:", address(referral));
        console.log("HiveClearing:", address(clearing));
        console.log("HivePortfolio:", address(portfolio));
        console.log("HiveAutoStrategy:", address(strategy));
        console.log("HiveToken:", address(token));
        console.log("HiveAgent:", address(agent));
        console.log("HiveBrain:", address(brain));
        console.log("HiveChat:", address(chat));
        console.log("HiveGovernance:", address(governance));
        console.log("HiveNotification:", address(notification));
        console.log("HiveFactory:", address(factory));
        console.log("═══════════════════════════════════════════");
    }
}
