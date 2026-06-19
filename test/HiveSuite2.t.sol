// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/verifier/HiveVerifier.sol";
import "../src/relayer/HiveRelayer.sol";
import "../src/oracle/HiveOracle.sol";
import "../src/token/HiveToken.sol";
import "../src/factory/HiveFactory.sol";
import "../src/identity/HiveID.sol";
import "../src/reputation/HiveReputation.sol";
import "../src/referral/HiveReferral.sol";
import "../src/portfolio/HivePortfolio.sol";

// ═══════════════════════════════════════════════
// HiveVerifier Tests
// ═══════════════════════════════════════════════

contract HiveVerifierTest is Test {
    HiveVerifier verifier;
    bytes32 userHash = keccak256(bytes("alice"));
    address authVerifier = address(0x5E01);

    function setUp() public {
        verifier = new HiveVerifier();
        verifier.authorizeVerifier(authVerifier);
        verifier.authorizeVerifier(address(verifier)); // For batch self-calls
    }

    function test_verify_proof() public {
        bytes memory proof = bytes("zk-proof-data");
        bytes32 nullifier = keccak256(bytes("nullifier-1"));

        vm.prank(authVerifier);
        verifier.verifyProof(
            userHash,
            HiveVerifier.ProofType.KYC_IDENTITY,
            proof,
            bytes(""),
            nullifier
        );

        assertTrue(verifier.isProofValid(userHash, HiveVerifier.ProofType.KYC_IDENTITY));
        assertTrue(verifier.usedNullifiers(nullifier));
    }

    function test_verify_batch() public {
        HiveVerifier.ProofType[] memory types = new HiveVerifier.ProofType[](2);
        types[0] = HiveVerifier.ProofType.KYC_AGE;
        types[1] = HiveVerifier.ProofType.KYC_IDENTITY;

        bytes[] memory proofs = new bytes[](2);
        proofs[0] = bytes("proof-age");
        proofs[1] = bytes("proof-identity");

        bytes[] memory signals = new bytes[](2);
        signals[0] = bytes("");
        signals[1] = bytes("");

        bytes32[] memory nullifiers = new bytes32[](2);
        nullifiers[0] = keccak256(bytes("n1"));
        nullifiers[1] = keccak256(bytes("n2"));

        vm.prank(authVerifier);
        verifier.verifyBatch(userHash, types, proofs, signals, nullifiers);

        assertTrue(verifier.isProofValid(userHash, HiveVerifier.ProofType.KYC_AGE));
        assertTrue(verifier.isProofValid(userHash, HiveVerifier.ProofType.KYC_IDENTITY));
    }

    function test_has_valid_kyc() public {
        assertFalse(verifier.hasValidKYC(userHash));

        vm.prank(authVerifier);
        verifier.verifyProof(userHash, HiveVerifier.ProofType.KYC_AGE, bytes("p"), bytes(""), keccak256(bytes("n1")));

        assertFalse(verifier.hasValidKYC(userHash)); // Need both AGE + IDENTITY

        vm.prank(authVerifier);
        verifier.verifyProof(userHash, HiveVerifier.ProofType.KYC_IDENTITY, bytes("p"), bytes(""), keccak256(bytes("n2")));

        assertTrue(verifier.hasValidKYC(userHash));
    }

    function test_revert_nullifier_replay() public {
        bytes32 nullifier = keccak256(bytes("same"));

        vm.prank(authVerifier);
        verifier.verifyProof(userHash, HiveVerifier.ProofType.KYC_AGE, bytes("p"), bytes(""), nullifier);

        vm.prank(authVerifier);
        vm.expectRevert(HiveVerifier.NullifierUsed.selector);
        verifier.verifyProof(userHash, HiveVerifier.ProofType.KYC_COUNTRY, bytes("p"), bytes(""), nullifier);
    }

    function test_revoke_proof() public {
        vm.prank(authVerifier);
        verifier.verifyProof(userHash, HiveVerifier.ProofType.KYC_AGE, bytes("p"), bytes(""), keccak256(bytes("n")));

        verifier.revokeProof(userHash, HiveVerifier.ProofType.KYC_AGE);
        assertFalse(verifier.isProofValid(userHash, HiveVerifier.ProofType.KYC_AGE));
    }

    function test_revert_unauthorized() public {
        vm.prank(address(0xBAD));
        vm.expectRevert(HiveVerifier.NotAuthorized.selector);
        verifier.verifyProof(userHash, HiveVerifier.ProofType.KYC_AGE, bytes("p"), bytes(""), keccak256(bytes("n")));
    }

    function test_get_verified_types() public {
        vm.prank(authVerifier);
        verifier.verifyProof(userHash, HiveVerifier.ProofType.KYC_AGE, bytes("p"), bytes(""), keccak256(bytes("n1")));
        vm.prank(authVerifier);
        verifier.verifyProof(userHash, HiveVerifier.ProofType.KYC_IDENTITY, bytes("p"), bytes(""), keccak256(bytes("n2")));

        uint8[] memory types = verifier.getVerifiedTypes(userHash);
        assertEq(types.length, 2);
    }
}

// ═══════════════════════════════════════════════
// HiveRelayer Tests
// ═══════════════════════════════════════════════

contract HiveRelayerTest is Test {
    HiveRelayer relayer;
    address primaryWallet = address(0x1);
    address hiveWallet = address(0x2);
    address recipient = address(0x3);

    function setUp() public {
        relayer = new HiveRelayer();
        vm.deal(address(relayer), 10 ether);
    }

    function test_get_nonce() public {
        assertEq(relayer.getNonce(primaryWallet), 0);
    }

    function test_encode_erc20_transfer() public {
        address token = address(0xA);
        bytes memory data = relayer.encodeERC20Transfer(token, recipient, 100e18);
        assertTrue(data.length > 0);
    }

    function test_encode_erc20_approve() public {
        address token = address(0xA);
        bytes memory data = relayer.encodeERC20Approve(token, recipient, 100e18);
        assertTrue(data.length > 0);
    }

    function test_set_paused() public {
        relayer.setPaused(true);
        assertTrue(relayer.paused());
    }

    function test_set_relay_fee() public {
        relayer.setRelayFee(50);
        assertEq(relayer.relayFeeBps(), 50);
    }

    function test_revert_not_owner() public {
        vm.prank(address(0xBAD));
        vm.expectRevert("Relayer: not owner");
        relayer.setPaused(true);
    }
}

// ═══════════════════════════════════════════════
// HiveOracle Tests
// ═══════════════════════════════════════════════

contract HiveOracleTest is Test {
    HiveOracle oracle;
    address tokenA = address(0xA);
    address tokenB = address(0xB);

    function setUp() public {
        oracle = new HiveOracle();
        oracle.addToken(tokenA, "ETH", "ethereum", 18);
        oracle.addToken(tokenB, "USDC", "usd-coin", 6);
    }

    function test_add_token() public {
        address tokenC = address(0xC);
        oracle.addToken(tokenC, "BTC", "bitcoin", 8);

        (, string memory symbol, , bool active) = oracle.tokenConfigs(tokenC);
        assertEq(symbol, "BTC");
        
        assertTrue(active);
    }

    function test_update_price() public {
        oracle.updatePrice(tokenA, 2000e8, "manual");

        (uint256 price, bool stale) = oracle.getPriceSafe(tokenA);
        assertEq(price, 2000e8);
        assertFalse(stale);
    }

    function test_batch_update() public {
        address[] memory tokens = new address[](2);
        tokens[0] = tokenA;
        tokens[1] = tokenB;

        uint256[] memory prices = new uint256[](2);
        prices[0] = 2000e8;
        prices[1] = 1e8;

        oracle.updatePrices(tokens, prices, "batch");

        assertEq(oracle.getPrice(tokenA), 2000e8);
        assertEq(oracle.getPrice(tokenB), 1e8);
    }

    function test_price_staleness() public {
        oracle.updatePrice(tokenA, 2000e8, "manual");

        // Fast forward past staleness threshold
        vm.warp(block.timestamp + 2 hours);

        (uint256 price, bool stale) = oracle.getPriceSafe(tokenA);
        assertEq(price, 2000e8);
        assertTrue(stale);
    }

    function test_revert_stale_price() public {
        oracle.updatePrice(tokenA, 2000e8, "manual");
        vm.warp(block.timestamp + 2 hours);

        vm.expectRevert(HiveOracle.PriceStale.selector);
        oracle.getPrice(tokenA);
    }

    function test_token_to_usd() public {
        oracle.updatePrice(tokenA, 2000e8, "manual");

        // 1 ETH = $2000
        uint256 usd = oracle.tokenToUSD(tokenA, 1e18);
        assertEq(usd, 2000e8);
    }

    function test_usd_to_token() public {
        oracle.updatePrice(tokenA, 2000e8, "manual");

        // $2000 = 1 ETH
        uint256 tokenAmount = oracle.usdToToken(tokenA, 2000e8);
        assertEq(tokenAmount, 1e18);
    }

    function test_remove_token() public {
        oracle.removeToken(tokenA);

        (, , , bool active2) = oracle.tokenConfigs(tokenA);
        assertFalse(active2);
    }

    function test_get_tracked_tokens() public {
        address[] memory tokens = oracle.getTrackedTokens();
        assertEq(tokens.length, 2);
        assertEq(tokens[0], tokenA);
        assertEq(tokens[1], tokenB);
    }
}

// ═══════════════════════════════════════════════
// HiveToken Tests
// ═══════════════════════════════════════════════

contract HiveTokenTest is Test {
    HiveToken token;
    address project = address(0x1);
    address user1 = address(0x2);
    address user2 = address(0x3);
    bytes32 projectId = keccak256(bytes("myproject"));

    function setUp() public {
        token = new HiveToken("Hive Token", "HIVE", 18, project, projectId, "https://hive.xyz/meta");
        vm.prank(project);
        token.mint(project, 1000e18);
    }

    function test_basic_erc20() public {
        assertEq(token.name(), "Hive Token");
        assertEq(token.symbol(), "HIVE");
        assertEq(token.decimals(), 18);
        assertEq(token.totalSupply(), 1000e18);
        assertEq(token.balanceOf(project), 1000e18);
    }

    function test_transfer() public {
        // Transfer mode is LAUNCHPAD_ONLY, project can transfer
        vm.prank(project);
        token.transfer(user1, 100e18);

        assertEq(token.balanceOf(user1), 100e18);
        assertEq(token.balanceOf(project), 900e18);
    }

    function test_approve_and_transferFrom() public {
        vm.prank(project);
        token.approve(user1, 500e18);

        vm.prank(user1);
        token.transferFrom(project, user2, 200e18);

        assertEq(token.balanceOf(user2), 200e18);
    }

    function test_mint() public {
        vm.prank(project);
        token.mint(user1, 500e18);

        assertEq(token.balanceOf(user1), 500e18);
        assertEq(token.totalSupply(), 1500e18);
    }

    function test_revert_max_supply() public {
        vm.prank(project);
        vm.expectRevert(HiveToken.MaxSupplyExceeded.selector);
        token.mint(user1, 2_000_000_000e18); // Exceeds 1B max
    }

    function test_transfer_restriction() public {
        // LAUNCHPAD_ONLY mode — non-whitelisted can't transfer
        vm.prank(project);
        token.transfer(user1, 100e18);

        vm.startPrank(user1);
        vm.expectRevert(HiveToken.TransferRestricted.selector);
        token.transfer(user2, 50e18);
        vm.stopPrank();
    }

    function test_set_transfer_mode() public {
        vm.prank(project);
        token.setTransferMode(HiveToken.TransferMode.OPEN);

        vm.prank(project);
        token.transfer(user1, 100e18);

        vm.prank(user1);
        token.transfer(user2, 50e18); // Now works

        assertEq(token.balanceOf(user2), 50e18);
    }

    function test_whitelist_mode() public {
        vm.startPrank(project);
        token.setTransferMode(HiveToken.TransferMode.WHITELIST_ONLY);
        token.setWhitelist(project, true);
        token.setWhitelist(user1, true);
        token.setWhitelist(user2, true);
        token.transfer(user1, 100e18);
        vm.stopPrank();

        vm.prank(project);
        token.transfer(user1, 100e18);

        vm.prank(user1);
        token.transfer(user2, 50e18); // Both whitelisted

        assertEq(token.balanceOf(user2), 50e18);
    }

    function test_vesting() public {
        vm.prank(project);
        token.createVesting(user1, 100e18, 30 days, 365 days, 1 days);

        // Before cliff — nothing claimable
        assertEq(token.claimableVesting(user1), 0);

        // After cliff
        vm.warp(block.timestamp + 31 days);
        uint256 claimable = token.claimableVesting(user1);
        assertGt(claimable, 0);

        vm.prank(user1);
        token.releaseVesting();
        assertEq(token.balanceOf(user1), claimable);
    }

    function test_set_minter() public {
        vm.prank(project);
        token.setMinter(address(0xCAFE));

        vm.prank(address(0xCAFE));
        token.mint(user1, 100e18);

        assertEq(token.balanceOf(user1), 100e18);
    }

    function test_revoke() public {
        vm.prank(project);
        token.revoke();

        vm.prank(project);
        vm.expectRevert(HiveToken.TokenIsRevoked.selector);
        token.transfer(user1, 100e18);
    }

    function test_transfer_ownership() public {
        vm.prank(project);
        token.transferOwnership(user1);

        assertEq(token.owner(), user1);
    }
}

// ═══════════════════════════════════════════════
// HiveFactory Tests
// ═══════════════════════════════════════════════

contract HiveFactoryTest is Test {
    HiveFactory factory;
    HiveID hiveID;
    HiveVerifier verifier;
    HiveReputation reputation;
    HiveOracle oracle;
    HiveReferral referral;
    HivePortfolio portfolio;
    HiveRelayer relayer;

    address owner = address(this);
    address user1 = address(0x1);
    address hiveWallet1 = address(0xA1);

    function setUp() public {
        // Deploy all modules — factory must be HiveID owner for addVerifier
        hiveID = new HiveID(0.01 ether);
        verifier = new HiveVerifier();
        reputation = new HiveReputation();
        oracle = new HiveOracle();
        referral = new HiveReferral();
        portfolio = new HivePortfolio();
        relayer = new HiveRelayer();

        // Deploy factory
        factory = new HiveFactory();

        // Pre-authorize verifier in HiveID (factory can't do this unless it's owner)
        hiveID.addVerifier(address(verifier));

        // Authorize factory to record reputation activities
        reputation.authorize(address(factory));

        // Initialize
        factory.initialize(
            address(hiveID),
            address(verifier),
            address(reputation),
            address(oracle),
            address(referral),
            address(portfolio),
            address(relayer)
        );
    }

    function test_initialize() public {
        assertTrue(factory.initialized());

        (address[7] memory modules, bool init) = factory.getSystemInfo();
        assertTrue(init);
        assertEq(modules[0], address(hiveID));
        assertEq(modules[1], address(verifier));
    }

    function test_revert_double_init() public {
        vm.expectRevert("Factory: already initialized");
        factory.initialize(
            address(hiveID), address(verifier), address(reputation),
            address(oracle), address(referral), address(portfolio), address(relayer)
        );
    }

    function test_register_with_referral() public {
        // User registers on HiveID first
        vm.deal(user1, 1 ether);
        vm.prank(user1);
        hiveID.register{value: 0.01 ether}("alice", hiveWallet1, HiveID.AccountType.User, "", "");

        // Then complete onboarding via factory
        bytes32 usernameHash = keccak256(bytes("alice"));
        vm.prank(user1);
        factory.completeOnboarding(usernameHash, "alice", bytes32(0));

        assertTrue(hiveID.isRegistered(user1));
        HiveReputation.ReputationScore memory score = reputation.getScore(usernameHash);
        assertEq(score.totalScore, 100); // Early adopter bonus
    }

    function test_update_module() public {
        address newVerifier = address(0x9E99);
        factory.updateModule("verifier", newVerifier);

        (address[7] memory modules, ) = factory.getSystemInfo();
        assertEq(modules[1], newVerifier);
    }

    function test_transfer_ownership() public {
        factory.transferOwnership(user1);
        assertEq(factory.owner(), user1);
    }
}
