// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "../interfaces/IHive.sol";

/**
 * @title HiveTreasury
 * @notice Treasury & fee collector for the Hive platform
 * @dev Multi-sig controlled, auto-distributes fees to stakers/referrers
 * @author Hive Team
 */

contract HiveTreasury {
    // ═══════════════════════════════════════════════════════════════
    //                           STATE
    // ═══════════════════════════════════════════════════════════════

    address public owner;
    bool public paused;

    /// @notice Multi-sig address for admin operations
    address public multiSig;

    /// @notice Staking contract for fee distribution
    IStaking public staking;

    /// @notice Referral contract for fee distribution
    IReferral public referral;

    /// @notice Fee distribution ratios (basis points, total = 10000)
    uint256 public stakerShare = 6000;  // 60%
    uint256 public referrerShare = 2500; // 25%
    uint256 public reserveShare = 1500;  // 15%

    /// @notice Reserve balance (accumulated)
    uint256 public reserveBalance;

    /// @notice Total fees collected
    uint256 public totalFeesCollected;

    /// @notice Total fees distributed to stakers
    uint256 public totalDistributedToStakers;

    /// @notice Total fees distributed to referrers
    uint256 public totalDistributedToReferrers;

    /// @notice Distribution history
    struct Distribution {
        uint256 timestamp;
        uint256 totalAmount;
        uint256 stakerAmount;
        uint256 referrerAmount;
        uint256 reserveAmount;
        uint256 stakerCount;
        uint256 referrerCount;
    }

    Distribution[] public distributions;

    /// @notice Track if address has received distribution in current round
    mapping(address => uint256) public lastDistributionRound;
    uint256 public currentRound;

    // ═══════════════════════════════════════════════════════════════
    //                          EVENTS
    // ═══════════════════════════════════════════════════════════════

    event FeesReceived(address indexed from, uint256 amount);
    event DistributionExecuted(uint256 indexed round, uint256 totalAmount, uint256 stakerAmount, uint256 referrerAmount, uint256 reserveAmount);
    event StakerPaid(address indexed staker, uint256 amount, uint256 round);
    event ReferrerPaid(address indexed referrer, uint256 amount, uint256 round);
    event ReserveWithdrawn(address indexed to, uint256 amount);
    event SharesUpdated(uint256 stakerShare, uint256 referrerShare, uint256 reserveShare);
    event MultiSigUpdated(address indexed newMultiSig);
    event Paused(address indexed by);
    event Unpaused(address indexed by);

    // ═══════════════════════════════════════════════════════════════
    //                         MODIFIERS
    // ═══════════════════════════════════════════════════════════════

    modifier onlyOwner() {
        require(msg.sender == owner, "HiveTreasury: not owner");
        _;
    }

    modifier onlyMultiSig() {
        require(msg.sender == multiSig, "HiveTreasury: not multi-sig");
        _;
    }

    modifier onlyAdmin() {
        require(msg.sender == owner || msg.sender == multiSig, "HiveTreasury: not admin");
        _;
    }

    modifier whenNotPaused() {
        require(!paused, "HiveTreasury: paused");
        _;
    }

    // ═══════════════════════════════════════════════════════════════
    //                        CONSTRUCTOR
    // ═══════════════════════════════════════════════════════════════

    constructor(address _multiSig) {
        owner = msg.sender;
        multiSig = _multiSig;
    }

    // ═══════════════════════════════════════════════════════════════
    //                     RECEIVE FEES
    // ═══════════════════════════════════════════════════════════════

    /// @notice Receive fees from HiveClearing or other contracts
    receive() external payable {
        _collectFees(msg.sender, msg.value);
    }

    /// @notice Collect fees with explicit amount
    /// @param from Source address
    /// @param amount Fee amount in wei
    function collectFees(address from, uint256 amount) external whenNotPaused {
        _collectFees(from, amount);
    }

    function _collectFees(address from, uint256 amount) internal {
        require(amount > 0, "HiveTreasury: zero amount");
        totalFeesCollected += amount;
        emit FeesReceived(from, amount);
    }

    // ═══════════════════════════════════════════════════════════════
    //                   DISTRIBUTE FEES
    // ═══════════════════════════════════════════════════════════════

    /// @notice Distribute collected fees to stakers and referrers
    /// @dev Can be called by anyone, but multi-sig preferred for timing
    function distribute() external whenNotPaused {
        uint256 balance = address(this).balance;
        require(balance > 0, "HiveTreasury: no fees to distribute");

        currentRound++;

        uint256 stakerAmount = (balance * stakerShare) / 10000;
        uint256 referrerAmount = (balance * referrerShare) / 10000;
        uint256 reserveAmt = balance - stakerAmount - referrerAmount;

        uint256 stakerCount;
        uint256 referrerCount;

        // Distribute to stakers
        if (address(staking) != address(0)) {
            stakerCount = _distributeToStakers(stakerAmount);
        } else {
            reserveAmt += stakerAmount; // No staking contract, go to reserve
        }

        // Distribute to referrers
        if (address(referral) != address(0)) {
            referrerCount = _distributeToReferrers(referrerAmount);
        } else {
            reserveAmt += referrerAmount; // No referral contract, go to reserve
        }

        // Add to reserve
        reserveBalance += reserveAmt;

        // Record distribution
        distributions.push(Distribution({
            timestamp: block.timestamp,
            totalAmount: balance,
            stakerAmount: stakerAmount,
            referrerAmount: referrerAmount,
            reserveAmount: reserveAmt,
            stakerCount: stakerCount,
            referrerCount: referrerCount
        }));

        totalDistributedToStakers += stakerAmount;
        totalDistributedToReferrers += referrerAmount;

        emit DistributionExecuted(currentRound, balance, stakerAmount, referrerAmount, reserveAmt);
    }

    /// @notice Distribute to stakers proportional to their stake
    function _distributeToStakers(uint256 totalAmount) internal returns (uint256 count) {
        address[] memory stakers = staking.getStakers();
        uint256 totalStaked = staking.totalStaked();

        if (totalStaked == 0 || stakers.length == 0) {
            reserveBalance += totalAmount;
            return 0;
        }

        uint256 distributed;
        for (uint256 i = 0; i < stakers.length; i++) {
            address staker = stakers[i];
            uint256 staked = staking.stakedAmount(staker);
            if (staked == 0) continue;

            uint256 share = (totalAmount * staked) / totalStaked;
            if (share == 0) continue;

            // Check not already distributed this round
            if (lastDistributionRound[staker] >= currentRound) continue;

            (bool success, ) = staker.call{value: share}("");
            if (success) {
                lastDistributionRound[staker] = currentRound;
                distributed += share;
                count++;
                emit StakerPaid(staker, share, currentRound);
            }
        }

        // Return undistributed to reserve
        if (distributed < totalAmount) {
            reserveBalance += (totalAmount - distributed);
        }
    }

    /// @notice Distribute to referrers proportional to their tier
    function _distributeToReferrers(uint256 totalAmount) internal returns (uint256 count) {
        address[] memory stakers = staking.getStakers();
        if (stakers.length == 0) {
            reserveBalance += totalAmount;
            return 0;
        }

        uint256 totalWeight;

        // Calculate total weight and distribute in one pass
        for (uint256 i = 0; i < stakers.length; i++) {
            address referrer = referral.getReferrer(stakers[i]);
            if (referrer == address(0)) continue;

            uint8 tier = referral.referralTier(referrer);
            totalWeight += uint256(tier + 1);
        }

        if (totalWeight == 0) {
            reserveBalance += totalAmount;
            return 0;
        }

        // Distribute
        uint256 distributed;
        for (uint256 i = 0; i < stakers.length; i++) {
            address referrer = referral.getReferrer(stakers[i]);
            if (referrer == address(0)) continue;

            uint8 tier = referral.referralTier(referrer);
            uint256 share = (totalAmount * uint256(tier + 1)) / totalWeight;

            if (share == 0) continue;

            (bool success, ) = referrer.call{value: share}("");
            if (success) {
                distributed += share;
                count++;
                emit ReferrerPaid(referrer, share, currentRound);
            }
        }

        // Return undistributed to reserve
        if (distributed < totalAmount) {
            reserveBalance += (totalAmount - distributed);
        }
    }

    // ═══════════════════════════════════════════════════════════════
    //                     RESERVE MANAGEMENT
    // ═══════════════════════════════════════════════════════════════

    /// @notice Withdraw reserve (multi-sig only)
    /// @param to Recipient address
    /// @param amount Amount to withdraw
    function withdrawReserve(address to, uint256 amount) external onlyMultiSig {
        require(to != address(0), "HiveTreasury: zero address");
        require(amount <= reserveBalance, "HiveTreasury: insufficient reserve");

        reserveBalance -= amount;

        (bool success, ) = to.call{value: amount}("");
        require(success, "HiveTreasury: transfer failed");

        emit ReserveWithdrawn(to, amount);
    }

    // ═══════════════════════════════════════════════════════════════
    //                      ADMIN FUNCTIONS
    // ═══════════════════════════════════════════════════════════════

    /// @notice Update fee distribution shares
    /// @param _stakerShare Staker share in basis points
    /// @param _referrerShare Referrer share in basis points
    /// @param _reserveShare Reserve share in basis points
    function updateShares(
        uint256 _stakerShare,
        uint256 _referrerShare,
        uint256 _reserveShare
    ) external onlyMultiSig {
        require(_stakerShare + _referrerShare + _reserveShare == 10000, "HiveTreasury: shares must sum to 10000");

        stakerShare = _stakerShare;
        referrerShare = _referrerShare;
        reserveShare = _reserveShare;

        emit SharesUpdated(_stakerShare, _referrerShare, _reserveShare);
    }

    /// @notice Update staking contract
    function setStaking(address _staking) external onlyMultiSig {
        staking = IStaking(_staking);
    }

    /// @notice Update referral contract
    function setReferral(address _referral) external onlyMultiSig {
        referral = IReferral(_referral);
    }

    /// @notice Update multi-sig address
    function setMultiSig(address _multiSig) external onlyOwner {
        require(_multiSig != address(0), "HiveTreasury: zero address");
        multiSig = _multiSig;
        emit MultiSigUpdated(_multiSig);
    }

    /// @notice Pause treasury
    function pause() external onlyAdmin {
        paused = true;
        emit Paused(msg.sender);
    }

    /// @notice Unpause treasury
    function unpause() external onlyAdmin {
        paused = false;
        emit Unpaused(msg.sender);
    }

    /// @notice Transfer ownership
    function transferOwnership(address newOwner) external onlyOwner {
        require(newOwner != address(0), "HiveTreasury: zero address");
        owner = newOwner;
    }

    // ═══════════════════════════════════════════════════════════════
    //                       VIEW FUNCTIONS
    // ═══════════════════════════════════════════════════════════════

    /// @notice Get number of distributions
    function getDistributionCount() external view returns (uint256) {
        return distributions.length;
    }

    /// @notice Get distribution details
    function getDistribution(uint256 index) external view returns (Distribution memory) {
        require(index < distributions.length, "HiveTreasury: invalid index");
        return distributions[index];
    }

    /// @notice Get available balance for distribution
    function getAvailableBalance() external view returns (uint256) {
        return address(this).balance - reserveBalance;
    }
}
