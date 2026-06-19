# Hive — Contract Verification Guide

## Network Info
- **Chain:** Ritual Testnet (Chain ID: 1979)
- **RPC:** `https://rpc.ritualfoundation.org`
- **Explorer:** `https://explorer.ritualfoundation.org`
- **Currency:** RITUAL
- **Deployed:** 2026-06-19
- **Deployer:** `0x4b171E1217b71E37777B7F56d89cCB441C1De301`

## Compiler Settings
```
Solidity: 0.8.20
Optimizer: enabled (100 runs)
via_ir: true
EVM: default (shanghai)
```

## How to Verify

### Option A: Sourcify (when Chain 1979 is supported)
```bash
# Install foundry if not installed
curl -L https://foundry.paradigm.xyz | bash
foundryup

# Clone repo
git clone https://github.com/frianowzki/hive.git
cd hive

# Verify any contract (example: HiveMultiSig)
forge verify-contract \
  --chain-id 1979 \
  --verifier sourcify \
  --optimizer-runs 100 \
  --compiler-version 0.8.20 \
  --via-ir \
  --guess-constructor-args \
  --rpc-url https://rpc.ritualfoundation.org \
  0xd450caB1dCe65ac7bB089Cf8dA9F20f37544B1B6 \
  src/multisig/HiveMultiSig.sol:HiveMultiSig
```

### Option B: Manual Comparison
1. Open `verification/flattened/<ContractName>.sol`
2. Compile locally with the compiler settings above
3. Compare bytecode with on-chain bytecode

### Option C: Blockscout API (when available)
```bash
# Verify with Blockscout verifier
forge verify-contract \
  --chain-id 1979 \
  --verifier blockscout \
  --verifier-url https://explorer.ritualfoundation.org/api \
  --optimizer-runs 100 \
  --compiler-version 0.8.20 \
  --via-ir \
  --guess-constructor-args \
  --rpc-url https://rpc.ritualfoundation.org \
  <ADDRESS> \
  <SourcePath>:<ContractName>
```

## Contract Addresses

| # | Contract | Address |
|---|----------|---------|
| 1 | HiveID | `0x013c6D5a4fa5D50a92261C4189a8F56900408A01` |
| 2 | HiveMultiSig | `0xd450caB1dCe65ac7bB089Cf8dA9F20f37544B1B6` |
| 3 | HiveVerifier | `0xDD2A524E0Bda702ed5f9b1740Dd145Ce2de23Eb6` |
| 4 | HiveRelayer | `0xa2FCc065f174e9BE536A090DD344B9C8b8Dc513c` |
| 5 | HiveOracle | `0x5D72F3faf4ada60E1beCa310a2FA82b7B731aEbE` |
| 6 | HiveStaking | `0x93dd206181e3519c9f9CAC38aaE5d67b6009b408` |
| 7 | HiveTreasury | `0x90fbd495c888ae010e40FD299E143FabFcf08C18` |
| 8 | HiveReputation | `0x4cbe69CC563D548e2DA214c6c7C16fC32b69526A` |
| 9 | HiveReferral | `0x6fc9D8aBFa06867D5932DA9C473D46B0224041ED` |
| 10 | HiveClearing | `0x631969799907Dc4914988298A7795783e24c20CC` |
| 11 | HivePortfolio | `0x81E38ad29B869De5dd99bC5da1386b65Ef2Da066` |
| 12 | HiveAutoStrategy | `0x1b3A537D4572c1020Bc72c9f4951704966d3BEF9` |
| 13 | HiveToken | `0xDA8185F0742b46A8B6D413Dc10eFC25E9FBd5ec3` |
| 14 | HiveAgent | `0x842441aB565a3C6C8183ABB08a735B2DEA184327` |
| 15 | HiveBrain | `0x0ad0234d3EA8bd41ee571b1B317fA98d46E642B4` |
| 16 | HiveChat | `0x615F139dDFb2f2f486133B3a2D9F74Dd2bA785B6` |
| 17 | HiveGovernance | `0xeadd2aB5D8f1Ead852927Dd56c34b365603c2702` |
| 18 | HiveNotification | `0x9a04677f219384Fe35E29E968d43e8BDC6392C42` |
| 19 | HiveFactory | `0x0241cfB0a6620f57988C75Cd06dA2914b21463c6` |

## Constructor Arguments

**HiveID:** `uint256(0)` — registrationFee (free)

**HiveMultiSig:** `address[]([deployer])`, `uint256(1)` — threshold, `bytes32(0)` — hiveIdHash

**HiveTreasury:** `address(multiSig)` — `0xd450caB1dCe65ac7bB089Cf8dA9F20f37544B1B6`

**HiveToken:** `string("Hive Token")`, `string("HIVE")`, `uint8(18)`, `address(deployer)`, `bytes32(0)`, `string("")`

**HiveBrain:** `address(0)` — queen (not set yet)

**HiveGovernance:** `address(staking)` — `0x93dd206181e3519c9f9CAC38aaE5d67b6009b408`, `address(multiSig)` — `0xd450caB1dCe65ac7bB089Cf8dA9F20f37544B1B6`

**HiveNotification:** `address(hiveID)` — `0x013c6D5a4fa5D50a92261C4189a8F56900408A01`

All other contracts: no constructor arguments.

## Files in This Directory

```
verification/
├── README.md                          # This file
├── DEPLOYMENT_MANIFEST.json           # Machine-readable deployment data
├── flattened/                         # Flattened source code (single-file)
│   ├── HiveID.sol
│   ├── HiveMultiSig.sol
│   ├── HiveVerifier.sol
│   ├── HiveRelayer.sol
│   ├── HiveOracle.sol
│   ├── HiveStaking.sol
│   ├── HiveTreasury.sol
│   ├── HiveReputation.sol
│   ├── HiveReferral.sol
│   ├── HiveClearing.sol
│   ├── HivePortfolio.sol
│   ├── HiveAutoStrategy.sol
│   ├── HiveToken.sol
│   ├── HiveAgent.sol
│   ├── HiveBrain.sol
│   ├── HiveChat.sol
│   ├── HiveGovernance.sol
│   ├── HiveNotification.sol
│   └── HiveFactory.sol
└── abis/                              # Contract ABIs
    ├── HiveID.json
    ├── HiveMultiSig.json
    ├── ... (19 total)
    └── HiveFactory.json
```
