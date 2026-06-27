// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/identity/HiveID.sol";

contract HiveIDTest is Test {
    HiveID public hiveID;

    address public owner = address(this);
    address public user1 = address(0x1);
    address public user2 = address(0x2);
    address public verifier = address(0x3);

    function setUp() public {
        hiveID = new HiveID(owner);
    }

    // ═══ Identity Registration Tests ═══

    function testRegisterIdentity() public {
        bytes32 zkProof = keccak256("proof-user1-18+");
        
        vm.prank(user1);
        hiveID.registerIdentity(zkProof, 1); // type = individual

        assertTrue(hiveID.isVerified(user1));
        assertEq(hiveID.getIdentityType(user1), 1);
    }

    function testRegisterOrganization() public {
        bytes32 zkProof = keccak256("proof-org-kyb");
        
        vm.prank(user2);
        hiveID.registerIdentity(zkProof, 2); // type = organization

        assertTrue(hiveID.isVerified(user2));
        assertEq(hiveID.getIdentityType(user2), 2);
    }

    function testDoubleRegister() public {
        bytes32 zkProof = keccak256("proof-user1");
        
        vm.prank(user1);
        hiveID.registerIdentity(zkProof, 1);

        vm.prank(user1);
        vm.expectRevert("ID: already registered");
        hiveID.registerIdentity(zkProof, 1);
    }

    // ═══ ZK Proof Verification Tests ═══

    function testVerifyAge() public {
        bytes32 zkProof = keccak256("proof-user1");
        vm.prank(user1);
        hiveID.registerIdentity(zkProof, 1);

        bytes32 zkProofAge = keccak256("proof-age-18+");
        vm.prank(user1);
        hiveID.verifyAttribute(zkProofAge, "age", 18);

        assertTrue(hiveID.hasAttribute(user1, "age"));
        assertEq(hiveID.getAttributeValue(user1, "age"), 18);
    }

    function testVerifyCountry() public {
        bytes32 zkProof = keccak256("proof-user1");
        vm.prank(user1);
        hiveID.registerIdentity(zkProof, 1);

        bytes32 zkProofCountry = keccak256("proof-country-US");
        vm.prank(user1);
        hiveID.verifyAttribute(zkProofCountry, "country", 840); // 840 = US

        assertTrue(hiveID.hasAttribute(user1, "country"));
        assertEq(hiveID.getAttributeValue(user1, "country"), 840);
    }

    function testVerifyAccredited() public {
        bytes32 zkProof = keccak256("proof-user1");
        vm.prank(user1);
        hiveID.registerIdentity(zkProof, 1);

        bytes32 zkProofAccredited = keccak256("proof-accredited");
        vm.prank(user1);
        hiveID.verifyAttribute(zkProofAccredited, "accredited", 1);

        assertTrue(hiveID.hasAttribute(user1, "accredited"));
        assertEq(hiveID.getAttributeValue(user1, "accredited"), 1);
    }

    // ═══ Access Control Tests ═══

    function testOnlyVerifiedCanParticipate() public {
        // Unverified user can't participate
        assertFalse(hiveID.isVerified(user1));
        
        // Register and verify
        bytes32 zkProof = keccak256("proof-user1");
        vm.prank(user1);
        hiveID.registerIdentity(zkProof, 1);
        
        assertTrue(hiveID.isVerified(user1));
    }

    function testRevocation() public {
        bytes32 zkProof = keccak256("proof-user1");
        
        vm.prank(user1);
        hiveID.registerIdentity(zkProof, 1);
        assertTrue(hiveID.isVerified(user1));

        // Owner revokes
        hiveID.revokeIdentity(user1);
        assertFalse(hiveID.isVerified(user1));
    }

    function testOnlyOwnerRevoke() public {
        vm.prank(user1);
        vm.expectRevert("ID: not owner");
        hiveID.revokeIdentity(user2);
    }

    // ═══ Privacy Tests ═══

    function testPrivateAttributes() public {
        bytes32 zkProof = keccak256("proof-user1");
        
        vm.prank(user1);
        hiveID.registerIdentity(zkProof, 1);

        // Attributes are private — only user can read their own
        vm.prank(user1);
        uint256 value = hiveID.getMyAttribute("age");
        assertEq(value, 0); // not set yet

        vm.prank(user1);
        hiveID.verifyAttribute(keccak256("proof-age"), "age", 25);

        vm.prank(user1);
        value = hiveID.getMyAttribute("age");
        assertEq(value, 25);
    }

    // ═══ Stats Tests ═══

    function testStats() public {
        bytes32 proof1 = keccak256("proof-user1");
        bytes32 proof2 = keccak256("proof-user2");
        
        vm.prank(user1);
        hiveID.registerIdentity(proof1, 1);
        
        vm.prank(user2);
        hiveID.registerIdentity(proof2, 2);

        (uint256 total, uint256 individuals, uint256 orgs) = hiveID.getStats();
        assertEq(total, 2);
        assertEq(individuals, 1);
        assertEq(orgs, 1);
    }
}
