// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

/**
 * @title HiveStaking
 * @notice Stake RITUAL tokens for fee discounts + priority access
 * @dev Lock periods with multipliers, voting power for governance
 * @author Hive Team
 */

contract HiveStaking {
    // ═══════════════════════════════════════════════════════════════
    //                           STATE
    // ═══════════════════════════════════════════════════════════════

    address public owner;

    /// @notice Staker tier thresholds (in RITUAL)
    uint256 public constant BRONZE_THRESHOLD = 0;
    uint256 public constant SILVER_THRESHOLD = 1000 ether;
    uint256 public constant GOLD_THRESHOLD = 10000 ether;
    uint256 public constant DIAMOND_THRESHOLD = 100000 ether;

    /// @notice Fee discounts per tier (basis points)
    uint256 public constant BRONZE_DISCOUNT = 0;    // 0%
    uint256 public constant SILVER_DISCOUNT = 1000;  // 10%
    uint256 public constant GOLD_DISCOUNT = 2500;    // 25%
    uint256 public constant DIAMOND_DISCOUNT = 5000; // 50%

    /// @notice Lock period options (seconds)
    uint256 public constant LOCK_7D = 7 days;
    uint256 public constant LOCK_30D = 30 days;
    uint256 public constant LOCK_90D = 90 days;
    uint256 public constant LOCK_365D = 365 days;

    /// @notice Lock multipliers (1e18 = 1x)
    uint256 public constant MULTIPLIER_7D = 1e18;    // 1x
    uint256 public constant MULTIPLIER_30D = 12e17;  // 1.2x
    uint256 public constant MULTIPLIER_90D = 15e17;  // 1.5x
    uint256 public constant MULTIPLIER_365D = 2e18;  // 2x

    /// @notice Emergency unstake penalty (basis points)
    uint256 public constant EMERGENCY_PENALTY = 1000; // 10%

    /// @notice Minimum stake amount
    uint256 public minStake = 1 ether;

    /// @notice Total staked
    uint256 public totalStaked;

    /// @notice Staker info
    struct StakerInfo {
        uint256 stakedAmount;
        uint256 lockedUntil;
        uint256 lockMultiplier;
        uint256 stakedAt;
        uint256 lastCompoundAt;
        bool autoCompound;
        uint256 rewardsAccrued;
    }

    mapping(address => StakerInfo) public stakers;

    /// @notice All stakers list
    address[] public stakerList;
    mapping(address => bool) public isStaker;

    /// @notice Pending rewards
    uint256 public rewardRate = 500; // 5% APY (basis points)
    uint256 public lastRewardUpdate;

    // ═══════════════════════════════════════════════════════════════
    //                          EVENTS
    // ═══════════════════════════════════════════════════════════════

    event Staked(address indexed user, uint256 amount, uint256 lockPeriod, uint256 multiplier);
    event Unstaked(address indexed user, uint256 amount, uint256 penalty);
    event EmergencyUnstaked(address indexed user, uint256 amount, uint256 penalty);
    event RewardsClaimed(address indexed user, uint256 amount);
    event RewardsCompounded(address indexed user, uint256 amount);
    event AutoCompoundToggled(address indexed user, bool enabled);
    event TierUpgraded(address indexed user, uint8 oldTier, uint8 newTier);
    event RewardRateUpdated(uint256 oldRate, uint256 newRate);

    // ═══════════════════════════════════════════════════════════════
    //                         MODIFIERS
    // ═══════════════════════════════════════════════════════════════

    modifier onlyOwner() {
        require(msg.sender == owner, "HiveStaking: not owner");
        _;
    }

    modifier onlyStaker() {
        require(stakers[msg.sender].stakedAmount > 0, "HiveStaking: not staker");
        _;
    }

    // ═══════════════════════════════════════════════════════════════
    //                        CONSTRUCTOR
    // ═══════════════════════════════════════════════════════════════

    constructor() {
        owner = msg.sender;
        lastRewardUpdate = block.timestamp;
    }

    // ═══ Configuration ═══

    address public treasury;        // HiveTreasury for fee notifications

    function setTreasury(address _treasury) external {
        require(msg.sender == owner, "HiveStaking: not owner");
        treasury = _treasury;
    }

    event TreasurySet(address indexed treasury);
    event StakeNotificationSent(address indexed staker, uint256 amount);

    // ═══════════════════════════════════════════════════════════════
    //                      STAKE / UNSTAKE
    // ═══════════════════════════════════════════════════════════════

    /// @notice Stake RITUAL tokens
    /// @param lockPeriod Lock period (0, 7d, 30d, 90d, 365d)
    function stake(uint256 lockPeriod) external payable {
        require(msg.value >= minStake, "HiveStaking: below minimum");

        StakerInfo storage info = stakers[msg.sender];

        // Determine multiplier
        uint256 multiplier = _getMultiplier(lockPeriod);

        // Update lock if extending
        uint256 newLockEnd = block.timestamp + lockPeriod;
        if (newLockEnd > info.lockedUntil) {
            info.lockedUntil = newLockEnd;
        }

        // Calculate weighted amount
        uint256 oldWeighted = info.stakedAmount * info.lockMultiplier / 1e18;
        info.stakedAmount += msg.value;
        info.lockMultiplier = multiplier;
        uint256 newWeighted = info.stakedAmount * multiplier / 1e18;

        // Update totals
        totalStaked += msg.value;

        // Add to staker list if new
        if (!isStaker[msg.sender]) {
            stakerList.push(msg.sender);
            isStaker[msg.sender] = true;
            info.stakedAt = block.timestamp;
        }

        // Calculate pending rewards before updating
        if (info.stakedAmount > 0) {
            _accrueRewards(msg.sender);
        }

        emit Staked(msg.sender, msg.value, lockPeriod, multiplier);
    }

    /// @notice Unstake RITUAL tokens
    /// @param amount Amount to unstake
    function unstake(uint256 amount) external onlyStaker {
        StakerInfo storage info = stakers[msg.sender];

        require(amount > 0, "HiveStaking: zero amount");
        require(amount <= info.stakedAmount, "HiveStaking: insufficient balance");
        require(block.timestamp >= info.lockedUntil, "HiveStaking: still locked");

        // Accrue rewards before unstaking
        _accrueRewards(msg.sender);

        info.stakedAmount -= amount;
        totalStaked -= amount;

        // Transfer back
        (bool success, ) = msg.sender.call{value: amount}("");
        require(success, "HiveStaking: transfer failed");

        emit Unstaked(msg.sender, amount, 0);
    }

    /// @notice Emergency unstake with penalty
    function emergencyUnstake() external onlyStaker {
        StakerInfo storage info = stakers[msg.sender];

        uint256 amount = info.stakedAmount;
        require(amount > 0, "HiveStaking: nothing staked");

        // Calculate penalty
        uint256 penalty = (amount * EMERGENCY_PENALTY) / 10000;
        uint256 payout = amount - penalty;

        // Clear state
        info.stakedAmount = 0;
        info.lockedUntil = 0;
        info.lockMultiplier = 0;
        info.rewardsAccrued = 0;
        totalStaked -= amount;

        // Remove from staker list
        _removeStaker(msg.sender);

        // Transfer with penalty deducted
        (bool success, ) = msg.sender.call{value: payout}("");
        require(success, "HiveStaking: transfer failed");

        emit EmergencyUnstaked(msg.sender, amount, penalty);
    }

    // ═══════════════════════════════════════════════════════════════
    //                        REWARDS
    // ═══════════════════════════════════════════════════════════════

    /// @notice Claim accrued rewards
    function claimRewards() external onlyStaker {
        StakerInfo storage info = stakers[msg.sender];

        _accrueRewards(msg.sender);

        uint256 rewards = info.rewardsAccrued;
        require(rewards > 0, "HiveStaking: no rewards");

        info.rewardsAccrued = 0;
        info.lastCompoundAt = block.timestamp;

        (bool success, ) = msg.sender.call{value: rewards}("");
        require(success, "HiveStaking: transfer failed");

        emit RewardsClaimed(msg.sender, rewards);
    }

    /// @notice Compound rewards back into stake
    function compoundRewards() external onlyStaker {
        StakerInfo storage info = stakers[msg.sender];

        _accrueRewards(msg.sender);

        uint256 rewards = info.rewardsAccrued;
        require(rewards > 0, "HiveStaking: no rewards");

        info.rewardsAccrued = 0;
        info.stakedAmount += rewards;
        info.lastCompoundAt = block.timestamp;
        totalStaked += rewards;

        emit RewardsCompounded(msg.sender, rewards);
    }

    /// @notice Toggle auto-compound
    function toggleAutoCompound() external onlyStaker {
        stakers[msg.sender].autoCompound = !stakers[msg.sender].autoCompound;
        emit AutoCompoundToggled(msg.sender, stakers[msg.sender].autoCompound);
    }

    /// @notice Accrue rewards for a staker
    function _accrueRewards(address staker) internal {
        StakerInfo storage info = stakers[staker];

        if (info.stakedAmount == 0) return;

        uint256 duration = block.timestamp - info.lastCompoundAt;
        if (duration == 0) return;

        // APY calculation: principal * rate * duration / (365 days * 1e4)
        uint256 reward = (info.stakedAmount * rewardRate * duration) / (365 days * 10000);

        // Apply lock multiplier bonus
        reward = reward * info.lockMultiplier / 1e18;

        info.rewardsAccrued += reward;
        info.lastCompoundAt = block.timestamp;

        // Auto-compound if enabled
        if (info.autoCompound && info.rewardsAccrued >= minStake) {
            info.stakedAmount += info.rewardsAccrued;
            totalStaked += info.rewardsAccrued;
            emit RewardsCompounded(staker, info.rewardsAccrued);
            info.rewardsAccrued = 0;
        }
    }

    // ═══════════════════════════════════════════════════════════════
    //                       VIEW FUNCTIONS
    // ═══════════════════════════════════════════════════════════════

    /// @notice Get staked amount for user
    function stakedAmount(address user) external view returns (uint256) {
        return stakers[user].stakedAmount;
    }

    /// @notice Get lock multiplier for user
    function lockMultiplier(address user) external view returns (uint256) {
        return stakers[user].lockMultiplier;
    }

    /// @notice Get staker tier (0=Bronze, 1=Silver, 2=Gold, 3=Diamond)
    function getTier(address user) external view returns (uint8) {
        return _getTier(stakers[user].stakedAmount);
    }

    /// @notice Get fee discount for user (basis points)
    function getFeeDiscount(address user) external view returns (uint256) {
        uint8 tier = _getTier(stakers[user].stakedAmount);
        return _getTierDiscount(tier);
    }

    /// @notice Get priority score for token sale allocation
    function getPriorityScore(address user) external view returns (uint256) {
        StakerInfo storage info = stakers[user];
        if (info.stakedAmount == 0) return 0;

        uint8 tier = _getTier(info.stakedAmount);
        uint256 basePriority = uint256(tier + 1) * 1000; // 1000, 2000, 3000, 4000

        // Lock multiplier bonus
        uint256 lockBonus = (info.lockMultiplier - 1e18) * 1000 / 1e18;

        return basePriority + lockBonus;
    }

    /// @notice Get all stakers
    function getStakers() external view returns (address[] memory) {
        return stakerList;
    }

    /// @notice Get staker count
    function getStakerCount() external view returns (uint256) {
        return stakerList.length;
    }

    /// @notice Get pending rewards
    function getPendingRewards(address user) external view returns (uint256) {
        StakerInfo storage info = stakers[user];
        if (info.stakedAmount == 0) return 0;

        uint256 duration = block.timestamp - info.lastCompoundAt;
        uint256 reward = (info.stakedAmount * rewardRate * duration) / (365 days * 10000);
        reward = reward * info.lockMultiplier / 1e18;

        return info.rewardsAccrued + reward;
    }

    /// @notice Get staker info
    function getStakerInfo(address user) external view returns (StakerInfo memory) {
        return stakers[user];
    }

    /// @notice Check if user can unstake
    function canUnstake(address user) external view returns (bool) {
        return block.timestamp >= stakers[user].lockedUntil;
    }

    // ═══════════════════════════════════════════════════════════════
    //                      INTERNAL HELPERS
    // ═══════════════════════════════════════════════════════════════

    function _getMultiplier(uint256 lockPeriod) internal pure returns (uint256) {
        if (lockPeriod >= LOCK_365D) return MULTIPLIER_365D;
        if (lockPeriod >= LOCK_90D) return MULTIPLIER_90D;
        if (lockPeriod >= LOCK_30D) return MULTIPLIER_30D;
        if (lockPeriod >= LOCK_7D) return MULTIPLIER_7D;
        return 1e18; // No lock = 1x
    }

    function _getTier(uint256 amount) internal pure returns (uint8) {
        if (amount >= DIAMOND_THRESHOLD) return 3;
        if (amount >= GOLD_THRESHOLD) return 2;
        if (amount >= SILVER_THRESHOLD) return 1;
        return 0;
    }

    function _getTierDiscount(uint8 tier) internal pure returns (uint256) {
        if (tier == 3) return DIAMOND_DISCOUNT;
        if (tier == 2) return GOLD_DISCOUNT;
        if (tier == 1) return SILVER_DISCOUNT;
        return BRONZE_DISCOUNT;
    }

    function _removeStaker(address staker) internal {
        isStaker[staker] = false;
        // Find and remove from list
        for (uint256 i = 0; i < stakerList.length; i++) {
            if (stakerList[i] == staker) {
                stakerList[i] = stakerList[stakerList.length - 1];
                stakerList.pop();
                break;
            }
        }
    }

    // ═══════════════════════════════════════════════════════════════
    //                      ADMIN FUNCTIONS
    // ═══════════════════════════════════════════════════════════════

    /// @notice Update reward rate
    function setRewardRate(uint256 _rate) external onlyOwner {
        require(_rate <= 2000, "HiveStaking: rate too high"); // Max 20% APY
        uint256 old = rewardRate;
        rewardRate = _rate;
        emit RewardRateUpdated(old, _rate);
    }

    /// @notice Update minimum stake
    function setMinStake(uint256 _minStake) external onlyOwner {
        minStake = _minStake;
    }

    /// @notice Fund rewards pool
    function fundRewards() external payable {
        // Just receive ETH for rewards
    }

    /// @notice Transfer ownership
    function transferOwnership(address newOwner) external onlyOwner {
        require(newOwner != address(0), "HiveStaking: zero address");
        owner = newOwner;
    }

    /// @notice Fallback to receive ETH
    receive() external payable {}
}
