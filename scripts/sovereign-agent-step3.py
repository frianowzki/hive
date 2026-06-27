#!/usr/bin/env python3
"""Step 2+3: Build calldata + configureFundAndStart"""

import os
import sys
import json

from ecies import encrypt as ecies_encrypt
from ecies.config import ECIES_CONFIG
from eth_abi.abi import encode
from web3 import Web3

ECIES_CONFIG.symmetric_nonce_length = 12

RPC_URL = "https://rpc.ritualfoundation.org"
PRIVATE_KEY = os.environ["PRIVATE_KEY"]
HF_TOKEN = os.environ["HF_TOKEN"]
OPENROUTER_API_KEY = os.environ["OPENROUTER_API_KEY"]

HARNESS = "0xEc87F4Cf6f1AD2fd47bfbB25b7FDAE093Fb6b097"
REGISTRY = "0x9644e8562cE0Fe12b4deeC4163c064A8862Bf47F"
HF_REPO_ID = "frianowzki/frio-ritual"
MODEL = "google/gemini-2.5-flash"
PROMPT = "You are a DeFi analytics agent on Ritual Chain. Analyze on-chain trends, identify yield opportunities, and provide actionable insights for builders. Return a brief summary."

w3 = Web3(Web3.HTTPProvider(RPC_URL))
account = w3.eth.account.from_key(PRIVATE_KEY)
SENDER = account.address
print(f"Sender: {SENDER}")

# ── Get executor + encrypt secrets ──
REGISTRY_ABI = [{
    "name": "getServicesByCapability",
    "type": "function",
    "stateMutability": "view",
    "inputs": [{"name": "capability", "type": "uint8"}, {"name": "checkValidity", "type": "bool"}],
    "outputs": [{"name": "", "type": "tuple[]", "components": [
        {"name": "node", "type": "tuple", "components": [
            {"name": "paymentAddress", "type": "address"},
            {"name": "teeAddress", "type": "address"},
            {"name": "teeType", "type": "uint8"},
            {"name": "publicKey", "type": "bytes"},
            {"name": "endpoint", "type": "string"},
            {"name": "certPubKeyHash", "type": "bytes32"},
            {"name": "capability", "type": "uint8"},
        ]},
        {"name": "isValid", "type": "bool"},
        {"name": "workloadId", "type": "bytes32"},
    ]}],
}]

registry = w3.eth.contract(address=REGISTRY, abi=REGISTRY_ABI)
services = registry.functions.getServicesByCapability(0, True).call()
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
print(f"Secrets encrypted: {len(encrypted)} bytes")

# Delivery selector
delivery_selector = Web3.keccak(text="onSovereignAgentResult(bytes32,bytes)")[:4]

# ── Build 23-field SovereignAgentParams ──
SOVEREIGN_REQUEST_TYPES = [
    "address", "uint256", "bytes", "uint64", "uint64", "string",
    "address", "bytes4", "uint256", "uint256", "uint256", "uint16",
    "string", "bytes",
    "(string,string,string)", "(string,string,string)",
    "(string,string,string)[]", "(string,string,string)",
    "string", "string[]", "uint16", "uint32", "string",
]

params = [
    executor,
    500,
    b"",
    5,
    6000,
    "SOVEREIGN_AGENT_TASK",
    Web3.to_checksum_address(HARNESS),
    delivery_selector,
    3_000_000,
    1_000_000_000,
    100_000_000,
    5,  # cliType=5 (crush)
    PROMPT,
    encrypted,
    ("hf", f"{HF_REPO_ID}/sessions/session-001.jsonl", "HF_TOKEN"),
    ("hf", f"{HF_REPO_ID}/artifacts/", "HF_TOKEN"),
    [],
    ("hf", f"{HF_REPO_ID}/prompts/default-system.md", ""),
    MODEL,
    [],
    50,
    8192,
    "",
]

# ── Schedule config ──
schedule = (
    500000,                # schedulerGas
    2000,                  # frequency
    500,                   # schedulerTtl
    w3.to_wei(20, "gwei"), # maxFeePerGas
    w3.to_wei(1, "gwei"),  # maxPriorityFeePerGas
    0,                     # value
)

# ── Rolling config ──
rolling = (
    5,     # windowNumCalls
    5000,  # rolloverThresholdBps
    1,     # rolloverRetryEveryCalls
)

lock_duration = 100000000

# ── Encode configureFundAndStart ──
# selector: 0xb1906702
selector = bytes.fromhex("b1906702")

schedule_tuple = "(uint32,uint32,uint32,uint256,uint256,uint256)"
rolling_tuple = "(uint32,uint16,uint16)"

encoded_args = encode(
    [f"({','.join(SOVEREIGN_REQUEST_TYPES)})", schedule_tuple, rolling_tuple, "uint256"],
    [params, schedule, rolling, lock_duration]
)

calldata = selector + encoded_args
print(f"Calldata: {len(calldata)} bytes")
print(f"Calldata hex: 0x{calldata.hex()[:100]}...")

# ── Send tx ──
scheduler_funding = w3.to_wei(0.1, "ether")
balance = w3.eth.get_balance(SENDER)
print(f"Balance: {w3.from_wei(balance, 'ether'):.4f} RITUAL")
print(f"Funding: {w3.from_wei(scheduler_funding, 'ether')} RITUAL")

tx = {
    "from": SENDER,
    "to": Web3.to_checksum_address(HARNESS),
    "value": scheduler_funding,
    "data": calldata,
    "nonce": w3.eth.get_transaction_count(SENDER),
    "maxFeePerGas": w3.to_wei(20, "gwei"),
    "maxPriorityFeePerGas": w3.to_wei(1, "gwei"),
    "chainId": 1979,
    "type": 2,
    "gas": 3000000,
}

signed = w3.eth.account.sign_transaction(tx, PRIVATE_KEY)
tx_hash = w3.eth.send_raw_transaction(signed.raw_transaction)
print(f"TX: {tx_hash.hex()}")
print(f"Explorer: https://explorer.ritualfoundation.org/tx/{tx_hash.hex()}")

receipt = w3.eth.wait_for_transaction_receipt(tx_hash, timeout=180)
print(f"Status: {'✅ OK' if receipt.status == 1 else '❌ FAIL'}")
print(f"Gas used: {receipt.gasUsed}")

if receipt.status == 1:
    print(f"\n{'='*60}")
    print(f"✅ SOVEREIGN AGENT CONFIGURED + FUNDED + STARTED!")
    print(f"Harness: {HARNESS}")
    print(f"Explorer: https://explorer.ritualfoundation.org/address/{HARNESS}")
    print(f"Schedule: every 2000 blocks (~11.7 min), 5 calls/window")
    print(f"Funding: 0.1 RITUAL")
    print(f"Model: {MODEL}")
    print(f"{'='*60}")
else:
    print("❌ FAILED!")
    # Try to decode revert
    sys.exit(1)
