<p align="center">
  <img src="logo_hive.png" width="200" alt="Hive Logo">
</p>

<h1 align="center">HIVE</h1>
<p align="center">Compliant AI Launchpad on Ritual Chain</p>

<p align="center">
  <a href="https://explorer.ritualfoundation.org">Explorer</a> •
  <a href="#architecture">Architecture</a> •
  <a href="#contracts">Contracts</a> •
  <a href="#quickstart">Quickstart</a>
</p>

---

## What is Hive?

Hive is a **compliant, AI-powered launchpad** built natively on [Ritual Chain](https://ritual.net) (Chain ID: 1979). It combines zero-knowledge identity verification, AI-driven price discovery, and decentralized governance into a single platform for launching and trading tokens.

**Core thesis:** Compliance and decentralization are not opposites. Hive uses zk-proofs to verify identity (KYC for individuals, KYB for projects/institutions) without exposing personal data on-chain. Users self-custody through a dual-wallet architecture — their primary wallet (browser extension) controls a Hive wallet (passkey-based) — keeping full custody while meeting regulatory requirements.

### Key Features

- **ZK-Proofed Identity** — KYC/KYB verification via zero-knowledge proofs. Prove you're 18+, prove your country, prove your organization — without revealing the underlying data
- **DKMS Privacy** — TEE-bound key derivation via Ritual DKMS precompile (0x0803). Private keys never leave the enclave. ECIES-encrypted KYC data stored on-chain, only TEE can decrypt
- **Dual Wallet Auth** — Primary wallet (ECDSA, e.g. MetaMask) + Hive wallet (Ritual passkey P-256). User always retains custody
- **AI-Driven Price Discovery** — Hive Clearing Auction (HCA) with Ritual LLM-powered pricing. Optimal token launch price determined by on-chain AI
- **Allora Price Feeds** — AI-inferred price predictions from Allora Network via Ritual HTTP precompile. Crowdsourced models supply predictions with confidence intervals
- **FLock Federated Training** — Self-improving AI via FLock.io federated learning. Training tasks, model submissions, validator voting, winner selection, ONNX deployment via Ritual precompile
- **EigenLayer AVS** — Hive as an Actively Validated Service secured by restaked ETH. Operator registration, delegation, slashing, service tasks, fee distribution
- **AI Agent Gateway** — On-chain chatbot powered by Ritual LLM precompile. Market analysis, token insights, strategy advice — all computed on-chain
- **Agent Brain (Async + PII)** — Sovereign AI brain with async LLM inference and PII mode. think() → plan() → act() pipeline with confidence threshold. PII mode ensures sensitive strategy data never hits the mempool
- **On-Chain Governance** — DAO voting with staked-weighted power, delegation, proposal types, quorum enforcement, and time-locked execution
- **4-Tier Staking** — Bronze → Silver → Gold → Diamond. Lock multiplier, auto-compound, fee discounts, priority access
- **Fee Economy** — Treasury auto-distributes fees: 60% to stakers, 25% to referrers, 15% to reserve

### Why Ritual Chain?

Hive is designed as a **flagship showcase** for Ritual's five research frontiers:

1. **Ritual LLM Precompile** — On-chain AI inference (HiveAgent, HiveBrain, HiveClearing)
2. **Ritual HTTP Precompile** — Off-chain data feeds (HiveOracle, Allora Network)
3. **Ritual DKMS Precompile** — TEE-bound key derivation for private KYC (HiveID)
4. **Ritual ECIES Precompile** — Encrypted P2P messaging (HiveChat)
5. **Ritual Passkey (P-256)** — Native passkey signatures for Hive wallets

No other chain supports all five primitives natively.

---

## Architecture

```
┌─────────────────────────────────────────────────────────────────────┐
│                          HIVE PROTOCOL                              │
│                                                                     │
│  ┌──────────┐  ┌──────────┐  ┌──────────┐  ┌──────────┐           │
│  │ HiveID   │  │HiveMulti │  │HiveVeri- │  │HiveRelay-│           │
│  │ (Identity│  │  Sig     │  │  fier    │  │   er     │           │
│  │  Layer)  │  │ (M-of-N) │  │  (ZK)    │  │ (MetaTx) │           │
│  └────┬─────┘  └────┬─────┘  └────┬─────┘  └────┬─────┘           │
│       │              │              │              │                 │
│  ┌────┴──────────────┴──────────────┴──────────────┴─────┐         │
│  │                   HiveFactory                          │         │
│  │              (Master Wiring Contract)                   │         │
│  └────┬──────────────┬──────────────┬──────────────┬─────┘         │
│       │              │              │              │                 │
│  ┌────┴─────┐  ┌─────┴────┐  ┌─────┴────┐  ┌─────┴────┐           │
│  │HiveClear-│  │HivePort- │  │HiveRepu- │  │HiveRefer-│           │
│  │  ing     │  │  folio   │  │ tation   │  │   ral    │           │
│  │ (HCA +   │  │(Holdings │  │(5-Tier   │  │(4-Tier   │           │
│  │  AI)     │  │ + PnL)   │  │ Score)   │  │ Engine)  │           │
│  └──────────┘  └──────────┘  └──────────┘  └──────────┘           │
│                                                                     │
│  ┌──────────┐  ┌──────────┐  ┌──────────┐  ┌──────────┐           │
│  │HiveToken │  │HiveOracle│  │HiveAgent │  │HiveBrain │           │
│  │(ERC20 +  │  │(Price    │  │(LLM      │  │(Sovereign│           │
│  │ Vesting) │  │ Feed)    │  │ Gateway) │  │ Agent)   │           │
│  └──────────┘  └──────────┘  └──────────┘  └──────────┘           │
│                                                                     │
│  ┌──────────┐  ┌──────────┐  ┌──────────┐  ┌──────────┐           │
│  │HiveGovern│  │HiveStak- │  │HiveTreas-│  │HiveNotif-│           │
│  │  ance    │  │   ing    │  │   ury    │  │ ication  │           │
│  │ (DAO)    │  │(4-Tier)  │  │(Fee      │  │(On-Chain │           │
│  │          │  │          │  │ Distrib) │  │ Events)  │           │
│  └──────────┘  └──────────┘  └──────────┘  └──────────┘           │
│                                                                     │
│  ┌──────────┐  ┌──────────┐  ┌──────────┐  ┌──────────┐           │
│  │HiveAuto- │  │HiveChat  │  │ Queen    │  │HiveLaunch│           │
│  │Strategy  │  │(Encrypted│  │(Brain    │  │  Pad     │           │
│  │(DCA/TP/  │  │  P2P)    │  │ Orchest) │  │(Token    │           │
│  │ SL/Trail)│  │          │  │          │  │ Launch)  │           │
│  └──────────┘  └──────────┘  └──────────┘  └──────────┘           │
└─────────────────────────────────────────────────────────────────────┘
                              │
                    ┌─────────┴─────────┐
                    │   Ritual Chain     │
                    │  ┌──────────────┐  │
                    │  │ LLM Precomp  │  │  ← On-chain AI inference
                    │  │ HTTP Precomp │  │  ← Off-chain data + Allora
                    │  │ DKMS Precomp │  │  ← TEE key derivation
                    │  │ ECIES Precomp│  │  ← Encrypted messaging
                    │  │ P-256 Passkey│  │  ← Native passkey auth
                    │  └──────────────┘  │
                    └────────────────────┘
```

### User Flow

```
User (MetaMask) ──→ HiveID ──→ Register (free) ──→ Get Hive Wallet (passkey)
      │                                                │
      │  Primary Wallet (ECDSA)                        │  Hive Wallet (P-256)
      │  - Signs all transactions                      │  - Receives funds
      │  - Controls Hive wallet                        │  - Internal operations
      │                                                │
      └──────────── Withdraw ──────────────────────────┘
                    (to primary or other HiveID)
```

---

## Contracts

### 🔐 Identity & Security Layer

| Contract | Address | Description |
|----------|---------|-------------|
| **HiveID** | `0x013c...08A01` | On-chain identity registry with DKMS privacy. Permanent username, dual-wallet binding, KYC/KYB verification, TEE-bound key derivation, ECIES-encrypted KYC storage, PII redaction mode |
| **HiveMultiSig** | `0xd450...4B1B6` | M-of-N multi-signature wallet with 24h timelock. Required for Project/VC accounts |
| **HiveVerifier** | `0xDD2A...23Eb6` | ZK proof verifier for KYC/KYB. 5 proof types (age, country, accreditation, org, sanctions). Nullifier + nonce replay prevention |
| **HiveRelayer** | `0xa2FC...513c` | Meta-transaction relayer. Primary wallet signs, relayer executes from hive wallet |

### 💰 Financial Infrastructure

| Contract | Address | Description |
|----------|---------|-------------|
| **HiveClearing** | `0x6319...c20CC` | Hive Clearing Auction with AI-driven pricing. Token sale mechanism where price is continuously determined by demand via Ritual LLM |
| **HivePortfolio** | `0x81E3...a066` | Holdings tracking, weighted average entry price, vesting schedules, PnL calculation |
| **HiveReputation** | `0x4cbe...526A` | 5-tier reputation scoring (Bronze → Diamond). Fee discounts based on score |
| **HiveReferral** | `0x6fc9...41ED` | 4-tier referral engine with fee sharing |
| **HiveOracle** | `0x5D72...1aEbE` | Price feed via Ritual HTTP precompile + Allora Network. AI-inferred price predictions with confidence intervals, batch fetching, price history |
| **HiveToken** | `0xDA81...5ec3` | ERC20 token with vesting schedules and transfer restrictions |
| **HiveStaking** | `0x93dd...b408` | 4-tier staking with Treasury integration. setTreasury() for fee notifications. Lock multiplier, auto-compound, voting power |
| **HiveTreasury** | `0x90fb...8C18` | Fee collector & distributor. Multi-sig controlled. Auto-distributes: 60% stakers, 25% referrers, 15% reserve |

### 🤖 AI & Agent Layer

| Contract | Address | Description |
|----------|---------|-------------|
| **HiveAgent** | `0x8424...4327` | AI Agent Gateway via Ritual LLM precompile. On-chain chatbot for market analysis, token insights, strategy advice |
| **HiveBrain** | `0x0ad0...42B4` | Sovereign agent brain with async LLM, PII mode, Oracle price feeds, and FLock model integration. 14 action types (incl. RunFlockInference, DeployFlockModel, GetOraclePrice). Cross-contract calls to HiveOracle and HiveFLock |
| **Queen** | `0xDC96...Ae8E` | Central orchestrator with AI integration. runCycle() calls Brain.think(). getOraclePrice(). setDivision() wires 9 modules (honeypot, strategy, registry, launchPad, marketMaker, council, brain, oracle, flock) |
| **HiveAutoStrategy** | `0x1b3A...BEF9` | Automated trading with Oracle integration. DCA, TP, SL, Trailing Stop. fetchPrice() calls HiveOracle.getBestPrice() |
| **HiveMarketMaker** | `0x9CC5...289b` | AI-driven market making via Ritual LLM |
| **HiveFLock** | — | Federated learning with Brain integration. setBrain() wiring. deployModel() notifies Brain. Training tasks, model validation, ONNX deployment, FLock API inference |
| **HiveEigenLayer** | — | EigenLayer AVS with cross-contract wiring. 4 operator roles. setHiveStaking/Brain/FLock/Treasury. Fee distribution notifies HiveTreasury |

### 🏛️ Governance

| Contract | Address | Description |
|----------|---------|-------------|
| **HiveGovernance** | `0xeadd...2702` | DAO governance. Voting power from staked RITUAL. Proposal types, delegation, quorum, time-locked execution via multi-sig |
| **HiveNotification** | `0x9a04...C42` | On-chain event system. Subscriptions, price alerts, webhook integration |

### 🔧 Infrastructure

| Contract | Address | Description |
|----------|---------|-------------|
| **HiveFactory** | `0x0241...63c6` | Master wiring contract. 25 module references. wireAll() connects AI layer (Brain↔Oracle↔FLock), security layer (EigenLayer↔Staking↔Treasury), Queen orchestration, and AutoStrategy pricing |
| **HiveChat** | `0x615F...85B6` | Encrypted P2P messaging via Ritual ECIES precompile |
| **HiveLaunchPad** | `0x1187...d572` | Token launch platform with HCA mechanics |
| **HiveCouncil** | `0xD79F...3D94` | Council governance (multi-representative) |
| **HivePoints** | `0xA2fE...01a7` | On-chain points/rewards system |
| **HiveRegistry** | `0xae3c...98183` | Contract registry for module discovery |
| **Drone** | `0x0542...3f2` | Autonomous execution agents |
| **Strategy** | `0x638d...A15C` | Base strategy contract (parent of HiveAutoStrategy) |

### 📚 Libraries & Interfaces

| Contract | Description |
|----------|-------------|
| **HiveTypes** | Shared type definitions (AccountType, VerificationType, etc.) |
| **RitualPrecompileConsumer** | Base contract for Ritual precompile integration (LLM, HTTP, ECIES, DKMS) |
| **IHive** | Hive protocol interface |
| **IRitual** | Ritual precompile interface |

---

## Project Structure

```
hive/
├── src/                          # Smart contracts (35 files, ~10,600 LOC)
│   ├── agent/
│   │   ├── HiveAgent.sol         # AI Agent Gateway (LLM precompile)
│   │   └── HiveBrain.sol         # Sovereign agent brain
│   ├── auction/
│   │   └── HiveClearing.sol      # Hive Clearing Auction + AI pricing
│   ├── chat/
│   │   └── HiveChat.sol          # Encrypted P2P messaging (ECIES)
│   ├── council/
│   │   └── HiveCouncil.sol       # Council governance
│   ├── drone/
│   │   └── Drone.sol             # Autonomous execution agents
│   ├── factory/
│   │   └── HiveFactory.sol       # Master wiring contract
│   ├── governance/
│   │   └── HiveGovernance.sol    # DAO governance
│   ├── identity/
│   │   └── HiveID.sol            # On-chain identity registry
│   ├── interfaces/
│   │   ├── IHive.sol             # Hive protocol interface
│   │   └── IRitual.sol           # Ritual precompile interface
│   ├── launch/
│   │   └── HiveLaunchPad.sol     # Token launch platform
│   ├── libraries/
│   │   ├── HiveTypes.sol         # Shared type definitions
│   │   └── RitualPrecompileConsumer.sol  # Ritual precompile base
│   ├── maker/
│   │   └── HiveMarketMaker.sol   # AI market maker
│   ├── multisig/
│   │   └── HiveMultiSig.sol      # M-of-N multi-sig wallet
│   ├── notification/
│   │   └── HiveNotification.sol  # On-chain event system
│   ├── oracle/
│   │   └── HiveOracle.sol        # Price feed (HTTP precompile)
│   ├── points/
│   │   └── HivePoints.sol        # Points/rewards system
│   ├── portfolio/
│   │   └── HivePortfolio.sol     # Holdings & PnL tracking
│   ├── queen/
│   │   └── Queen.sol             # Brain orchestrator
│   ├── referral/
│   │   └── HiveReferral.sol      # 4-tier referral engine
│   ├── registry/
│   │   └── HiveRegistry.sol      # Contract registry
│   ├── relayer/
│   │   └── HiveRelayer.sol       # Meta-transaction relayer
│   ├── reputation/
│   │   └── HiveReputation.sol    # 5-tier reputation scoring
│   ├── staking/
│   │   └── HiveStaking.sol       # 4-tier staking system
│   ├── strategy/
│   │   ├── HiveAutoStrategy.sol  # Automated trading strategies
│   │   └── Strategy.sol          # Base strategy contract
│   ├── token/
│   │   └── HiveToken.sol         # ERC20 + vesting
│   ├── treasury/
│   │   ├── HiveTreasury.sol      # Fee collector & distributor
│   └── verifier/
│       └── HiveVerifier.sol      # ZK proof verifier
│
├── test/                         # Test suite (300 tests)
│   ├── Hive.t.sol                # Core integration tests
│   ├── HiveID.t.sol              # HiveID + DKMS privacy tests
│   ├── HiveSuite.t.sol           # Suite 1: ID, MultiSig, Clearing, etc.
│   ├── HiveSuite2.t.sol          # Suite 2: Verifier, Relayer, Oracle, etc.
│   ├── AlloraBrain.t.sol         # Allora + HiveBrain async/PII tests
│   ├── HiveFLock.t.sol           # FLock federated learning tests
│   └── HiveEigenLayer.t.sol      # EigenLayer AVS tests
│
├── script/
│   └── Deploy.s.sol              # Deployment script (19 contracts)
│
├── subgraph/                     # TheGraph subgraph
│   ├── schema.graphql            # 15 entity types
│   ├── subgraph.yaml             # 8 data sources
│   └── src/                      # AssemblyScript mappings
│       ├── clearing.ts
│       ├── identity.ts
│       ├── staking.ts
│       ├── governance.ts
│       ├── treasury.ts
│       ├── notification.ts
│       ├── relayer.ts
│       └── brain.ts
│
├── verification/                 # Contract verification package
│   ├── README.md                 # Manual verification guide
│   ├── DEPLOYMENT_MANIFEST.json  # Addresses, constructor args, compiler settings
│   ├── flattened/                # 19 flattened source files
│   └── abis/                     # 19 JSON ABIs
│
├── AUDIT_REPORT.md               # Security audit report
├── AUDIT_REPORT.pdf              # Audit report (PDF)
├── foundry.toml                  # Foundry configuration
└── .env.example                  # Environment template
```

---

## Network

| Property | Value |
|----------|-------|
| **Chain** | Ritual Testnet |
| **Chain ID** | 1979 |
| **RPC** | `https://rpc.ritualfoundation.org` |
| **Explorer** | `https://explorer.ritualfoundation.org` |
| **Currency** | RITUAL |
| **Deployer** | `0x4b171E1217b71E37777B7F56d89cCB441C1De301` |


### Interconnections

All modules connected via `HiveFactory.wireAll()`:

```
                    ┌─────────────┐
                    │ HiveFactory │
                    │ (25 modules)│
                    └──────┬──────┘
                           │
        ┌──────────────────┼──────────────────┐
        │                  │                  │
   wireAILayer()     wireSecurityLayer()   wireQueen()
        │                  │                  │
  ┌─────┴─────┐     ┌─────┴──────┐    ┌─────┴──────┐
  │Brain↔Oracle│    │EigenLayer↔ │    │Queen↔Brain │
  │Brain↔FLock │    │Staking↔    │    │Queen↔Oracle│
  │FLock→Brain │    │Treasury    │    │Queen↔FLock │
  └───────────┘     └────────────┘    └────────────┘
```

**AI Chain:** HiveBrain ↔ HiveOracle (prices) ↔ HiveFLock (models)
**Security Chain:** HiveEigenLayer ↔ HiveStaking ↔ HiveTreasury
**Orchestration:** Queen → Brain (think) → Strategy (execute) → Registry (heartbeat)
**User Flow:** HiveAutoStrategy → HiveOracle (fetchPrice) → HiveMarketMaker (swap)

---

## Quickstart

### Prerequisites

- [Foundry](https://book.getfoundry.sh/) (forge, cast, anvil)
- Git

### Build

```bash
git clone https://github.com/frianowzki/hive.git
cd hive
forge build
```

### Test

```bash
forge test -vv
```

All 300 tests should pass.

### Deploy

```bash
# Copy and fill environment
cp .env.example .env
# Edit .env with your PRIVATE_KEY

# Deploy to Ritual Testnet
forge script script/Deploy.s.sol \
  --rpc-url https://rpc.ritualfoundation.org \
  --broadcast \
  --verify
```

### Verify Contracts

See [`verification/README.md`](verification/README.md) for verification instructions.

---

## Compiler Settings

```
Solidity:     0.8.20
Optimizer:    enabled (100 runs)
via_ir:       true
EVM Version:  default (shanghai)
```

`via_ir` is enabled to resolve stack-too-deep errors in complex contracts (HiveRelayer, HiveClearing).

---

## Security

See [`AUDIT_REPORT.md`](AUDIT_REPORT.md) for the full audit report.

**Summary:**
- **Critical:** 0
- **High:** 0
- **Medium:** 2 (HiveClearing rounding edge case, HiveRelayer nonce reuse window)
- **Low:** 5 (event indexing, input validation, etc.)
- **Informational:** 8 (gas optimizations, documentation)
- **Status:** ✅ Approved for testnet deployment

---

## License

MIT

---

<p align="center">
  Built on <a href="https://ritual.net">Ritual Chain</a> • 35 contracts • 300 tests • Powered by Ritual LLM, HTTP, DKMS, ECIES, and Passkey precompiles • Price feeds by <a href="https://allora.network">Allora Network</a> • Training by <a href="https://flock.io">FLock.io</a> • Secured by <a href="https://eigenlayer.xyz">EigenLayer</a>
</p>