// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/identity/HiveID.sol";

contract HiveIDTest is Test {
    HiveID public hiveID;

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

    function setUp() public {
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
