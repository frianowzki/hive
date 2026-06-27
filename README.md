<div align="center">

<img src="https://raw.githubusercontent.com/frianowzki/hive/master/logo_hive.png" width="120" alt="Hive">

<br>

# `H I V E`

### **Compliant AI Launchpad on Ritual Testnet**

<br>

![Solidity](https://img.shields.io/badge/Solidity-0.8.20-363636?style=flat&logo=solidity)
![Foundry](https://img.shields.io/badge/Foundry-v2-363636?style=flat)
![Tests](https://img.shields.io/badge/Tests-320%20passed-00cc88)
![Contracts](https://img.shields.io/badge/Contracts-33%20deployed-6366f1)
![Chain](https://img.shields.io/badge/Chain-Ritual%20Testnet%20(1979)-8b5cf6)
![License](https://img.shields.io/badge/License-MIT-363636)

<br>

[**Explorer**](https://explorer.ritualfoundation.org) · [**Contracts**](#-contracts) · [**Architecture**](#-architecture) · [**Quickstart**](#-quickstart) · [**Deployer**](https://sovereign-deployer.vercel.app)

</div>

---

## What is Hive?

**Hive** is a compliant, AI-powered launchpad built natively on [Ritual Testnet](https://ritual.net) (Chain ID: 1979). Zero-knowledge identity. AI-driven price discovery. Decentralized governance. One platform.

**Core thesis:** Compliance and decentralization are not opposites.

Hive uses zk-proofs to verify identity (KYC for individuals, KYB for projects) without exposing personal data on-chain. Users self-custody through a dual-wallet architecture — primary wallet (browser extension) controls a Hive wallet (passkey-based) — keeping full custody while meeting regulatory requirements.

<br>

### Key Features

<table>
<tr>
<td width="50%">

**🔐 Identity & Privacy**
- **ZK-Proofed Identity** — KYC/KYB via zero-knowledge proofs. Prove age, country, organization — without revealing data
- **DKMS Privacy** — TEE-bound key derivation via Ritual DKMS precompile (0x0803). Private keys never leave the enclave
- **Dual Wallet Auth** — Primary (ECDSA/MetaMask) + Hive (Ritual passkey P-256). User always retains custody

</td>
<td width="50%">

**🤖 AI Engine**
- **AI-Driven Price Discovery** — Hive Clearing Auction (HCA) with on-chain Ritual LLM pricing
- **Allora Price Feeds** — AI-inferred predictions from Allora Network via HTTP precompile
- **FLock Federated Training** — Self-improving AI via federated learning. Training → Validation → ONNX deployment

</td>
</tr>
<tr>
<td>

**💰 DeFi Infrastructure**
- **4-Tier Staking** — Bronze → Silver → Gold → Diamond. Lock multiplier, auto-compound, fee discounts
- **Fee Economy** — Auto-distributes: 60% stakers / 25% referrers / 15% reserve
- **Governance** — DAO voting with staked-weighted power, delegation, quorum, time-locked execution

</td>
<td>

**🛠️ Platform**
- **Agent Gateway** — On-chain chatbot powered by Ritual LLM precompile
- **Sovereign Agents** — Autonomous agents with async LLM + PII mode
- **Meta-Tx Relayer** — Gasless transactions via primary wallet signing

</td>
</tr>
</table>

<br>

### Why Ritual Testnet?

Hive is a **flagship showcase** for Ritual's five research frontiers:

| Precompile | Usage | Contracts |
|:---:|---|---|
| **LLM** | On-chain AI inference | HiveAgent, HiveBrain, HiveClearing |
| **HTTP** | Off-chain data feeds | HiveOracle, Allora Network |
| **DKMS** | TEE-bound key derivation | HiveID, HiveDKMS |
| **ECIES** | Encrypted P2P messaging | HiveChat |
| **P-256** | Native passkey auth | Hive wallets |

> *No other chain supports all five primitives natively.*

---

## 🏗️ Architecture

```
┌─────────────────────────────────────────────────────────────────────────┐
│                            HIVE PROTOCOL                                │
│                                                                         │
│  ┌─────────────────────────── SECURITY ───────────────────────────┐    │
│  │                                                                │    │
│  │   HiveID        HiveMultiSig      HiveVerifier    HiveRelayer  │    │
│  │   (Identity)    (M-of-N)          (ZK Proofs)     (Meta-Tx)    │    │
│  │                                                                │    │
│  └────────────────────────────┬───────────────────────────────────┘    │
│                               │                                         │
│  ┌────────────────────────────┴───────────────────────────────────┐    │
│  │                       HiveFactory (25 modules)                  │    │
│  └───┬──────────┬──────────┬──────────┬──────────┬────────────────┘    │
│      │          │          │          │          │                      │
│  ┌───┴──┐  ┌───┴──┐  ┌───┴──┐  ┌───┴──┐  ┌───┴──┐                   │
│  │Clear │  │Oracle│  │Brain │  │FLock │  │DKMS  │  ← AI + Privacy    │
│  │ing   │  │(Feed)│  │(LLM) │  │(FL)  │  │(TEE) │                    │
│  └──────┘  └──────┘  └──────┘  └──────┘  └──────┘                    │
│                                                                         │
│  ┌───┴──┐  ┌───┴──┐  ┌───┴──┐  ┌───┴──┐  ┌───┴──┐                   │
│  │Stak- │  │Treas-│  │Honey-│  │Refer-│  │Gov-  │  ← Economics      │
│  │ing   │  │ury   │  │Pot   │  │ral   │  │ern   │                    │
│  └──────┘  └──────┘  └──────┘  └──────┘  └──────┘                    │
│                                                                         │
│  ┌───┴──┐  ┌───┴──┐  ┌───┴──┐  ┌───┴──┐  ┌───┴──┐                   │
│  │Queen │  │Agent │  │Lock  │  │USD   │  │Fauc- │  ← Platform        │
│  │(Orch)│  │Fact. │  │(Vest)│  │(Stab)│  │et    │                    │
│  └──────┘  └──────┘  └──────┘  └──────┘  └──────┘                    │
│                                                                         │
│                          ┌─────────────┐                               │
│                          │  Ritual L1  │                               │
│                          │  Chain 1979 │                               │
│                          └─────────────┘                               │
└─────────────────────────────────────────────────────────────────────────┘
```

### Data Flow

```
User → HiveID (verify) → HiveClearing (bid) → HoneyPot (fee) → Stakers/Referrers/Reserve
                                                    ↓
                                              HiveBrain (analyze) ← HiveOracle (prices)
                                                    ↓                   ↑
                                              HiveFLock (train)    Allora Network
                                                    ↓
                                              ONNX → Ritual Precompile
```

---

## 📋 Contracts

### 🔐 Identity & Security

| Contract | Description |
|---|---|
| **HiveID** | On-chain identity registry. Permanent username, dual-wallet binding, KYC/KYB verification, TEE-bound key derivation, ECIES-encrypted storage, PII redaction |
| **HiveDKMS** | TEE-bound key management via Ritual DKMS precompile (0x0803). ECIES encrypt/decrypt, key derivation, owner-bound keys |
| **HiveMultiSig** | M-of-N multi-signature wallet with 24h timelock |
| **HiveVerifier** | ZK proof verifier for KYC/KYB. 5 proof types (age, country, accreditation, org, sanctions) |
| **HiveRelayer** | Meta-transaction relayer. Primary wallet signs, relayer executes |

### 💰 Financial Infrastructure

| Contract | Description |
|---|---|
| **HiveClearing** | Hive Clearing Auction (HCA). AI-driven price discovery via Ritual LLM. Refund mechanism, batch bidding, settlement |
| **HoneyPot** | Treasury vault with auto-distribution: 60% stakers / 25% referrers / 15% reserve. Per-referrer tracking, no-staker fallback |
| **HiveStaking** | 4-tier staking (Bronze → Diamond). Lock multiplier, auto-compound, fee discounts, voting power |
| **HiveTreasury** | Fee collector & distributor. Multi-sig controlled |
| **HiveOracle** | Price feed via Ritual HTTP precompile + Allora Network. AI-inferred predictions with confidence intervals |
| **HiveToken** | ERC20 with vesting and transfer restrictions |
| **HivePortfolio** | Holdings tracking, weighted average entry, PnL |
| **HiveReputation** | 5-tier reputation scoring |
| **HiveReferral** | 4-tier referral engine with fee sharing |

### 🤖 AI & Agents

| Contract | Description |
|---|---|
| **HiveBrain** | Sovereign agent brain. Async LLM, PII mode, Oracle integration, 14 action types |
| **HiveFLock** | Federated learning via FLock.io. Training tasks, model validation, ONNX deployment, winner selection |
| **HiveAgent** | AI Agent Gateway via Ritual LLM precompile |
| **HiveAgentFactory** | Per-user sovereign agent summoning |
| **Queen** | Central orchestrator. `runCycle()` → Brain.think() → Strategy.execute() |
| **HiveAutoStrategy** | Automated trading: DCA, TP, SL, Trailing Stop |
| **HiveMarketMaker** | AI-driven market making via Ritual LLM |

### 🏛️ Governance & Platform

| Contract | Description |
|---|---|
| **HiveGovernance** | DAO voting. Staked-weighted power, delegation, quorum, time-locked execution |
| **HiveNotification** | On-chain event system with subscriptions and price alerts |
| **HiveLock** | Vesting (Linear, Cliff+Linear, Custom). Create/claim/cancel |
| **hiveUSD** | USD-pegged stablecoin for testnet (100B supply) |
| **HiveFaucet** | Claim 1,000 hiveUSD every 24h |

### 🔧 Infrastructure

| Contract | Description |
|---|---|
| **HiveFactory** | Master wiring contract. `wireAll()` connects all 25 modules |
| **HiveChat** | Encrypted P2P via Ritual ECIES precompile |
| **HiveLaunchPad** | Token launch with HCA mechanics |
| **HiveRegistry** | Contract registry for module discovery |
| **HiveCouncil** | Council governance (multi-representative) |
| **HivePoints** | On-chain points/rewards |

---

## 📁 Project Structure

```
hive/
├── src/                              # 33 contracts, ~12,000 LOC
│   ├── agent/                        # AI agent layer
│   │   ├── HiveAgent.sol             # LLM Gateway
│   │   ├── HiveAgentFactory.sol      # Agent summoning
│   │   ├── HiveBrain.sol             # Sovereign brain
│   │   ├── HiveGovernor.sol          # Safety layer
│   │   └── HiveSovereignAgent.sol    # Ritual Sovereign Agent
│   ├── auction/
│   │   └── HiveClearing.sol          # HCA + AI pricing
│   ├── identity/
│   │   └── HiveID.sol                # ZK-proofed identity
│   ├── privacy/
│   │   └── HiveDKMS.sol              # TEE-bound key management
│   ├── training/
│   │   └── HiveFLock.sol             # Federated learning
│   ├── oracle/
│   │   └── HiveOracle.sol            # Allora price feeds
│   ├── staking/
│   │   └── HiveStaking.sol           # 4-tier staking
│   ├── treasury/
│   │   ├── HiveTreasury.sol          # Fee collector
│   │   └── HoneyPot.sol              # Auto-distribution vault
│   ├── governance/
│   │   └── HiveGovernance.sol        # DAO
│   └── ...                           # 20+ more modules
│
├── test/                             # 320 tests, all passing
│   ├── Hive.t.sol                    # Core integration
│   ├── HiveClearing.t.sol            # HCA tests
│   ├── HiveDKMS.t.sol                # DKMS privacy tests
│   ├── HiveFeeDistribution.t.sol     # Fee economy tests
│   ├── HiveFLock.t.sol               # Federated learning tests
│   ├── HiveID.t.sol                  # Identity tests
│   ├── HiveOracle.t.sol              # Oracle tests
│   └── HiveSuite2.t.sol              # Suite 2
│
├── script/
│   ├── Deploy.s.sol                  # Phase 1 deployment
│   └── DeployV3.s.sol                # Phase 2 deployment
│
├── vercel-deploy/                    # Sovereign Deployer UI
│   ├── index.html                    # Frosted glass deployer
│   └── api/encode.py                 # Calldata encoder
│
└── foundry.toml                      # via_ir: true, optimizer: 100 runs
```

---

## 🌐 Network

| | |
|---|---|
| **Chain** | Ritual Testnet |
| **Chain ID** | `1979` |
| **RPC** | `https://rpc.ritualfoundation.org` |
| **Explorer** | `https://explorer.ritualfoundation.org` |
| **Currency** | RITUAL |
| **Block Time** | ~348ms |

---

## 🚀 Quickstart

### Prerequisites

- [Foundry](https://book.getfoundry.sh/) (forge, cast, anvil)

### Build & Test

```bash
git clone https://github.com/frianowzki/hive.git
cd hive
forge build
forge test -vv
```

### Deploy

```bash
cp .env.example .env
# Edit .env with your PRIVATE_KEY

forge script script/Deploy.s.sol \
  --rpc-url https://rpc.ritualfoundation.org \
  --broadcast --verify
```

### Sovereign Deployer

Deploy autonomous AI agents on-chain via the web UI:

**[sovereign-deployer.vercel.app](https://sovereign-deployer.vercel.app)**

- ZeroClaw (CLI_TYPE=6) recommended
- Native LLM provider (no API key needed)
- Model: `zai-org/GLM-4.7-FP8`
- Simulate before broadcast
- Hybrid agent scanning (localStorage + on-chain events)

---

## ⚙️ Compiler

```
Solidity      0.8.20
Optimizer     enabled (100 runs)
via_ir        true
EVM           shanghai
```

---

## 🔒 Security

**Audit:** [`audit/AUDIT_REPORT.md`](audit/AUDIT_REPORT.md) · [`PDF`](audit/AUDIT_REPORT.pdf)

| Severity | Count | Status |
|:---:|:---:|:---:|
| Critical | 0 | ✅ |
| High | 0 | ✅ |
| Medium | 2 | ✅ Fixed |
| Low | 5 | ✅ Fixed |
| Info | 8 | ✅ Noted |

**Scope:** Core 31 contracts (pre-interconnection). Access control, reentrancy, fund safety, zk-proof verification, DAO governance.

**Not yet audited:** Phase 1-3 integrations, HiveBrain ↔ Oracle ↔ FLock data flow, Queen orchestration, HiveLock, AgentFactory, HiveUSD + Faucet.

> **Production readiness:** Testnet only. Full re-audit required before mainnet.

---

## 📜 License

MIT

---

<div align="center">

**Built on [Ritual Testnet](https://ritual.net)**

33 contracts · 320 tests · 5 Ritual precompiles

Price feeds by [Allora Network](https://allora.network) · Training by [FLock.io](https://flock.io)

<br>

*Built by [Frianowzki](https://github.com/frianowzki)*

</div>
