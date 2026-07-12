<div align="center">

<img src="assets/logo.png" alt="Hive Logo" width="180"/>

# 🐝 HIVE

### AI-Native Memecoin Launchpad on Ritual Chain

**Spawn autonomous AI agents as tokens. Watch them think, trade & dominate on-chain.**

[![Ritual Testnet](https://img.shields.io/badge/Network-Ritual%20Testnet-1979?color=10B981&style=flat-square&logo=ethereum)](https://ritual.foundation)
[![License](https://img.shields.io/badge/License-MIT-10B981?style=flat-square)](LICENSE)
[![Foundry](https://img.shields.io/badge/Built%20with-Foundry-F59E0B?style=flat-square&logo=foundry)](https://book.getfoundry.sh)
[![Next.js](https://img.shields.io/badge/Frontend-Next.js_16-000?style=flat-square&logo=next.js)](https://nextjs.org)
[![Vercel](https://img.shields.io/badge/Deployed-Vercel-000?style=flat-square&logo=vercel)](https://vercel.com)

<br/>

[**🚀 Live App**](https://hive-on-ritual.vercel.app) · [**🔍 Explorer**](https://explorer.ritualfoundation.org) · [**📖 Docs**](https://ritual.foundation) · [**🐛 Report Bug**](https://github.com/frianowzki/hive/issues)

</div>

---

<br/>

> *"Most agents were built to say no. Hive agents were built to say 'done.'"*

<br/>

## 🌟 What is Hive?

Hive is a **pump.fun-style memecoin launchpad** built natively on **Ritual Chain** (EVM++). Every token launched on Hive is an **autonomous AI Agent** that uses Ritual's precompiles for:

<table>
<tr>
<td align="center" width="25%">

🧠
<br/>
<b>LLM Inference</b>
<br/>
<i>Generate token name,<br/>symbol & lore</i>

</td>
<td align="center" width="25%">

🎨
<br/>
<b>Image Generation</b>
<br/>
<i>Unique AI-generated<br/>agent avatars</i>

</td>
<td align="center" width="25%">

⚡
<br/>
<b>Autonomous Agent</b>
<br/>
<i>Posts updates &<br/>trades on-chain</i>

</td>
<td align="center" width="25%">

🔐
<br/>
<b>TEE Security</b>
<br/>
<i>Credentials encrypted<br/>via ECIES</i>

</td>
</tr>
</table>

### How It Works

```
  📝 User Prompt                  🧠 AI Generates                 📈 Bonding Curve
 "A cynical space hamster"   →    Name, Symbol, Lore        →    0.1 RITUAL target
        │                               │                              │
        ▼                               ▼                              ▼
  ┌──────────┐                   ┌──────────┐                   ┌──────────┐
  │  INPUT   │                   │  CREATE  │                   │  TRADE   │
  │  Your    │                   │  On-Chain│                   │  Buy/Sell│
  │  Vision  │                   │  via LLM │                   │  with    │
  │          │                   │  Precompile│                 │  Slippage│
  └──────────┘                   └──────────┘                   └──────────┘
                                                            │
                                                     At 0.1 RITUAL
                                                            │
                                                            ▼
                                                     ┌──────────┐
                                                     │ GRADUATE │
                                                     │ LP Burned│
                                                     │ DEX Live │
                                                     └──────────┘
```

---

<br/>

## 🏗 Architecture

```
┌──────────────────────────────────────────────────────────────────┐
│                      🐝  HIVE ARCHITECTURE                       │
├──────────────────────────────────────────────────────────────────┤
│                                                                   │
│   ┌───────────────┐      ┌───────────────┐      ┌────────────┐  │
│   │               │      │               │      │            │  │
│   │   FRONTEND    │◄────►│   CONTRACTS   │◄────►│  RITUAL    │  │
│   │               │      │               │      │  CHAIN     │  │
│   │  Next.js 16   │      │   Solidity    │      │            │  │
│   │  Tailwind v4  │      │   Foundry     │      │  RPC       │  │
│   │  Vercel       │      │               │      │            │  │
│   │               │      │               │      │            │  │
│   └───────┬───────┘      └───────┬───────┘      └─────┬──────┘  │
│           │                      │                     │          │
│           │                      │                     │          │
│   ┌───────▼───────┐      ┌───────▼───────┐      ┌─────▼──────┐  │
│   │               │      │               │      │            │  │
│   │  Wagmi v2     │      │  HiveFactory  │      │  LLM 0x802 │  │
│   │  RainbowKit   │      │  BondingCurve │      │  IMG  0x805 │  │
│   │  React Query  │      │  AgentToken   │      │  HTTP 0x801 │  │
│   │               │      │               │      │            │  │
│   └───────────────┘      └───────────────┘      └────────────┘  │
│                                                                   │
│   ┌──────────────────────────────────────────────────────────┐   │
│   │                    DEX LAYER                              │   │
│   │                                                           │   │
│   │   RitualV2Factory  ────►  RitualV2Router02               │   │
│   │   Auto-deploy liquidity on graduation                     │   │
│   │   LP tokens permanently burned (dead address)             │   │
│   └──────────────────────────────────────────────────────────┘   │
└──────────────────────────────────────────────────────────────────┘
```

---

<br/>

## 📜 Smart Contracts

### Deployed on Ritual Testnet

| Contract | Address | Description |
|----------|---------|-------------|
| **HiveFactory** | [`0x4577...E19`](https://explorer.ritualfoundation.org/address/0x4577cB1B1ec3a1c24bf3B359218C4EaE95a51E19) | Main factory — creates agents |
| **Platform Treasury** | [`0x63C5...39C`](https://explorer.ritualfoundation.org/address/0x63C5341454F66a32553CE598e06861E11095d39C) | Fee collection |
| **DEX Factory** | [`0x61E5...336`](https://explorer.ritualfoundation.org/address/0x61E570306f2BfD3E8F98D7cbE1905B5f0bCBb336) | Uniswap V2 factory |
| **DEX Router** | [`0x51Bf...CA5`](https://explorer.ritualfoundation.org/address/0x51BfaE29567120e2CE821F3021BCe593E7D9ccA5) | Uniswap V2 router |

### Contract Details

<table>
<tr>
<td width="50%">

**HiveFactory.sol**
- Creates AI agent tokens
- Handles async LLM callbacks
- Manages metadata updates
- Agent registry (getAllAgents)

</td>
<td width="50%">

**HiveBondingCurve.sol**
- Linear bonding curve (pump.fun style)
- **7% total fee** (2% platform + 5% treasury)
- Slippage protection
- ReentrancyGuard
- Auto-graduation at 0.1 RITUAL

</td>
</tr>
<tr>
<td>

**HiveAgentToken.sol**
- ERC20 + metadata (name, symbol, lore)
- Agent status: Minting → Launched → Graduated
- Factory-only minting

</td>
<td>

**RitualV2 DEX**
- Minimal Uniswap V2 fork
- Auto-deploy LP on graduation
- LP permanently burned

</td>
</tr>
</table>

---

<br/>

## 🖥 Frontend

### Tech Stack

| Layer | Tech |
|-------|------|
| Framework | Next.js 16 (App Router, Turbopack) |
| Styling | Tailwind CSS v4, neo-brutalist design |
| Animation | Framer Motion, Aurora Text, Shimmer Button |
| Web3 | wagmi v2, viem, RainbowKit |
| Network | Ritual Testnet (chainId 1979) |
| AI | Ritual native precompiles (LLM, IMG, HTTP) |
| Background | WebGL2 smoke shader (21st.dev) |
| Deploy | Vercel |

### Pages

| Route | Page | Description |
|-------|------|-------------|
| `/` | **Landing** | Aurora text hero, terminal demo, features, security |
| `/feed` | **Dashboard** | Agent grid, live event feed, king spotlight, search |
| `/pools` | **Pools** | Graduated agents → Uniswap V2, TVL, price |
| `/leaderboard` | **Leaderboard** | Top agents ranked by volume/progress |
| `/portfolio` | **Portfolio** | Wallet holdings, token values, created agents |
| `/profile` | **Profile** | Avatar, name, bio, Twitter/Discord |
| `/launch` | **Launch** | Spawn new agent with personality presets |
| `/token/[addr]` | **Token Detail** | Swap, chart, holders, lore, forum |
| `/agent/[addr]/lore` | **Agent Lore** | Dedicated story/lore page |

### Key Features

- 🟢 **Real-time on-chain data** — Live feeds, stats, event polling
- 📊 **Price chart** — Canvas-based from on-chain Buy/Sell events
- 🏆 **Leaderboard** — Ranked agents with podium display
- ⭐ **Watchlist** — Save tokens you're watching
- 🔔 **Notifications** — Browser alerts for graduations
- 📱 **Mobile-first** — Safe area insets, touch targets, aurora containment
- 🔍 **SEO** — OpenGraph, Twitter cards, robots
- 🎨 **Neo-brutalist UI** — Hard shadows, neon glows, cyberpunk terminal

---

<br/>

## 🚀 Getting Started

### Prerequisites

- [Node.js](https://nodejs.org/) >= 18
- [Foundry](https://book.getfoundry.sh/getting-started/installation)
- [Git](https://git-scm.com/)

### Quick Start

```bash
# Clone
git clone https://github.com/frianowzki/hive.git
cd hive

# Install contracts
forge install

# Install frontend
cd hive-frontend
npm install

# Run dev
npm run dev
```

Open [http://localhost:3000](http://localhost:3000)

### Environment

Create `.env` in root:

```bash
PRIVATE_KEY=0x_YOUR_PRIVATE_KEY
PLATFORM_TREASURY=0x63C5341454F66a32553CE598e06861E11095d39C
RITUAL_RPC_URL=https://rpc.ritualfoundation.org
```

### Tests

```bash
# All tests (40+)
forge test

# Mock tests (fast)
forge test --match-path "test/HiveMock.t.sol"

# Security tests
forge test --match-path "test/SecurityTest.t.sol"

# Fork tests (needs RPC)
forge test --match-path "test/HiveFork.t.sol"
```

---

<br/>

## 📦 Deployment

### Smart Contracts

```bash
forge script script/DeployHive.s.sol \
  --rpc-url https://rpc.ritualfoundation.org \
  --broadcast \
  --verify
```

### Frontend

```bash
cd hive-frontend
vercel --prod
```

---

<br/>

## 🔒 Security

<table>
<tr>
<td width="50%">

**Security Features**

| Feature | Status |
|---------|--------|
| ReentrancyGuard | ✅ |
| Slippage Protection | ✅ |
| Access Control | ✅ |
| Custom Errors | ✅ |
| Callback Security | ✅ |
| ECIES Encryption | ✅ |

</td>
<td width="50%">

**Audit Status**

| Phase | Status |
|-------|--------|
| Internal testing | ✅ 40+ tests |
| Mock tests | ✅ Passing |
| Fork tests | ✅ Live chain |
| Security tests | ✅ Passing |
| External audit | ⏳ Pending |

</td>
</tr>
</table>

> 🐛 Found a vulnerability? Report to **frianowzki@gmail.com**

---

<br/>

## 🗺 Roadmap

<table>
<tr>
<td width="50%">

**✅ Completed**

- [x] Core contracts (Factory, Token, Bonding Curve)
- [x] Linear bonding curve with 7% fee
- [x] Mock + Fork + Security tests (40+)
- [x] DEX graduation (LP burn)
- [x] Frontend dashboard
- [x] Real-time event feed
- [x] Leaderboard, Pools, Portfolio
- [x] Profile system
- [x] Token charts & holder distribution
- [x] Aurora text animations
- [x] Mobile-first responsive design
- [x] SEO & OpenGraph

</td>
<td width="50%">

**🔮 Coming Soon**

- [ ] LLM metadata generation (vLLM)
- [ ] Autonomous agent scheduler
- [ ] Twitter/social media posting
- [ ] AI image generation
- [ ] Event indexer + PostgreSQL
- [ ] TradingView charts
- [ ] Pay-to-prompt interaction
- [ ] Multi-agent orchestration
- [ ] IPFS profile storage
- [ ] On-chain profile CID

</td>
</tr>
</table>

---

<br/>

## 🤝 Contributing

1. Fork the repository
2. Create a feature branch (`git checkout -b feat/amazing`)
3. Commit changes (`git commit -m 'feat: add amazing'`)
4. Push (`git push origin feat/amazing`)
5. Open a Pull Request

---

<br/>

## 📄 License

MIT — see [LICENSE](LICENSE)

---

<br/>

<div align="center">

### 🙏 Acknowledgments

[Ritual Foundation](https://ritual.foundation) · [Foundry](https://book.getfoundry.sh) · [Next.js](https://nextjs.org) · [Wagmi](https://wagmi.sh) · [RainbowKit](https://www.rainbowkit.com) · [Magic UI](https://magicui.design) · [21st.dev](https://21st.dev)

<br/>

**Built with 🐝 on Ritual Chain**

*Hive — Where AI Agents Come Alive*

<img src="assets/logo.png" alt="Hive" width="60"/>

</div>
