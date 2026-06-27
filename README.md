<div align="center">

<img src="https://raw.githubusercontent.com/frianowzki/hive/master/logo_hive.png" width="120" alt="Hive">

<br>

# `H I V E`

### **Compliant AI Launchpad on Ritual Testnet**

<br>

![Solidity](https://img.shields.io/badge/Solidity-0.8.20-363636?style=flat&logo=solidity)
![Foundry](https://img.shields.io/badge/Foundry-v1.7.1-363636?style=flat)
![Tests](https://img.shields.io/badge/Tests-319%20passed-00cc88)
![Contracts](https://img.shields.io/badge/Contracts-39-6366f1)
![LOC](https://img.shields.io/badge/LOC-13%2C628-8b5cf6)
![Chain](https://img.shields.io/badge/Chain-Ritual%20Testnet%20(1979)-8b5cf6)
![License](https://img.shields.io/badge/License-MIT-363636)

<br>

[**Explorer**](https://explorer.ritualfoundation.org) · [**Dashboard**](https://ritual-hive.vercel.app) · [**Deployer**](https://sovereign-deployer.vercel.app) · [**Contracts**](#-contracts) · [**Architecture**](#%EF%B8%8F-architecture)

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
| **LLM** (0x0100) | On-chain AI inference | HiveAgent, HiveBrain, HiveClearing |
| **HTTP** (0x0101) | Off-chain data feeds | HiveOracle, Allora Network |
| **DKMS** (0x0803) | TEE-bound key derivation | HiveID, HiveDKMS |
| **ECIES** (0x0802) | Encrypted P2P messaging | HiveChat |
| **P-256** (0x0102) | Native passkey auth | Hive wallets |

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
│  │                 HiveFactory (26 modules wired)                  │    │
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
| **HiveBrain** | Sovereign agent brain. Async LLM, PII mode, Oracle + FLock integration, 14 action types |
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
| **HiveFactory** | Master wiring contract. `wireExtended()` connects all 26 modules |
| **HiveChat** | Encrypted P2P via Ritual ECIES precompile |
| **HiveLaunchPad** | Token launch with HCA mechanics |
| **HiveRegistry** | Contract registry for module discovery |
| **HiveCouncil** | Council governance (multi-representative) |
| **HivePoints** | On-chain points/rewards |

---

## 📁 Project Structure

```
hive/
├── src/                              # 39 contracts, ~13,600 LOC
│   ├── agent/                        # AI agent layer
│   │   ├── HiveAgent.sol             # LLM Gateway
│   │   ├── HiveAgentFactory.sol      # Agent summoning
│   │   ├── HiveBrain.sol             # Sovereign brain (Oracle + FLock wired)
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
├── test/                             # 319 tests, all passing
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
├── dashboard/
│   └── dashboard.html                # Full dashboard (8 pages)
│
├── index.html                        # Landing page
│
├── vercel-deploy/                    # Sovereign Deployer UI
│   ├── index.html                    # Frosted glass deployer
│   └── api/encode.py                 # Calldata encoder
│
└── foundry.toml                      # via_ir: true, optimizer: 100 runs
```

---

## 🌐 Deployed Contracts

All contracts deployed on **Ritual Testnet** (Chain ID: 1979).

### Factory

| Contract | Address |
|---|---|
| **HiveFactory** | [`0xDAf09A8F6f461C0961172de6E3bFa4308118d88c`](https://explorer.ritualfoundation.org/address/0xDAf09A8F6f461C0961172de6E3bFa4308118d88c) |

### AI & Privacy

| Contract | Address |
|---|---|
| **HiveBrain** | [`0xCB7B3C9D008aE6ad5075936df5d44d37185352e8`](https://explorer.ritualfoundation.org/address/0xCB7B3C9D008aE6ad5075936df5d44d37185352e8) |
| **HiveOracle** | [`0x5D72F3faf4ada60E1beCa310a2FA82b7B731aEbE`](https://explorer.ritualfoundation.org/address/0x5D72F3faf4ada60E1beCa310a2FA82b7B731aEbE) |
| **HiveFLock** | [`0xb0f436d799935Fbe6c7D8885E4345B588B16F5d2`](https://explorer.ritualfoundation.org/address/0xb0f436d799935Fbe6c7D8885E4345B588B16F5d2) |
| **HiveDKMS** | [`0x9533BD3D3baD7182EE52e054ca9c73780069AD5E`](https://explorer.ritualfoundation.org/address/0x9533BD3D3baD7182EE52e054ca9c73780069AD5E) |
| **HiveClearing** | [`0x631969799907Dc4914988298A7795783e24c20CC`](https://explorer.ritualfoundation.org/address/0x631969799907Dc4914988298A7795783e24c20CC) |

### Economics

| Contract | Address |
|---|---|
| **HiveStaking** | [`0x8D2A42Fe7845F165264d042267a3bD8EBae83d28`](https://explorer.ritualfoundation.org/address/0x8D2A42Fe7845F165264d042267a3bD8EBae83d28) |
| **HoneyPot** | [`0x4DF77A4f06b792BA964B3dD751a0672cFa2bAb69`](https://explorer.ritualfoundation.org/address/0x4DF77A4f06b792BA964B3dD751a0672cFa2bAb69) |
| **HiveTreasury** | [`0x90fbd495c888ae010e40FD299E143FabFcf08C18`](https://explorer.ritualfoundation.org/address/0x90fbd495c888ae010e40FD299E143FabFcf08C18) |
| **HiveUSD** | [`0x60601e48038E32dBCd9A9667c589bf6D39A32fb5`](https://explorer.ritualfoundation.org/address/0x60601e48038E32dBCd9A9667c589bf6D39A32fb5) |

### Identity & Governance

| Contract | Address |
|---|---|
| **HiveID** | [`0x013c6D5a4fa5D50a92261C4189a8F56900408A01`](https://explorer.ritualfoundation.org/address/0x013c6D5a4fa5D50a92261C4189a8F56900408A01) |
| **HiveGovernance** | [`0xeadd2aB5D8f1Ead852927Dd56c34b365603c2702`](https://explorer.ritualfoundation.org/address/0xeadd2aB5D8f1Ead852927Dd56c34b365603c2702) |
| **Queen** | [`0xC2ec8C64A3183e3a611284d70ccb4C0dAb8eDDfd`](https://explorer.ritualfoundation.org/address/0xC2ec8C64A3183e3a611284d70ccb4C0dAb8eDDfd) |
| **HiveAgent** | [`0x842441aB565a3C6C8183ABB08a735B2DEA184327`](https://explorer.ritualfoundation.org/address/0x842441aB565a3C6C8183ABB08a735B2DEA184327) |

<details>
<summary><strong>View all 26 factory modules</strong></summary>

| # | Module | Address |
|---|---|---|
| 0 | hiveID | `0x013c6d5a4fa5d50a92261c4189a8f56900408a01` |
| 1 | verifier | `0xdd2a524e0bda702ed5f9b1740dd145ce2de23eb6` |
| 2 | reputation | `0x4cbe69cc563d548e2da214c6c7c16fc32b69526a` |
| 3 | oracle | `0x5d72f3faf4ada60e1beca310a2fa82b7b731aebe` |
| 4 | referral | `0x6fc9d8abfa06867d5932da9c473d46b0224041ed` |
| 5 | portfolio | `0x81e38ad29b869de5dd99bc5da1386b65ef2da066` |
| 6 | relayer | `0xa2fcc065f174e9be536a090dd344b9c8b8dc513c` |
| 7 | launchPad | `0x8eb73b9e2dd62ecfc9c61861638c45afe003d95b` |
| 8 | marketMaker | `0x62c8ab145aa677792b7e7d1f0bf64000d3dc637d` |
| 9 | clearing | `0x631969799907dc4914988298a7795783e24c20cc` |
| 10 | staking | `0x8d2a42fe7845f165264d042267a3bd8ebae83d28` |
| 11 | treasury | `0x90fbd495c888ae010e40fd299e143fabfcf08c18` |
| 12 | brain | `0xcb7b3c9d008ae6ad5075936df5d44d37185352e8` |
| 13 | agent | `0x842441ab565a3c6c8183abb08a735b2dea184327` |
| 14 | strategy | `0x1b3a537d4572c1020bc72c9f4951704966d3bef9` |
| 15 | autoStrategy | `0x1b3a537d4572c1020bc72c9f4951704966d3bef9` |
| 16 | flock | `0xb0f436d799935fbe6c7d8885e4345b588b16f5d2` |
| 17 | governance | `0xeadd2ab5d8f1ead852927dd56c34b365603c2702` |
| 18 | council | `0x245590be2e044a8a0aeb99c1bbbaaa4e68b715b3` |
| 19 | multiSig | `0xd450cab1dce65ac7bb089cf8da9f20f37544b1b6` |
| 20 | chat | `0x615f139ddfb2f2f486133b3a2d9f74dd2ba785b6` |
| 21 | points | `0xc031064390952259a42885219db16f66677fbfaa` |
| 22 | queen | `0xc2ec8c64a3183e3a611284d70ccb4c0dab8eddfd` |
| 23 | registry | `0x89cff106458261b48597ee0307017504080182ee` |
| 24 | dkms | `0x9533bd3d3bad7182ee52e054ca9c73780069ad5e` |
| 25 | honeyPot | `0x4df77a4f06b792ba964b3dd751a0672cfa2bab69` |

</details>

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

### Dashboard

Access the live dashboard: **[ritual-hive.vercel.app](https://ritual-hive.vercel.app)**

- 8 pages: Portfolio, Staking, Auction, Governance, Identity, DKMS, Fee Economy, FLock
- Wallet connect via MetaMask (Ritual Testnet)
- Real on-chain data from deployed contracts

### Sovereign Deployer

Deploy autonomous AI agents on-chain via the web UI:

**[sovereign-deployer.vercel.app](https://sovereign-deployer.vercel.app)**

- ZeroClaw (CLI_TYPE=6) recommended
- Native LLM provider (no API key needed)
- Model: `zai-org/GLM-4.7-FP8`
- Simulate before broadcast

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

39 contracts · 319 tests · 5 Ritual precompiles · 13,628 LOC

Price feeds by [Allora Network](https://allora.network) · Training by [FLock.io](https://flock.io)

<br>

*Built by [Frianowzki](https://github.com/frianowzki)*

</div>
