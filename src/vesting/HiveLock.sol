// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

/**
 * @title HiveLock
 * @notice Token vesting & lock manager for Hive platform
 * @dev Supports Linear, Cliff+Linear, and Custom vesting schedules
 * @author Hive Team
 */

interface IERC20 {
    function balanceOf(address) external view returns (uint256);
    function transfer(address, uint256) external returns (bool);
    function transferFrom(address, address, uint256) external returns (bool);
}

contract HiveLock {
    // ═══════════════════════════════════════════════════════════════
    //                           STATE
    // ═══════════════════════════════════════════════════════════════

    address public owner;
    bool public paused;

    /// @notice Vesting schedule types
    enum VestingType {
        LINEAR,          // Linear release over duration
        CLIFF_LINEAR,    // Cliff period, then linear
        CUSTOM           // Custom unlock steps
    }

    /// @notice A single vesting schedule
    struct VestingSchedule {
        address beneficiary;      // Who receives tokens
        address token;            // ERC20 token address
        uint256 totalAmount;      // Total tokens locked
        uint256 claimedAmount;    // Tokens already claimed
        uint256 startTime;        // When vesting starts
        uint256 cliffDuration;    // Cliff period (seconds)
        uint256 vestingDuration;  // Total vesting period (seconds)
        uint256 unlockPercentage; // % unlocked at cliff (for CLIFF_LINEAR, basis points)
        VestingType vestingType;
        bool cancelled;           // If schedule was cancelled
        string label;             // Optional label (e.g., "Seed", "Team", "Airdrop")
    }

    /// @notice Custom unlock step
    struct UnlockStep {
        uint256 timestamp;    // When this step unlocks
        uint256 percentage;   // % of total (basis points, 10000 = 100%)
    }

    /// @notice scheduleId => VestingSchedule
    mapping(uint256 => VestingSchedule) public schedules;

    /// @notice scheduleId => custom unlock steps (only for CUSTOM type)
    mapping(uint256 => UnlockStep[]) public customSteps;

    /// @notice Total number of schedules created
    uint256 public scheduleCount;

    /// @notice beneficiary => list of schedule IDs
    mapping(address => uint256[]) public beneficiarySchedules;

    /// @notice Total locked per token
    mapping(address => uint256) public totalLocked;

    /// @notice Total claimed per token
    mapping(address => uint256) public totalClaimed;

    /// @notice Admin list
    mapping(address => bool) public admins;

    // ═══════════════════════════════════════════════════════════════
    //                          EVENTS
    // ═══════════════════════════════════════════════════════════════

    event ScheduleCreated(
        uint256 indexed scheduleId,
        address indexed beneficiary,
        address indexed token,
        uint256 totalAmount,
        VestingType vestingType,
        string label
    );
    event TokensClaimed(
        uint256 indexed scheduleId,
        address indexed beneficiary,
        uint256 amount
    );
    event ScheduleCancelled(
        uint256 indexed scheduleId,
        uint256 refundedAmount
    );
    event Paused(address indexed by);
    event Unpaused(address indexed by);

    // ═══════════════════════════════════════════════════════════════
    //                         MODIFIERS
    // ═══════════════════════════════════════════════════════════════

    uint256 private _reentrancyStatus;

    modifier onlyOwner() {
        require(msg.sender == owner, "HiveLock: not owner");
        _;
    }

    modifier onlyAdmin() {
        require(msg.sender == owner || admins[msg.sender], "HiveLock: not admin");
        _;
    }

    modifier whenNotPaused() {
        require(!paused, "HiveLock: paused");
        _;
    }

    modifier nonReentrant() {
        require(_reentrancyStatus != 1, "HiveLock: reentrant");
        _reentrancyStatus = 1;
        _;
        _reentrancyStatus = 0;
    }

    // ═══════════════════════════════════════════════════════════════
    //                        CONSTRUCTOR
    // ═══════════════════════════════════════════════════════════════

    constructor() {
        owner = msg.sender;
        admins[msg.sender] = true;
    }

    // ═══════════════════════════════════════════════════════════════
    //                    CREATE VESTING SCHEDULE
    // ═══════════════════════════════════════════════════════════════

    /// @notice Create a LINEAR vesting schedule
    function createLinear(
        address beneficiary,
        address token,
        uint256 amount,
        uint256 startTime,
        uint256 duration,
        string calldata label
    ) external onlyAdmin whenNotPaused returns (uint256) {
        require(beneficiary != address(0), "HiveLock: zero beneficiary");
        require(token != address(0), "HiveLock: zero token");
        require(amount > 0, "HiveLock: zero amount");
        require(duration > 0, "HiveLock: zero duration");

        // Transfer tokens to contract
        require(
            IERC20(token).transferFrom(msg.sender, address(this), amount),
            "HiveLock: transfer failed"
        );

        uint256 id = scheduleCount++;
        schedules[id] = VestingSchedule({
            beneficiary: beneficiary,
            token: token,
            totalAmount: amount,
            claimedAmount: 0,
            startTime: startTime == 0 ? block.timestamp : startTime,
            cliffDuration: 0,
            vestingDuration: duration,
            unlockPercentage: 0,
            vestingType: VestingType.LINEAR,
            cancelled: false,
            label: label
        });

        beneficiarySchedules[beneficiary].push(id);
        totalLocked[token] += amount;

        emit ScheduleCreated(id, beneficiary, token, amount, VestingType.LINEAR, label);
        return id;
    }

    /// @notice Create a CLIFF_LINEAR vesting schedule
    function createCliffLinear(
        address beneficiary,
        address token,
        uint256 amount,
        uint256 startTime,
        uint256 cliffDuration,
        uint256 vestingDuration,
        uint256 cliffPercentageBps,
        string calldata label
    ) external onlyAdmin whenNotPaused returns (uint256) {
        require(beneficiary != address(0), "HiveLock: zero beneficiary");
        require(token != address(0), "HiveLock: zero token");
        require(amount > 0, "HiveLock: zero amount");
        require(cliffPercentageBps <= 5000, "HiveLock: cliff max 50%");
        require(vestingDuration > cliffDuration, "HiveLock: duration < cliff");

        require(
            IERC20(token).transferFrom(msg.sender, address(this), amount),
            "HiveLock: transfer failed"
        );

        uint256 id = scheduleCount++;
        schedules[id] = VestingSchedule({
            beneficiary: beneficiary,
            token: token,
            totalAmount: amount,
            claimedAmount: 0,
            startTime: startTime == 0 ? block.timestamp : startTime,
            cliffDuration: cliffDuration,
            vestingDuration: vestingDuration,
            unlockPercentage: cliffPercentageBps,
            vestingType: VestingType.CLIFF_LINEAR,
            cancelled: false,
            label: label
        });

        beneficiarySchedules[beneficiary].push(id);
        totalLocked[token] += amount;

        emit ScheduleCreated(id, beneficiary, token, amount, VestingType.CLIFF_LINEAR, label);
        return id;
    }

    /// @notice Create a CUSTOM vesting schedule with discrete unlock steps
    function createCustom(
        address beneficiary,
        address token,
        uint256 amount,
        uint256 startTime,
        UnlockStep[] calldata steps,
        string calldata label
    ) external onlyAdmin whenNotPaused returns (uint256) {
        require(beneficiary != address(0), "HiveLock: zero beneficiary");
        require(token != address(0), "HiveLock: zero token");
        require(amount > 0, "HiveLock: zero amount");
        require(steps.length > 0 && steps.length <= 20, "HiveLock: 1-20 steps");

        // Validate total percentage = 100%
        uint256 totalPct;
        for (uint256 i = 0; i < steps.length; i++) {
            totalPct += steps[i].percentage;
            require(steps[i].timestamp > 0, "HiveLock: zero timestamp");
            if (i > 0) {
                require(steps[i].timestamp > steps[i-1].timestamp, "HiveLock: unordered");
            }
        }
        require(totalPct == 10000, "HiveLock: steps != 100%");

        require(
            IERC20(token).transferFrom(msg.sender, address(this), amount),
            "HiveLock: transfer failed"
        );

        uint256 id = scheduleCount++;
        schedules[id] = VestingSchedule({
            beneficiary: beneficiary,
            token: token,
            totalAmount: amount,
            claimedAmount: 0,
            startTime: startTime == 0 ? block.timestamp : startTime,
            cliffDuration: 0,
            vestingDuration: steps[steps.length - 1].timestamp - (startTime == 0 ? block.timestamp : startTime),
            unlockPercentage: 0,
            vestingType: VestingType.CUSTOM,
            cancelled: false,
            label: label
        });

        for (uint256 i = 0; i < steps.length; i++) {
            customSteps[id].push(steps[i]);
        }

        beneficiarySchedules[beneficiary].push(id);
        totalLocked[token] += amount;

        emit ScheduleCreated(id, beneficiary, token, amount, VestingType.CUSTOM, label);
        return id;
    }

    // ═══════════════════════════════════════════════════════════════
    //                       CLAIM TOKENS
    // ═══════════════════════════════════════════════════════════════

    /// @notice Claim all vested tokens for a schedule
    function claim(uint256 scheduleId) external whenNotPaused nonReentrant {
        VestingSchedule storage s = schedules[scheduleId];
        require(msg.sender == s.beneficiary, "HiveLock: not beneficiary");
        require(!s.cancelled, "HiveLock: cancelled");

        uint256 vested = _computeVested(scheduleId);
        uint256 claimable = vested - s.claimedAmount;
        require(claimable > 0, "HiveLock: nothing to claim");

        s.claimedAmount += claimable;
        totalClaimed[s.token] += claimable;

        require(
            IERC20(s.token).transfer(s.beneficiary, claimable),
            "HiveLock: transfer failed"
        );

        emit TokensClaimed(scheduleId, s.beneficiary, claimable);
    }

    /// @notice Claim all vested tokens across all schedules for caller
    function claimAll() external whenNotPaused nonReentrant {
        uint256[] memory ids = beneficiarySchedules[msg.sender];
        for (uint256 i = 0; i < ids.length; i++) {
            VestingSchedule storage s = schedules[ids[i]];
            if (s.cancelled) continue;

            uint256 vested = _computeVested(ids[i]);
            uint256 claimable = vested - s.claimedAmount;
            if (claimable == 0) continue;

            s.claimedAmount += claimable;
            totalClaimed[s.token] += claimable;

            require(
                IERC20(s.token).transfer(s.beneficiary, claimable),
                "HiveLock: transfer failed"
            );

            emit TokensClaimed(ids[i], s.beneficiary, claimable);
        }
    }

    // ═══════════════════════════════════════════════════════════════
    //                     CANCEL SCHEDULE
    // ═══════════════════════════════════════════════════════════════

    /// @notice Cancel a vesting schedule (admin only). Unvested tokens returned to owner.
    function cancelSchedule(uint256 scheduleId) external onlyAdmin {
        VestingSchedule storage s = schedules[scheduleId];
        require(!s.cancelled, "HiveLock: already cancelled");

        uint256 vested = _computeVested(scheduleId);
        uint256 unvested = s.totalAmount - vested;
        uint256 unclaimed = vested - s.claimedAmount;

        s.cancelled = true;
        totalLocked[s.token] -= (s.totalAmount - s.claimedAmount);

        // Return unvested tokens to owner
        if (unvested > 0) {
            require(
                IERC20(s.token).transfer(owner, unvested),
                "HiveLock: transfer failed"
            );
        }

        // Allow beneficiary to claim remaining vested tokens
        // (they can still call claim() on cancelled schedules if claimable > 0)

        emit ScheduleCancelled(scheduleId, unvested);
    }

    // ═══════════════════════════════════════════════════════════════
    //                    COMPUTE VESTED AMOUNT
    // ═══════════════════════════════════════════════════════════════

    function _computeVested(uint256 scheduleId) internal view returns (uint256) {
        VestingSchedule storage s = schedules[scheduleId];

        if (block.timestamp < s.startTime) return 0;

        if (s.vestingType == VestingType.LINEAR) {
            return _computeLinear(s);
        } else if (s.vestingType == VestingType.CLIFF_LINEAR) {
            return _computeCliffLinear(s);
        } else {
            return _computeCustom(scheduleId);
        }
    }

    function _computeLinear(VestingSchedule storage s) internal view returns (uint256) {
        if (block.timestamp >= s.startTime + s.vestingDuration) {
            return s.totalAmount;
        }
        uint256 elapsed = block.timestamp - s.startTime;
        return (s.totalAmount * elapsed) / s.vestingDuration;
    }

    function _computeCliffLinear(VestingSchedule storage s) internal view returns (uint256) {
        if (block.timestamp < s.startTime + s.cliffDuration) {
            return 0; // Still in cliff
        }

        // Cliff amount
        uint256 cliffAmount = (s.totalAmount * s.unlockPercentage) / 10000;

        if (block.timestamp >= s.startTime + s.vestingDuration) {
            return s.totalAmount;
        }

        // Linear vesting of remaining after cliff
        uint256 remaining = s.totalAmount - cliffAmount;
        uint256 postCliffDuration = s.vestingDuration - s.cliffDuration;
        uint256 postCliffElapsed = block.timestamp - s.startTime - s.cliffDuration;

        return cliffAmount + (remaining * postCliffElapsed) / postCliffDuration;
    }

    function _computeCustom(uint256 scheduleId) internal view returns (uint256) {
        VestingSchedule storage s = schedules[scheduleId];
        UnlockStep[] storage steps = customSteps[scheduleId];

        uint256 vested;
        for (uint256 i = 0; i < steps.length; i++) {
            if (block.timestamp >= steps[i].timestamp) {
                vested += (s.totalAmount * steps[i].percentage) / 10000;
            }
        }
        return vested;
    }

    // ═══════════════════════════════════════════════════════════════
    //                       VIEW FUNCTIONS
    // ═══════════════════════════════════════════════════════════════

    /// @notice Get vested amount for a schedule
    function getVestedAmount(uint256 scheduleId) external view returns (uint256) {
        return _computeVested(scheduleId);
    }

    /// @notice Get claimable amount for a schedule
    function getClaimableAmount(uint256 scheduleId) external view returns (uint256) {
        VestingSchedule storage s = schedules[scheduleId];
        if (s.cancelled) return 0;
        uint256 vested = _computeVested(scheduleId);
        return vested > s.claimedAmount ? vested - s.claimedAmount : 0;
    }

    /// @notice Get all schedule IDs for a beneficiary
    function getSchedules(address beneficiary) external view returns (uint256[] memory) {
        return beneficiarySchedules[beneficiary];
    }

    /// @notice Get schedule count
    function getScheduleCount() external view returns (uint256) {
        return scheduleCount;
    }

    /// @notice Get custom steps for a schedule
    function getCustomSteps(uint256 scheduleId) external view returns (UnlockStep[] memory) {
        return customSteps[scheduleId];
    }

    /// @notice Get total claimable across all schedules for a beneficiary
    function getTotalClaimable(address beneficiary) external view returns (uint256 total) {
        uint256[] memory ids = beneficiarySchedules[beneficiary];
        for (uint256 i = 0; i < ids.length; i++) {
            VestingSchedule storage s = schedules[ids[i]];
            if (s.cancelled) continue;
            uint256 vested = _computeVested(ids[i]);
            uint256 claimable = vested > s.claimedAmount ? vested - s.claimedAmount : 0;
            total += claimable;
        }
    }

    // ═══════════════════════════════════════════════════════════════
    //                       ADMIN FUNCTIONS
    // ═══════════════════════════════════════════════════════════════

    function addAdmin(address admin) external onlyOwner {
        require(admin != address(0), "HiveLock: zero address");
        admins[admin] = true;
    }

    function removeAdmin(address admin) external onlyOwner {
        admins[admin] = false;
    }

    function pause() external onlyAdmin {
        paused = true;
        emit Paused(msg.sender);
    }

    function unpause() external onlyAdmin {
        paused = false;
        emit Unpaused(msg.sender);
    }

    function transferOwnership(address newOwner) external onlyOwner {
        require(newOwner != address(0), "HiveLock: zero address");
        owner = newOwner;
    }

    /// @notice Emergency withdraw any token (owner only)
    function emergencyWithdraw(address token, uint256 amount) external onlyOwner {
        require(paused, "HiveLock: not paused");
        IERC20(token).transfer(owner, amount);
    }
}
