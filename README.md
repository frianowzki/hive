     1|<p align="center">
     2|  <img src="logo_hive.png" width="200" alt="Hive Logo">
     3|</p>
     4|
     5|<h1 align="center">HIVE</h1>
     6|<p align="center">Compliant AI Launchpad on Ritual Chain</p>
     7|
     8|<p align="center">
     9|  <a href="https://explorer.ritualfoundation.org">Explorer</a> •
    10|  <a href="#architecture">Architecture</a> •
    11|  <a href="#contracts">Contracts</a> •
    12|  <a href="#quickstart">Quickstart</a>
    13|</p>
    14|
    15|---
    16|
    17|## What is Hive?
    18|
    19|Hive is a **compliant, AI-powered launchpad** built natively on [Ritual Chain](https://ritual.net) (Chain ID: 1979). It combines zero-knowledge identity verification, AI-driven price discovery, and decentralized governance into a single platform for launching and trading tokens.
    20|
    21|**Core thesis:** Compliance and decentralization are not opposites. Hive uses zk-proofs to verify identity (KYC for individuals, KYB for projects/institutions) without exposing personal data on-chain. Users self-custody through a dual-wallet architecture — their primary wallet (browser extension) controls a Hive wallet (passkey-based) — keeping full custody while meeting regulatory requirements.
    22|
    23|### Key Features
    24|
    25|- **ZK-Proofed Identity** — KYC/KYB verification via zero-knowledge proofs. Prove you're 18+, prove your country, prove your organization — without revealing the underlying data
    26|- **DKMS Privacy** — TEE-bound key derivation via Ritual DKMS precompile (0x0803). Private keys never leave the enclave. ECIES-encrypted KYC data stored on-chain, only TEE can decrypt
    27|- **Dual Wallet Auth** — Primary wallet (ECDSA, e.g. MetaMask) + Hive wallet (Ritual passkey P-256). User always retains custody
    28|- **AI-Driven Price Discovery** — Hive Clearing Auction (HCA) with Ritual LLM-powered pricing. Optimal token launch price determined by on-chain AI
    29|- **Allora Price Feeds** — AI-inferred price predictions from Allora Network via Ritual HTTP precompile. Crowdsourced models supply predictions with confidence intervals
    30|- **FLock Federated Training** — Self-improving AI via FLock.io federated learning. Training tasks, model submissions, validator voting, winner selection, ONNX deployment via Ritual precompile
    31|    32|- **AI Agent Gateway** — On-chain chatbot powered by Ritual LLM precompile. Market analysis, token insights, strategy advice — all computed on-chain
    33|- **Agent Brain (Async + PII)** — Sovereign AI brain with async LLM inference and PII mode. think() → plan() → act() pipeline with confidence threshold. PII mode ensures sensitive strategy data never hits the mempool
    34|- **On-Chain Governance** — DAO voting with staked-weighted power, delegation, proposal types, quorum enforcement, and time-locked execution
    35|- **4-Tier Staking** — Bronze → Silver → Gold → Diamond. Lock multiplier, auto-compound, fee discounts, priority access
    36|- **Fee Economy** — Treasury auto-distributes fees: 60% to stakers, 25% to referrers, 15% to reserve
    37|
    38|### Why Ritual Chain?
    39|
    40|Hive is designed as a **flagship showcase** for Ritual's five research frontiers:
    41|
    42|1. **Ritual LLM Precompile** — On-chain AI inference (HiveAgent, HiveBrain, HiveClearing)
    43|2. **Ritual HTTP Precompile** — Off-chain data feeds (HiveOracle, Allora Network)
    44|3. **Ritual DKMS Precompile** — TEE-bound key derivation for private KYC (HiveID)
    45|4. **Ritual ECIES Precompile** — Encrypted P2P messaging (HiveChat)
    46|5. **Ritual Passkey (P-256)** — Native passkey signatures for Hive wallets
    47|
    48|No other chain supports all five primitives natively.
    49|
    50|---
    51|
    52|## Architecture
    53|
    54|```
    55|┌─────────────────────────────────────────────────────────────────────┐
    56|│                          HIVE PROTOCOL                              │
    57|│                                                                     │
    58|│  ┌──────────┐  ┌──────────┐  ┌──────────┐  ┌──────────┐           │
    59|│  │ HiveID   │  │HiveMulti │  │HiveVeri- │  │HiveRelay-│           │
    60|│  │ (Identity│  │  Sig     │  │  fier    │  │   er     │           │
    61|│  │  Layer)  │  │ (M-of-N) │  │  (ZK)    │  │ (MetaTx) │           │
    62|│  └────┬─────┘  └────┬─────┘  └────┬─────┘  └────┬─────┘           │
    63|│       │              │              │              │                 │
    64|│  ┌────┴──────────────┴──────────────┴──────────────┴─────┐         │
    65|│  │                   HiveFactory                          │         │
    66|│  │              (Master Wiring Contract)                   │         │
    67|│  └────┬──────────────┬──────────────┬──────────────┬─────┘         │
    68|│       │              │              │              │                 │
    69|│  ┌────┴─────┐  ┌─────┴────┐  ┌─────┴────┐  ┌─────┴────┐           │
    70|│  │HiveClear-│  │HivePort- │  │HiveRepu- │  │HiveRefer-│           │
    71|│  │  ing     │  │  folio   │  │ tation   │  │   ral    │           │
    72|│  │ (HCA +   │  │(Holdings │  │(5-Tier   │  │(4-Tier   │           │
    73|│  │  AI)     │  │ + PnL)   │  │ Score)   │  │ Engine)  │           │
    74|│  └──────────┘  └──────────┘  └──────────┘  └──────────┘           │
    75|│                                                                     │
    76|│  ┌──────────┐  ┌──────────┐  ┌──────────┐  ┌──────────┐           │
    77|│  │HiveToken │  │HiveOracle│  │HiveAgent │  │HiveBrain │           │
    78|│  │(ERC20 +  │  │(Price    │  │(LLM      │  │(Sovereign│           │
    79|│  │ Vesting) │  │ Feed)    │  │ Gateway) │  │ Agent)   │           │
    80|│  └──────────┘  └──────────┘  └──────────┘  └──────────┘           │
    81|│                                                                     │
    82|│  ┌──────────┐  ┌──────────┐  ┌──────────┐  ┌──────────┐           │
    83|│  │HiveGovern│  │HiveStak- │  │HiveTreas-│  │HiveNotif-│           │
    84|│  │  ance    │  │   ing    │  │   ury    │  │ ication  │           │
    85|│  │ (DAO)    │  │(4-Tier)  │  │(Fee      │  │(On-Chain │           │
    86|│  │          │  │          │  │ Distrib) │  │ Events)  │           │
    87|│  └──────────┘  └──────────┘  └──────────┘  └──────────┘           │
    88|│                                                                     │
    89|│  ┌──────────┐  ┌──────────┐  ┌──────────┐  ┌──────────┐           │
    90|│  │HiveAuto- │  │HiveChat  │  │ Queen    │  │HiveLaunch│           │
    91|│  │Strategy  │  │(Encrypted│  │(Brain    │  │  Pad     │           │
    92|│  │(DCA/TP/  │  │  P2P)    │  │ Orchest) │  │(Token    │           │
    93|│  │ SL/Trail)│  │          │  │          │  │ Launch)  │           │
    94|│  └──────────┘  └──────────┘  └──────────┘  └──────────┘           │
    95|└─────────────────────────────────────────────────────────────────────┘
    96|                              │
    97|                    ┌─────────┴─────────┐
    98|                    │   Ritual Chain     │
    99|                    │  ┌──────────────┐  │
   100|                    │  │ LLM Precomp  │  │  ← On-chain AI inference
   101|                    │  │ HTTP Precomp │  │  ← Off-chain data + Allora
   102|                    │  │ DKMS Precomp │  │  ← TEE key derivation
   103|                    │  │ ECIES Precomp│  │  ← Encrypted messaging
   104|                    │  │ P-256 Passkey│  │  ← Native passkey auth
   105|                    │  └──────────────┘  │
   106|                    └────────────────────┘
   107|```
   108|
   109|### User Flow
   110|
   111|```
   112|User (MetaMask) ──→ HiveID ──→ Register (free) ──→ Get Hive Wallet (passkey)
   113|      │                                                │
   114|      │  Primary Wallet (ECDSA)                        │  Hive Wallet (P-256)
   115|      │  - Signs all transactions                      │  - Receives funds
   116|      │  - Controls Hive wallet                        │  - Internal operations
   117|      │                                                │
   118|      └──────────── Withdraw ──────────────────────────┘
   119|                    (to primary or other HiveID)
   120|```
   121|
   122|---
   123|
   124|## Contracts
   125|
   126|### 🔐 Identity & Security Layer
   127|
   128|| Contract | Address | Description |
   129||----------|---------|-------------|
   130|| **HiveID** | `0x013c...08A01` | On-chain identity registry with DKMS privacy. Permanent username, dual-wallet binding, KYC/KYB verification, TEE-bound key derivation, ECIES-encrypted KYC storage, PII redaction mode |
   131|| **HiveMultiSig** | `0xd450...4B1B6` | M-of-N multi-signature wallet with 24h timelock. Required for Project/VC accounts |
   132|| **HiveVerifier** | `0xDD2A...23Eb6` | ZK proof verifier for KYC/KYB. 5 proof types (age, country, accreditation, org, sanctions). Nullifier + nonce replay prevention |
   133|| **HiveRelayer** | `0xa2FC...513c` | Meta-transaction relayer. Primary wallet signs, relayer executes from hive wallet |
   134|
   135|### 💰 Financial Infrastructure
   136|
   137|| Contract | Address | Description |
   138||----------|---------|-------------|
   139|| **HiveClearing** | `0x6319...c20CC` | Hive Clearing Auction with AI-driven pricing. Token sale mechanism where price is continuously determined by demand via Ritual LLM |
   140|| **HivePortfolio** | `0x81E3...a066` | Holdings tracking, weighted average entry price, vesting schedules, PnL calculation |
   141|| **HiveReputation** | `0x4cbe...526A` | 5-tier reputation scoring (Bronze → Diamond). Fee discounts based on score |
   142|| **HiveReferral** | `0x6fc9...41ED` | 4-tier referral engine with fee sharing |
   143|| **HiveOracle** | `0x5D72...1aEbE` | Price feed via Ritual HTTP precompile + Allora Network. AI-inferred price predictions with confidence intervals, batch fetching, price history |
   144|| **HiveToken** | `0xDA81...5ec3` | ERC20 token with vesting schedules and transfer restrictions |
   145|| **HiveStaking** | `0x93dd...b408` | 4-tier staking with Treasury integration. setTreasury() for fee notifications. Lock multiplier, auto-compound, voting power |
   146|| **HiveTreasury** | `0x90fb...8C18` | Fee collector & distributor. Multi-sig controlled. Auto-distributes: 60% stakers, 25% referrers, 15% reserve |
   147|
   148|### 🤖 AI & Agent Layer
   149|
   150|| Contract | Address | Description |
   151||----------|---------|-------------|
   152|| **HiveAgent** | `0x8424...4327` | AI Agent Gateway via Ritual LLM precompile. On-chain chatbot for market analysis, token insights, strategy advice |
   153|| **HiveBrain** | `0x0ad0...42B4` | Sovereign agent brain with async LLM, PII mode, Oracle price feeds, and FLock model integration. 14 action types (incl. RunFlockInference, DeployFlockModel, GetOraclePrice). Cross-contract calls to HiveOracle and HiveFLock |
   154|| **Queen** | `0xDC96...Ae8E` | Central orchestrator with AI integration. runCycle() calls Brain.think(). getOraclePrice(). setDivision() wires 9 modules (honeypot, strategy, registry, launchPad, marketMaker, council, brain, oracle, flock) |
   155|| **HiveAutoStrategy** | `0x1b3A...BEF9` | Automated trading with Oracle integration. DCA, TP, SL, Trailing Stop. fetchPrice() calls HiveOracle.getBestPrice() |
   156|| **HiveMarketMaker** | `0x62C8...637D` | AI-driven market making via Ritual LLM |
   157|| **HiveFLock** | `0xb0f4...F5d2` | Federated learning with Brain integration. setBrain() wiring. deployModel() notifies Brain. Training tasks, model validation, ONNX deployment, FLock API inference |
   158|   159|
   160|### 🏛️ Governance
   161|
   162|| Contract | Address | Description |
   163||----------|---------|-------------|
   164|| **HiveGovernance** | `0xeadd...2702` | DAO governance. Voting power from staked RITUAL. Proposal types, delegation, quorum, time-locked execution via multi-sig |
   165|| **HiveNotification** | `0x9a04...C42` | On-chain event system. Subscriptions, price alerts, webhook integration |
   166|
   167|### 🔧 Infrastructure
   168|
   169|| Contract | Address | Description |
   170||----------|---------|-------------|
   171|| **HiveFactory** | `0x0241...63c6` | Master wiring contract. 25 module references. wireAll() connects AI layer (Brain↔Oracle↔FLock), security layer (Staking↔Treasury), Queen orchestration, and AutoStrategy pricing |
   172|| **HiveChat** | `0x615F...85B6` | Encrypted P2P messaging via Ritual ECIES precompile |
   173|| **HiveLaunchPad** | `0x8eb7...3d95b` | Token launch platform with HCA mechanics |
   174|| **HiveCouncil** | `0xD79F...3D94` | Council governance (multi-representative) |
   175|| **HivePoints** | `0xA2fE...01a7` | On-chain points/rewards system |
   176|| **HiveRegistry** | `0x89Cf...82eE` | Contract registry for module discovery |
   177|| **Drone** | `0x8607...704` | Autonomous execution agents |
   178|| **Strategy** | `0xc2d2...b202` | Base strategy contract (parent of HiveAutoStrategy) |
   179|
   180|### 📚 Libraries & Interfaces
   181|
   182|| Contract | Description |
   183||----------|-------------|
   184|| **HiveTypes** | Shared type definitions (AccountType, VerificationType, etc.) |
   185|| **RitualPrecompileConsumer** | Base contract for Ritual precompile integration (LLM, HTTP, ECIES, DKMS) |
   186|| **IHive** | Hive protocol interface |
   187|| **IRitual** | Ritual precompile interface |
   188|
   189|---
   190|
   191|## Project Structure
   192|
   193|```
   194|hive/
   195|├── src/                          # Smart contracts (35 files: 29 deployable contracts + 6 libraries/interfaces, ~10,700 LOC)
   196|│   ├── agent/
   197|│   │   ├── HiveAgent.sol         # AI Agent Gateway (LLM precompile)
   198|│   │   └── HiveBrain.sol         # Sovereign agent brain
   199|│   ├── auction/
   200|│   │   └── HiveClearing.sol      # Hive Clearing Auction + AI pricing
   201|│   ├── chat/
   202|│   │   └── HiveChat.sol          # Encrypted P2P messaging (ECIES)
   203|│   ├── council/
   204|│   │   └── HiveCouncil.sol       # Council governance
   205|│   ├── drone/
   206|│   │   └── Drone.sol             # Autonomous execution agents
   207|│   ├── factory/
   208|│   │   └── HiveFactory.sol       # Master wiring contract
   209|│   ├── governance/
   210|│   │   └── HiveGovernance.sol    # DAO governance
   211|│   ├── identity/
   212|│   │   └── HiveID.sol            # On-chain identity registry
   213|│   ├── interfaces/
   214|│   │   ├── IHive.sol             # Hive protocol interface
   215|│   │   └── IRitual.sol           # Ritual precompile interface
   216|│   ├── launch/
   217|│   │   └── HiveLaunchPad.sol     # Token launch platform
   218|│   ├── libraries/
   219|│   │   ├── HiveTypes.sol         # Shared type definitions
   220|│   │   └── RitualPrecompileConsumer.sol  # Ritual precompile base
   221|│   ├── maker/
   222|│   │   └── HiveMarketMaker.sol   # AI market maker
   223|│   ├── multisig/
   224|│   │   └── HiveMultiSig.sol      # M-of-N multi-sig wallet
   225|│   ├── notification/
   226|│   │   └── HiveNotification.sol  # On-chain event system
   227|│   ├── oracle/
   228|│   │   └── HiveOracle.sol        # Price feed (HTTP precompile)
   229|│   ├── points/
   230|│   │   └── HivePoints.sol        # Points/rewards system
   231|│   ├── portfolio/
   232|│   │   └── HivePortfolio.sol     # Holdings & PnL tracking
   233|│   ├── queen/
   234|│   │   └── Queen.sol             # Brain orchestrator
   235|│   ├── referral/
   236|│   │   └── HiveReferral.sol      # 4-tier referral engine
   237|│   ├── registry/
   238|│   │   └── HiveRegistry.sol      # Contract registry
   239|│   ├── relayer/
   240|│   │   └── HiveRelayer.sol       # Meta-transaction relayer
   241|│   ├── reputation/
   242|│   │   └── HiveReputation.sol    # 5-tier reputation scoring
   243|│   ├── staking/
   244|│   │   └── HiveStaking.sol       # 4-tier staking system
   245|│   ├── strategy/
   246|│   │   ├── HiveAutoStrategy.sol  # Automated trading strategies
   247|│   │   └── Strategy.sol          # Base strategy contract
   248|│   ├── token/
   249|│   │   └── HiveToken.sol         # ERC20 + vesting
   250|│   ├── treasury/
   251|│   │   ├── HiveTreasury.sol      # Fee collector & distributor
   252|│   └── verifier/
   253|│       └── HiveVerifier.sol      # ZK proof verifier
   254|│
   255|├── test/                         # Test suite (300 tests)
   256|│   ├── Hive.t.sol                # Core integration tests
   257|│   ├── HiveID.t.sol              # HiveID + DKMS privacy tests
   258|│   ├── HiveSuite.t.sol           # Suite 1: ID, MultiSig, Clearing, etc.
   259|│   ├── HiveSuite2.t.sol          # Suite 2: Verifier, Relayer, Oracle, etc.
   260|│   ├── AlloraBrain.t.sol         # Allora + HiveBrain async/PII tests
   261|│   ├── HiveFLock.t.sol           # FLock federated learning tests
   262|   263|│
   264|├── script/
   265|│   └── Deploy.s.sol              # Deployment script (19 contracts)
   266|│
   267|├── subgraph/                     # TheGraph subgraph
   268|│   ├── schema.graphql            # 15 entity types
   269|│   ├── subgraph.yaml             # 8 data sources
   270|│   └── src/                      # AssemblyScript mappings
   271|│       ├── clearing.ts
   272|│       ├── identity.ts
   273|│       ├── staking.ts
   274|│       ├── governance.ts
   275|│       ├── treasury.ts
   276|│       ├── notification.ts
   277|│       ├── relayer.ts
   278|│       └── brain.ts
   279|│
   280|├── verification/                 # Contract verification package
   281|│   ├── README.md                 # Manual verification guide
   282|│   ├── DEPLOYMENT_MANIFEST.json  # Addresses, constructor args, compiler settings
   283|│   ├── flattened/                # 19 flattened source files
   284|│   └── abis/                     # 19 JSON ABIs
   285|│
   286|├── audit/
   287|│   ├── AUDIT_REPORT.md             # Security audit report
   288|│   └── AUDIT_REPORT.pdf            # Audit report (PDF)
   289|│
   290|├── foundry.toml                  # Foundry configuration
   291|└── .env.example                  # Environment template
   292|```
   293|
   294|---
   295|
   296|## Network
   297|
   298|| Property | Value |
   299||----------|-------|
   300|| **Chain** | Ritual Testnet |
   301|| **Chain ID** | 1979 |
   302|| **RPC** | `https://rpc.ritualfoundation.org` |
   303|| **Explorer** | `https://explorer.ritualfoundation.org` |
   304|| **Currency** | RITUAL |
   305|| **Deployer** | `0x4b171E1217b71E37777B7F56d89cCB441C1De301` |
   306|
   307|
   308|### Interconnections
   309|
   310|All modules connected via `HiveFactory.wireAll()`:
   311|
   312|```
   313|                    ┌─────────────┐
   314|                    │ HiveFactory │
   315|                    │ (25 modules)│
   316|                    └──────┬──────┘
   317|                           │
   318|        ┌──────────────────┼──────────────────┐
   319|        │                  │                  │
   320|   wireAILayer()     wireSecurityLayer()   wireQueen()
   321|        │                  │                  │
   322|  ┌─────┴─────┐     ┌─────┴──────┐    ┌─────┴──────┐
   323|  │Brain↔Oracle│    │ Staking↔   │    │Queen↔Brain │
   324|  │Brain↔FLock │    │Staking↔    │    │Queen↔Oracle│
   325|  │FLock→Brain │    │Treasury    │    │Queen↔FLock │
   326|  └───────────┘     └────────────┘    └────────────┘
   327|```
   328|
   329|**AI Chain:** HiveBrain ↔ HiveOracle (prices) ↔ HiveFLock (models)
   330|**Security Chain:** HiveStaking ↔ HiveTreasury
   331|**Orchestration:** Queen → Brain (think) → Strategy (execute) → Registry (heartbeat)
   332|**User Flow:** HiveAutoStrategy → HiveOracle (fetchPrice) → HiveMarketMaker (swap)
   333|
   334|---
   335|
   336|## Quickstart
   337|
   338|### Prerequisites
   339|
   340|- [Foundry](https://book.getfoundry.sh/) (forge, cast, anvil)
   341|- Git
   342|
   343|### Build
   344|
   345|```bash
   346|git clone https://github.com/frianowzki/hive.git
   347|cd hive
   348|forge build
   349|```
   350|
   351|### Test
   352|
   353|```bash
   354|forge test -vv
   355|```
   356|
   357|All 300 tests should pass.
   358|
   359|### Deploy
   360|
   361|```bash
   362|# Copy and fill environment
   363|cp .env.example .env
   364|# Edit .env with your PRIVATE_KEY
   365|
   366|# Deploy to Ritual Testnet
   367|forge script script/Deploy.s.sol \
   368|  --rpc-url https://rpc.ritualfoundation.org \
   369|  --broadcast \
   370|  --verify
   371|```
   372|
   373|### Verify Contracts
   374|
   375|See [`verification/README.md`](verification/README.md) for verification instructions.
   376|
   377|---
   378|
   379|## Compiler Settings
   380|
   381|```
   382|Solidity:     0.8.20
   383|Optimizer:    enabled (100 runs)
   384|via_ir:       true
   385|EVM Version:  default (shanghai)
   386|```
   387|
   388|`via_ir` is enabled to resolve stack-too-deep errors in complex contracts (HiveRelayer, HiveClearing).
   389|
   390|---
   391|
   392|## Security
   393|
   394|**Audit:** [`audit/AUDIT_REPORT.md`](audit/AUDIT_REPORT.md) · [`PDF`](audit/AUDIT_REPORT.pdf)
   395|
   396|| Severity | Count | Status |
   397||----------|-------|--------|
   398|| Critical | 0 | ✅ |
   399|| High | 0 | ✅ |
   400|| Medium | 2 | ✅ Fixed (HiveClearing rounding, HiveRelayer nonce) |
   401|| Low | 5 | ✅ Fixed (event indexing, input validation) |
   402|| Info | 8 | ✅ Noted (gas optimizations, documentation) |
   403|
   404|**Audit scope:** Core 31 contracts (pre-interconnection). Covers access control, reentrancy, fund safety, zk-proof verification, DAO governance.
   405|
   406|**Not yet audited:**
   407|- Phase 1-3 integrations (Allora, FLock, wireAll wiring)
   408|- HiveBrain ↔ HiveOracle ↔ HiveFLock data flow
   409|   410|- Queen orchestration cycle (Brain → Strategy → Registry)
   411|
   412|**Production readiness:** Testnet only. Full re-audit required before mainnet.
   413|
   414|---
   415|
   416|## License
   417|
   418|MIT
   419|
   420|---
   421|
   422|<p align="center">
   423|  Built on <a href="https://ritual.net">Ritual Chain</a> • 29 contracts deployed • 300 tests • Powered by Ritual LLM, HTTP, DKMS, ECIES, and Passkey precompiles • Price feeds by <a href="https://allora.network">Allora Network</a> • Training by <a href="https://flock.io">FLock.io</a> 
   424|</p>