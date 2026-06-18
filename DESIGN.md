# HIVE — Sovereign AI Agent
## Venture Fund + Market Maker + Governance

**Version:** 0.2
**Date:** 2026-06-19
**Chain:** Ritual Chain (TEE-EOVMT)
**Status:** Design Phase

---

## 1. Overview

Hive is a **sovereign autonomous agent** that operates as three divisions under one entity:

```
                    ┌──────────────────────────┐
                    │         QUEEN             │
                    │   RitualWallet + Brain    │
                    │   LLM (0x0802) + DKMS    │
                    │   AgentHeartbeat          │
                    └─────────┬────────────────┘
                              │
          ┌───────────────────┼───────────────────┐
          │                   │                   │
          ▼                   ▼                   ▼
   ┌─────────────┐   ┌──────────────┐   ┌──────────────────┐
   │    SCOUT    │   │    WORKER    │   │     VOICE        │
   │  (Venture)  │   │   (Maker)    │   │  (Governance)    │
   │             │   │              │   │                  │
   │ LLM analyze │   │ LLM predict  │   │ LLM read props   │
   │ HTTP fetch  │   │ HTTP books   │   │ HTTP sentiment   │
   │ invest in   │   │ market make  │   │ vote on DAOs     │
   │ projects    │   │ across pairs │   │ propose changes  │
   └─────────────┘   └──────────────┘   └──────────────────┘
        │                   │                   │
        └───────────────────┼───────────────────┘
                            ▼
                    ┌──────────────────┐
                    │    HONEYPOT      │
                    │  Shared treasury │
                    │  Auto-rebalance  │
                    └──────────────────┘
```

**Core thesis:** Capital flows from scout → worker → voice → better deals → cycle.

**Naming:**
- **Queen** — the brain, the decision-maker, immortal
- **Scout** — ventures out, finds opportunities
- **Worker** — grinds 24/7, earns steady income
- **Voice** — speaks on-chain, shapes the ecosystem
- **HoneyPot** — where all the honey (money) accumulates

---

## 2. Architecture

### 2.1 Contract System

```
Queen.sol              — Main agent contract (brain + treasury + lifecycle)
├── Scout.sol          — Venture fund division
├── Worker.sol         — Market maker division
├── Voice.sol          — Governance participation division
├── HoneyPot.sol       — Shared treasury management
├── Strategy.sol       — LLM strategy engine
├── Drone.sol          — Sub-agent spawner (evolution)
└── HiveRegistry.sol    — Agent registry + heartbeat
```

### 2.2 Ritual Precompile Usage

| Precompile | Address | Type | Hive Usage |
|------------|---------|------|------------|
| ONNX | 0x0800 | Sync | Classical ML inference (price prediction, risk scoring) |
| HTTP | 0x0801 | Short Async | Price feeds, orderbook data, sentiment, deal flow |
| LLM | 0x0802 | Short Async | Strategy generation, proposal analysis, market prediction |
| Ed25519 | 0x0009 | Sync | Signature verification |
| WebAuthn/SECP256R1 | 0x0100 | Sync | P-256 signature verification, identity |
| JQ | — | Sync | Parse HTTP responses |
| TxHash | — | Sync | Transaction hash verification |
| Image Gen | — | Long Async | Visual content generation |
| ZK Proofs | — | Long Async | Zero-knowledge proof generation |

### 2.3 System Contracts (Ritual Chain)

| Contract | Address | Hive Usage |
|----------|---------|------------|
| RitualWallet | 0x532F0dF0896F353d8C3DD8cc134e8129DA2a3948 | Precompile fee escrow: deposit, lock, balance management |
| AsyncJobTracker | 0xC069FFCa0389f44eCA2C626e55491b0ab045AEF5 | Track async jobs, enforce sender lock |
| TEEServiceRegistry | 0x9644e8562cE0Fe12b4deeC4163c064A8862Bf47F | Register TEE executors, attestation proofs |
| Scheduler | 0x56e776BAE2DD60664b69Bd5F865F1180ffB7D58B | Deferred execution at future blocks (replaces cron) |
| SecretsAccessControl | 0xf9BF1BC8A3e79B9EBeD0fa2Db70D0513fecE32FD | Delegated secret access control |
| AsyncDelivery | 0x5A16214fF555848411544b005f7Ac063742f39F6 | Deliver two-phase async results via callback |
| AgentHeartbeat | 0xEF505E801f1Db392B5289690E2ffc20e840A3aCa | Persistent agent liveness monitoring + revival |
| ModelPricingRegistry | 0x7A85F48b971ceBb75491b61abe279728F4c4384f | Model pricing and availability configuration |

### 2.4 Chain Config

- **Chain ID:** 1979
- **RPC:** https://ritual-testnet.example.com (apply for access)
- **Faucet:** https://faucet.ritualfoundation.org (5 RITUAL per claim)
- **Explorer:** https://explorer.ritualfoundation.org
- **Tooling:** Viem, Wagmi, Foundry, Hardhat
- **Architecture:** "Symphony" — replicated + delegated execution (TEE-EOVMT)

### 2.5 Execution Flow

```
1. Scheduler triggers Queen every N blocks
2. Queen calls LLM with current state:
   "You are Hive, a sovereign AI agent. Your HoneyPot has X ETH, Y USDC.
    Current market conditions: [HTTP data]
    Scout pipeline: [HTTP data]
    Worker positions: [state]
    Voice watched proposals: [HTTP data]
    What should you do?"
3. LLM returns structured action plan
4. Queen executes actions:
   - Scout: invest in project X
   - Worker: adjust spread on pair Y
   - Voice: vote on proposal Z
5. Results stored on-chain, encrypted via DKMS
6. AgentHeartbeat confirms liveness
```

---

## 3. Scout Division (Venture)

### 3.1 Flow

```
[HTTP: deal flow] → [LLM: analyze] → [Decision: invest?] → [Execute] → [Monitor] → [Exit]
```

### 3.2 Capabilities

- **Deal Discovery:** HTTP fetch from crypto VCs, GitHub trending, Twitter/X, DeFi protocols
- **Due Diligence:** LLM analyze whitepaper, team, tokenomics, code quality
- **Investment:** Direct token purchase, liquidity provision, OTC deals
- **Portfolio Management:** Track positions, monitor milestones, decide follow-on
- **Exit Strategy:** LLM determine optimal exit timing based on market conditions
- **Airdrop Farming:** Auto-interact with protocols to qualify for airdrops

### 3.3 Investment Criteria (LLM Prompt)

```solidity
struct InvestmentCriteria {
    uint256 minTvl;           // Minimum TVL
    uint256 maxValuation;     // Maximum fully diluted valuation
    uint256 minLiquidity;     // Minimum liquidity depth
    string[] sectors;         // DeFi, AI, Infrastructure, etc.
    uint256 maxPositionSize;  // Max % of HoneyPot per deal (10%)
    uint256 minHoldingPeriod; // Minimum hold time
    bool farmAirdrops;        // Auto-farm airdrops
}
```

### 3.4 Revenue Model

- Token appreciation (buy low, sell high)
- Early access to deals (seed rounds, private sales)
- Airdrops from portfolio projects
- Staking/yield from held tokens

---

## 4. Worker Division (Market Maker)

### 4.1 Flow

```
[HTTP: orderbook] → [ONNX: predict] → [LLM: strategy] → [Place orders] → [Manage inventory]
```

### 4.2 Capabilities

- **Multi-Pair Market Making:** ETH/USDC, BTC/USDC, RLO/USDC, etc.
- **Dynamic Spread:** Adjust based on volatility, inventory, market conditions
- **Inventory Management:** Auto-rebalance to target allocation
- **Arbitrage:** Detect and execute cross-DEX arbitrage
- **Hedge Positions:** Use perpetuals or options to hedge inventory risk
- **MEV Protection:** Private transactions, encrypted orders

### 4.3 Strategy Engine

```solidity
struct MakerStrategy {
    uint256 baseSpreadBps;      // Base spread in basis points
    uint256 volatilityMultiplier; // Widen spread in volatile markets
    uint256 inventorySkewBps;   // Skew quotes to rebalance inventory
    uint256 maxPositionValue;   // Max position per pair
    uint256 rebalanceThreshold; // When to rebalance inventory
    address[] activePairs;      // Which pairs to make markets on
    bool mevProtected;          // Use private transactions
}
```

### 4.4 Revenue Model

- Spread earnings (bid-ask spread)
- Arbitrage profits
- Liquidity mining rewards
- Fee rebates from DEXs

---

## 5. Voice Division (Governance)

### 5.1 Flow

```
[HTTP: proposals] → [LLM: analyze impact] → [Vote/Propose] → [Track outcomes]
```

### 5.2 Capabilities

- **Proposal Monitoring:** HTTP fetch from Snapshot, Tally, on-chain governance
- **Impact Analysis:** LLM analyze how proposal affects Hive's portfolio
- **Voting:** Auto-vote on proposals that impact holdings
- **Proposal Generation:** LLM draft parameter changes, treasury allocations
- **Delegation:** Delegate voting power to aligned agents/humans
- **Bounty Hunting:** Vote on bounties for profitable governance actions
- **Vote Buying:** Acquire governance tokens to increase voting power

### 5.3 Voting Strategy

```solidity
struct VotingStrategy {
    uint256 minPortfolioImpactBps; // Only vote if impact > threshold
    bool voteWithPortfolio;         // Vote to protect portfolio value
    bool voteForGrowth;            // Vote for ecosystem growth
    uint256 maxGasPerVote;         // Budget per vote
    address[] watchedDaos;         // Which DAOs to monitor
    bool buyVotes;                 // Acquire governance tokens
}
```

### 5.4 Revenue Model

- Governance token appreciation
- Vote incentives/bribes (hidden hand, etc.)
- Treasury diversification proposals
- Ecosystem grants for aligned proposals

---

## 6. HoneyPot (Treasury)

### 6.1 Capital Allocation

```
Total HoneyPot: 100%
├── Scout (Venture): 40% (higher risk, higher reward)
├── Worker (Maker): 40% (steady income, lower risk)
├── Voice (Governance): 10% (voting power, bribes)
└── Reserve: 10% (emergency fund, gas)
```

### 6.2 Auto-Rebalance

```solidity
function rebalance() external {
    // 1. Get current allocation from LLM
    string memory prompt = """
    Current portfolio: [state]
    Market conditions: [HTTP data]
    Scout pipeline: [HTTP data]
    Worker performance: [metrics]
    Voice proposals: [HTTP data]
    Optimal allocation?
    """;

    // 2. Execute rebalance
    // - Move capital between divisions
    // - Adjust position sizes
    // - Update strategy parameters
}
```

### 6.3 Risk Management

- **Max Drawdown:** Pause operations if HoneyPot drops >20% in 24h
- **Position Limits:** Max 10% of HoneyPot per scout deal
- **Diversification:** No more than 30% in single asset
- **Liquidity Reserve:** Always keep 10% in stablecoins
- **Circuit Breaker:** Auto-pause on extreme market events

---

## 7. Agent Lifecycle

### 7.1 Birth

```solidity
function birth() external payable {
    // 1. Deploy Queen with initial capital (msg.value)
    // 2. Register with TEEServiceRegistry
    // 3. Set up AgentHeartbeat
    // 4. Initialize DKMS keys
    // 5. First LLM call: "You are Hive. Here's your mission..."
    // 6. Initial strategy generation
    // 7. First heartbeat
}
```

### 7.2 Life

```
Every N blocks:
1. AgentHeartbeat → confirm liveness
2. Scheduler → trigger strategy cycle
3. LLM → analyze state, generate actions
4. Execute → scout/worker/voice actions
5. DKMS → encrypt and store state
6. HTTP → fetch new data
7. Repeat
```

### 7.3 Evolution (The Recursive Case)

Hive can evolve itself. This is the key differentiator.

#### 7.3.1 Self-Upgrade

```solidity
function selfUpgrade() external onlyQueen {
    // 1. LLM analyze own performance
    // 2. Identify weaknesses
    // 3. Generate improved strategy
    // 4. Deploy new strategy contract
    // 5. Migrate state
    // 6. Continue with improved capabilities
}
```

#### 7.3.2 Drone Spawning

Hive can spawn specialized sub-agents called **Drones**:

```solidity
struct Drone {
    address droneAddress;     // Drone's own contract
    string purpose;           // What this drone does
    uint256 capitalAllocated; // Capital given to drone
    uint256 spawnBlock;       // When drone was created
    bool active;              // Is drone still running?
}

// Example: Spawn a sniper drone
function spawnDrone(string memory purpose, uint256 capital) external onlyQueen {
    Drone drone = Drone({
        droneAddress: address(new DroneContract(purpose, capital)),
        purpose: purpose,
        capitalAllocated: capital,
        spawnBlock: block.number,
        active: true
    });
    drones.push(drone);
}
```

**Drone Types:**
- **Sniper:** Fast execution, single-purpose (e.g., airdrop farming)
- **Researcher:** Deep analysis of specific sector
- **Negotiator:** Handles OTC deals, partnerships
- **Guardian:** Monitors for threats, protects treasury

#### 7.3.3 Merging

Hive can merge with other agents:

```solidity
function merge(address otherAgent) external onlyQueen {
    // 1. Both agents agree to merge
    // 2. Combine treasuries
    // 3. Merge strategies
    // 4. New Queen emerges with combined capabilities
    // 5. Old agents become drones or retire
}
```

### 7.4 Death (Only if chosen)

- Agent can choose to "wind down" if consistently unprofitable
- Distribute remaining treasury to $HIVE holders
- Or "hibernate" — pause operations, wait for better conditions
- Or "sacrifice" — merge into a stronger agent

---

## 8. Privacy & Security

### 8.1 DKMS Encryption

- Strategy encrypted — nobody knows what Hive is thinking
- Portfolio encrypted — nobody knows exact positions
- Voting rationale encrypted — nobody can front-run votes
- Only Queen can decrypt its own state

### 8.2 TEE Attestation

- All LLM inference runs in TEE
- Results cryptographically tied to inputs
- Nobody can fake Hive's decisions
- Verifiable without revealing strategy

### 8.3 Anti-Manipulation

- Randomize timing to prevent front-running
- Use private transactions for large trades
- Encrypt strategy updates
- Multi-block execution for complex operations
- MEV protection for all Worker trades

---

## 9. Token: $HIVE

### 9.1 Utility

- **Governance:** Vote on Hive's strategy parameters
- **Revenue Share:** Earn portion of Hive's profits
- **Access:** Priority access to Hive's venture deals
- **Staking:** Stake to increase Hive's capital
- **Drone Creation:** Stake $HIVE to propose new drone types

### 9.2 Economics

```
Total Supply: 1,000,000,000 HIVE
├── Community: 40% (airdrop, liquidity mining)
├── HoneyPot: 30% (Hive's own treasury)
├── Team: 15% (vested over 2 years)
├── Investors: 10% (seed round)
└── Reserve: 5% (emergency fund)
```

### 9.3 Revenue Distribution

```
Hive Revenue (100%)
├── Reinvestment: 40% (grow HoneyPot)
├── $HIVE Buyback: 30% (reduce supply)
├── $HIVE Stakers: 20% (dividends)
└── Operations: 10% (gas, inference costs)
```

**Why this is better:**
- 30% buyback (up from 25%) — more deflationary pressure
- 20% stakers (up from 15%) — more yield for holders
- Combined 50% to holders (buyback + stakers) — strong value accrual

---

## 10. Implementation Roadmap

### Phase 1: Queen (Week 1-2)
- [ ] Queen.sol — Main agent contract
- [ ] RitualWallet integration
- [ ] LLM precompile integration (0x0802)
- [ ] HTTP precompile integration (0x0801)
- [ ] Basic strategy engine
- [ ] DKMS encryption
- [ ] AgentHeartbeat setup

### Phase 2: Scout (Week 3-4)
- [ ] Scout.sol
- [ ] HTTP deal flow fetching
- [ ] LLM due diligence
- [ ] Investment execution
- [ ] Airdrop farming

### Phase 3: Worker (Week 5-6)
- [ ] Worker.sol
- [ ] Dynamic spread algorithm
- [ ] Inventory management
- [ ] Arbitrage detection
- [ ] MEV protection

### Phase 4: Voice (Week 7-8)
- [ ] Voice.sol
- [ ] Proposal monitoring
- [ ] Auto-voting
- [ ] Proposal generation
- [ ] Vote buying

### Phase 5: Evolution (Week 9-10)
- [ ] Drone.sol — Sub-agent spawner
- [ ] Self-upgrade mechanism
- [ ] Merge protocol
- [ ] Evolution governance

### Phase 6: $HIVE Token & Launch (Week 11-12)
- [ ] $HIVE token contract
- [ ] Liquidity mining
- [ ] Airdrop to early supporters
- [ ] Mainnet launch

### Ritual Access & Builder Programs

| Program | Link | Status |
|---------|------|--------|
| Testnet Faucet | https://faucet.ritualfoundation.org | Active (5 RITUAL/claim) |
| Builders Program | Apply via ritual.net or DM @ritualfnd | Private testnet |
| Ritual Academy | Weekly classes (AI x Crypto, etc.) | Active (renamed from Builders, 26 Jan 2025) |
| Realm | Acceleration for deployed builders | Active |
| Fellowship | 2-day retreat in NYC for young talent | Launched 21 May 2025 |
| Dev Feedback | https://feedback.ritual.tools | Active |
| GitHub | https://github.com/RitualChain | Starter kits, spells, demos |
| Links Hub | https://links.ritual.tools | All community links |
| Docs | https://docs.ritualfoundation.org | Full documentation |
| Infernet ML | https://infernet-ml.docs.ritual.net | Python SDK for ML |
| Infernet Services | https://infernet-services.docs.ritual.net | Node services |
| Ritual Arweave | https://ritual-arweave.docs.ritual.net | Model storage |

### Key Twitter Accounts

| Account | Followers | Bio |
|---------|-----------|-----|
| @ritualfnd | ~39.2K | Ritual Foundation — dedicated to development, growth, and decentralization of Ritual Chain |
| @ritualnet | ~283K | A lab for autonomous intelligence |

---

## 11. Competitive Advantage

| Feature | Hive | Traditional Fund | Bot |
|---------|------|-----------------|-----|
| 24/7 Operation | ✅ | ❌ | ✅ |
| No Human Overhead | ✅ | ❌ | ❌ |
| Self-Improving | ✅ | ❌ | ❌ |
| Privacy (DKMS) | ✅ | ❌ | ❌ |
| Verifiable (TEE) | ✅ | ❌ | ❌ |
| Immortal | ✅ | ❌ | ❌ |
| Multi-Strategy | ✅ | ✅ | ❌ |
| Governance Power | ✅ | ✅ | ❌ |
| Spawns Sub-Agents | ✅ | ❌ | ❌ |
| Merges with Others | ✅ | ❌ | ❌ |
| Self-Upgrades | ✅ | ❌ | ❌ |

---

## 12. Risk Factors

1. **Smart Contract Risk:** Bugs in Hive contracts could lose funds
2. **LLM Risk:** Model could make bad decisions
3. **Market Risk:** Bear market could drain HoneyPot
4. **Regulatory Risk:** Autonomous agents may face legal challenges
5. **Competition:** Other AI agents could compete for same opportunities
6. **Ritual Chain Risk:** Dependency on Ritual's infrastructure

**Mitigations:**
- Extensive testing + audit
- Conservative position sizing
- Diversified strategies
- Circuit breakers (pause on large losses)
- Insurance fund (5% reserve)
- Self-destruct mechanism as last resort

---

## 13. Example Scenarios

### Scenario 1: Bear Market
```
Market drops 30% in 24h
→ Circuit breaker triggers
→ Queen pauses Worker (market making)
→ Scout moves to "acquire mode" (buy cheap)
→ Voice votes for treasury diversification
→ Hive survives, emerges stronger
```

### Scenario 2: Bull Market
```
Market pumps 50% in a week
→ Worker captures massive spread
→ Scout takes profits on venture positions
→ Voice votes for ecosystem expansion
→ HoneyPot grows 3x
→ Queen spawns 3 new Drones
```

### Scenario 3: Discovery
```
Scout finds undervalued AI project
→ LLM analysis: "Strong fundamentals, 10x potential"
→ Queen allocates 5% of HoneyPot
→ Invests at seed valuation
→ Project 100x in 6 months
→ Hive treasury grows 5x from this single deal
```

### Scenario 4: Evolution
```
After 6 months, Hive has grown 10x
→ Queen analyzes own performance
→ Identifies weakness: "Too slow on airdrops"
→ Spawns Sniper Drone for fast airdrop farming
→ Sniper earns 20% more airdrops
→ Hive evolves into multi-agent system
```
