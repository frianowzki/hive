# Hive × Ritual Ecosystem — Technical Research Report
**Date:** 2026-06-19
**Status:** Track A & B Research Complete

---

## 1. Allora Network → HiveMarketMaker

### What
Decentralized AI inference network. Crowdsourced models supply price predictions, network synthesizes best inference.

### API Endpoint
```
Mainnet: https://api.allora.network/v2/allora/consumer/<chainId>?allora_topic_id=<topicId>
Testnet: https://allora-api.testnet.allora.network/emissions/v7/latest_network_inferences/<topicId>
```
- Requires API key (register at allora.network)
- Returns: network-inferred price predictions with confidence intervals

### Integration Path
**Option A — Off-chain (recommended for Phase 2):**
1. HiveMarketMaker backend queries Allora API for price feeds
2. Submit price to HiveOracle on-chain
3. Market maker uses HiveOracle price

**Option B — On-chain via Ritual HTTP precompile:**
1. HiveMarketMaker calls Ritual precompile `0x0801` (HTTP)
2. Precompile fetches Allora API inside TEE
3. Result attested and returned to contract
4. Constraint: one async precompile per tx

### Topic IDs (examples)
- Topic 1: BTC/USD price prediction
- Topic 42: ETH/USD price prediction
- Others: check Allora marketplace

### Cost
- API key free for consumers
- Gas on Allora chain for on-chain queries

### Effort: 3-5 days
### Impact: HIGH — market maker accuracy++

---

## 2. Ritual Precompiles → HiveBrain (LLM Inference)

### What
Ritual Chain enshrines 16 precompiles. Key ones for Hive:

| Precompile | Address | Use Case |
|-----------|---------|----------|
| ONNX | `0x0800` | Classical ML models |
| LLM | `0x0802` | LLM inference in TEE |
| HTTP | `0x0801` | External API calls |
| DKMS | `0x0803` | Key derivation |
| Scheduler | `0x0804` | Scheduled execution |
| FHE | `0x0807` | Computation on encrypted data |
| Ed25519 | `0x0009` | Signature verification |

### Execution Model
- **Replicated:** Standard EVM (deterministic, every validator re-executes)
- **Delegated:** TEE-based (LLM, HTTP — runs once, result attested)
- Both share state in same block (superposition)

### Integration for HiveBrain
```solidity
// Call LLM precompile for market analysis
bytes memory result = address(0x0802).call(
    abi.encode(prompt, modelParams)
);
// Result is TEE-attested, verifiable
```

### Constraint
One async precompile per transaction. Cannot combine HTTP + LLM in same tx. Need separate txs or Scheduler.

### Effort: 3-5 days
### Impact: HIGH — on-chain AI inference for market maker

---

## 3. FLock.io → HiveBrain + HiveAutoStrategy

### What
Decentralized federated learning. Multiple contributors train models without sharing raw data.

### Architecture
1. **Training Platform:** train.flock.io — stake on tasks, submit models
2. **Fed-Ledger API:** `https://fed-ledger-prod.flock.io/api/v1/tasks/submit-result`
3. **Validation:** Validators verify model quality
4. **HuggingFace:** Models uploaded to HF repos

### Integration Path
**For Hive:**
1. Create training task on FLock platform (e.g., "optimize market making spread")
2. Multiple data scientists stake and train models
3. Best model selected by validators
4. Deploy winning model via Ritual ONNX precompile (`0x0800`)
5. HiveAutoStrategy uses on-chain model

### API
```bash
# Submit trained model
curl --location 'https://fed-ledger-prod.flock.io/api/v1/tasks/submit-result' \
--header 'flock-api-key: <key>' \
--header 'Content-Type: application/json' \
--data '{
    "task_id": 29,
    "data": {
        "hg_repo_id": "org/model-name",
        "base_model": "qwen1.5",
        "gpu_type": "A100",
        "revision": "<commit-hash>"
    }
}'
```

### Requirements
- FLock API key (stake on task)
- HuggingFace account
- GPU for training (or use FLock's distributed nodes)

### Effort: 5-7 days
### Impact: HIGH — market maker evolves over time

---

## 4. Story Protocol → HiveBrain IP Registration

### What
On-chain IP registration and licensing. Register AI models as intellectual property.

### SDK
```bash
npm install @story-protocol/core-sdk
```

### Networks
- **Aeneid** (testnet) — Chain ID 1315
- **Homer** (mainnet) — Chain ID 1514

### Integration for Hive
1. Train model (via FLock or independently)
2. Register as IP Asset on Story Protocol
3. Attach license terms (e.g., "commercial use allowed, 5% royalty")
4. Other projects can license HiveBrain models → revenue stream

### Flow
```typescript
import { StoryClient } from '@story-protocol/core-sdk';

// Register IP
const ipAsset = await client.ipAsset.register({
  nftContract: '0x...', // ERC-721
  tokenId: '1',
  metadata: { name: 'HiveBrain Market Maker v1' }
});

// Attach license
await client.license.attachLicenseTerms({
  ipId: ipAsset.ipId,
  licenseTermsId: '1' // Commercial use, 5% royalty
});
```

### Key Features
- IP Asset Registry (ERC-721 → IP Account)
- Licensing Module (parent-child IP relationships)
- Royalty Module (automated revenue flow)
- Dispute Module (IP protection)
- WIP Module (wrap IP into ERC-20 for DeFi)

### Effort: 2-3 days
### Impact: MEDIUM — revenue stream + credibility

---

## 5. EigenLayer → HiveStaking

### What
Restaking protocol. Stake ETH to secure multiple services simultaneously (AVS).

### GitHub
- `Layr-Labs/eigenlayer-contracts` — core contracts
- `Layr-Labs/eigenlayer-middleware` — AVS middleware

### AVS (Actively Validated Services)
- Custom services secured by restaked ETH
- Operators run AVS nodes, earn fees
- Slashing conditions defined per AVS

### Integration for Hive
**Option A — Become an AVS:**
1. HiveStaking registers as EigenLayer AVS
2. Operators stake ETH to secure Hive services
3. HiveMarketMaker/HiveBrain execution verified by operators
4. Slashing for malicious behavior

**Option B — Use EigenLayer for staking:**
1. Users restake via EigenLayer → earn Hive fees + EigenLayer points
2. HiveStaking integrates EigenLayer delegation

### Note
EigenLayer docs are behind Cloudflare protection. Need browser access for detailed integration guide.

### Effort: 3-5 days
### Impact: MEDIUM — institutional-grade security narrative

---

## 6. Nillion nilDB → HiveID (Private KYC)

### Status: SKIPPED — Using Ritual native privacy instead (DKMS 0x0803, ECIES, FHE 0x0807). No external dependency needed.

### SDK Installed
```bash
pip install secretvaults  # Python 3.12+
```

### Testnet Endpoints
```
nilDB Nodes:
  - https://nildb-stg-n1.nillion.network
  - https://nildb-stg-n2.nillion.network
  - https://nildb-stg-n3.nillion.network

nilChain: http://rpc.testnet.nilchain-rpc-proxy.nilogy.xyz
nilAuth: https://nilauth.sandbox.app-cluster.sandbox.nilogy.xyz
```

### Blocker
Need to subscribe via Developer Portal (developer.nillion.com) — requires MetaMask wallet connection.

### Effort: 2-3 days (after subscription)
### Impact: HIGH — privacy killer feature

---

## Integration Priority Matrix

| # | Integration | Effort | Impact | Phase |
|---|-----------|--------|--------|-------|
| 1 | ~~Nillion nilDB~~ | — | SKIPPED | — | Using Ritual native privacy |
| 2 | Ritual LLM Precompile | 3-5d | HIGH | 2 |
| 3 | Allora Price Feeds | 3-5d | HIGH | 2 |
| 4 | FLock Training | 5-7d | HIGH | 3 |
| 5 | Story Protocol IP | 2-3d | MEDIUM | 3 |
| 6 | EigenLayer AVS | 3-5d | MEDIUM | 3 |

---

## Recommended Execution Order

1. ~~**Nillion**~~ SKIPPED — Ritual native privacy (DKMS, ECIES, FHE) is superior: no subscription, TEE hardware security, same-block latency
2. **Ritual LLM** (on-chain inference) → HiveBrain intelligence
3. **Allora** (price feeds) → HiveMarketMaker accuracy
4. **FLock** (federated training) → Market maker evolution
5. **Story Protocol** (IP registration) → Revenue stream
6. **EigenLayer** (AVS) → Security upgrade