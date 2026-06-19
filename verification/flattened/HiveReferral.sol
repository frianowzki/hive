// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

// src/referral/HiveReferral.sol

/// @title HiveReferral — On-chain Referral Engine
/// @notice Track referrals and distribute rewards per HiveID

contract HiveReferral {
    // ═══ Types ═══

    struct Referral {
        bytes32 referrerHash;   // Who referred
        bytes32 refereeHash;    // Who was referred
        uint256 timestamp;
        uint256 rewardAmount;
        bool rewardClaimed;
    }

    struct ReferrerStats {
        uint256 totalReferrals;
        uint256 activeReferrals;    // Referees who completed KYC
        uint256 totalRewardsEarned;
        uint256 totalRewardsClaimed;
        uint256 tier;               // 0-3 based on referral count
    }

    // ═══ State ═══

    // usernameHash => referral code
    mapping(bytes32 => bytes32) public referralCodes;
    // referral code => usernameHash
    mapping(bytes32 => bytes32) public codeToUser;
    // usernameHash => who referred them
    mapping(bytes32 => bytes32) public referredBy;
    // usernameHash => list of referrals made
    mapping(bytes32 => Referral[]) public referrals;
    // usernameHash => stats
    mapping(bytes32 => ReferrerStats) public stats;

    // Reward config
    uint256 public baseReward = 0.001 ether;    // Base reward per referral
    mapping(uint256 => uint256) public tierMultiplier; // tier => multiplier (100 = 1x)

    // Fee sharing
    uint256 public referralFeeShareBps = 200; // 2% of platform fees to referrer

    // Total rewards pool
    uint256 public rewardPool;
    mapping(bytes32 => uint256) public claimableRewards;

    address public owner;

    // ═══ Events ═══

    event ReferralCodeCreated(bytes32 indexed usernameHash, bytes32 code);
    event ReferralRegistered(bytes32 indexed referrer, bytes32 indexed referee, uint256 reward);
    event RewardClaimed(bytes32 indexed usernameHash, uint256 amount);
    event RewardPoolFunded(uint256 amount);

    // ═══ Constructor ═══

    constructor() {
        owner = msg.sender;

        // Tier multipliers
        tierMultiplier[0] = 100;   // 0-4 referrals: 1x
        tierMultiplier[1] = 150;   // 5-19 referrals: 1.5x
        tierMultiplier[2] = 200;   // 49 referrals: 2x
        tierMultiplier[3] = 300;   // 50+ referrals: 3x
    }

    // ═══ Create Referral Code ═══

    /// @notice Generate a referral code for a HiveID
    function createReferralCode(bytes32 usernameHash) external returns (bytes32 code) {
        require(referralCodes[usernameHash] == bytes32(0), "Referral: code exists");

        code = keccak256(abi.encodePacked(usernameHash, block.timestamp));
        referralCodes[usernameHash] = code;
        codeToUser[code] = usernameHash;

        emit ReferralCodeCreated(usernameHash, code);
        return code;
    }

    // ═══ Register Referral ═══

    /// @notice Register a new referral (called when user registers with referral code)
    function registerReferral(bytes32 refereeHash, bytes32 referralCode) external {
        require(referredBy[refereeHash] == bytes32(0), "Referral: already referred");
        require(codeToUser[referralCode] != bytes32(0), "Referral: invalid code");

        bytes32 referrerHash = codeToUser[referralCode];
        require(referrerHash != refereeHash, "Referral: self-referral");

        referredBy[refereeHash] = referrerHash;

        // Update stats
        ReferrerStats storage s = stats[referrerHash];
        s.totalReferrals++;

        // Calculate reward based on updated count
        uint256 tier = _calculateTier(s.totalReferrals);
        uint256 reward = (baseReward * tierMultiplier[tier]) / 100;

        s.totalRewardsEarned += reward;
        s.tier = tier;

        // Add to claimable
        claimableRewards[referrerHash] += reward;

        // Record referral
        referrals[referrerHash].push(Referral({
            referrerHash: referrerHash,
            refereeHash: refereeHash,
            timestamp: block.timestamp,
            rewardAmount: reward,
            rewardClaimed: false
        }));

        emit ReferralRegistered(referrerHash, refereeHash, reward);
    }

    // ═══ Mark Referral Active ═══

    /// @notice Mark referral as active (when referee completes KYC)
    function markActive(bytes32 refereeHash) external {
        // In production, restrict to HiveID contract
        bytes32 referrerHash = referredBy[refereeHash];
        if (referrerHash != bytes32(0)) {
            stats[referrerHash].activeReferrals++;
        }
    }

    // ═══ Fee Sharing ═══

    /// @notice Distribute platform fee share to referrer
    function distributeFeeShare(bytes32 usernameHash, uint256 feeAmount) external {
        // In production, restrict to authorized contracts
        bytes32 referrerHash = referredBy[usernameHash];
        if (referrerHash == bytes32(0)) return; // No referrer

        uint256 share = (feeAmount * referralFeeShareBps) / 10000;
        if (share == 0) return;

        ReferrerStats storage s = stats[referrerHash];
        uint256 tier = _calculateTier(s.totalReferrals);
        uint256 adjustedShare = (share * tierMultiplier[tier]) / 100;

        claimableRewards[referrerHash] += adjustedShare;
        s.totalRewardsEarned += adjustedShare;
    }

    // ═══ Claim Rewards ═══

    /// @notice Claim accumulated referral rewards
    function claimRewards(bytes32 usernameHash) external returns (uint256 amount) {
        amount = claimableRewards[usernameHash];
        require(amount > 0, "Referral: nothing to claim");

        claimableRewards[usernameHash] = 0;
        stats[usernameHash].totalRewardsClaimed += amount;

        (bool sent, ) = msg.sender.call{value: amount}("");
        require(sent, "Referral: transfer failed");

        emit RewardClaimed(usernameHash, amount);
    }

    // ═══ Tier ═══

    function _calculateTier(uint256 referralCount) internal pure returns (uint256) {
        if (referralCount >= 50) return 3;
        if (referralCount >= 20) return 2;
        if (referralCount >= 5) return 1;
        return 0;
    }

    // ═══ Fund Pool ═══

    /// @notice Fund the reward pool
    function fundPool() external payable {
        rewardPool += msg.value;
        emit RewardPoolFunded(msg.value);
    }

    // ═══ View ═══

    function getReferralCode(bytes32 usernameHash) external view returns (bytes32) {
        return referralCodes[usernameHash];
    }

    function getReferrer(bytes32 usernameHash) external view returns (bytes32) {
        return referredBy[usernameHash];
    }

    function getReferrals(bytes32 usernameHash) external view returns (Referral[] memory) {
        return referrals[usernameHash];
    }

    function getStats(bytes32 usernameHash) external view returns (ReferrerStats memory) {
        return stats[usernameHash];
    }

    function getClaimable(bytes32 usernameHash) external view returns (uint256) {
        return claimableRewards[usernameHash];
    }

    function getTierName(uint256 tier) external pure returns (string memory) {
        if (tier == 3) return "Ambassador";
        if (tier == 2) return "Advocate";
        if (tier == 1) return "Promoter";
        return "Starter";
    }

    // ═══ Admin ═══

    function setBaseReward(uint256 _reward) external {
        require(msg.sender == owner, "Referral: not owner");
        baseReward = _reward;
    }

    function setFeeShareBps(uint256 _bps) external {
        require(msg.sender == owner, "Referral: not owner");
        require(_bps <= 1000, "Referral: max 10%");
        referralFeeShareBps = _bps;
    }

    receive() external payable {
        rewardPool += msg.value;
    }
}
