// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/privacy/HiveDKMS.sol";

contract HiveDKMSTest is Test {
    HiveDKMS public dkms;

    address public owner = address(this);
    address public user1 = address(0x1);
    address public user2 = address(0x2);

    function setUp() public {
        dkms = new HiveDKMS(owner);
    }

    // ═══ Key Management Tests ═══

    function testDeriveKey() public {
        uint256 keyIndex = dkms.deriveKey(user1, "hive-identity");
        assertTrue(keyIndex > 0); // hash-based fallback returns non-zero

        // Same params = same index
        uint256 keyIndex2 = dkms.deriveKey(user1, "hive-identity");
        assertEq(keyIndex, keyIndex2);
    }

    function testMultipleKeys() public {
        uint256 idx1 = dkms.deriveKey(user1, "hive-identity");
        uint256 idx2 = dkms.deriveKey(user1, "hive-treasury");
        uint256 idx3 = dkms.deriveKey(user2, "hive-identity");

        assertTrue(idx1 != idx2);
        assertTrue(idx1 != idx3);
    }

    // ═══ Encrypted Storage Tests ═══

    function testStoreEncrypted() public {
        bytes memory data = "sensitive KYC data";
        bytes memory encrypted = abi.encodePacked(data); // mock encryption

        dkms.storeEncrypted(user1, "kyc", encrypted);

        bytes memory stored = dkms.getEncrypted(user1, "kyc");
        assertEq(stored.length, encrypted.length);
    }

    function testMultipleDataSlots() public {
        dkms.storeEncrypted(user1, "kyc", bytes("kyc-data"));
        dkms.storeEncrypted(user1, "portfolio", bytes("portfolio-data"));
        dkms.storeEncrypted(user1, "strategy", bytes("strategy-data"));

        assertEq(dkms.getEncrypted(user1, "kyc").length, 8);
        assertEq(dkms.getEncrypted(user1, "portfolio").length, 14);
        assertEq(dkms.getEncrypted(user1, "strategy").length, 13);
    }

    function testOverwriteEncrypted() public {
        dkms.storeEncrypted(user1, "kyc", bytes("old-data"));
        dkms.storeEncrypted(user1, "kyc", bytes("new-data-longer"));

        bytes memory stored = dkms.getEncrypted(user1, "kyc");
        assertEq(stored.length, 15); // "new-data-longer"
    }

    // ═══ Access Control Tests ═══

    function testOnlyOwnerStore() public {
        vm.prank(user1);
        vm.expectRevert("DKMS: not owner");
        dkms.storeEncrypted(user1, "kyc", bytes("data"));
    }

    function testGetDataSlots() public {
        dkms.storeEncrypted(user1, "kyc", bytes("kyc-data"));
        dkms.storeEncrypted(user1, "portfolio", bytes("portfolio-data"));

        string[] memory slots = dkms.getDataSlots(user1);
        assertEq(slots.length, 2);
        assertEq(slots[0], "kyc");
        assertEq(slots[1], "portfolio");
    }

    // ═══ Key Rotation Tests ═══

    function testRotateKey() public {
        uint256 oldIdx = dkms.deriveKey(user1, "hive-identity");
        dkms.rotateKey(user1, "hive-identity");
        
        // After rotation, the key index has changed
        uint256 rotatedIdx = dkms.keyIndices(user1, "hive-identity");
        assertTrue(rotatedIdx != oldIdx);
        assertEq(dkms.keyRotations(user1, "hive-identity"), 1);
    }

    function testOnlyOwnerRotate() public {
        vm.prank(user1);
        vm.expectRevert("DKMS: not owner");
        dkms.rotateKey(user1, "hive-identity");
    }
}
