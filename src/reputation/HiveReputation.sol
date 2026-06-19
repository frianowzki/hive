// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

/// @title HiveReputation — On-chain Reputation System
/// @notice Tracks user reputation based on platform activity
/// @dev Score affects: sale priority, fees, governance weight

contract HiveReputation {
    // ═══ Types ═══

    enum ActivityType {
        SaleParticipation,  // Participated in token sale
        SuccessfulTrade,    // Profitable trade
        GovernanceVote,     // Voted in DAO
        Referral,           // Referred a new user
        Staking,            // Staked tokens
        EarlyAdopter,       // Was early to platform
        CommunityContribution // Helped community
    }

    struct ReputationScore {
        uint256 totalScore;
        uint256 saleScore;          // From sale participation
        uint256 tradeScore;         // From trading activity
        uint256 governanceScore;    // From voting
        uint256 referralScore;      // From referrals
        uint256 stakingScore;       // From staking
        uint256 bonusScore;         // Early adopter + community
        uint256 lastUpdated;
        uint256 tier;               // 0-4 (Bronze/Silver/Gold/Platinum/Diamond)
    }

    struct Activity {
        ActivityType activityType;
        uint256 points;
        uint256 timestamp;
        string metadata;
    }

    // ═══ State ═══

    mapping(bytes32 => ReputationScore) public scores; // usernameHash => score
    mapping(bytes32 => Activity[]) public activities;
    mapping(bytes32 => mapping(uint8 => uint256)) public activityCount;

    // Tier thresholds
    uint256 public constant TIER_BRONZE = 0;
    uint256 public constant TIER_SILVER = 100;
    uint256 public constant TIER_GOLD = 500;
    uint256 public constant TIER_PLATINUM = 2000;
    uint256 public constant TIER_DIAMOND = 10000;

    // Points per activity
    mapping(ActivityType => uint256) public pointsPerActivity;

    // Authorized callers (other Hive contracts)
    mapping(address => bool) public authorized;

    address public owner;

    // ═══ Events ═══

    event ReputationUpdated(bytes32 indexed usernameHash, uint256 newTotal, uint256 tier);
    event ActivityRecorded(bytes32 indexed usernameHash, ActivityType activityType, uint256 points);
    event TierUpgraded(bytes32 indexed usernameHash, uint256 oldTier, uint256 newTier);

    // ═══ Constructor ═══

    constructor() {
        owner = msg.sender;

        // Default points per activity
        pointsPerActivity[ActivityType.SaleParticipation] = 10;
        pointsPerActivity[ActivityType.SuccessfulTrade] = 20;
        pointsPerActivity[ActivityType.GovernanceVote] = 15;
        pointsPerActivity[ActivityType.Referral] = 50;
        pointsPerActivity[ActivityType.Staking] = 5;
        pointsPerActivity[ActivityType.EarlyAdopter] = 100;
        pointsPerActivity[ActivityType.CommunityContribution] = 30;
    }

    // ═══ Record Activity ═══

    /// @notice Record a reputation-earning activity
    /// @param usernameHash The user's HiveID username hash
    /// @param activityType Type of activity
    /// @param metadata Optional context string
    function recordActivity(
        bytes32 usernameHash,
        ActivityType activityType,
        string calldata metadata
    ) external {
        require(authorized[msg.sender] || msg.sender == owner, "Rep: not authorized");

        uint256 points = pointsPerActivity[activityType];

        activities[usernameHash].push(Activity({
            activityType: activityType,
            points: points,
            timestamp: block.timestamp,
            metadata: metadata
        }));

        activityCount[usernameHash][uint8(activityType)]++;

        // Update score
        ReputationScore storage score = scores[usernameHash];
        uint256 oldTier = score.tier;

        score.totalScore += points;
        score.lastUpdated = block.timestamp;

        // Update category score
        if (activityType == ActivityType.SaleParticipation) {
            score.saleScore += points;
        } else if (activityType == ActivityType.SuccessfulTrade) {
            score.tradeScore += points;
        } else if (activityType == ActivityType.GovernanceVote) {
            score.governanceScore += points;
        } else if (activityType == ActivityType.Referral) {
            score.referralScore += points;
        } else if (activityType == ActivityType.Staking) {
            score.stakingScore += points;
        } else {
            score.bonusScore += points;
        }

        // Calculate tier
        uint256 newTier = _calculateTier(score.totalScore);
        if (newTier != oldTier) {
            score.tier = newTier;
            emit TierUpgraded(usernameHash, oldTier, newTier);
        }

        emit ActivityRecorded(usernameHash, activityType, points);
        emit ReputationUpdated(usernameHash, score.totalScore, score.tier);
    }

    // ═══ Tier Calculation ═══

    function _calculateTier(uint256 totalScore) internal pure returns (uint256) {
        if (totalScore >= TIER_DIAMOND) return 4;
        if (totalScore >= TIER_PLATINUM) return 3;
        if (totalScore >= TIER_GOLD) return 2;
        if (totalScore >= TIER_SILVER) return 1;
        return 0;
    }

    // ═══ Benefits ═══

    /// @notice Get fee discount based on tier (bps)
    function getFeeDiscount(bytes32 usernameHash) external view returns (uint256) {
        uint256 tier = scores[usernameHash].tier;
        if (tier == 4) return 500;      // Diamond: 5% discount
        if (tier == 3) return 300;      // Platinum: 3%
        if (tier == 2) return 150;      // Gold: 1.5%
        if (tier == 1) return 50;       // Silver: 0.5%
        return 0;                        // Bronze: no discount
    }

    /// @notice Get sale priority (lower = higher priority)
    function getSalePriority(bytes32 usernameHash) external view returns (uint256) {
        uint256 tier = scores[usernameHash].tier;
        if (tier == 4) return 0;        // Diamond: first access
        if (tier == 3) return 1;        // Platinum: second
        if (tier == 2) return 2;        // Gold: third
        if (tier == 1) return 3;        // Silver: fourth
        return 4;                        // Bronze: last
    }

    /// @notice Get governance weight multiplier (100 = 1x)
    function getGovernanceWeight(bytes32 usernameHash) external view returns (uint256) {
        uint256 tier = scores[usernameHash].tier;
        if (tier == 4) return 200;      // Diamond: 2x
        if (tier == 3) return 150;      // Platinum: 1.5x
        if (tier == 2) return 120;      // Gold: 1.2x
        if (tier == 1) return 110;      // Silver: 1.1x
        return 100;                      // Bronze: 1x
    }

    // ═══ View ═══

    function getScore(bytes32 usernameHash) external view returns (ReputationScore memory) {
        return scores[usernameHash];
    }

    function getActivities(bytes32 usernameHash) external view returns (Activity[] memory) {
        return activities[usernameHash];
    }

    function getActivityCount(bytes32 usernameHash, ActivityType aType) external view returns (uint256) {
        return activityCount[usernameHash][uint8(aType)];
    }

    function getTierName(uint256 tier) external pure returns (string memory) {
        if (tier == 4) return "Diamond";
        if (tier == 3) return "Platinum";
        if (tier == 2) return "Gold";
        if (tier == 1) return "Silver";
        return "Bronze";
    }

    // ═══ Admin ═══

    function authorize(address caller) external {
        require(msg.sender == owner, "Rep: not owner");
        authorized[caller] = true;
    }

    function revoke(address caller) external {
        require(msg.sender == owner, "Rep: not owner");
        authorized[caller] = false;
    }

    function setPoints(ActivityType aType, uint256 points) external {
        require(msg.sender == owner, "Rep: not owner");
        pointsPerActivity[aType] = points;
    }
}
