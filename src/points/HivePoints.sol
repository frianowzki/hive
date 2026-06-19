// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

/// @title Points — Hive Points System (Tokenless)
/// @notice Tracks user engagement across all Hive modules

contract HivePoints {
    // ═══ State ═══

    struct UserPoints {
        uint256 buyPoints;       // Token purchases
        uint256 lpPoints;        // Liquidity provision
        uint256 govPoints;       // Governance votes
        uint256 referralPoints;  // Referrals
        uint256 bonusMultiplier; // Early/diamond hands (10000 = 1x)
        address referredBy;
        uint256 lastActivity;
    }

    mapping(address => UserPoints) public users;
    address[] public userList;

    uint256 public totalPoints;
    uint256 public constant BPS = 10_000;

    // Multipliers
    uint256 public earlyMultiplier = 15_000;  // 1.5x first 24h
    uint256 public diamondMultiplier = 20_000; // 2x hold >30 days
    uint256 public lpMultiplier = 20_000;      // 2x for LP
    uint256 public referralBps = 500;           // 5% of referee points

    uint256 public earlyWindow = 24 hours;
    uint256 public diamondThreshold = 30 days;

    // ═══ Events ═══

    event PointsEarned(address indexed user, string category, uint256 amount, uint256 total);
    event ReferralSet(address indexed user, address indexed referrer);
    event MultiplierUpdated(string param, uint256 value);

    // ═══ Points Calculation ═══

    /// @notice Award buy points
    function awardBuy(address user, uint256 amount) external {
        _ensureRegistered(user);

        uint256 pts = amount;
        uint256 multiplier = _getMultiplier(user);

        // Early bonus
        if (block.timestamp - _getGenesis() < earlyWindow) {
            multiplier = (multiplier * earlyMultiplier) / BPS;
        }

        pts = (pts * multiplier) / BPS;
        users[user].buyPoints += pts;
        users[user].lastActivity = block.timestamp;
        totalPoints += pts;

        // Referral bonus
        if (users[user].referredBy != address(0)) {
            uint256 refPts = (pts * referralBps) / BPS;
            users[users[user].referredBy].referralPoints += refPts;
            totalPoints += refPts;
            emit PointsEarned(users[user].referredBy, "referral", refPts, _totalFor(users[user].referredBy));
        }

        emit PointsEarned(user, "buy", pts, _totalFor(user));
    }

    /// @notice Award LP points (per day)
    function awardLP(address user, uint256 amount, uint256 duration) external {
        uint256 pts = (amount * duration) / 1 days;
        pts = (pts * lpMultiplier) / BPS;

        // Diamond hands bonus
        if (duration >= diamondThreshold) {
            pts = (pts * diamondMultiplier) / BPS;
        }

        users[user].lpPoints += pts;
        users[user].lastActivity = block.timestamp;
        totalPoints += pts;

        _ensureRegistered(user);
        emit PointsEarned(user, "lp", pts, _totalFor(user));
    }

    /// @notice Award governance points
    function awardGov(address user) external {
        uint256 pts = 10; // 10 points per vote
        users[user].govPoints += pts;
        users[user].lastActivity = block.timestamp;
        totalPoints += pts;

        _ensureRegistered(user);
        emit PointsEarned(user, "gov", pts, _totalFor(user));
    }

    /// @notice Set referral
    function setReferral(address referrer) external {
        require(users[msg.sender].referredBy == address(0), "Points: referral already set");
        require(referrer != msg.sender, "Points: cannot self-refer");
        require(users[referrer].lastActivity > 0, "Points: referrer not active");

        users[msg.sender].referredBy = referrer;
        emit ReferralSet(msg.sender, referrer);
    }

    // ═══ View ═══

    function totalFor(address user) external view returns (uint256) {
        return _totalFor(user);
    }

    function rank(address user) external view returns (uint256) {
        uint256 pts = _totalFor(user);
        uint256 r = 1;
        for (uint256 i = 0; i < userList.length; i++) {
            if (_totalFor(userList[i]) > pts) r++;
        }
        return r;
    }

    function topHolders(uint256 count) external view returns (address[] memory, uint256[] memory) {
        if (count > userList.length) count = userList.length;

        address[] memory addrs = new address[](count);
        uint256[] memory pts = new uint256[](count);

        // Simple selection — find top N
        for (uint256 i = 0; i < count; i++) {
            uint256 maxPts = 0;
            uint256 maxIdx = 0;
            for (uint256 j = 0; j < userList.length; j++) {
                uint256 p = _totalFor(userList[j]);
                if (p > maxPts) {
                    bool alreadySelected = false;
                    for (uint256 k = 0; k < i; k++) {
                        if (addrs[k] == userList[j]) { alreadySelected = true; break; }
                    }
                    if (!alreadySelected) {
                        maxPts = p;
                        maxIdx = j;
                    }
                }
            }
            addrs[i] = userList[maxIdx];
            pts[i] = maxPts;
        }

        return (addrs, pts);
    }

    // ═══ Internal ═══

    function _totalFor(address user) internal view returns (uint256) {
        return users[user].buyPoints + users[user].lpPoints +
               users[user].govPoints + users[user].referralPoints;
    }

    function _getMultiplier(address user) internal view returns (uint256) {
        if (users[user].bonusMultiplier > 0) return users[user].bonusMultiplier;
        return BPS; // 1x default
    }

    uint256 public genesis;

    constructor() {
        genesis = block.timestamp;
    }

    function _getGenesis() internal view returns (uint256) {
        return genesis;
    }

    function _ensureRegistered(address user) internal {
        if (users[user].lastActivity == 0) {
            users[user].lastActivity = block.timestamp;
            userList.push(user);
        }
    }
}
