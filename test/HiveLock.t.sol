// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "forge-std/Test.sol";
import "../src/vesting/HiveLock.sol";

contract MockERC20 {
    string public name;
    string public symbol;
    uint8 public decimals = 18;
    uint256 public totalSupply;
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    constructor(string memory _name, string memory _symbol) {
        name = _name;
        symbol = _symbol;
    }

    function mint(address to, uint256 amount) external {
        balanceOf[to] += amount;
        totalSupply += amount;
    }

    function approve(address spender, uint256 amount) external returns (bool) {
        allowance[msg.sender][spender] = amount;
        return true;
    }

    function transfer(address to, uint256 amount) external returns (bool) {
        require(balanceOf[msg.sender] >= amount, "insufficient");
        balanceOf[msg.sender] -= amount;
        balanceOf[to] += amount;
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        require(balanceOf[from] >= amount, "insufficient");
        require(allowance[from][msg.sender] >= amount, "not approved");
        balanceOf[from] -= amount;
        balanceOf[to] += amount;
        allowance[from][msg.sender] -= amount;
        return true;
    }
}

contract HiveLockTest is Test {
    HiveLock lock;
    MockERC20 token;
    address admin = address(0xA);
    address beneficiary = address(0xB);

    function setUp() public {
        lock = new HiveLock();
        token = new MockERC20("Hive Token", "HIVE");
        lock.addAdmin(admin);
        token.mint(address(this), 1_000_000e18);
        token.approve(address(lock), 1_000_000e18);
    }

    // ═══ LINEAR VESTING ═══

    function test_createLinear() public {
        uint256 id = lock.createLinear(beneficiary, address(token), 100_000e18, 0, 365 days, "Seed");
        assertEq(id, 0);
        assertEq(lock.scheduleCount(), 1);
        assertEq(lock.totalLocked(address(token)), 100_000e18);
    }

    function test_linearVesting_midpoint() public {
        lock.createLinear(beneficiary, address(token), 100_000e18, 0, 365 days, "Seed");
        vm.warp(block.timestamp + 182 days);
        uint256 vested = lock.getVestedAmount(0);
        assertGt(vested, 49_000e18);
        assertLt(vested, 51_000e18);
    }

    function test_linearVesting_full() public {
        lock.createLinear(beneficiary, address(token), 100_000e18, 0, 365 days, "Seed");
        vm.warp(block.timestamp + 365 days);
        assertEq(lock.getVestedAmount(0), 100_000e18);
    }

    function test_claimLinear() public {
        lock.createLinear(beneficiary, address(token), 100_000e18, 0, 365 days, "Seed");
        vm.warp(block.timestamp + 182 days);
        assertGt(lock.getClaimableAmount(0), 0);
        vm.prank(beneficiary);
        lock.claim(0);
        assertGt(token.balanceOf(beneficiary), 0);
    }

    // ═══ CLIFF LINEAR VESTING ═══

    function test_cliffLinear_beforeCliff() public {
        lock.createCliffLinear(beneficiary, address(token), 100_000e18, 0, 90 days, 365 days, 2500, "Team");
        vm.warp(block.timestamp + 30 days);
        assertEq(lock.getVestedAmount(0), 0);
    }

    function test_cliffLinear_atCliff() public {
        lock.createCliffLinear(beneficiary, address(token), 100_000e18, 0, 90 days, 365 days, 2500, "Team");
        vm.warp(block.timestamp + 90 days);
        assertEq(lock.getVestedAmount(0), 25_000e18);
    }

    function test_cliffLinear_full() public {
        lock.createCliffLinear(beneficiary, address(token), 100_000e18, 0, 90 days, 365 days, 2500, "Team");
        vm.warp(block.timestamp + 365 days);
        assertEq(lock.getVestedAmount(0), 100_000e18);
    }

    // ═══ CUSTOM VESTING ═══

    function test_createCustom() public {
        uint256 start = block.timestamp;
        HiveLock.UnlockStep[] memory steps = new HiveLock.UnlockStep[](3);
        steps[0] = HiveLock.UnlockStep({ timestamp: start + 90 days, percentage: 2000 });
        steps[1] = HiveLock.UnlockStep({ timestamp: start + 180 days, percentage: 3000 });
        steps[2] = HiveLock.UnlockStep({ timestamp: start + 365 days, percentage: 5000 });
        uint256 id = lock.createCustom(beneficiary, address(token), 100_000e18, 0, steps, "Airdrop");
        assertEq(id, 0);
    }

    function test_customPartialVest() public {
        uint256 start = block.timestamp;
        HiveLock.UnlockStep[] memory steps = new HiveLock.UnlockStep[](3);
        steps[0] = HiveLock.UnlockStep({ timestamp: start + 90 days, percentage: 2000 });
        steps[1] = HiveLock.UnlockStep({ timestamp: start + 180 days, percentage: 3000 });
        steps[2] = HiveLock.UnlockStep({ timestamp: start + 365 days, percentage: 5000 });
        lock.createCustom(beneficiary, address(token), 100_000e18, 0, steps, "Airdrop");
        vm.warp(block.timestamp + 120 days);
        assertEq(lock.getVestedAmount(0), 20_000e18);
    }

    // ═══ CANCEL ═══

    function test_cancelSchedule() public {
        lock.createLinear(beneficiary, address(token), 100_000e18, 0, 365 days, "Seed");
        vm.warp(block.timestamp + 100 days);
        lock.cancelSchedule(0);
        // Verify schedule is cancelled via getClaimableAmount returning 0
        assertEq(lock.getClaimableAmount(0), 0);
    }

    // ═══ CLAIM ALL ═══

    function test_claimAll() public {
        lock.createLinear(beneficiary, address(token), 50_000e18, 0, 365 days, "Seed");
        lock.createLinear(beneficiary, address(token), 50_000e18, 0, 365 days, "Team");
        vm.warp(block.timestamp + 182 days);
        vm.prank(beneficiary);
        lock.claimAll();
        assertGt(token.balanceOf(beneficiary), 0);
    }

    // ═══ EDGE CASES ═══

    function test_revertNonBeneficiaryClaim() public {
        lock.createLinear(beneficiary, address(token), 100_000e18, 0, 365 days, "Seed");
        vm.warp(block.timestamp + 182 days);
        vm.prank(address(0xdead));
        vm.expectRevert("HiveLock: not beneficiary");
        lock.claim(0);
    }

    function test_revertZeroAmount() public {
        vm.expectRevert("HiveLock: zero amount");
        lock.createLinear(beneficiary, address(token), 0, 0, 365 days, "Fail");
    }

    function test_revertZeroDuration() public {
        vm.expectRevert("HiveLock: zero duration");
        lock.createLinear(beneficiary, address(token), 100_000e18, 0, 0, "Fail");
    }

    function test_revertCliffTooHigh() public {
        vm.expectRevert("HiveLock: cliff max 50%");
        lock.createCliffLinear(beneficiary, address(token), 100_000e18, 0, 90 days, 365 days, 6000, "Fail");
    }

    // ═══ ADMIN ═══

    function test_addRemoveAdmin() public {
        address newAdmin = address(0xC);
        lock.addAdmin(newAdmin);
        assertTrue(lock.admins(newAdmin));
        lock.removeAdmin(newAdmin);
        assertFalse(lock.admins(newAdmin));
    }

    function test_pause() public {
        lock.pause();
        assertTrue(lock.paused());
        vm.prank(admin);
        vm.expectRevert("HiveLock: paused");
        lock.createLinear(beneficiary, address(token), 100_000e18, 0, 365 days, "Fail");
    }

    // ═══ MULTIPLE BENEFICIARIES ═══

    function test_multipleBeneficiaries() public {
        address user1 = address(0xC);
        address user2 = address(0xD);
        lock.createLinear(user1, address(token), 50_000e18, 0, 365 days, "Seed-1");
        lock.createLinear(user2, address(token), 50_000e18, 0, 365 days, "Seed-2");

        uint256[] memory ids1 = lock.getSchedules(user1);
        uint256[] memory ids2 = lock.getSchedules(user2);
        assertEq(ids1.length, 1);
        assertEq(ids2.length, 1);
    }

    function test_getTotalClaimable() public {
        lock.createLinear(beneficiary, address(token), 50_000e18, 0, 365 days, "A");
        lock.createLinear(beneficiary, address(token), 50_000e18, 0, 365 days, "B");
        vm.warp(block.timestamp + 182 days);
        uint256 total = lock.getTotalClaimable(beneficiary);
        assertGt(total, 49_000e18); // Two 50K schedules at ~50% each = ~50K total
    }
}
