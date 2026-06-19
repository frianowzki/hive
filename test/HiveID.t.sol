// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/identity/HiveID.sol";

/// @dev Mock DKMS precompile — returns a deterministic 65-byte uncompressed public key
contract MockDkmsPrecompile {
    /// @dev abi.encode(executor, owner, keyIndex, keyType) → public key
    fallback(bytes calldata) external payable returns (bytes memory) {
        // Return a 65-byte uncompressed secp256k1 public key
        // 0x04 prefix + 32-byte x + 32-byte y
        return abi.encodePacked(
            hex"04",
            hex"aabbccddaabbccddaabbccddaabbccddaabbccddaabbccddaabbccddaabbccdd",
            hex"1122334411223344112233441122334411223344112233441122334411223344"
        );
    }
}

contract HiveIDTest is Test {
    HiveID public hiveID;

    // Redeclare events for vm.expectEmit (Solidity 0.8.20 doesn't support ContractName.EventName)
    event IdentityKeyDerived(bytes32 indexed usernameHash, uint256 keyIndex, bytes publicKey, uint256 timestamp);
    event KycDataStored(bytes32 indexed usernameHash, uint256 dataSize, bool piiEnabled, uint256 timestamp);
    event PiiModeUpdated(bytes32 indexed usernameHash, bool piiEnabled);

    address public owner = address(this);
    address public user1 = address(0x1001);
    address public user2 = address(0x1002);
    address public project1 = address(0x2001);
    address public investor1 = address(0x3001);
    address public hiveWallet1 = address(0xA001);
    address public hiveWallet2 = address(0xA002);
    address public hiveWalletP = address(0xA003);
    address public hiveWalletI = address(0xA004);
    address public verifier = address(0x5E01);
    address public unauthorized = address(0xBAD);

    uint256 constant REG_FEE = 0.01 ether;

    // DKMS precompile address
    address constant DKMS_ADDR = address(0x0803);

    // Expected 65-byte public key from mock
    bytes constant MOCK_PUBKEY = abi.encodePacked(
        hex"04",
        hex"aabbccddaabbccddaabbccddaabbccddaabbccddaabbccddaabbccddaabbccdd",
        hex"1122334411223344112233441122334411223344112233441122334411223344"
    );

    function setUp() public {
        // Deploy mock DKMS precompile at the precompile address
        MockDkmsPrecompile mock = new MockDkmsPrecompile();
        vm.etch(DKMS_ADDR, address(mock).code);

        hiveID = new HiveID(REG_FEE);
        hiveID.addVerifier(verifier);
    }

    // ═══ Registration ═══

    function test_register_basic() public {
        vm.deal(user1, 1 ether);
        vm.prank(user1);
        hiveID.register{value: REG_FEE}("alice", hiveWallet1, HiveID.AccountType.User, "", "");

        assertTrue(hiveID.isRegistered(user1));
        assertTrue(hiveID.isUsernameAvailable("alice") == false);

        HiveID.Identity memory id = hiveID.getIdentityByPrimary(user1);
        assertEq(id.primaryWallet, user1);
        assertEq(id.hiveWallet, hiveWallet1);
        assertEq(uint8(id.accountType), uint8(HiveID.AccountType.User));
        assertEq(uint8(id.verification), uint8(HiveID.VerificationType.None));
    }

    function test_register_project() public {
        vm.deal(project1, 1 ether);
        vm.prank(project1);
        hiveID.register{value: REG_FEE}("myprotocol", hiveWalletP, HiveID.AccountType.Project, "enc@email", "enc@twitter");

        HiveID.Identity memory id = hiveID.getIdentity("myprotocol");
        assertEq(uint8(id.accountType), uint8(HiveID.AccountType.Project));
        assertEq(id.emailEncrypted, "enc@email");
        assertEq(id.socialEncrypted, "enc@twitter");
    }

    function test_register_investor() public {
        vm.deal(investor1, 1 ether);
        vm.prank(investor1);
        hiveID.register{value: REG_FEE}("ventures", hiveWalletI, HiveID.AccountType.Investor, "", "");

        HiveID.Identity memory id = hiveID.getIdentityByHive(hiveWalletI);
        assertEq(uint8(id.accountType), uint8(HiveID.AccountType.Investor));
    }

    function test_register_revert_username_taken() public {
        vm.deal(user1, 1 ether);
        vm.deal(user2, 1 ether);

        vm.prank(user1);
        hiveID.register{value: REG_FEE}("alice", hiveWallet1, HiveID.AccountType.User, "", "");

        vm.prank(user2);
        vm.expectRevert(HiveID.UsernameTaken.selector);
        hiveID.register{value: REG_FEE}("alice", hiveWallet2, HiveID.AccountType.User, "", "");
    }

    function test_register_revert_short_username() public {
        vm.deal(user1, 1 ether);
        vm.prank(user1);
        vm.expectRevert(HiveID.UsernameInvalid.selector);
        hiveID.register{value: REG_FEE}("ab", hiveWallet1, HiveID.AccountType.User, "", "");
    }

    function test_register_revert_primary_wallet_linked() public {
        vm.deal(user1, 1 ether);
        vm.prank(user1);
        hiveID.register{value: REG_FEE}("alice", hiveWallet1, HiveID.AccountType.User, "", "");

        vm.prank(user1);
        vm.expectRevert(HiveID.PrimaryWalletLinked.selector);
        hiveID.register{value: REG_FEE}("bob", hiveWallet2, HiveID.AccountType.User, "", "");
    }

    function test_register_revert_hive_wallet_linked() public {
        vm.deal(user1, 1 ether);
        vm.deal(user2, 1 ether);

        vm.prank(user1);
        hiveID.register{value: REG_FEE}("alice", hiveWallet1, HiveID.AccountType.User, "", "");

        vm.prank(user2);
        vm.expectRevert(HiveID.HiveWalletLinked.selector);
        hiveID.register{value: REG_FEE}("bob", hiveWallet1, HiveID.AccountType.User, "", "");
    }

    function test_register_revert_insufficient_fee() public {
        vm.deal(user1, 1 ether);
        vm.prank(user1);
        vm.expectRevert(HiveID.InsufficientFee.selector);
        hiveID.register{value: 0.001 ether}("alice", hiveWallet1, HiveID.AccountType.User, "", "");
    }

    function test_register_revert_zero_hive_wallet() public {
        vm.deal(user1, 1 ether);
        vm.prank(user1);
        vm.expectRevert(HiveID.InvalidAddress.selector);
        hiveID.register{value: REG_FEE}("alice", address(0), HiveID.AccountType.User, "", "");
    }

    function test_register_refunds_excess() public {
        vm.deal(user1, 2 ether);
        uint256 balanceBefore = user1.balance;

        vm.prank(user1);
        hiveID.register{value: 1 ether}("alice", hiveWallet1, HiveID.AccountType.User, "", "");

        assertApproxEqAbs(user1.balance, balanceBefore - REG_FEE, 0.001 ether);
    }

    // ═══ Verification ═══

    function test_verify_kyc_user() public {
        _registerUser("alice", user1, hiveWallet1);

        vm.prank(verifier);
        hiveID.verify(
            keccak256(bytes("alice")),
            HiveID.VerificationType.KYC,
            keccak256(bytes("zk-proof-data"))
        );

        assertTrue(hiveID.isVerified(user1));
        HiveID.Identity memory id = hiveID.getIdentity("alice");
        assertEq(uint8(id.verification), uint8(HiveID.VerificationType.KYC));
    }

    function test_verify_kyb_project() public {
        _registerProject("myprotocol", project1, hiveWalletP);

        vm.prank(verifier);
        hiveID.verify(
            keccak256(bytes("myprotocol")),
            HiveID.VerificationType.KYB,
            keccak256(bytes("zk-proof-kyb"))
        );

        assertTrue(hiveID.isVerified(project1));
    }

    function test_verify_revert_unauthorized() public {
        _registerUser("alice", user1, hiveWallet1);

        vm.prank(unauthorized);
        vm.expectRevert("HiveID: not authorized verifier");
        hiveID.verify(
            keccak256(bytes("alice")),
            HiveID.VerificationType.KYC,
            keccak256(bytes("proof"))
        );
    }

    function test_verify_revert_user_needs_kyc_not_kyb() public {
        _registerUser("alice", user1, hiveWallet1);

        vm.prank(verifier);
        vm.expectRevert("HiveID: users require KYC");
        hiveID.verify(
            keccak256(bytes("alice")),
            HiveID.VerificationType.KYB,
            keccak256(bytes("proof"))
        );
    }

    function test_verify_revert_project_needs_kyb_not_kyc() public {
        _registerProject("myprotocol", project1, hiveWalletP);

        vm.prank(verifier);
        vm.expectRevert("HiveID: projects/investors require KYB");
        hiveID.verify(
            keccak256(bytes("myprotocol")),
            HiveID.VerificationType.KYC,
            keccak256(bytes("proof"))
        );
    }

    // ═══ Wallet Management ═══

    function test_update_hive_wallet() public {
        _registerUser("alice", user1, hiveWallet1);

        address newHive = address(0xBEEF);
        vm.prank(user1);
        hiveID.updateHiveWallet(newHive);

        HiveID.Identity memory id = hiveID.getIdentity("alice");
        assertEq(id.hiveWallet, newHive);
        assertEq(hiveID.hiveToIdentity(newHive), keccak256(bytes("alice")));
        assertEq(hiveID.hiveToIdentity(hiveWallet1), bytes32(0)); // Old unmapped
    }

    function test_update_hive_wallet_revert_linked() public {
        _registerUser("alice", user1, hiveWallet1);
        _registerUser("bob", user2, hiveWallet2);

        vm.prank(user1);
        vm.expectRevert(HiveID.HiveWalletLinked.selector);
        hiveID.updateHiveWallet(hiveWallet2);
    }

    // ═══ Transfers ═══

    function test_transfer_eth_between_hive_ids() public {
        _registerUser("alice", user1, hiveWallet1);
        _registerUser("bob", user2, hiveWallet2);
        _verifyUser("alice");

        // Fund Alice's primary wallet
        vm.deal(user1, 2 ether);

        vm.prank(user1);
        hiveID.transferETH{value: 1 ether}("bob");

        // Bob's hive wallet should have received ETH
        assertEq(hiveWallet2.balance, 1 ether);
    }

    function test_transfer_revert_not_verified() public {
        _registerUser("alice", user1, hiveWallet1);
        _registerUser("bob", user2, hiveWallet2);

        vm.deal(user1, 1 ether);
        vm.prank(user1);
        vm.expectRevert("HiveID: not verified");
        hiveID.transferETH{value: 0.5 ether}("bob");
    }

    function test_transfer_revert_not_registered() public {
        vm.deal(unauthorized, 1 ether);
        vm.prank(unauthorized);
        vm.expectRevert("HiveID: not registered");
        hiveID.transferETH{value: 0.5 ether}("alice");
    }

    // ═══ Admin ═══

    function test_add_remove_verifier() public {
        address newVerifier = address(0x999);
        hiveID.addVerifier(newVerifier);
        assertTrue(hiveID.verifiers(newVerifier));

        hiveID.removeVerifier(newVerifier);
        assertFalse(hiveID.verifiers(newVerifier));
    }

    function test_set_registration_fee() public {
        hiveID.setRegistrationFee(0.05 ether);
        assertEq(hiveID.registrationFee(), 0.05 ether);
    }

    function test_withdraw_fees() public {
        _registerUser("alice", user1, hiveWallet1);

        address treasury = address(0xFEE);
        uint256 balanceBefore = treasury.balance;

        hiveID.withdrawFees(treasury);
        assertEq(treasury.balance, balanceBefore + REG_FEE);
    }

    // ═══ View Functions ═══

    function test_is_username_available() public {
        assertTrue(hiveID.isUsernameAvailable("alice"));
        _registerUser("alice", user1, hiveWallet1);
        assertFalse(hiveID.isUsernameAvailable("alice"));
    }

    function test_get_identity_by_hive() public {
        _registerUser("alice", user1, hiveWallet1);
        HiveID.Identity memory id = hiveID.getIdentityByHive(hiveWallet1);
        assertEq(id.primaryWallet, user1);
    }

    function test_identity_count() public {
        assertEq(hiveID.identityCount(), 0);
        _registerUser("alice", user1, hiveWallet1);
        assertEq(hiveID.identityCount(), 1);
        _registerUser("bob", user2, hiveWallet2);
        assertEq(hiveID.identityCount(), 2);
    }

    // ═══ DKMS Privacy Tests ═══

    function test_derive_identity_key() public {
        _registerUser("alice", user1, hiveWallet1);
        bytes32 aliceHash = keccak256(bytes("alice"));

        // Derive DKMS key
        vm.prank(user1);
        hiveID.deriveIdentityKey(aliceHash);

        // Verify key was stored
        assertTrue(hiveID.hasDkmsKey(aliceHash));
        bytes memory pubKey = hiveID.getDkmsPublicKey(aliceHash);
        assertEq(pubKey.length, 65); // Uncompressed secp256k1

        // Verify key index
        assertEq(hiveID.dkmsKeyIndex(aliceHash), 0);
        assertEq(hiveID.getDkmsKeyIndex(aliceHash), 0);
    }

    function test_derive_identity_key_emits_event() public {
        _registerUser("alice", user1, hiveWallet1);
        bytes32 aliceHash = keccak256(bytes("alice"));

        vm.expectEmit(true, false, false, true);
        emit IdentityKeyDerived(aliceHash, 0, MOCK_PUBKEY, block.timestamp);

        vm.prank(user1);
        hiveID.deriveIdentityKey(aliceHash);
    }

    function test_derive_identity_key_revert_already_derived() public {
        _registerUser("alice", user1, hiveWallet1);
        bytes32 aliceHash = keccak256(bytes("alice"));

        vm.prank(user1);
        hiveID.deriveIdentityKey(aliceHash);

        // Second call should revert
        vm.prank(user1);
        vm.expectRevert(HiveID.KeyAlreadyDerived.selector);
        hiveID.deriveIdentityKey(aliceHash);
    }

    function test_derive_identity_key_revert_unauthorized() public {
        _registerUser("alice", user1, hiveWallet1);
        bytes32 aliceHash = keccak256(bytes("alice"));

        vm.prank(unauthorized);
        vm.expectRevert("HiveID: not identity owner");
        hiveID.deriveIdentityKey(aliceHash);
    }

    function test_rotate_identity_key() public {
        _registerUser("alice", user1, hiveWallet1);
        bytes32 aliceHash = keccak256(bytes("alice"));

        // Initial derive
        vm.prank(user1);
        hiveID.deriveIdentityKey(aliceHash);
        assertEq(hiveID.dkmsKeyIndex(aliceHash), 0);

        // Rotate to index 1
        vm.prank(user1);
        hiveID.rotateIdentityKey(aliceHash);
        assertEq(hiveID.dkmsKeyIndex(aliceHash), 1);
        assertEq(hiveID.getDkmsKeyIndex(aliceHash), 1);

        // Key should still be valid
        assertTrue(hiveID.hasDkmsKey(aliceHash));
        bytes memory pubKey = hiveID.getDkmsPublicKey(aliceHash);
        assertEq(pubKey.length, 65);
    }

    function test_store_encrypted_kyc() public {
        _registerUser("alice", user1, hiveWallet1);
        bytes32 aliceHash = keccak256(bytes("alice"));

        // Derive DKMS key first
        vm.prank(user1);
        hiveID.deriveIdentityKey(aliceHash);

        // Store encrypted KYC data
        bytes memory fakeEncryptedKyc = abi.encodePacked("encrypted-kyc-blob-data-here");
        vm.prank(user1);
        hiveID.storeEncryptedKyc(aliceHash, fakeEncryptedKyc, true);

        // Verify stored
        assertTrue(hiveID.hasEncryptedKyc(aliceHash));
        assertEq(hiveID.getEncryptedKycSize(aliceHash), fakeEncryptedKyc.length);

        // Verify PII mode
        HiveID.Identity memory id = hiveID.getIdentity("alice");
        assertTrue(id.piiEnabled);
    }

    function test_store_encrypted_kyc_emits_event() public {
        _registerUser("alice", user1, hiveWallet1);
        bytes32 aliceHash = keccak256(bytes("alice"));

        vm.prank(user1);
        hiveID.deriveIdentityKey(aliceHash);

        bytes memory fakeEncryptedKyc = abi.encodePacked("encrypted-data");
        vm.expectEmit(true, false, false, true);
        emit KycDataStored(aliceHash, fakeEncryptedKyc.length, true, block.timestamp);

        vm.prank(user1);
        hiveID.storeEncryptedKyc(aliceHash, fakeEncryptedKyc, true);
    }

    function test_store_encrypted_kyc_revert_no_dkms_key() public {
        _registerUser("alice", user1, hiveWallet1);
        bytes32 aliceHash = keccak256(bytes("alice"));

        bytes memory fakeEncryptedKyc = abi.encodePacked("encrypted-data");
        vm.prank(user1);
        vm.expectRevert(HiveID.NoDkmsKey.selector);
        hiveID.storeEncryptedKyc(aliceHash, fakeEncryptedKyc, true);
    }

    function test_store_encrypted_kyc_revert_empty_data() public {
        _registerUser("alice", user1, hiveWallet1);
        bytes32 aliceHash = keccak256(bytes("alice"));

        vm.prank(user1);
        hiveID.deriveIdentityKey(aliceHash);

        vm.prank(user1);
        vm.expectRevert(HiveID.EmptyKycData.selector);
        hiveID.storeEncryptedKyc(aliceHash, "", true);
    }

    function test_store_encrypted_kyc_revert_unauthorized() public {
        _registerUser("alice", user1, hiveWallet1);
        bytes32 aliceHash = keccak256(bytes("alice"));

        vm.prank(user1);
        hiveID.deriveIdentityKey(aliceHash);

        bytes memory fakeEncryptedKyc = abi.encodePacked("encrypted-data");
        vm.prank(unauthorized);
        vm.expectRevert("HiveID: not identity owner");
        hiveID.storeEncryptedKyc(aliceHash, fakeEncryptedKyc, true);
    }

    function test_set_pii_mode() public {
        _registerUser("alice", user1, hiveWallet1);
        bytes32 aliceHash = keccak256(bytes("alice"));

        // Initially PII disabled
        HiveID.Identity memory id = hiveID.getIdentity("alice");
        assertFalse(id.piiEnabled);

        // Enable PII
        vm.prank(user1);
        hiveID.setPiiMode(aliceHash, true);

        id = hiveID.getIdentity("alice");
        assertTrue(id.piiEnabled);

        // Disable PII
        vm.prank(user1);
        hiveID.setPiiMode(aliceHash, false);

        id = hiveID.getIdentity("alice");
        assertFalse(id.piiEnabled);
    }

    function test_set_pii_mode_emits_event() public {
        _registerUser("alice", user1, hiveWallet1);
        bytes32 aliceHash = keccak256(bytes("alice"));

        vm.expectEmit(true, false, false, false);
        emit PiiModeUpdated(aliceHash, true);

        vm.prank(user1);
        hiveID.setPiiMode(aliceHash, true);
    }

    function test_set_pii_mode_revert_unauthorized() public {
        _registerUser("alice", user1, hiveWallet1);
        bytes32 aliceHash = keccak256(bytes("alice"));

        vm.prank(unauthorized);
        vm.expectRevert("HiveID: not identity owner");
        hiveID.setPiiMode(aliceHash, true);
    }

    function test_full_privacy_flow() public {
        // 1. Register
        _registerUser("alice", user1, hiveWallet1);
        bytes32 aliceHash = keccak256(bytes("alice"));

        // 2. Derive DKMS key
        vm.prank(user1);
        hiveID.deriveIdentityKey(aliceHash);
        assertTrue(hiveID.hasDkmsKey(aliceHash));

        // 3. Store encrypted KYC with PII mode
        bytes memory encryptedKyc = abi.encodePacked(
            "ECIES-encrypted-passport-data-with-dkms-public-key"
        );
        vm.prank(user1);
        hiveID.storeEncryptedKyc(aliceHash, encryptedKyc, true);
        assertTrue(hiveID.hasEncryptedKyc(aliceHash));

        // 4. Verify KYC (via verifier)
        vm.prank(verifier);
        hiveID.verify(
            aliceHash,
            HiveID.VerificationType.KYC,
            keccak256(bytes("zk-proof-kyc"))
        );
        assertTrue(hiveID.isVerified(user1));

        // 5. Rotate DKMS key
        vm.prank(user1);
        hiveID.rotateIdentityKey(aliceHash);
        assertEq(hiveID.getDkmsKeyIndex(aliceHash), 1);

        // 6. Final state check
        HiveID.Identity memory id = hiveID.getIdentity("alice");
        assertTrue(id.exists);
        assertTrue(id.piiEnabled);
        assertTrue(id.dkmsPublicKey.length > 0);
        assertTrue(id.encryptedKycData.length > 0);
        assertEq(uint8(id.verification), uint8(HiveID.VerificationType.KYC));
    }

    // ═══ Helpers ═══

    function _registerUser(string memory username, address primary, address hiveWallet) internal {
        vm.deal(primary, 1 ether);
        vm.prank(primary);
        hiveID.register{value: REG_FEE}(username, hiveWallet, HiveID.AccountType.User, "", "");
    }

    function _registerProject(string memory username, address primary, address hiveWallet) internal {
        vm.deal(primary, 1 ether);
        vm.prank(primary);
        hiveID.register{value: REG_FEE}(username, hiveWallet, HiveID.AccountType.Project, "", "");
    }

    function _verifyUser(string memory username) internal {
        vm.prank(verifier);
        hiveID.verify(
            keccak256(bytes(username)),
            HiveID.VerificationType.KYC,
            keccak256(bytes("zk-proof"))
        );
    }
}
