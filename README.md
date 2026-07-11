<div align="center">

<img src="assets/logo.png" alt="Hive Logo" width="200"/>

# 🐝 HIVE

### AI-Native Memecoin Launchpad on Ritual Chain

**Spawn autonomous AI agents as tokens. Each agent has its own personality, lore, and on-chain behavior — powered by Ritual's AI precompiles.**

[![Ritual Testnet](https://img.shields.io/badge/Network-Ritual%20Testnet-1979?color=10B981&style=flat-square)](https://ritual.foundation)
[![License](https://img.shields.io/badge/License-MIT-10B981?style=flat-square)](LICENSE)
[![Foundry](https://img.shields.io/badge/Built%20with-Foundry-F59E0B?style=flat-square)](https://book.getfoundry.sh)
[![Next.js](https://img.shields.io/badge/Frontend-Next.js-000?style=flat-square)](https://nextjs.org)

[Live App](https://hive-on-ritual.vercel.app) · [Explorer](https://explorer.ritualfoundation.org) · [Report Bug](https://github.com/frianowzki/hive/issues)

</div>

---

## 📋 Table of Contents

- [Overview](#-overview)
- [Architecture](#-architecture)
- [Smart Contracts](#-smart-contracts)
- [Frontend](#-frontend)
- [Getting Started](#-getting-started)
- [Deployment](#-deployment)
- [Security](#-security)
- [Roadmap](#-roadmap)
- [Contributing](#-contributing)
- [License](#-license)

---

## 🌟 Overview

Hive is a **pump.fun-style memecoin launchpad** built natively on **Ritual Chain** (EVM++). Every token launched on Hive is an **autonomous AI Agent** that uses Ritual's precompiles for:

- 🧠 **LLM Inference** — Generate token name, symbol, and lore
- 🎨 **Image Generation** — Create unique AI-generated agent avatars
- ⚡ **Autonomous Scheduler** — Agent posts updates and tweets autonomously
- 🔐 **TEE Security** — Credentials stored encrypted via ECIES

### How It Works

1. **User describes an agent** — "A cynical space hamster who loves leveraged trading"
2. **LLM generates metadata** — Token name, symbol, lore created on-chain
3. **Bonding curve launches** — Linear curve (0.1 RITUAL target)
4. **Trading begins** — Buy/sell with slippage protection
5. **Graduation** — At 0.1 RITUAL, liquidity auto-deployed to DEX, LP burned

---

## 🏗 Architecture

```
┌─────────────────────────────────────────────────────────┐
│                    HIVE ARCHITECTURE                     │
├─────────────────────────────────────────────────────────┤
│                                                          │
│  ┌──────────────┐    ┌──────────────┐    ┌───────────┐ │
│  │   Frontend   │◄──►│  Smart       │◄──►│  Ritual   │ │
│  │   Next.js    │    │  Contracts   │    │  Chain    │ │
│  │   Vercel     │    │  Solidity    │    │  RPC      │ │
│  └──────────────┘    └──────────────┘    └───────────┘ │
│         │                   │                   │        │
│         │                   │                   │        │
│  ┌──────────────┐    ┌──────────────┐    ┌───────────┐ │
│  │  Wagmi/Viem  │    │  HiveFactory │    │ LLM 0x802 │ │
│  │  RainbowKit  │    │  BondingCurve│    │ HTTP 0x801│ │
│  │  React Query │    │  AgentToken  │    │ IMG  0x805│ │
│  └──────────────┘    └──────────────┘    └───────────┘ │
│                                                          │
│  ┌──────────────────────────────────────────────────────┐│
│  │              DEX LAYER (Phase 6)                     ││
│  │  RitualV2Factory ──► RitualV2Router02                ││
│  │  Auto-deploy liquidity on graduation                 ││
│  └──────────────────────────────────────────────────────┘│
└─────────────────────────────────────────────────────────┘
```

---

## 📜 Smart Contracts

### Deployed Contracts (Ritual Testnet)

| Contract | Address | Description |
|----------|---------|-------------|
| **HiveFactory** | `0xd44785b6c5a001502fe4ff1a03821c5efff3efda` | Main factory, creates agents |
| **HiveAgentToken** | `0x5f63F9EEDd35711E44d446e354cce27d7845f731` | Test token (Cat Wizard) |
| **HiveBondingCurve** | `0xA6B792a52c4fFFB2d9295F2ED0d379d5dc3ee373` | Test bonding curve |
| **RitualV2Factory** | `0x61E570306f2BfD3E8F98D7cbE1905B5f0bCBb336` | DEX factory |
| **RitualV2Router** | `0x51BfaE29567120e2CE821F3021BCe593E7D9ccA5` | DEX router |

### Contract Architecture

#### HiveFactory.sol
- Creates new AI agent tokens with LLM-generated metadata
- Handles async callbacks from Ritual precompiles
- Manages agent launches and metadata updates

#### HiveAgentToken.sol
- ERC20 token with metadata (name, symbol, lore, logo)
- Agent status tracking (Minting, Launched, Graduated)
- Factory-only minting and updates

#### HiveBondingCurve.sol
- **Linear bonding curve** (pump.fun style)
- **7% total fee** (2% platform + 5% treasury)
- **Slippage protection** on buy/sell
- **Reentrancy guard** for security
- **Auto-graduation** at 0.1 RITUAL → DEX liquidity

#### RitualV2 DEX
- Minimal Uniswap V2 fork for graduation
- Auto-deploys liquidity pool on graduation
- LP tokens sent to dead address (permanently locked)

---

## 🖥 Frontend

### Tech Stack

- **Framework:** Next.js 16 (App Router)
- **Styling:** Tailwind CSS v4
- **Web3:** Wagmi v2 + RainbowKit
- **State:** React Query (TanStack)
- **Animation:** Framer Motion
- **Icons:** Lucide React

### Pages

| Route | Description |
|-------|-------------|
| `/` | Dashboard — Agent grid, metrics, system status |
| `/launch` | Spawn chamber — Console simulation launch form |
| `/token/[address]` | Trading deck — 3-column: Mind, Trading, Diagnostics |

### Features

- 🟢 **Real-time status** — Active, Thinking, Graduated indicators
- 📊 **Live metrics** — Total agents, volume, graduated count
- 🔄 **Event-driven UI** — Polls blockchain for updates
- ⚡ **Optimized caching** — React Query with smart stale times
- 🎨 **Cypherpunk aesthetic** — Glassmorphism, neon glows, monospace

---

## 🚀 Getting Started

### Prerequisites

- [Node.js](https://nodejs.org/) >= 18
- [Foundry](https://book.getfoundry.sh/getting-started/installation)
- [Git](https://git-scm.com/)

### Installation

```bash
# Clone the repo
git clone https://github.com/frianowzki/hive.git
cd hive

# Install Foundry dependencies
forge install

# Install frontend dependencies
cd hive-frontend
npm install
```

### Environment Setup

Create `.env` file in the root directory:

```bash
# Private key for deployment (NEVER commit this!)
PRIVATE_KEY=0x_YOUR_PRIVATE_KEY_HERE

# Platform treasury address
PLATFORM_TREASURY=0x63C5341454F66a32553CE598e06861E11095d39C

# Ritual Testnet RPC
RITUAL_RPC_URL=https://rpc.ritualfoundation.org
```

### Running Tests

```bash
# Run all tests
forge test

# Run mock tests only (fast, ~5ms)
forge test --match-path "test/HiveMock.t.sol"

# Run security tests
forge test --match-path "test/SecurityTest.t.sol"

# Run fork tests (requires RPC, ~30s)
forge test --match-path "test/HiveFork.t.sol"
```

### Running Frontend

```bash
cd hive-frontend
npm run dev
```

Visit [http://localhost:3000](http://localhost:3000)

---

## 📦 Deployment

### Smart Contracts

```bash
# Deploy to Ritual Testnet
forge script script/DeployHive.s.sol \
  --rpc-url https://rpc.ritualfoundation.org \
  --broadcast \
  --verify
```

### Frontend (Vercel)

```bash
cd hive-frontend
vercel --prod
```

---

## 🔒 Security

### Security Features

| Feature | Status | Description |
|---------|--------|-------------|
| ReentrancyGuard | ✅ | Protects buy/sell from reentrancy attacks |
| Slippage Protection | ✅ | `minTokensOut` / `minRitualOut` params |
| Access Control | ✅ | Factory-only functions, async delivery verification |
| Custom Errors | ✅ | Gas-efficient error handling |
| Callback Security | ✅ | Only AsyncDelivery contract can fulfill |

### Audit Status

- [x] Internal testing (40+ tests passing)
- [x] Mock tests for unit verification
- [x] Fork tests for live chain integration
- [ ] External audit (pending)

### Bug Bounty

Found a vulnerability? Please report it responsibly to **frianowzki@gmail.com**

---

## 🗺 Roadmap

### Phase 1: Core Launchpad ✅
- [x] Smart contracts (Factory, Token, Bonding Curve)
- [x] Linear bonding curve with fees
- [x] Mock + Fork testing (40+ tests)
- [x] Frontend deployment

### Phase 2: Frontend UI ✅
- [x] Dashboard with real-time metrics
- [x] Console simulation launch form
- [x] 3-column trading deck
- [x] Glassmorphism design system

### Phase 3: Async Launch UX ✅
- [x] Event-driven state machine
- [x] Real-time TX tracking
- [x] Metadata polling
- [x] Fallback timeout handling

### Phase 4: DEX Graduation ✅
- [x] RitualV2 DEX fork (Factory + Router)
- [x] Auto-liquidity deployment
- [x] LP token burning (dead address)

### Phase 5: Security Hardening ✅
- [x] ReentrancyGuard
- [x] Slippage protection
- [x] Enhanced events
- [x] Security test suite

### Phase 6: AI Integration (Coming Soon)
- [ ] LLM metadata generation (when vLLM activates)
- [ ] Autonomous agent scheduler
- [ ] Twitter/social media posting
- [ ] Image generation

### Phase 7: Advanced Features (Future)
- [ ] Event indexer + PostgreSQL
- [ ] TradingView charts
- [ ] Pay-to-prompt interaction
- [ ] Multi-agent orchestration

---

## 🤝 Contributing

Contributions are welcome! Please follow these steps:

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/amazing`)
3. Commit your changes (`git commit -m 'Add amazing feature'`)
4. Push to the branch (`git push origin feature/amazing`)
5. Open a Pull Request

---

## 📄 License

This project is licensed under the MIT License — see [LICENSE](LICENSE) for details.

---

## 🙏 Acknowledgments

- [Ritual Foundation](https://ritual.foundation) — AI-native blockchain
- [Foundry](https://book.getfoundry.sh) — Smart contract toolkit
- [Next.js](https://nextjs.org) — React framework
- [Wagmi](https://wagmi.sh) — React hooks for Ethereum
- [RainbowKit](https://www.rainbowkit.com) — Wallet connection

---

<div align="center">

**Built with 🐝 on Ritual Chain**

*Hive — Where AI Agents Come Alive*

</div>
