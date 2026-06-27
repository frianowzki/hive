#!/usr/bin/env python3
"""
Sovereign Agent Factory Deploy — 3-step flow:
1. predictHarness → deployHarness(salt)
2. Build calldata (ECIES encrypt + ABI encode 23-field params)
3. configureFundAndStart(params, schedule, rolling, lockDuration)
"""

import os
import sys
import json
import time

from ecies import encrypt as ecies_encrypt
from ecies.config import ECIES_CONFIG
from eth_abi.abi import decode, encode
from web3 import Web3

ECIES_CONFIG.symmetric_nonce_length = 12

# ── Config ──
RPC_URL = os.environ.get("RPC_URL", "https://rpc.ritualfoundation.org")
PRIVATE_KEY = os.environ["PRIVATE_KEY"]

SOVEREIGN_FACTORY = "0x9dC4C054e53bCc4Ce0A0Ff09E890A7a8e817f304"
REGISTRY = "0x9644e8562cE0Fe12b4deeC4163c064A8862Bf47F"
TRACKER = "0xC069FFCa0389f44eCA2C626e55491b0ab045AEF5"
RITUAL_WALLET = "0x532F0dF0896F353d8C3DD8cc134e8129DA2a3948"

HF_TOKEN = os.environ["HF_TOKEN"]
HF_REPO_ID = os.environ.get("HF_REPO_ID", "frianowzki/frio-ritual")
OPENROUTER_API_KEY = os.environ["OPENROUTER_API_KEY"]
MODEL = os.environ.get("MODEL", "google/gemini-2.5-flash")
PROMPT = os.environ.get("PROMPT", "You are a DeFi analytics agent on Ritual Chain. Analyze on-chain trends, identify yield opportunities, and provide actionable insights for builders. Return a brief summary of your findings.")

USER_SALT = os.environ.get("USER_SALT", "hive-sovereign-v3")
CLI_TYPE = int(os.environ.get("CLI_TYPE", "5"))  # 5=crush

# ── Derived ──
w3 = Web3(Web3.HTTPProvider(RPC_URL))
account = w3.eth.account.from_key(PRIVATE_KEY)
SENDER = account.address
print(f"Sender: {SENDER}")
print(f"Chain: {w3.eth.chain_id}")
print(f"Balance: {w3.from_wei(w3.eth.get_balance(SENDER), 'ether'):.4f} RITUAL")

# ── ABI fragments ──
FACTORY_ABI = [
    {
        "name": "predictHarness",
        "type": "function",
        "stateMutability": "view",
        "inputs": [
            {"name": "owner", "type": "address"},
            {"name": "userSalt", "type": "bytes32"},
        ],
        "outputs": [
            {"name": "harness", "type": "address"},
            {"name": "childSalt", "type": "bytes32"},
        ],
    },
    {
        "name": "deployHarness",
        "type": "function",
        "stateMutability": "nonpayable",
        "inputs": [{"name": "userSalt", "type": "bytes32"}],
        "outputs": [{"name": "harness", "type": "address"}],
    },
]

REGISTRY_ABI = [
    {
        "name": "getServicesByCapability",
        "type": "function",
        "stateMutability": "view",
        "inputs": [
            {"name": "capability", "type": "uint8"},
            {"name": "checkValidity", "type": "bool"},
        ],
        "outputs": [
            {
                "name": "",
                "type": "tuple[]",
                "components": [
                    {
                        "name": "node",
                        "type": "tuple",
                        "components": [
                            {"name": "paymentAddress", "type": "address"},
                            {"name": "teeAddress", "type": "address"},
                            {"name": "teeType", "type": "uint8"},
                            {"name": "publicKey", "type": "bytes"},
                            {"name": "endpoint", "type": "string"},
                            {"name": "certPubKeyHash", "type": "bytes32"},
                            {"name": "capability", "type": "uint8"},
                        ],
                    },
                    {"name": "isValid", "type": "bool"},
                    {"name": "workloadId", "type": "bytes32"},
                ],
            }
        ],
    }
]

TRACKER_ABI = [
    {
        "name": "hasPendingJobForSender",
        "type": "function",
        "stateMutability": "view",
        "inputs": [{"name": "sender", "type": "address"}],
        "outputs": [{"name": "", "type": "bool"}],
    }
]

SOVEREIGN_REQUEST_TYPES = [
    "address", "uint256", "bytes", "uint64", "uint64", "string",
    "address", "bytes4", "uint256", "uint256", "uint256", "uint16",
    "string", "bytes",
    "(string,string,string)", "(string,string,string)",
    "(string,string,string)[]", "(string,string,string)",
    "string", "string[]", "uint16", "uint32", "string",
]


def send_tx(tx_data, to, value=0, gas_limit=3000000):
    """Build, sign, send tx. Return receipt."""
    # Ensure tx_data is bytes
    if isinstance(tx_data, str):
        tx_data = bytes.fromhex(tx_data[2:]) if tx_data.startswith("0x") else bytes.fromhex(tx_data)
    tx = {
        "from": SENDER,
        "to": to,
        "value": value,
        "data": tx_data,
        "nonce": w3.eth.get_transaction_count(SENDER),
        "maxFeePerGas": w3.to_wei(20, "gwei"),
        "maxPriorityFeePerGas": w3.to_wei(1, "gwei"),
        "chainId": 1979,
        "type": 2,
    }
    tx["gas"] = gas_limit
    signed = w3.eth.account.sign_transaction(tx, PRIVATE_KEY)
    tx_hash = w3.eth.send_raw_transaction(signed.raw_transaction)
    print(f"  tx: {tx_hash.hex()}")
    receipt = w3.eth.wait_for_transaction_receipt(tx_hash, timeout=120)
    print(f"  status: {'✅ OK' if receipt.status == 1 else '❌ FAIL'} (gas {receipt.gasUsed})")
    return receipt


# ── 0. Check pending job ──
tracker = w3.eth.contract(address=TRACKER, abi=TRACKER_ABI)
pending = tracker.functions.hasPendingJobForSender(SENDER).call()
if pending:
    print("ERROR: Has pending async job. Wait or use different key.")
    sys.exit(1)
print("✅ No pending jobs")


# ── 1. Predict + Deploy Harness ──
factory = w3.eth.contract(address=SOVEREIGN_FACTORY, abi=FACTORY_ABI)
user_salt_bytes = Web3.keccak(text=USER_SALT)
print(f"\nSalt: {USER_SALT} → {user_salt_bytes.hex()}")

predicted, child_salt = factory.functions.predictHarness(SENDER, user_salt_bytes).call()
print(f"Predicted harness: {predicted}")

# Check if already deployed
code = w3.eth.get_code(predicted)
if code and code != b"" and code != b"\x00":
    print(f"✅ Harness already deployed at {predicted}")
    harness_addr = predicted
else:
    print(f"\n── Step 1: deployHarness ──")
    deploy_data = factory.encode_abi("deployHarness", [user_salt_bytes])
    receipt = send_tx(deploy_data, SOVEREIGN_FACTORY, gas_limit=500000)
    if receipt.status != 1:
        print("❌ deployHarness failed!")
        sys.exit(1)
    harness_addr = predicted
    print(f"✅ Harness deployed: {harness_addr}")


# ── 2. Get executor + encrypt secrets ──
print(f"\n── Step 2: Build calldata ──")
registry = w3.eth.contract(address=REGISTRY, abi=REGISTRY_ABI)
services = registry.functions.getServicesByCapability(0, True).call()
if not services:
    print("ERROR: No valid executors found")
    sys.exit(1)

node = services[0][0]
executor = Web3.to_checksum_address(node[1])
pub_key_bytes = bytes(node[3])
print(f"Executor: {executor}")

# Encrypt secrets
secrets_json = json.dumps({
    "LLM_PROVIDER": "openrouter",
    "OPENROUTER_API_KEY": OPENROUTER_API_KEY,
    "HF_TOKEN": HF_TOKEN,
})
encrypted = ecies_encrypt(pub_key_bytes.hex(), secrets_json.encode())
print(f"Secrets encrypted ({len(encrypted)} bytes)")

# Delivery selector
delivery_selector = Web3.keccak(text="onSovereignAgentResult(bytes32,bytes)")[:4]

# Build 23-field params
params = [
    executor,                                                    # 1. executor
    500,                                                         # 2. ttl
    b"",                                                         # 3. userPublicKey
    5,                                                           # 4. pollIntervalBlocks
    6000,                                                        # 5. maxPollBlock
    "SOVEREIGN_AGENT_TASK",                                      # 6. taskIdMarker
    Web3.to_checksum_address(harness_addr),                      # 7. deliveryTarget
    delivery_selector,                                           # 8. deliverySelector
    3_000_000,                                                   # 9. deliveryGasLimit
    1_000_000_000,                                               # 10. deliveryMaxFeePerGas
    100_000_000,                                                 # 11. deliveryMaxPriorityFeePerGas
    CLI_TYPE,                                                    # 12. cliType
    PROMPT,                                                      # 13. prompt
    encrypted,                                                   # 14. encryptedSecrets
    ("hf", f"{HF_REPO_ID}/sessions/session-001.jsonl", "HF_TOKEN"),  # 15. convoHistory
    ("hf", f"{HF_REPO_ID}/artifacts/", "HF_TOKEN"),                  # 16. output
    [],                                                          # 17. skills
    ("hf", f"{HF_REPO_ID}/prompts/default-system.md", ""),           # 18. systemPrompt
    MODEL,                                                       # 19. model
    [],                                                          # 20. tools
    50,                                                          # 21. maxTurns
    8192,                                                        # 22. maxTokens
    "",                                                          # 23. rpcUrls
]

request_input = encode(SOVEREIGN_REQUEST_TYPES, params)
print(f"Request encoded ({len(request_input)} bytes)")


# ── 3. configureFundAndStart ──
print(f"\n── Step 3: configureFundAndStart ──")

# Schedule config
schedule = (
    500000,             # schedulerGas
    2000,               # frequency (blocks, ~11.7 min)
    500,                # schedulerTtl
    w3.to_wei(20, "gwei"),  # maxFeePerGas
    w3.to_wei(1, "gwei"),   # maxPriorityFeePerGas
    0,                  # value
)

# Rolling config
rolling = (
    5,      # windowNumCalls
    5000,   # rolloverThresholdBps (50%)
    1,      # rolloverRetryEveryCalls
)

lock_duration = 100000000  # blocks
scheduler_funding = w3.to_wei(0.1, "ether")  # 0.1 RITUAL

# ABI encode configureFundAndStart
# configureFundAndStart(SovereignAgentParams, SovereignScheduleConfig, SovereignRollingConfig, uint256)
harness_abi_configure = "b1906702"

# Build the calldata manually using the selector from docs
# selector: 0xb1906702
selector = bytes.fromhex("b1906702")

# We need to encode the struct types
schedule_tuple = "(uint32,uint32,uint32,uint256,uint256,uint256)"
rolling_tuple = "(uint32,uint16,uint16)"
full_types = f"({','.join(SOVEREIGN_REQUEST_TYPES)}),{schedule_tuple},{rolling_tuple},uint256"

encoded_args = encode(
    [f"({','.join(SOVEREIGN_REQUEST_TYPES)})", schedule_tuple, rolling_tuple, "uint256"],
    [params, schedule, rolling, lock_duration]
)

calldata = selector + encoded_args
print(f"Calldata: {len(calldata)} bytes")

print(f"\nSending configureFundAndStart with {w3.from_wei(scheduler_funding, 'ether')} RITUAL funding...")
receipt = send_tx(calldata, harness_addr, value=scheduler_funding, gas_limit=3000000)

if receipt.status == 1:
    print(f"\n{'='*60}")
    print(f"✅ SOVEREIGN AGENT DEPLOYED!")
    print(f"Harness: {harness_addr}")
    print(f"Explorer: https://explorer.ritualfoundation.org/address/{harness_addr}")
    print(f"Schedule: every 2000 blocks (~11.7 min), 5 calls per window")
    print(f"Funding: 0.1 RITUAL")
    print(f"{'='*60}")
else:
    print(f"\n❌ configureFundAndStart FAILED!")
    # Try to get revert reason
    sys.exit(1)
