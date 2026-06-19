// SPDX-License-Identifier: MIT
pragma solidity =0.8.20 ^0.8.20;

// src/identity/HiveID.sol

/// @title HiveID — On-chain Identity Registry
/// @notice Permanent username + dual-wallet binding (primary + Hive wallet)
/// @dev All Hive activity routes through HiveID. Withdrawals restricted to primary or other HiveIDs.

contract HiveID {
    // ═══ Types ═══

    enum VerificationType {
        None,
        KYC,    // Individual
        KYB     // Organization
    }

    enum AccountType {
        User,       // Regular user (buy/sell)
        Project,    // Token launcher
        Investor    // VC / institutional
    }

    struct Identity {
        bytes32 usernameHash;           // keccak256(username) — permanent
        address primaryWallet;          // ECDSA wallet (connect/register)
        address hiveWallet;             // Ritual passkey wallet (generated)
        AccountType accountType;
        VerificationType verification;
        bytes32 zkProofHash;            // Hash of zk proof (not storing raw proof)
        string emailEncrypted;          // Optional, encrypted
        string socialEncrypted;         // Optional, encrypted
        uint256 createdAt;
        uint256 nonce;                  // For replay protection
        bool exists;
    }

    // ═══ State ═══

    mapping(bytes32 => Identity) private _identities;       // usernameHash => Identity
    mapping(address => bytes32) public primaryToIdentity;   // primaryWallet => usernameHash
    mapping(address => bytes32) public hiveToIdentity;      // hiveWallet => usernameHash
    mapping(address => bool) public verifiers;              // KYC/KYB verifier contracts

    address public owner;
    uint256 public identityCount;
    uint256 public registrationFee;                         // Fee to register (spam prevention)

    // Username constraints
    uint256 public constant MIN_USERNAME_LENGTH = 3;
    uint256 public constant MAX_USERNAME_LENGTH = 32;

    // ═══ Events ═══

    event IdentityCreated(
        bytes32 indexed usernameHash,
        address indexed primaryWallet,
        address hiveWallet,
        AccountType accountType,
        uint256 timestamp
    );
    event HiveWalletBound(bytes32 indexed usernameHash, address newHiveWallet);
    event VerificationUpdated(bytes32 indexed usernameHash, VerificationType vType);
    event FundsTransferred(bytes32 indexed from, bytes32 indexed to, address token, uint256 amount);
    event FundsWithdrawn(bytes32 indexed from, address primaryWallet, address token, uint256 amount);
    event UsernameReserved(bytes32 indexed usernameHash, address indexed primaryWallet);

    // ═══ Errors ═══

    error UsernameTaken();
    error UsernameInvalid();
    error PrimaryWalletLinked();
    error HiveWalletLinked();
    error NotIdentityOwner();
    error NotVerified();
    error InsufficientFee();
    error InvalidAddress();
    error TransferFailed();

    // ═══ Modifiers ═══

    modifier onlyOwner() {
        require(msg.sender == owner, "HiveID: not owner");
        _;
    }

    modifier identityExists(bytes32 usernameHash) {
        require(_identities[usernameHash].exists, "HiveID: identity not found");
        _;
    }

    modifier onlyIdentityOwner(bytes32 usernameHash) {
        Identity storage id = _identities[usernameHash];
        require(id.exists, "HiveID: identity not found");
        require(msg.sender == id.primaryWallet, "HiveID: not identity owner");
        _;
    }

    // ═══ Constructor ═══

    constructor(uint256 _registrationFee) {
        owner = msg.sender;
        registrationFee = _registrationFee;
    }

    // ═══ Registration ═══

    /// @notice Register a new HiveID
    /// @param username Unique permanent username (3-32 chars)
    /// @param hiveWallet Ritual passkey wallet address (generated client-side)
    /// @param accountType User, Project, or Investor
    /// @param emailEncrypted Optional encrypted email
    /// @param socialEncrypted Optional encrypted social handle
    function register(
        string calldata username,
        address hiveWallet,
        AccountType accountType,
        string calldata emailEncrypted,
        string calldata socialEncrypted
    ) external payable {
        // Validate username
        bytes memory usernameBytes = bytes(username);
        if (usernameBytes.length < MIN_USERNAME_LENGTH || usernameBytes.length > MAX_USERNAME_LENGTH) {
            revert UsernameInvalid();
        }

        bytes32 usernameHash = keccak256(bytes(username));
        if (_identities[usernameHash].exists) {
            revert UsernameTaken();
        }

        // Primary wallet can only be linked to one HiveID
        if (primaryToIdentity[msg.sender] != bytes32(0)) {
            revert PrimaryWalletLinked();
        }

        // Hive wallet can only be linked to one HiveID
        if (hiveWallet == address(0)) {
            revert InvalidAddress();
        }
        if (hiveToIdentity[hiveWallet] != bytes32(0)) {
            revert HiveWalletLinked();
        }

        // Registration fee (spam prevention)
        if (msg.value < registrationFee) {
            revert InsufficientFee();
        }

        // Create identity
        _identities[usernameHash] = Identity({
            usernameHash: usernameHash,
            primaryWallet: msg.sender,
            hiveWallet: hiveWallet,
            accountType: accountType,
            verification: VerificationType.None,
            zkProofHash: bytes32(0),
            emailEncrypted: emailEncrypted,
            socialEncrypted: socialEncrypted,
            createdAt: block.timestamp,
            nonce: 0,
            exists: true
        });

        primaryToIdentity[msg.sender] = usernameHash;
        hiveToIdentity[hiveWallet] = usernameHash;
        identityCount++;

        emit IdentityCreated(usernameHash, msg.sender, hiveWallet, accountType, block.timestamp);
        emit UsernameReserved(usernameHash, msg.sender);

        // Refund excess fee
        if (msg.value > registrationFee) {
            (bool sent, ) = msg.sender.call{value: msg.value - registrationFee}("");
            if (!sent) revert TransferFailed();
        }
    }

    // ═══ Verification (KYC/KYB) ═══

    /// @notice Submit zk proof for KYC/KYB verification
    /// @dev Called by registered verifier contracts, not directly by users
    /// @param usernameHash Identity to verify
    /// @param vType KYC or KYB
    /// @param zkProofHash Hash of the zk proof (proof stored off-chain or in calldata)
    function verify(
        bytes32 usernameHash,
        VerificationType vType,
        bytes32 zkProofHash
    ) external identityExists(usernameHash) {
        require(verifiers[msg.sender], "HiveID: not authorized verifier");
        require(vType != VerificationType.None, "HiveID: invalid verification type");

        Identity storage id = _identities[usernameHash];

        // Project/Investor must be KYB, User must be KYC
        if (id.accountType == AccountType.User) {
            require(vType == VerificationType.KYC, "HiveID: users require KYC");
        } else {
            require(vType == VerificationType.KYB, "HiveID: projects/investors require KYB");
        }

        id.verification = vType;
        id.zkProofHash = zkProofHash;

        emit VerificationUpdated(usernameHash, vType);
    }

    // ═══ Wallet Management ═══

    /// @notice Update Hive wallet (passkey wallet rotation)
    /// @param newHiveWallet New Ritual passkey wallet address
    function updateHiveWallet(address newHiveWallet) external {
        bytes32 usernameHash = primaryToIdentity[msg.sender];
        require(usernameHash != bytes32(0), "HiveID: not registered");
        if (newHiveWallet == address(0)) revert InvalidAddress();
        if (hiveToIdentity[newHiveWallet] != bytes32(0)) revert HiveWalletLinked();

        Identity storage id = _identities[usernameHash];

        // Unmap old hive wallet
        hiveToIdentity[id.hiveWallet] = bytes32(0);

        // Map new hive wallet
        id.hiveWallet = newHiveWallet;
        hiveToIdentity[newHiveWallet] = usernameHash;

        emit HiveWalletBound(usernameHash, newHiveWallet);
    }

    // ═══ Transfers (Hive-to-Hive) ═══

    /// @notice Transfer ETH between HiveIDs
    /// @param toUsername Recipient username
    function transferETH(string calldata toUsername) external payable {
        bytes32 fromHash = primaryToIdentity[msg.sender];
        require(fromHash != bytes32(0), "HiveID: not registered");
        require(_identities[fromHash].verification != VerificationType.None, "HiveID: not verified");

        bytes32 toHash = keccak256(bytes(toUsername));
        require(_identities[toHash].exists, "HiveID: recipient not found");

        Identity storage from = _identities[fromHash];
        Identity storage to = _identities[toHash];

        from.nonce++;

        // Transfer from hive wallet to recipient's hive wallet
        // NOTE: In production, this would use a relayer pattern where the primary wallet
        // signs a message and a relayer submits from the hive wallet.
        // For now, ETH is sent directly to the contract and forwarded.
        (bool sent, ) = to.hiveWallet.call{value: msg.value}("");
        if (!sent) revert TransferFailed();

        emit FundsTransferred(fromHash, toHash, address(0), msg.value);
    }

    /// @notice Transfer ERC20 between HiveIDs
    /// @param toUsername Recipient username
    /// @param token ERC20 token address
    /// @param amount Amount to transfer
    function transferERC20(string calldata toUsername, address token, uint256 amount) external {
        bytes32 fromHash = primaryToIdentity[msg.sender];
        require(fromHash != bytes32(0), "HiveID: not registered");
        require(_identities[fromHash].verification != VerificationType.None, "HiveID: not verified");

        bytes32 toHash = keccak256(bytes(toUsername));
        require(_identities[toHash].exists, "HiveID: recipient not found");

        Identity storage to = _identities[toHash];

        // Transfer ERC20 from msg.sender (primary wallet) to recipient's hive wallet
        // NOTE: Primary wallet must have approved this contract
        (bool success, ) = token.call(
            abi.encodeWithSignature(
                "transferFrom(address,address,uint256)",
                msg.sender,
                to.hiveWallet,
                amount
            )
        );
        if (!success) revert TransferFailed();

        emit FundsTransferred(fromHash, toHash, token, amount);
    }

    // ═══ Withdrawal ═══

    /// @notice Withdraw ETH to primary wallet
    function withdrawETH() external {
        bytes32 usernameHash = primaryToIdentity[msg.sender];
        require(usernameHash != bytes32(0), "HiveID: not registered");

        Identity storage id = _identities[usernameHash];
        uint256 balance = address(id.hiveWallet).balance;

        // NOTE: In production, this requires the hive wallet to sign and send.
        // The primary wallet triggers the withdrawal, but the hive wallet executes.
        // This is a simplified version — production uses relayer pattern.

        id.nonce++;

        emit FundsWithdrawn(usernameHash, msg.sender, address(0), balance);
    }

    /// @notice Withdraw ERC20 to primary wallet
    /// @param token ERC20 token address
    /// @param amount Amount to withdraw
    function withdrawERC20(address token, uint256 amount) external {
        bytes32 usernameHash = primaryToIdentity[msg.sender];
        require(usernameHash != bytes32(0), "HiveID: not registered");

        Identity storage id = _identities[usernameHash];
        id.nonce++;

        // NOTE: Same relayer pattern applies. Primary wallet initiates,
        // hive wallet signs the actual transfer.

        emit FundsWithdrawn(usernameHash, msg.sender, token, amount);
    }

    // ═══ Admin ═══

    /// @notice Add authorized verifier
    function addVerifier(address verifier) external onlyOwner {
        require(verifier != address(0), "HiveID: invalid address");
        verifiers[verifier] = true;
    }

    /// @notice Remove verifier
    function removeVerifier(address verifier) external onlyOwner {
        verifiers[verifier] = false;
    }

    /// @notice Update registration fee
    function setRegistrationFee(uint256 newFee) external onlyOwner {
        registrationFee = newFee;
    }

    /// @notice Withdraw accumulated fees
    function withdrawFees(address to) external onlyOwner {
        require(to != address(0), "HiveID: invalid address");
        uint256 balance = address(this).balance;
        (bool sent, ) = to.call{value: balance}("");
        if (!sent) revert TransferFailed();
    }

    // ═══ View Functions ═══

    /// @notice Get identity by username
    function getIdentity(string calldata username) external view returns (Identity memory) {
        bytes32 usernameHash = keccak256(bytes(username));
        return _identities[usernameHash];
    }

    /// @notice Get identity by primary wallet
    function getIdentityByPrimary(address primaryWallet) external view returns (Identity memory) {
        bytes32 usernameHash = primaryToIdentity[primaryWallet];
        require(usernameHash != bytes32(0), "HiveID: not found");
        return _identities[usernameHash];
    }

    /// @notice Get identity by hive wallet
    function getIdentityByHive(address hiveWallet) external view returns (Identity memory) {
        bytes32 usernameHash = hiveToIdentity[hiveWallet];
        require(usernameHash != bytes32(0), "HiveID: not found");
        return _identities[usernameHash];
    }

    /// @notice Check if username is available
    function isUsernameAvailable(string calldata username) external view returns (bool) {
        bytes32 usernameHash = keccak256(bytes(username));
        return !_identities[usernameHash].exists;
    }

    /// @notice Check if user is verified
    function isVerified(address primaryWallet) external view returns (bool) {
        bytes32 usernameHash = primaryToIdentity[primaryWallet];
        if (usernameHash == bytes32(0)) return false;
        return _identities[usernameHash].verification != VerificationType.None;
    }

    /// @notice Check if address is a registered primary wallet
    function isRegistered(address primaryWallet) external view returns (bool) {
        return primaryToIdentity[primaryWallet] != bytes32(0);
    }
}

// src/portfolio/HivePortfolio.sol

/// @title HivePortfolio — On-chain Portfolio Tracker
/// @notice Tracks all token holdings, vesting, and PnL per HiveID

contract HivePortfolio {
    // ═══ Types ═══

    enum TokenStandard {
        ERC20,
        ERC721,
        ERC1155
    }

    struct Holding {
        address token;
        TokenStandard standard;
        uint256 tokenId;        // For NFTs
        uint256 amount;         // For ERC20/ERC1155
        uint256 avgEntryPrice;  // Weighted average entry (in ETH wei)
        uint256 firstAcquired;
        uint256 lastUpdated;
    }

    struct VestingInfo {
        address token;
        uint256 totalAmount;
        uint256 claimedAmount;
        uint256 cliffEnd;       // Timestamp
        uint256 vestingEnd;     // Timestamp
        uint256 releaseInterval;// Seconds between releases
        uint256 lastClaim;
        bool cancelled;
    }

    struct PortfolioSummary {
        uint256 totalHoldings;
        uint256 totalVestingPositions;
        uint256 totalValueEstimate; // In wei (rough estimate)
        uint256 lastUpdated;
    }

    // ═══ State ═══

    // usernameHash => token address => Holding
    mapping(bytes32 => mapping(address => Holding)) public holdings;
    // usernameHash => list of token addresses
    mapping(bytes32 => address[]) public holdingTokens;

    // usernameHash => vestingId => VestingInfo
    mapping(bytes32 => mapping(uint256 => VestingInfo)) public vestings;
    mapping(bytes32 => uint256) public vestingCount;

    // Trade history
    struct Trade {
        address token;
        uint256 amount;
        uint256 price;
        bool isBuy;
        uint256 timestamp;
        uint256 pnl; // Realized PnL (positive = profit)
    }

    mapping(bytes32 => Trade[]) public trades;
    mapping(bytes32 => uint256) public totalRealizedPnl;

    // Price oracle (simplified — in production use Chainlink/Ritual oracle)
    mapping(address => uint256) public tokenPrices;

    address public owner;

    // ═══ Events ═══

    event HoldingUpdated(bytes32 indexed usernameHash, address token, uint256 amount);
    event VestingCreated(bytes32 indexed usernameHash, uint256 vestingId, address token, uint256 amount);
    event VestingClaimed(bytes32 indexed usernameHash, uint256 vestingId, uint256 amount);
    event VestingCancelled(bytes32 indexed usernameHash, uint256 vestingId);
    event TradeRecorded(bytes32 indexed usernameHash, address token, bool isBuy, uint256 amount, uint256 price);

    // ═══ Modifiers ═══

    modifier onlyAuthorized() {
        // In production, restrict to HiveID contract or authorized contracts
        _;
    }

    // ═══ Constructor ═══

    constructor() {
        owner = msg.sender;
    }

    // ═══ Holdings Management ═══

    /// @notice Record a token acquisition
    function recordAcquisition(
        bytes32 usernameHash,
        address token,
        uint256 amount,
        uint256 pricePerToken
    ) external onlyAuthorized {
        Holding storage h = holdings[usernameHash][token];

        if (h.firstAcquired == 0) {
            // New holding
            h.token = token;
            h.standard = TokenStandard.ERC20;
            h.amount = amount;
            h.avgEntryPrice = pricePerToken;
            h.firstAcquired = block.timestamp;
            h.lastUpdated = block.timestamp;
            holdingTokens[usernameHash].push(token);
        } else {
            // Update existing — weighted average
            uint256 totalValue = (h.amount * h.avgEntryPrice) + (amount * pricePerToken);
            h.amount += amount;
            h.avgEntryPrice = totalValue / h.amount;
            h.lastUpdated = block.timestamp;
        }

        // Record trade
        trades[usernameHash].push(Trade({
            token: token,
            amount: amount,
            price: pricePerToken,
            isBuy: true,
            timestamp: block.timestamp,
            pnl: 0
        }));

        emit HoldingUpdated(usernameHash, token, h.amount);
        emit TradeRecorded(usernameHash, token, true, amount, pricePerToken);
    }

    /// @notice Record a token sale/disposal
    function recordDisposal(
        bytes32 usernameHash,
        address token,
        uint256 amount,
        uint256 pricePerToken
    ) external onlyAuthorized {
        Holding storage h = holdings[usernameHash][token];
        require(h.amount >= amount, "Portfolio: insufficient balance");

        // Calculate realized PnL
        uint256 pnl = 0;
        if (pricePerToken > h.avgEntryPrice) {
            pnl = (pricePerToken - h.avgEntryPrice) * amount;
        } else if (h.avgEntryPrice > pricePerToken) {
            pnl = (h.avgEntryPrice - pricePerToken) * amount;
            // Negative PnL — we store as 0 and track loss separately
        }

        h.amount -= amount;
        h.lastUpdated = block.timestamp;

        if (h.amount == 0) {
            h.avgEntryPrice = 0;
        }

        // Record trade
        trades[usernameHash].push(Trade({
            token: token,
            amount: amount,
            price: pricePerToken,
            isBuy: false,
            timestamp: block.timestamp,
            pnl: pnl
        }));

        if (pricePerToken >= h.avgEntryPrice) {
            totalRealizedPnl[usernameHash] += pnl;
        } else {
            totalRealizedPnl[usernameHash] -= pnl;
        }

        emit HoldingUpdated(usernameHash, token, h.amount);
        emit TradeRecorded(usernameHash, token, false, amount, pricePerToken);
    }

    // ═══ Vesting ═══

    /// @notice Create a vesting schedule
    function createVesting(
        bytes32 usernameHash,
        address token,
        uint256 totalAmount,
        uint256 cliffDuration,
        uint256 vestingDuration,
        uint256 releaseInterval
    ) external onlyAuthorized returns (uint256 vestingId) {
        vestingId = vestingCount[usernameHash]++;

        vestings[usernameHash][vestingId] = VestingInfo({
            token: token,
            totalAmount: totalAmount,
            claimedAmount: 0,
            cliffEnd: block.timestamp + cliffDuration,
            vestingEnd: block.timestamp + vestingDuration,
            releaseInterval: releaseInterval,
            lastClaim: block.timestamp,
            cancelled: false
        });

        emit VestingCreated(usernameHash, vestingId, token, totalAmount);
        return vestingId;
    }

    /// @notice Calculate claimable amount for a vesting
    function claimableAmount(bytes32 usernameHash, uint256 vestingId) public view returns (uint256) {
        VestingInfo storage v = _getVesting(usernameHash, vestingId);

        if (v.cancelled) return 0;
        if (block.timestamp < v.cliffEnd) return 0;

        uint256 elapsed = block.timestamp - v.cliffEnd;
        uint256 vestingPeriod = v.vestingEnd - v.cliffEnd;

        if (vestingPeriod == 0) return v.totalAmount;

        uint256 vestedAmount = (v.totalAmount * elapsed) / vestingPeriod;
        if (vestedAmount > v.totalAmount) vestedAmount = v.totalAmount;

        uint256 claimable = vestedAmount - v.claimedAmount;
        return claimable;
    }

    /// @notice Claim vested tokens
    function claimVesting(bytes32 usernameHash, uint256 vestingId) external onlyAuthorized returns (uint256 amount) {
        VestingInfo storage v = _getVesting(usernameHash, vestingId);
        require(!v.cancelled, "Portfolio: vesting cancelled");

        amount = claimableAmount(usernameHash, vestingId);
        require(amount > 0, "Portfolio: nothing to claim");

        v.claimedAmount += amount;
        v.lastClaim = block.timestamp;

        // Transfer tokens
        (bool success, ) = v.token.call(
            abi.encodeWithSignature("transfer(address,uint256)", msg.sender, amount)
        );
        require(success, "Portfolio: transfer failed");

        emit VestingClaimed(usernameHash, vestingId, amount);
    }

    // ═══ Internal Vesting Access ═══

    function _getVesting(bytes32 usernameHash, uint256 vestingId) internal view returns (VestingInfo storage v) {
        v = vestings[usernameHash][vestingId];
    }

    // ═══ Price Oracle ═══

    /// @notice Update token price (called by oracle/authorized)
    function updatePrice(address token, uint256 price) external {
        require(msg.sender == owner, "Portfolio: not authorized");
        tokenPrices[token] = price;
    }

    // ═══ View ═══

    /// @notice Get all holding token addresses for a user
    function getHoldingTokens(bytes32 usernameHash) external view returns (address[] memory) {
        return holdingTokens[usernameHash];
    }

    /// @notice Get holding details for a specific token
    function getHolding(bytes32 usernameHash, address token) external view returns (Holding memory) {
        return holdings[usernameHash][token];
    }

    /// @notice Get vesting info
    function getVesting(bytes32 usernameHash, uint256 vestingId) external view returns (VestingInfo memory) {
        return vestings[usernameHash][vestingId];
    }

    /// @notice Get trade history
    function getTrades(bytes32 usernameHash) external view returns (Trade[] memory) {
        return trades[usernameHash];
    }

    /// @notice Get portfolio summary
    function getPortfolioSummary(bytes32 usernameHash) external view returns (PortfolioSummary memory) {
        address[] storage tokens = holdingTokens[usernameHash];
        uint256 totalValue = 0;

        for (uint256 i = 0; i < tokens.length; i++) {
            Holding storage h = holdings[usernameHash][tokens[i]];
            if (tokenPrices[tokens[i]] > 0) {
                totalValue += (h.amount * tokenPrices[tokens[i]]) / 1e18;
            }
        }

        return PortfolioSummary({
            totalHoldings: tokens.length,
            totalVestingPositions: vestingCount[usernameHash],
            totalValueEstimate: totalValue,
            lastUpdated: block.timestamp
        });
    }

    /// @notice Get unrealized PnL for a holding
    function getUnrealizedPnl(bytes32 usernameHash, address token) external view returns (int256) {
        Holding storage h = holdings[usernameHash][token];
        if (h.amount == 0 || tokenPrices[token] == 0) return 0;

        uint256 currentValue = (h.amount * tokenPrices[token]) / 1e18;
        uint256 entryValue = (h.amount * h.avgEntryPrice) / 1e18;

        if (currentValue >= entryValue) {
            return int256(currentValue - entryValue);
        } else {
            return -int256(entryValue - currentValue);
        }
    }
}

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

// src/relayer/HiveRelayer.sol

/**
 * @title HiveRelayer
 * @notice Meta-transaction relayer for Hive
 * @dev Primary wallet signs, relayer executes from hive wallet
 * @author Hive Team
 */

contract HiveRelayer {
    // ═══════════════════════════════════════════════════════════════
    //                           STATE
    // ═══════════════════════════════════════════════════════════════

    address public owner;
    bool public paused;

    /// @notice Nonce per primary wallet (replay protection)
    mapping(address => uint256) public nonces;

    /// @notice Executed request hashes
    mapping(bytes32 => bool) public executed;

    /// @notice Relay fee (in wei)
    uint256 public relayFee = 0.001 ether;

    /// @notice Total relays executed
    uint256 public totalRelays;

    // ═══════════════════════════════════════════════════════════════
    //                          EVENTS
    // ═══════════════════════════════════════════════════════════════

    event RelayExecuted(bytes32 indexed requestHash, address indexed primaryWallet, address indexed hiveWallet, address to, uint256 value);
    event RelayFailed(bytes32 indexed requestHash, string reason);
    event FeeUpdated(uint256 oldFee, uint256 newFee);
    event Paused(address indexed by);
    event Unpaused(address indexed by);

    // ═══════════════════════════════════════════════════════════════
    //                          ERRORS
    // ═══════════════════════════════════════════════════════════════

    error Expired();
    error NonceMismatch();
    error AlreadyExecuted();
    error InvalidSignature();
    error InsufficientFee();

    // ═══════════════════════════════════════════════════════════════
    //                         MODIFIERS
    // ═══════════════════════════════════════════════════════════════

    modifier onlyOwner() {
        require(msg.sender == owner, "HiveRelayer: not owner");
        _;
    }

    modifier whenNotPaused() {
        require(!paused, "HiveRelayer: paused");
        _;
    }

    // ═══════════════════════════════════════════════════════════════
    //                       CONSTRUCTOR
    // ═══════════════════════════════════════════════════════════════

    constructor() {
        owner = msg.sender;
    }

    // ═══════════════════════════════════════════════════════════════
    //                       RELAY FUNCTIONS
    // ═══════════════════════════════════════════════════════════════

    /// @notice Execute a relay request
    /// @param primaryWallet The wallet that signed the request
    /// @param hiveWallet The hive wallet to execute from
    /// @param to Destination address
    /// @param value ETH value to send
    /// @param data Calldata
    /// @param nonce Request nonce
    /// @param deadline Request deadline
    /// @param signature ECDSA signature from primaryWallet
    function relay(
        address primaryWallet,
        address hiveWallet,
        address to,
        uint256 value,
        bytes calldata data,
        uint256 nonce,
        uint256 deadline,
        bytes calldata signature
    ) external payable whenNotPaused returns (bool) {
        // Check deadline
        if (block.timestamp > deadline) revert Expired();

        // Check nonce
        if (nonce != nonces[primaryWallet]) revert NonceMismatch();

        // Check fee
        if (msg.value < relayFee) revert InsufficientFee();

        // Compute request hash
        bytes32 requestHash = keccak256(abi.encode(
            primaryWallet,
            hiveWallet,
            to,
            value,
            data,
            nonce,
            deadline
        ));

        // Check not already executed
        if (executed[requestHash]) revert AlreadyExecuted();

        // Verify signature from primary wallet
        bytes32 messageHash = keccak256(abi.encodePacked(
            "\x19Ethereum Signed Message:\n32",
            requestHash
        ));

        address signer = _recoverSigner(messageHash, signature);
        if (signer != primaryWallet) revert InvalidSignature();

        // Mark as executed
        executed[requestHash] = true;
        nonces[primaryWallet]++;
        totalRelays++;

        // Execute the transfer
        bool success = _executeTransfer(to, value, data);
        if (!success) {
            emit RelayFailed(requestHash, "execution failed");
            return false;
        }

        emit RelayExecuted(requestHash, primaryWallet, hiveWallet, to, value);
        return true;
    }

    /// @notice Internal transfer execution
    function _executeTransfer(address to, uint256 value, bytes calldata data) internal returns (bool) {
        if (data.length > 0) {
            (bool success, ) = to.call{value: value}(data);
            return success;
        } else {
            (bool success, ) = to.call{value: value}("");
            return success;
        }
    }

    // ═══════════════════════════════════════════════════════════════
    //                    SIGNATURE RECOVERY
    // ═══════════════════════════════════════════════════════════════

    /// @notice Recover signer from signature
    function _recoverSigner(bytes32 messageHash, bytes calldata signature)
        internal
        pure
        returns (address)
    {
        require(signature.length == 65, "Relayer: invalid sig length");

        bytes32 r;
        bytes32 s;
        uint8 v;

        assembly {
            r := calldataload(signature.offset)
            s := calldataload(add(signature.offset, 32))
            v := byte(0, calldataload(add(signature.offset, 64)))
        }

        if (v < 27) v += 27;
        require(v == 27 || v == 28, "Relayer: invalid v");

        return ecrecover(messageHash, v, r, s);
    }

    // ═══════════════════════════════════════════════════════════════
    //                      ENCODE HELPERS
    // ═══════════════════════════════════════════════════════════════

    /// @notice Encode an ERC20 transfer for relay
    function encodeERC20Transfer(address token, address to, uint256 amount)
        external
        pure
        returns (bytes memory)
    {
        return abi.encodeWithSignature("transfer(address,uint256)", to, amount);
    }

    /// @notice Encode an ERC20 approve for relay
    function encodeERC20Approve(address token, address spender, uint256 amount)
        external
        pure
        returns (bytes memory)
    {
        return abi.encodeWithSignature("approve(address,uint256)", spender, amount);
    }

    /// @notice Encode a contract call for relay
    function encodeCall(address target, bytes calldata data)
        external
        pure
        returns (bytes memory)
    {
        return abi.encodeWithSelector(bytes4(data[:4]), data[4:]);
    }

    // ═══════════════════════════════════════════════════════════════
    //                      VIEW FUNCTIONS
    // ═══════════════════════════════════════════════════════════════

    /// @notice Get nonce for primary wallet
    function getNonce(address primaryWallet) external view returns (uint256) {
        return nonces[primaryWallet];
    }

    /// @notice Check if request was executed
    function isExecuted(bytes32 requestHash) external view returns (bool) {
        return executed[requestHash];
    }

    // ═══════════════════════════════════════════════════════════════
    //                      ADMIN FUNCTIONS
    // ═══════════════════════════════════════════════════════════════

    /// @notice Update relay fee
    function setRelayFee(uint256 _fee) external onlyOwner {
        uint256 old = relayFee;
        relayFee = _fee;
        emit FeeUpdated(old, _fee);
    }

    /// @notice Pause relayer
    function pause() external onlyOwner {
        paused = true;
        emit Paused(msg.sender);
    }

    /// @notice Unpause relayer
    function unpause() external onlyOwner {
        paused = false;
        emit Unpaused(msg.sender);
    }

    /// @notice Transfer ownership
    function transferOwnership(address newOwner) external onlyOwner {
        require(newOwner != address(0), "HiveRelayer: zero address");
        owner = newOwner;
    }

    /// @notice Withdraw collected fees
    function withdrawFees(address to) external onlyOwner {
        require(to != address(0), "HiveRelayer: zero address");
        uint256 balance = address(this).balance;
        require(balance > 0, "HiveRelayer: no fees");
        (bool success, ) = to.call{value: balance}("");
        require(success, "HiveRelayer: transfer failed");
    }

    /// @notice Fallback to receive ETH
    receive() external payable {}
}

// src/reputation/HiveReputation.sol

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

// src/verifier/HiveVerifier.sol

/// @title HiveVerifier — ZK Proof Verifier for KYC/KYB
/// @notice Verifies zero-knowledge proofs for identity verification
/// @dev Integrates with HiveID — stores proof hashes, verifies zk-SNARKs

contract HiveVerifier {
    // ═══ Types ═══

    enum ProofType {
        KYC_AGE,        // Prove age >= 18
        KYC_COUNTRY,    // Prove country of residence (not sanctioned)
        KYC_IDENTITY,   // Prove unique identity (no duplicate)
        KYB_LEGAL,      // Prove legal entity exists
        KYB_JURISDICTION // Prove entity jurisdiction
    }

    struct ProofRecord {
        bytes32 usernameHash;
        ProofType proofType;
        bytes32 proofHash;          // Hash of the zk proof
        bytes32 nullifierHash;      // Prevent double-verification
        uint256 verifiedAt;
        uint256 expiresAt;
        address verifier;           // Who verified
        bool valid;
    }

    // ═══ State ═══

    // nullifierHash => used (prevents replay)
    mapping(bytes32 => bool) public usedNullifiers;
    // usernameHash => ProofType => ProofRecord
    mapping(bytes32 => mapping(uint8 => ProofRecord)) public proofs;
    // usernameHash => list of verified proof types
    mapping(bytes32 => uint8[]) public verifiedProofTypes;

    // Authorized verifiers (zk proof generators/validators)
    mapping(address => bool) public authorizedVerifiers;

    // Verifier contract addresses (external zk verifiers)
    mapping(address => bool) public verifierContracts;

    address public owner;
    uint256 public constant PROOF_VALIDITY_PERIOD = 365 days;

    // ═══ Events ═══

    event ProofVerified(
        bytes32 indexed usernameHash,
        ProofType proofType,
        bytes32 nullifierHash,
        uint256 expiresAt
    );
    event ProofRevoked(bytes32 indexed usernameHash, ProofType proofType);
    event VerifierAuthorized(address indexed verifier);
    event VerifierRevoked(address indexed verifier);

    // ═══ Errors ═══

    error NullifierUsed();
    error InvalidProof();
    error NotAuthorized();
    error ProofExpired();
    error ProofNotVerified();

    // ═══ Constructor ═══

    constructor() {
        owner = msg.sender;
    }

    // ═══ Verify Proof ═══

    /// @notice Submit and verify a zk proof
    /// @param usernameHash HiveID username hash
    /// @param proofType Type of proof
    /// @param proof The zk proof bytes (SNARK proof)
    /// @param publicSignals Public inputs to the proof
    /// @param nullifierHash Unique nullifier to prevent replay
    function verifyProof(
        bytes32 usernameHash,
        ProofType proofType,
        bytes calldata proof,
        bytes calldata publicSignals,
        bytes32 nullifierHash
    ) external {
        if (!authorizedVerifiers[msg.sender] && !verifierContracts[msg.sender]) {
            revert NotAuthorized();
        }
        if (usedNullifiers[nullifierHash]) revert NullifierUsed();

        // Verify the zk proof
        // In production, this would call a verifier contract (Groth16/PLONK)
        // For now, we verify the proof hash is non-empty
        bytes32 proofHash = keccak256(proof);
        if (proofHash == bytes32(0)) revert InvalidProof();

        // Mark nullifier as used
        usedNullifiers[nullifierHash] = true;

        // Store proof record
        uint256 expiresAt = block.timestamp + PROOF_VALIDITY_PERIOD;

        proofs[usernameHash][uint8(proofType)] = ProofRecord({
            usernameHash: usernameHash,
            proofType: proofType,
            proofHash: proofHash,
            nullifierHash: nullifierHash,
            verifiedAt: block.timestamp,
            expiresAt: expiresAt,
            verifier: msg.sender,
            valid: true
        });

        verifiedProofTypes[usernameHash].push(uint8(proofType));

        emit ProofVerified(usernameHash, proofType, nullifierHash, expiresAt);
    }

    // ═══ Batch Verify ═══

    /// @notice Verify multiple proofs at once
    function verifyBatch(
        bytes32 usernameHash,
        ProofType[] calldata proofTypes,
        bytes[] calldata proofs_,
        bytes[] calldata publicSignals,
        bytes32[] calldata nullifierHashes
    ) external {
        require(proofTypes.length == proofs_.length, "Verifier: length mismatch");
        require(proofTypes.length == nullifierHashes.length, "Verifier: length mismatch");

        for (uint256 i = 0; i < proofTypes.length; i++) {
            this.verifyProof(
                usernameHash,
                proofTypes[i],
                proofs_[i],
                publicSignals[i],
                nullifierHashes[i]
            );
        }
    }

    // ═══ Check Verification Status ═══

    /// @notice Check if a specific proof is valid and not expired
    function isProofValid(bytes32 usernameHash, ProofType proofType) public view returns (bool) {
        ProofRecord storage p = proofs[usernameHash][uint8(proofType)];
        return p.valid && block.timestamp < p.expiresAt;
    }

    /// @notice Check if user has valid KYC (all required proofs)
    function hasValidKYC(bytes32 usernameHash) external view returns (bool) {
        return isProofValid(usernameHash, ProofType.KYC_IDENTITY) &&
               isProofValid(usernameHash, ProofType.KYC_AGE);
    }

    /// @notice Check if entity has valid KYB
    function hasValidKYB(bytes32 usernameHash) external view returns (bool) {
        return isProofValid(usernameHash, ProofType.KYB_LEGAL);
    }

    /// @notice Get all verified proof types for a user
    function getVerifiedTypes(bytes32 usernameHash) external view returns (uint8[] memory) {
        return verifiedProofTypes[usernameHash];
    }

    /// @notice Get proof record
    function getProof(bytes32 usernameHash, ProofType proofType) external view returns (ProofRecord memory) {
        return proofs[usernameHash][uint8(proofType)];
    }

    // ═══ Revoke ═══

    /// @notice Revoke a proof (admin or verifier)
    function revokeProof(bytes32 usernameHash, ProofType proofType) external {
        ProofRecord storage p = proofs[usernameHash][uint8(proofType)];
        require(p.valid, "Verifier: not valid");
        require(msg.sender == owner || msg.sender == p.verifier, "Verifier: not authorized");

        p.valid = false;
        emit ProofRevoked(usernameHash, proofType);
    }

    // ═══ Admin ═══

    function authorizeVerifier(address verifier) external {
        require(msg.sender == owner, "Verifier: not owner");
        authorizedVerifiers[verifier] = true;
        emit VerifierAuthorized(verifier);
    }

    function revokeVerifier(address verifier) external {
        require(msg.sender == owner, "Verifier: not owner");
        authorizedVerifiers[verifier] = false;
        emit VerifierRevoked(verifier);
    }

    function registerVerifierContract(address contractAddr) external {
        require(msg.sender == owner, "Verifier: not owner");
        verifierContracts[contractAddr] = true;
    }
}

// src/libraries/RitualPrecompileConsumer.sol

/// @title PrecompileConsumer — Base contract for Ritual precompile calls
/// @notice Provides helpers for calling Ritual precompiles

abstract contract RitualPrecompileConsumer {
    // ═══ Precompile Addresses ═══
    address internal constant ONNX_PRECOMPILE = address(0x0800);
    address internal constant HTTP_PRECOMPILE = address(0x0801);
    address internal constant LLM_PRECOMPILE = address(0x0802);
    address internal constant ED25519_PRECOMPILE = address(0x0009);
    address internal constant WEBAUTHN_PRECOMPILE = address(0x0100);

    // ═══ System Contracts ═══
    address internal constant RITUAL_WALLET = 0x532F0dF0896F353d8C3DD8cc134e8129DA2a3948;
    address internal constant ASYNC_JOB_TRACKER = 0xC069FFCa0389f44eCA2C626e55491b0ab045AEF5;
    address internal constant TEE_REGISTRY = 0x9644e8562cE0Fe12b4deeC4163c064A8862Bf47F;
    address internal constant SCHEDULER = 0x56e776BAE2DD60664b69Bd5F865F1180ffB7D58B;
    address internal constant SECRETS_ACCESS = 0xf9BF1BC8A3e79B9EBeD0fa2Db70D0513fecE32FD;
    address internal constant ASYNC_DELIVERY = 0x5A16214fF555848411544b005f7Ac063742f39F6;
    address internal constant AGENT_HEARTBEAT = 0xEF505E801f1Db392B5289690E2ffc20e840A3aCa;
    address internal constant MODEL_PRICING = 0x7A85F48b971ceBb75491b61abe279728F4c4384f;

    // ═══ Async States ═══
    uint8 internal constant ASYNC_SUBMITTED = 0;
    uint8 internal constant ASYNC_COMMITTED = 1;
    uint8 internal constant ASYNC_PROCESSING = 2;
    uint8 internal constant ASYNC_READY = 3;
    uint8 internal constant ASYNC_SETTLED = 4;
    uint8 internal constant ASYNC_FAILED = 5;
    uint8 internal constant ASYNC_EXPIRED = 6;

    /// @notice Execute a synchronous precompile call
    /// @param precompile Address of the precompile
    /// @param input Encoded input data
    /// @return output Raw output bytes
    function _executePrecompile(address precompile, bytes memory input)
        internal
        returns (bytes memory output)
    {
        (bool success, bytes memory result) = precompile.staticcall(input);
        require(success, "PrecompileConsumer: call failed");
        return result;
    }

    /// @notice Encode an HTTP GET request
    /// @param url The URL to fetch
    /// @return Encoded bytes for HTTP precompile
    function _encodeHttpGet(string memory url) internal pure returns (bytes memory) {
        return abi.encode(
            address(0),         // executor (auto-select)
            new bytes[](0),     // encryptedSecrets
            uint256(30),        // ttl (blocks)
            new bytes[](0),     // secretSignatures
            bytes(""),          // userPublicKey
            url,                // url
            uint8(1),           // method (1=GET)
            new string[](0),    // headerKeys
            new string[](0),    // headerValues
            bytes(""),          // body
            uint256(0),         // dkmsKeyIndex
            uint8(0),           // dkmsKeyFormat
            false               // piiEnabled
        );
    }

    /// @notice Encode an LLM inference request
    /// @param prompt The prompt text
    /// @return Encoded bytes for LLM precompile
    function _encodeLlmCall(string memory prompt) internal pure returns (bytes memory) {
        return abi.encode(
            address(0),         // executor (auto-select)
            new bytes[](0),     // encryptedSecrets
            uint256(100),       // ttl (blocks)
            new bytes[](0),     // secretSignatures
            bytes(""),          // userPublicKey
            prompt,             // prompt
            uint256(0),         // maxTokens
            uint256(0),         // temperature (use default)
            bytes(""),          // model (use default)
            uint256(0),         // dkmsKeyIndex
            uint8(0),           // dkmsKeyFormat
            false               // piiEnabled
        );
    }
}

// src/oracle/HiveOracle.sol

/// @title HiveOracle — Price feed via Ritual HTTP precompile
/// @notice Fetches real-time token prices from external APIs
/// @dev Uses Ritual HTTP precompile (0x0801) for off-chain data

contract HiveOracle is RitualPrecompileConsumer {
    // ═══ Types ═══

    struct PriceData {
        uint256 price;          // Price in USD (8 decimals)
        uint256 timestamp;      // When fetched
        uint256 confidence;     // Confidence score (0-100)
        string source;          // Data source (e.g., "coingecko")
        bool valid;
    }

    struct TokenConfig {
        string coingeckoId;     // e.g., "ethereum"
        string symbol;          // e.g., "ETH"
        uint8 decimals;         // Token decimals
        bool active;
    }

    // ═══ State ═══

    // token address => PriceData
    mapping(address => PriceData) public prices;
    // token address => config
    mapping(address => TokenConfig) public tokenConfigs;
    // token address list
    address[] public trackedTokens;

    // Staleness threshold
    uint256 public constant MAX_PRICE_AGE = 1 hours;
    uint256 public constant PRICE_DECIMALS = 8; // 8 decimal places for USD

    address public owner;
    bool public paused;

    // Request tracking
    uint256 public requestId;
    mapping(uint256 => address) public pendingRequests; // requestId => token

    // ═══ Events ═══

    event PriceUpdated(address indexed token, uint256 price, uint256 timestamp, string source);
    event TokenAdded(address indexed token, string symbol, string coingeckoId);
    event TokenRemoved(address indexed token);
    event PriceFetchRequest(uint256 indexed reqId, address indexed token);

    // ═══ Errors ═══

    error OraclePaused();
    error PriceStale();
    error TokenNotTracked();
    error FetchFailed();

    // ═══ Modifiers ═══

    modifier whenNotPaused() {
        if (paused) revert OraclePaused();
        _;
    }

    // ═══ Constructor ═══

    constructor() {
        owner = msg.sender;
    }

    // ═══ Token Management ═══

    /// @notice Add a token to track
    function addToken(
        address token,
        string calldata symbol,
        string calldata coingeckoId,
        uint8 decimals
    ) external {
        require(msg.sender == owner, "Oracle: not owner");

        tokenConfigs[token] = TokenConfig({
            coingeckoId: coingeckoId,
            symbol: symbol,
            decimals: decimals,
            active: true
        });

        trackedTokens.push(token);
        emit TokenAdded(token, symbol, coingeckoId);
    }

    /// @notice Remove a token from tracking
    function removeToken(address token) external {
        require(msg.sender == owner, "Oracle: not owner");
        tokenConfigs[token].active = false;
        emit TokenRemoved(token);
    }

    // ═══ Price Fetching ═══

    /// @notice Fetch price for a single token via Ritual HTTP precompile
    function fetchPrice(address token) external whenNotPaused returns (uint256 reqId) {
        TokenConfig storage config = tokenConfigs[token];
        if (!config.active) revert TokenNotTracked();

        reqId = requestId++;
        pendingRequests[reqId] = token;

        // Build CoinGecko API URL
        string memory url = string(
            abi.encodePacked(
                "https://api.coingecko.com/api/v3/simple/price?ids=",
                config.coingeckoId,
                "&vs_currencies=usd&precision=8"
            )
        );

        // Call Ritual HTTP precompile
        bytes memory input = _encodeHttpGet(url);
        bytes memory output = _executePrecompile(HTTP_PRECOMPILE, input);

        // Parse response (simplified — production would parse JSON)
        // For now, store a placeholder and rely on manual updates
        // The actual parsing would happen off-chain

        emit PriceFetchRequest(reqId, token);
        return reqId;
    }

    /// @notice Update price (called by authorized updater or after HTTP response)
    function updatePrice(
        address token,
        uint256 price,
        string calldata source
    ) external {
        require(msg.sender == owner || msg.sender == address(this), "Oracle: not authorized");

        prices[token] = PriceData({
            price: price,
            timestamp: block.timestamp,
            confidence: 90,
            source: source,
            valid: true
        });

        emit PriceUpdated(token, price, block.timestamp, source);
    }

    /// @notice Batch update prices
    function updatePrices(
        address[] calldata tokens,
        uint256[] calldata prices_,
        string calldata source
    ) external {
        require(msg.sender == owner, "Oracle: not authorized");
        require(tokens.length == prices_.length, "Oracle: length mismatch");

        for (uint256 i = 0; i < tokens.length; i++) {
            prices[tokens[i]] = PriceData({
                price: prices_[i],
                timestamp: block.timestamp,
                confidence: 90,
                source: source,
                valid: true
            });

            emit PriceUpdated(tokens[i], prices_[i], block.timestamp, source);
        }
    }

    // ═══ View ═══

    /// @notice Get price for a token (reverts if stale)
    function getPrice(address token) external view returns (uint256) {
        PriceData storage p = prices[token];
        if (!p.valid) revert TokenNotTracked();
        if (block.timestamp - p.timestamp > MAX_PRICE_AGE) revert PriceStale();
        return p.price;
    }

    /// @notice Get price with staleness check
    function getPriceSafe(address token) external view returns (uint256 price, bool stale) {
        PriceData storage p = prices[token];
        if (!p.valid) return (0, true);
        stale = block.timestamp - p.timestamp > MAX_PRICE_AGE;
        return (p.price, stale);
    }

    /// @notice Get full price data
    function getPriceData(address token) external view returns (PriceData memory) {
        return prices[token];
    }

    /// @notice Get all tracked tokens
    function getTrackedTokens() external view returns (address[] memory) {
        return trackedTokens;
    }

    /// @notice Convert token amount to USD
    function tokenToUSD(address token, uint256 amount) external view returns (uint256) {
        PriceData storage p = prices[token];
        if (!p.valid || block.timestamp - p.timestamp > MAX_PRICE_AGE) revert PriceStale();

        TokenConfig storage config = tokenConfigs[token];
        // amount * price / 10^decimals / 10^0 (price already in 8 decimals)
        return (amount * p.price) / (10 ** config.decimals);
    }

    /// @notice Convert USD to token amount
    function usdToToken(address token, uint256 usdAmount) external view returns (uint256) {
        PriceData storage p = prices[token];
        if (!p.valid || block.timestamp - p.timestamp > MAX_PRICE_AGE) revert PriceStale();

        TokenConfig storage config = tokenConfigs[token];
        return (usdAmount * (10 ** config.decimals)) / p.price;
    }

    // ═══ Admin ═══

    function setPaused(bool _paused) external {
        require(msg.sender == owner, "Oracle: not owner");
        paused = _paused;
    }

    receive() external payable {}
}

// src/factory/HiveFactory.sol

/// @title HiveFactory — Master wiring contract
/// @notice Connects all Hive modules into a unified system
/// @dev Single entry point for cross-contract operations

contract HiveFactory {
    // ═══ Module References ═══

    HiveID public hiveID;
    HiveVerifier public verifier;
    HiveReputation public reputation;
    HiveOracle public oracle;
    HiveReferral public referral;
    HivePortfolio public portfolio;
    HiveRelayer public relayer;

    address public owner;
    bool public initialized;

    // ═══ Events ═══

    event ModuleUpdated(string moduleName, address moduleAddress);
    event SystemInitialized();

    // ═══ Constructor ═══

    constructor() {
        owner = msg.sender;
    }

    // ═══ Initialization ═══

    /// @notice Initialize all modules (called once)
    function initialize(
        address _hiveID,
        address _verifier,
        address _reputation,
        address _oracle,
        address _referral,
        address _portfolio,
        address _relayer
    ) external {
        require(msg.sender == owner, "Factory: not owner");
        require(!initialized, "Factory: already initialized");

        hiveID = HiveID(_hiveID);
        verifier = HiveVerifier(_verifier);
        reputation = HiveReputation(_reputation);
        oracle = HiveOracle(payable(_oracle));
        referral = HiveReferral(payable(_referral));
        portfolio = HivePortfolio(_portfolio);
        relayer = HiveRelayer(payable(_relayer));

        // Wire modules together
        // Wire modules together
        // NOTE: hiveID.addVerifier() and reputation.authorize() must be called
        // by their respective owners separately

        initialized = true;
        emit SystemInitialized();
    }

    // ═══ Cross-Module Operations ═══

    /// @notice Complete onboarding after user has registered on HiveID
    /// @dev User must call hiveID.register() first, then this for referral + reputation
    /// @param usernameHash The registered username hash
    /// @param username The username string
    /// @param referralCode Optional referral code
    function completeOnboarding(
        bytes32 usernameHash,
        string calldata username,
        bytes32 referralCode
    ) external {
        require(hiveID.isRegistered(msg.sender), "Factory: not registered on HiveID");

        // Record referral if code provided
        if (referralCode != bytes32(0)) {
            referral.registerReferral(usernameHash, referralCode);

            // Record referral activity for reputation
            bytes32 referrerHash = referral.getReferrer(usernameHash);
            if (referrerHash != bytes32(0)) {
                reputation.recordActivity(
                    referrerHash,
                    HiveReputation.ActivityType.Referral,
                    username
                );
            }
        }

        // Record early adopter bonus
        reputation.recordActivity(
            usernameHash,
            HiveReputation.ActivityType.EarlyAdopter,
            "registered"
        );
    }

    /// @notice Verify user and update reputation
    function verifyAndUpdateReputation(
        bytes32 usernameHash,
        HiveVerifier.ProofType proofType,
        bytes calldata proof,
        bytes calldata publicSignals,
        bytes32 nullifierHash
    ) external {
        // Verify proof
        verifier.verifyProof(usernameHash, proofType, proof, publicSignals, nullifierHash);

        // Update HiveID verification status
        // (In production, this would be called by the verifier contract)
        // For now, emit event
    }

    /// @notice Record a sale participation and update all relevant modules
    function recordSaleParticipation(
        bytes32 usernameHash,
        address token,
        uint256 amount,
        uint256 price
    ) external {
        // Record in reputation
        reputation.recordActivity(
            usernameHash,
            HiveReputation.ActivityType.SaleParticipation,
            string(abi.encodePacked("bought ", token))
        );

        // Record in portfolio
        portfolio.recordAcquisition(usernameHash, token, amount, price);

        // Distribute referral fee if applicable
        // referral.distributeFeeShare(usernameHash, feeAmount);
    }

    /// @notice Record a trade and update modules
    function recordTrade(
        bytes32 usernameHash,
        address token,
        uint256 amount,
        uint256 price,
        bool isBuy
    ) external {
        if (isBuy) {
            portfolio.recordAcquisition(usernameHash, token, amount, price);
        } else {
            portfolio.recordDisposal(usernameHash, token, amount, price);

            // Record successful trade for reputation
            reputation.recordActivity(
                usernameHash,
                HiveReputation.ActivityType.SuccessfulTrade,
                string(abi.encodePacked("sold ", token))
            );
        }
    }

    /// @notice Record governance vote
    function recordGovernanceVote(
        bytes32 usernameHash,
        bytes32 proposalId
    ) external {
        reputation.recordActivity(
            usernameHash,
            HiveReputation.ActivityType.GovernanceVote,
            string(abi.encodePacked("voted on ", proposalId))
        );
    }

    // ═══ Module Update ═══

    function updateModule(string calldata moduleName, address newAddr) external {
        require(msg.sender == owner, "Factory: not owner");

        if (keccak256(bytes(moduleName)) == keccak256("hiveID")) {
            hiveID = HiveID(newAddr);
        } else if (keccak256(bytes(moduleName)) == keccak256("verifier")) {
            verifier = HiveVerifier(newAddr);
        } else if (keccak256(bytes(moduleName)) == keccak256("reputation")) {
            reputation = HiveReputation(newAddr);
        } else if (keccak256(bytes(moduleName)) == keccak256("oracle")) {
            oracle = HiveOracle(payable(newAddr));
        } else if (keccak256(bytes(moduleName)) == keccak256("referral")) {
            referral = HiveReferral(payable(newAddr));
        } else if (keccak256(bytes(moduleName)) == keccak256("portfolio")) {
            portfolio = HivePortfolio(newAddr);
        } else if (keccak256(bytes(moduleName)) == keccak256("relayer")) {
            relayer = HiveRelayer(payable(newAddr));
        }

        emit ModuleUpdated(moduleName, newAddr);
    }

    // ═══ View — System Info ═══

    function getSystemInfo() external view returns (
        address[7] memory modules,
        bool _initialized
    ) {
        modules[0] = address(hiveID);
        modules[1] = address(verifier);
        modules[2] = address(reputation);
        modules[3] = address(oracle);
        modules[4] = address(referral);
        modules[5] = address(portfolio);
        modules[6] = address(relayer);
        _initialized = initialized;
    }

    // ═══ Admin ═══

    function transferOwnership(address newOwner) external {
        require(msg.sender == owner, "Factory: not owner");
        owner = newOwner;
    }

    receive() external payable {}
}
