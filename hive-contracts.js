/**
 * Hive Contract Integration Layer
 * 33 contracts on Ritual Chain (1979)
 * Minimal ABIs — only functions the dashboard needs
 */

const HIVE = {
  CHAIN_ID: 1979,
  RPC: 'https://rpc.ritualfoundation.org',
  EXPLORER: 'https://explorer.ritualfoundation.org',
  CURRENCY: 'RITUAL',

  // ═══ CONTRACT ADDRESSES ═══
  addr: {
    // Core
    HiveToken:        '0xDA8185F0742b46A8B6D413Dc10eFC25E9FBd5ec3',
    HiveFactory:      '0x0241cfB0a6620f57988C75Cd06dA2914b21463c6',
    HiveRegistry:     '0x89Cff106458261b48597ee0307017504080182eE',
    HivePoints:       '0xC031064390952259a42885219dB16F66677fbfaa',

    // DeFi
    HiveStaking:      '0x8D2A42Fe7845F165264d042267a3bD8EBae83d28',
    HiveTreasury:     '0x90fbd495c888ae010e40FD299E143FabFcf08C18',
    HivePortfolio:    '0x81E38ad29B869De5dd99bC5da1386b65Ef2Da066',
    HiveLaunchPad:    '0x8eb73b9e2dD62EcFC9C61861638C45afe003d95b',
    HiveClearing:     '0x631969799907Dc4914988298A7795783e24c20CC',
    HiveMarketMaker:  '0x62C8AB145AA677792b7E7d1f0Bf64000D3DC637D',
    HiveAutoStrategy: '0x1b3A537D4572c1020Bc72c9f4951704966d3BEF9',

    // AI
    HiveBrain:        '0x0ad0234d3EA8bd41ee571b1B317fA98d46E642B4',
    HiveAgent:        '0x842441aB565a3C6C8183ABB08a735B2DEA184327',
    HiveFLock:        '0xb0f436d799935Fbe6c7D8885E4345B588B16F5d2',
    Strategy:         '0xc2d24F72D2B5A82F9cBb0C6Aa4bd5157bc66b202',
    Queen:            '0xC2ec8C64A3183e3a611284d70ccb4C0dAb8eDDfd',
    Drone:            '0x8607e68C53970A5bF300c106d3eA2db5ff8BC704',

    // Governance
    HiveGovernance:   '0xeadd2aB5D8f1Ead852927Dd56c34b365603c2702',
    HiveMultiSig:     '0xd450caB1dCe65ac7bB089Cf8dA9F20f37544B1B6',
    HiveCouncil:      '0x245590BE2E044A8a0aeB99C1bbBAAa4e68B715B3',

    // Identity & Reputation
    HiveID:           '0x013c6D5a4fa5D50a92261C4189a8F56900408A01',
    HiveReputation:   '0x4cbe69CC563D548e2DA214c6c7C16fC32b69526A',
    HiveVerifier:     '0xDD2A524E0Bda702ed5f9b1740Dd145Ce2de23Eb6',

    // Infra
    HiveOracle:       '0x5D72F3faf4ada60E1beCa310a2FA82b7B731aEbE',
    HiveRelayer:      '0xa2FCc065f174e9BE536A090DD344B9C8b8Dc513c',
    HiveReferral:     '0x6fc9D8aBFa06867D5932DA9C473D46B0224041ED',
    HiveNotification: '0x9a04677f219384Fe35E29E968d43e8BDC6392C42',
    HiveChat:         '0x615F139dDFb2f2f486133B3a2D9F74Dd2bA785B6',
    HiveEigenLayer:   '0xD0239931Eb19f3B0E0Ac1946685fab6fFB4FeC0F',

    // Vesting
    HiveLock:         '0xc731018373799B4D34b1A2bB03387Cc126b5Cc3d',
    HiveAgentFactory: '0x54850a183d105784d192d9926ec65fede5a42189',

    // New: hiveUSD + Faucet
    HiveUSD:          '0x60601e48038E32dBCd9A9667c589bf6D39A32fb5',
    HiveFaucet:       '0x1ed73Ac27FfDF1D009CbC064C1eeDb910932AA61',
  },

  // ═══ MINIMAL ABIs ═══
  abi: {
    // ERC20 + HiveToken specifics
    HiveToken: [
      'function name() view returns (string)',
      'function symbol() view returns (string)',
      'function decimals() view returns (uint8)',
      'function totalSupply() view returns (uint256)',
      'function balanceOf(address) view returns (uint256)',
      'function allowance(address,address) view returns (uint256)',
      'function approve(address,uint256) returns (bool)',
      'function transfer(address,uint256) returns (bool)',
      'function transferFrom(address,address,uint256) returns (bool)',
      'function MAX_SUPPLY() view returns (uint256)',
      'function minter() view returns (address)',
      'function transferMode() view returns (uint8)',
      'function hasVesting(address) view returns (bool)',
      'function claimableVesting(address) view returns (uint256)',
      'function releaseVesting()',
      'event Transfer(address indexed from, address indexed to, uint256 value)',
      'event Approval(address indexed owner, address indexed spender, uint256 value)',
    ],

    // Staking
    HiveStaking: [
      'function totalStaked() view returns (uint256)',
      'function stakedAmount(address) view returns (uint256)',
      'function getPendingRewards(address) view returns (uint256)',
      'function getTier(address) view returns (uint256)',
      'function getStakerInfo(address) view returns (uint256 amount, uint256 lockEnd, uint256 tier, uint256 multiplier, bool autoCompound)',
      'function getStakerCount() view returns (uint256)',
      'function getFeeDiscount(address) view returns (uint256)',
      'function getPriorityScore(address) view returns (uint256)',
      'function minStake() view returns (uint256)',
      'function rewardRate() view returns (uint256)',
      'function isStaker(address) view returns (bool)',
      'function stake(uint256 lockPeriod) payable',
      'function unstake(uint256 amount)',
      'function claimRewards()',
      'function compoundRewards()',
      'function toggleAutoCompound()',
      'function emergencyUnstake()',
      'event Staked(address indexed user, uint256 amount, uint256 lockPeriod)',
      'event Unstaked(address indexed user, uint256 amount)',
      'event RewardsClaimed(address indexed user, uint256 amount)',
    ],

    // Treasury
    HiveTreasury: [
      'function getAvailableBalance() view returns (uint256)',
      'function totalFeesCollected() view returns (uint256)',
      'function totalDistributedToStakers() view returns (uint256)',
      'function totalDistributedToReferrers() view returns (uint256)',
      'function getDistributionCount() view returns (uint256)',
      'function reserveBalance() view returns (uint256)',
      'function currentRound() view returns (uint256)',
      'function stakerShare() view returns (uint256)',
      'function referrerShare() view returns (uint256)',
      'function reserveShare() view returns (uint256)',
      'function paused() view returns (bool)',
      'event FeesCollected(address indexed from, uint256 amount)',
      'event Distribution(address indexed stakers, uint256 stakerAmount, address indexed referrers, uint256 referrerAmount, uint256 reserveAmount)',
    ],

    // Governance
    HiveGovernance: [
      'function proposalCount() view returns (uint256)',
      'function getProposal(uint256) view returns (uint8 proposalType, string description, address proposer, uint256 forVotes, uint256 againstVotes, uint256 abstainVotes, uint256 startBlock, uint256 endBlock, uint8 state, bool emergency)',
      'function hasVoted(uint256,address) view returns (bool)',
      'function getVote(uint256,address) view returns (uint8)',
      'function state(uint256) view returns (uint8)',
      'function votingPeriod() view returns (uint256)',
      'function quorumBps() view returns (uint256)',
      'function proposalThreshold() view returns (uint256)',
      'function propose(uint8,string,address,bytes,bool)',
      'function castVote(uint256,uint8)',
      'function delegate(address)',
      'function undelegate()',
      'event ProposalCreated(uint256 indexed proposalId, uint8 proposalType, string description, address proposer, bool emergency)',
      'event VoteCast(uint256 indexed proposalId, address indexed voter, uint8 support, uint256 weight)',
    ],

    // Registry
    HiveRegistry: [
      'function agentCount() view returns (uint256)',
      'function getActiveAgents() view returns (address[])',
      'function getAgent(address) view returns (string name, uint256 registeredAt, uint256 lastHeartbeat, uint256 heartbeatInterval, bool active)',
      'function isRegistered(address) view returns (bool)',
      'function isAlive(address) view returns (bool)',
      'function checkLiveness(address) view returns (bool)',
      'function register(string,uint256)',
      'function heartbeat()',
      'event AgentRegistered(address indexed agent, string name)',
      'event Heartbeat(address indexed agent)',
    ],

    // Points
    HivePoints: [
      'function totalPoints() view returns (uint256)',
      'function totalFor(address) view returns (uint256)',
      'function users(address) view returns (uint256 points, uint256 lastUpdate, address referrer, bool isEarly)',
      'function rank(address) view returns (uint256)',
      'function topHolders(uint256) view returns (address[], uint256[])',
      'function genesis() view returns (uint256)',
      'function referralBps() view returns (uint256)',
      'event PointsAwarded(address indexed user, uint256 amount, string reason)',
    ],

    // Portfolio
    HivePortfolio: [
      'function getPortfolioSummary(bytes32) view returns (uint256 totalValue, uint256 totalPnl, uint256 holdingCount, uint256 vestingCount)',
      'function getHoldingTokens(bytes32) view returns (address[])',
      'function getHolding(bytes32,address) view returns (uint256 amount, uint256 avgPrice, uint256 realizedPnl)',
      'function getTrades(bytes32) view returns (tuple(address token, uint256 amount, uint256 pricePerToken, uint256 timestamp, bool isBuy)[])',
      'function getUnrealizedPnl(bytes32,address) view returns (int256)',
    ],

    // LaunchPad
    HiveLaunchPad: [
      'function saleCount() view returns (uint256)',
      'function getSale(uint256) view returns (address token, uint256 totalSupply, uint256 price, uint256 startTime, uint256 endTime, bool finalized)',
      'function participate(uint256,uint256) payable',
      'event SaleCreated(uint256 indexed saleId, address token, uint256 price)',
      'event Participation(uint256 indexed saleId, address indexed buyer, uint256 amount)',
    ],

    // Clearing (Auctions)
    HiveClearing: [
      'function auctionCount() view returns (uint256)',
      'function getAuction(uint256) view returns (address token, uint256 totalSupply, uint256 minPrice, uint256 maxPrice, uint256 currentPrice, uint256 startTime, uint256 endTime, bool settled)',
      'function placeBid(uint256,uint256) payable',
      'function settle(uint256)',
      'function getUserBids(uint256,address) view returns (uint256 amount, uint256 price)',
      'event AuctionCreated(uint256 indexed auctionId, address token)',
      'event BidPlaced(uint256 indexed auctionId, address indexed bidder, uint256 amount)',
    ],

    // Factory
    HiveFactory: [
      'function getSystemInfo() view returns (uint256 totalContracts, bool allWired, uint256 chainId)',
      'function completeOnboarding(bytes32,string,bytes32)',
      'function recordTrade(bytes32,address,uint256,uint256,bool)',
      'function recordGovernanceVote(bytes32,bytes32)',
      'function recordSaleParticipation(bytes32,address,uint256,uint256)',
    ],

    // Reputation
    HiveReputation: [
      'function getScore(bytes32) view returns (uint256)',
      'function getTierName(uint256) view returns (string)',
      'function getFeeDiscount(bytes32) view returns (uint256)',
      'function getGovernanceWeight(bytes32) view returns (uint256)',
      'function getSalePriority(bytes32) view returns (uint256)',
    ],

    // MarketMaker
    HiveMarketMaker: [
      'function getOrderBook(address) view returns (tuple(address trader, uint256 amount, uint256 price, bool isBuy, uint256 timestamp)[])',
      'function placeOrder(address,uint256,uint256,bool)',
      'event OrderPlaced(address indexed token, address indexed trader, uint256 amount, uint256 price, bool isBuy)',
    ],

    // AutoStrategy
    HiveAutoStrategy: [
      'function strategyCount() view returns (uint256)',
      'function getStrategy(uint256) view returns (string name, address target, uint256 allocation, bool active)',
      'function deposit(uint256,uint256) payable',
      'function withdraw(uint256,uint256)',
      'event Deposit(address indexed user, uint256 indexed strategyId, uint256 amount)',
    ],

    // MultiSig
    HiveMultiSig: [
      'function getTransactionCount() view returns (uint256)',
      'function getTransaction(uint256) view returns (address to, uint256 value, bytes data, bool executed, uint256 confirmations)',
      'function submitTransaction(address,uint256,bytes)',
      'function confirmTransaction(uint256)',
      'function executeTransaction(uint256)',
      'event SubmitTransaction(address indexed owner, uint256 indexed txIndex, address indexed to, uint256 value)',
      'event ConfirmTransaction(address indexed owner, uint256 indexed txIndex)',
      'event ExecuteTransaction(address indexed owner, uint256 indexed txIndex)',
    ],

    // HiveUSD (100B stablecoin)
    HiveUSD: [
      'function name() view returns (string)',
      'function symbol() view returns (string)',
      'function decimals() view returns (uint8)',
      'function totalSupply() view returns (uint256)',
      'function MAX_SUPPLY() view returns (uint256)',
      'function balanceOf(address) view returns (uint256)',
      'function allowance(address,address) view returns (uint256)',
      'function approve(address,uint256) returns (bool)',
      'function transfer(address,uint256) returns (bool)',
      'function transferFrom(address,address,uint256) returns (bool)',
      'function mint(address,uint256)',
      'function minter() view returns (address)',
      'function owner() view returns (address)',
      'function setMinter(address)',
      'function transferOwnership(address)',
      'event Transfer(address indexed from, address indexed to, uint256 value)',
      'event Approval(address indexed owner, address indexed spender, uint256 value)',
    ],

    // HiveFaucet (daily 1000 hiveUSD claim)
    HiveFaucet: [
      'function token() view returns (address)',
      'function owner() view returns (address)',
      'function CLAIM_AMOUNT() view returns (uint256)',
      'function COOLDOWN() view returns (uint256)',
      'function lastClaim(address) view returns (uint256)',
      'function claim()',
      'function canClaim(address) view returns (bool)',
      'function timeUntilClaim(address) view returns (uint256)',
      'function withdraw(address,uint256)',
      'function transferOwnership(address)',
      'event Claimed(address indexed user, uint256 amount, uint256 timestamp)',
    ],

    // HiveOracle — Price feeds
    HiveOracle: [
      'function prices(address) view returns (uint256 price, uint256 timestamp, uint256 confidence, string source, bool valid)',
      'function tokenConfigs(address) view returns (string coingeckoId, string symbol, uint8 decimals, uint256 alloraTopicId, bool active)',
      'function trackedTokens(uint256) view returns (address)',
      'function getTrackedTokensCount() view returns (uint256)',
      'function updatePrice(address,uint256,string)',
      'function fetchPrice(address) returns (uint256)',
      'event PriceUpdated(address indexed token, uint256 price, uint256 timestamp, string source)',
    ],

    // HiveReferral
    HiveReferral: [
      'function createReferralCode(bytes32) returns (bytes32)',
      'function registerReferral(bytes32,bytes32)',
      'function claimRewards(bytes32) returns (uint256)',
      'function getReferralCode(bytes32) view returns (bytes32)',
      'function getReferrer(bytes32) view returns (bytes32)',
      'function getReferrals(bytes32) view returns (tuple(bytes32 referrerHash, bytes32 refereeHash, uint256 timestamp, uint256 rewardAmount, bool rewardClaimed)[])',
      'function getStats(bytes32) view returns (uint256 totalReferrals, uint256 activeReferrals, uint256 totalRewardsEarned, uint256 totalRewardsClaimed, uint256 tier)',
      'function getClaimable(bytes32) view returns (uint256)',
      'function getTierName(uint256) view returns (string)',
      'function baseReward() view returns (uint256)',
      'function feeShareBps() view returns (uint256)',
      'function fundPool() payable',
      'event ReferralCodeCreated(bytes32 indexed usernameHash, bytes32 code)',
      'event ReferralRegistered(bytes32 indexed referrer, bytes32 indexed referee, uint256 reward)',
      'event RewardClaimed(bytes32 indexed usernameHash, uint256 amount)',
    ],

    // HiveNotification
    HiveNotification: [
      'function subscribe(uint256,string)',
      'function updateSubscription(uint256)',
      'function unsubscribe()',
      'function setPriceAlert(string,uint256,bool)',
      'function cancelPriceAlert(uint256)',
      'function markRead(uint256)',
      'function markAllRead()',
      'function getUnreadCount(address) view returns (uint256)',
      'function getNotificationCount(address) view returns (uint256)',
      'function getSubscription(address) view returns (uint256 eventMask, uint256 lastNotified, string webhookUrl, bool active)',
      'function getPriceAlertCount(address) view returns (uint256)',
      'event Subscribed(address indexed user, uint256 eventMask)',
      'event PriceAlertSet(address indexed user, uint256 alertId, string token, uint256 threshold, bool above)',
      'event PriceAlertTriggered(address indexed user, uint256 alertId, string token, uint256 currentPrice)',
      'event NotificationRead(address indexed user, uint256 index)',
    ],

    // HiveLock (Vesting)
    HiveLock: [
      'function createLinear(address,address,uint256,uint256,uint256,string)',
      'function createCliffLinear(address,address,uint256,uint256,uint256,uint256,uint256,string)',
      'function claim(uint256)',
      'function claimAll()',
      'function getVestedAmount(uint256) view returns (uint256)',
      'function getClaimableAmount(uint256) view returns (uint256)',
      'function getSchedules(address) view returns (uint256[])',
      'function getScheduleCount() view returns (uint256)',
      'function getTotalClaimable(address) view returns (uint256)',
      'function schedules(uint256) view returns (address beneficiary, address token, uint256 totalAmount, uint256 claimedAmount, uint256 startTime, uint256 cliffDuration, uint256 vestingDuration, uint256 unlockPercentage, uint8 vestingType, bool cancelled, string label)',
      'function paused() view returns (bool)',
      'event ScheduleCreated(uint256 indexed scheduleId, address indexed beneficiary, address token, uint256 totalAmount, uint8 vestingType)',
      'event TokensClaimed(uint256 indexed scheduleId, address indexed beneficiary, uint256 amount)',
      'event ScheduleCancelled(uint256 indexed scheduleId)',
    ],

    // HiveAgentFactory
    HiveAgentFactory: [
      'function summonAgent(string,string,string,uint32) payable returns (address,address)',
      'function summonAgentCustom(string,string,string,uint32,uint256,uint256,uint256,uint256) payable returns (address,address)',
      'function deactivateAgent(address)',
      'function getUserAgents(address) view returns (tuple(address agent, address governor, string name, bytes32 sector, uint256 deployedAt, bool active)[])',
      'function getUserAgentCount(address) view returns (uint256)',
      'function getAllAgents(uint256,uint256) view returns (address[])',
      'function getAgentInfo(address) view returns (address owner, address governor, string name, bytes32 sector, uint256 deployedAt, bool active)',
      'function deploymentFee() view returns (uint256)',
      'function freeTierEnabled() view returns (bool)',
      'function hasUsedFreeTier(address) view returns (bool)',
      'event AgentSummoned(address indexed user, address indexed agent, address indexed governor, string name, bytes32 sector)',
      'event AgentDeactivated(address indexed user, address indexed agent)',
    ],
  },
};

// ═══ CONTRACT PROVIDER ═══
class HiveProvider {
  constructor() {
    this.ethers = null;
    this.provider = null;
    this.signer = null;
    this.contracts = {};
    this.address = null;
    this._ready = false;
  }

  async init() {
    if (this._ready) return true;
    if (typeof ethers === 'undefined') {
      console.error('[Hive] ethers.js not loaded');
      return false;
    }
    this.ethers = ethers;

    // Use window.ethereum if available, else fallback to RPC
    if (window.ethereum) {
      this.provider = new ethers.BrowserProvider(window.ethereum);
      try {
        this.signer = await this.provider.getSigner();
        this.address = await this.signer.getAddress();
      } catch (e) {
        // Read-only mode
        this.signer = null;
      }
    }

    // Always have a read-only RPC provider
    this.rpcProvider = new ethers.JsonRpcProvider(HIVE.RPC, HIVE.CHAIN_ID);

    // Init all contracts
    for (const [name, addr] of Object.entries(HIVE.addr)) {
      const abi = HIVE.abi[name];
      if (!abi) continue;
      const readContract = new ethers.Contract(addr, abi, this.rpcProvider);
      this.contracts[name] = readContract;
      if (this.signer) {
        this.contracts[name + '_write'] = new ethers.Contract(addr, abi, this.signer);
      }
    }

    this._ready = true;
    return true;
  }

  getContract(name) {
    return this.contracts[name] || null;
  }

  getWriteContract(name) {
    return this.contracts[name + '_write'] || this.contracts[name] || null;
  }

  // ═══ DASHBOARD DATA ═══
  async getDashboardStats(address) {
    await this.init();
    const staking = this.getContract('HiveStaking');
    const governance = this.getContract('HiveGovernance');
    const registry = this.getContract('HiveRegistry');
    const points = this.getContract('HivePoints');
    const token = this.getContract('HiveToken');
    const treasury = this.getContract('HiveTreasury');

    const results = await Promise.allSettled([
      staking.totalStaked(),
      governance.proposalCount(),
      registry.agentCount(),
      address ? points.totalFor(address) : Promise.resolve(0n),
      address ? token.balanceOf(address) : Promise.resolve(0n),
      address ? staking.stakedAmount(address) : Promise.resolve(0n),
      address ? staking.getPendingRewards(address) : Promise.resolve(0n),
      treasury.getAvailableBalance(),
      token.totalSupply(),
      points.totalPoints(),
      staking.getStakerCount(),
    ]);

    const val = (i, fallback = 0n) => results[i].status === 'fulfilled' ? results[i].value : fallback;

    return {
      totalStaked: val(0),
      proposalCount: val(1),
      agentCount: val(2),
      userPoints: val(3),
      tokenBalance: val(4),
      userStaked: val(5),
      pendingRewards: val(6),
      treasuryBalance: val(7),
      totalSupply: val(8),
      globalPoints: val(9),
      stakerCount: val(10),
    };
  }

  // ═══ STAKING ═══
  async getStakeInfo(address) {
    await this.init();
    const staking = this.getContract('HiveStaking');
    if (!address || !staking) return null;

    const [info, pending, tier, discount, isStaker] = await Promise.allSettled([
      staking.getStakerInfo(address),
      staking.getPendingRewards(address),
      staking.getTier(address),
      staking.getFeeDiscount(address),
      staking.isStaker(address),
    ]);

    const tierNames = ['None', 'Bronze', 'Silver', 'Gold', 'Diamond'];

    return {
      amount: info.status === 'fulfilled' ? info.value[0] : 0n,
      lockEnd: info.status === 'fulfilled' ? info.value[1] : 0n,
      tier: tier.status === 'fulfilled' ? Number(tier.value) : 0,
      tierName: tierNames[tier.status === 'fulfilled' ? Number(tier.value) : 0] || 'None',
      multiplier: info.status === 'fulfilled' ? info.value[3] : 0n,
      autoCompound: info.status === 'fulfilled' ? info.value[4] : false,
      pendingRewards: pending.status === 'fulfilled' ? pending.value : 0n,
      discount: discount.status === 'fulfilled' ? Number(discount.value) : 0,
      isStaker: isStaker.status === 'fulfilled' ? isStaker.value : false,
      minStake: await staking.minStake().catch(() => 0n),
    };
  }

  // ═══ GOVERNANCE ═══
  async getProposals(page = 0, pageSize = 10) {
    await this.init();
    const governance = this.getContract('HiveGovernance');
    const count = Number(await governance.proposalCount());
    const proposals = [];
    const start = Math.max(0, count - 1 - page * pageSize);
    const end = Math.max(0, start - pageSize);

    for (let i = start; i > end; i--) {
      try {
        const p = await governance.getProposal(i);
        const stateNames = ['Pending', 'Active', 'Canceled', 'Defeated', 'Succeeded', 'Queued', 'Expired', 'Executed'];
        proposals.push({
          id: i,
          proposalType: Number(p[0]),
          description: p[1],
          proposer: p[2],
          forVotes: p[3],
          againstVotes: p[4],
          abstainVotes: p[5],
          startBlock: p[6],
          endBlock: p[7],
          state: Number(p[8]),
          stateName: stateNames[Number(p[8])] || 'Unknown',
          emergency: p[9],
        });
      } catch (e) { break; }
    }
    return { total: count, proposals };
  }

  // ═══ AGENTS ═══
  async getAgents() {
    await this.init();
    const registry = this.getContract('HiveRegistry');
    const agentAddrs = await registry.getActiveAgents().catch(() => []);
    const agents = [];

    for (const addr of agentAddrs.slice(0, 20)) {
      try {
        const info = await registry.getAgent(addr);
        const alive = await registry.isAlive(addr);
        agents.push({
          address: addr,
          name: info[0],
          registeredAt: info[1],
          lastHeartbeat: info[2],
          heartbeatInterval: info[3],
          active: info[4],
          alive,
        });
      } catch (e) {}
    }
    return agents;
  }

  // ═══ POINTS ═══
  async getPointsInfo(address) {
    await this.init();
    const points = this.getContract('HivePoints');
    if (!address) return { user: 0n, rank: 0, global: 0n, topHolders: [] };

    const [userPts, userRank, global, top] = await Promise.allSettled([
      points.totalFor(address),
      points.rank(address),
      points.totalPoints(),
      points.topHolders(10),
    ]);

    return {
      user: userPts.status === 'fulfilled' ? userPts.value : 0n,
      rank: userRank.status === 'fulfilled' ? Number(userRank.value) : 0,
      global: global.status === 'fulfilled' ? global.value : 0n,
      topHolders: top.status === 'fulfilled' ? { addresses: top.value[0], points: top.value[1] } : { addresses: [], points: [] },
    };
  }

  // ═══ TRANSACTIONS (from events) ═══
  async getRecentTransactions(address, limit = 20) {
    await this.init();
    if (!address) return [];

    const token = this.getContract('HiveToken');
    const staking = this.getContract('HiveStaking');
    const governance = this.getContract('HiveGovernance');

    const txs = [];

    // Get Transfer events
    try {
      const filter = token.filters.Transfer(address, null);
      const filterTo = token.filters.Transfer(null, address);
      const [sent, received] = await Promise.all([
        token.queryFilter(filter, -5000),
        token.queryFilter(filterTo, -5000),
      ]);
      for (const e of [...sent, ...received]) {
        const block = await e.getBlock();
        txs.push({
          type: e.args[0].toLowerCase() === address.toLowerCase() ? 'Send' : 'Receive',
          amount: e.args[2],
          hash: e.transactionHash,
          timestamp: block.timestamp,
          blockNumber: e.blockNumber,
        });
      }
    } catch (e) {}

    // Get Staking events
    try {
      const stakeFilter = staking.filters.Staked(address);
      const unstakeFilter = staking.filters.Unstaked(address);
      const rewardFilter = staking.filters.RewardsClaimed(address);
      const [staked, unstaked, rewards] = await Promise.all([
        staking.queryFilter(stakeFilter, -5000),
        staking.queryFilter(unstakeFilter, -5000),
        staking.queryFilter(rewardFilter, -5000),
      ]);
      for (const e of [...staked, ...unstaked, ...rewards]) {
        const block = await e.getBlock();
        txs.push({
          type: e.eventName === 'Staked' ? 'Stake' : e.eventName === 'Unstaked' ? 'Unstake' : 'Claim Rewards',
          amount: e.args[1],
          hash: e.transactionHash,
          timestamp: block.timestamp,
          blockNumber: e.blockNumber,
        });
      }
    } catch (e) {}

    // Get Governance events
    try {
      const voteFilter = governance.filters.VoteCast(null, address);
      const votes = await governance.queryFilter(voteFilter, -5000);
      for (const e of votes) {
        const block = await e.getBlock();
        txs.push({
          type: 'Vote',
          amount: 0n,
          hash: e.transactionHash,
          timestamp: block.timestamp,
          blockNumber: e.blockNumber,
          extra: `Proposal #${e.args[0]}`,
        });
      }
    } catch (e) {}

    // Sort by block number desc, limit
    txs.sort((a, b) => b.blockNumber - a.blockNumber);
    return txs.slice(0, limit);
  }

  // ═══ WRITE OPERATIONS ═══
  async stake(amount, lockDays) {
    const staking = this.getWriteContract('HiveStaking');
    if (!staking) throw new Error('Wallet not connected');
    const lockPeriod = lockDays * 86400; // days → seconds (0, 604800, 2592000, 7776000, 31536000)
    const tx = await staking.stake(lockPeriod, { value: amount });
    return tx.wait();
  }

  async unstake(amount) {
    const staking = this.getWriteContract('HiveStaking');
    if (!staking) throw new Error('Wallet not connected');
    const tx = await staking.unstake(amount);
    return tx.wait();
  }

  async claimRewards() {
    const staking = this.getWriteContract('HiveStaking');
    if (!staking) throw new Error('Wallet not connected');
    const tx = await staking.claimRewards();
    return tx.wait();
  }

  async castVote(proposalId, support) {
    const governance = this.getWriteContract('HiveGovernance');
    if (!governance) throw new Error('Wallet not connected');
    const tx = await governance.castVote(proposalId, support);
    return tx.wait();
  }

  async delegate(delegatee) {
    const governance = this.getWriteContract('HiveGovernance');
    if (!governance) throw new Error('Wallet not connected');
    const tx = await governance.delegate(delegatee);
    return tx.wait();
  }

  // ═══ FAUCET ═══
  async claimFaucet() {
    const faucet = this.getWriteContract('HiveFaucet');
    if (!faucet) throw new Error('Wallet not connected');
    const tx = await faucet.claim();
    return tx.wait();
  }

  async canClaimFaucet(address) {
    await this.init();
    const faucet = this.getContract('HiveFaucet');
    return faucet.canClaim(address);
  }

  async getFaucetInfo(address) {
    await this.init();
    const faucet = this.getContract('HiveFaucet');
    const [canClaim, timeLeft, claimAmount, cooldown, balance] = await Promise.all([
      faucet.canClaim(address),
      faucet.timeUntilClaim(address),
      faucet.CLAIM_AMOUNT(),
      faucet.COOLDOWN(),
      this.getContract('HiveUSD').balanceOf(faucet.target || faucet.address),
    ]);
    return { canClaim, timeLeft, claimAmount, cooldown, faucetBalance: balance };
  }

  // ═══ ORACLE ═══
  async getOraclePrice(tokenAddress) {
    await this.init();
    const oracle = this.getContract('HiveOracle');
    if (!oracle) return null;
    try {
      const [price, timestamp, confidence, source, valid] = await oracle.prices(tokenAddress);
      return {
        price: Number(price) / 1e8, // 8 decimals to float
        timestamp: Number(timestamp),
        confidence: Number(confidence),
        source,
        valid
      };
    } catch (e) {
      console.error('[Hive] Oracle price error:', e);
      return null;
    }
  }

  async getOraclePriceFormatted(tokenAddress) {
    const data = await this.getOraclePrice(tokenAddress);
    if (!data || !data.valid) return null;
    return data.price;
  }

  // ═══ UTILITIES ═══
  formatEther(wei) {
    if (!this.ethers) return '0';
    return parseFloat(this.ethers.formatEther(wei)).toLocaleString('en-US', { maximumFractionDigits: 4 });
  }

  formatGwei(wei) {
    if (!this.ethers) return '0';
    return parseFloat(this.ethers.formatUnits(wei, 9)).toLocaleString('en-US', { maximumFractionDigits: 2 });
  }

  shortAddr(addr) {
    if (!addr) return '—';
    return addr.slice(0, 6) + '...' + addr.slice(-4);
  }

  explorerTx(hash) {
    return `${HIVE.EXPLORER}/tx/${hash}`;
  }

  explorerAddr(addr) {
    return `${HIVE.EXPLORER}/address/${addr}`;
  }

  timeAgo(timestamp) {
    const now = Math.floor(Date.now() / 1000);
    const diff = now - timestamp;
    if (diff < 60) return 'just now';
    if (diff < 3600) return `${Math.floor(diff / 60)}m ago`;
    if (diff < 86400) return `${Math.floor(diff / 3600)}h ago`;
    return `${Math.floor(diff / 86400)}d ago`;
  }
}

// Global instance
window.hive = new HiveProvider();
