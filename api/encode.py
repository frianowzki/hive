"""
/api/encode — Vercel Python serverless function
Encodes calldata for configureFundAndStart on Ritual Sovereign Agent Harness.

POST body (JSON):
  harness, prompt, model, hfRepo, hfToken, secrets, fundAmount, frequency, windowCalls, lockDuration

Returns:
  { calldata, executor, encryptedSize, calldataSize }
"""

import json
import os
import sys

from http.server import BaseHTTPRequestHandler

# ── Lazy imports (Vercel cold start) ──
from ecies import encrypt as ecies_encrypt
from ecies.config import ECIES_CONFIG
from eth_abi.abi import encode
from web3 import Web3

ECIES_CONFIG.symmetric_nonce_length = 12  # CRITICAL for Ritual TEE

RPC_URL = "https://rpc.ritualfoundation.org"
REGISTRY = "0x9644e8562cE0Fe12b4deeC4163c064A8862Bf47F"

REGISTRY_ABI = [{
    "name": "getServicesByCapability",
    "type": "function",
    "stateMutability": "view",
    "inputs": [
        {"name": "capability", "type": "uint8"},
        {"name": "checkValidity", "type": "bool"},
    ],
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

# 23-field SovereignAgentParams types (matches Ritual harness ABI)
SOVEREIGN_REQUEST_TYPES = [
    "address", "uint256", "bytes", "uint64", "uint64", "string",
    "address", "bytes4", "uint256", "uint256", "uint256", "uint16",
    "string", "bytes",
    "(string,string,string)", "(string,string,string)",
    "(string,string,string)[]", "(string,string,string)",
    "string", "string[]", "uint16", "uint32", "string",
]

# configureFundAndStart selector
SELECTOR = bytes.fromhex("b1906702")


def encode_calldata(body: dict) -> dict:
    harness = body["harness"]
    prompt = body.get("prompt", "You are a sovereign AI agent on Ritual Chain.")
    model = body.get("model", "google/gemini-2.5-flash")
    hf_repo = body.get("hfRepo", "")
    hf_token = body.get("hfToken", "")
    secrets_json = body.get("secrets", "{}")
    fund_amount = float(body.get("fundAmount", 0.1))
    frequency = int(body.get("frequency", 2000))
    window_calls = int(body.get("windowCalls", 5))
    lock_duration = int(body.get("lockDuration", 100000))
    scheduler_gas = int(body.get("schedulerGas", 800000))
    rollover_bps = int(body.get("rolloverBps", 5000))
    rollover_retry = int(body.get("rolloverRetry", 1))
    max_fee_gwei = int(body.get("maxFeeGwei", 20))
    priority_fee_gwei = int(body.get("priorityFeeGwei", 1))

    w3 = Web3(Web3.HTTPProvider(RPC_URL))

    # ── 1. Fetch TEE executor from Registry ──
    registry = w3.eth.contract(address=REGISTRY, abi=REGISTRY_ABI)
    services = registry.functions.getServicesByCapability(0, True).call()
    if not services:
        raise RuntimeError("No valid TEE services found in registry")

    node = services[0][0]
    executor = Web3.to_checksum_address(node[1])
    pub_key_bytes = bytes(node[3])
    pub_key_hex = pub_key_bytes.hex()

    # ── 2. Encrypt secrets with ECIES ──
    encrypted = ecies_encrypt(pub_key_hex, secrets_json.encode())
    encrypted_size = len(encrypted)

    # ── 3. Build delivery selector ──
    delivery_selector = Web3.keccak(text="onSovereignAgentResult(bytes32,bytes)")[:4]

    # ── 4. Build 23-field SovereignAgentParams ──
    params = [
        executor,                         # 1. executor
        500,                              # 2. maxSteps
        b"",                              # 3. toolSchema
        5,                                # 4. maxToolCalls
        6000,                             # 5. maxContextTokens
        "SOVEREIGN_AGENT_TASK",           # 6. taskType
        Web3.to_checksum_address(harness),# 7. deliveryTarget
        delivery_selector,                # 8. deliverySelector
        3_000_000,                        # 9. agentGasLimit
        1_000_000_000,                    # 10. agentTimeoutNs
        100_000_000,                      # 11. agentMemoryBytes
        5,                                # 12. cliType (5=ZeroClaw)
        prompt,                           # 13. prompt
        encrypted,                        # 14. encryptedSecrets
        ("hf", f"{hf_repo}/sessions/session-001.jsonl", "HF_TOKEN"),  # 15. sessionStorage
        ("hf", f"{hf_repo}/artifacts/", "HF_TOKEN"),                  # 16. artifactStorage
        [],                                                               # 17. extraStorage
        ("hf", f"{hf_repo}/prompts/default-system.md", ""),           # 18. promptStorage
        model,                            # 19. model
        [],                               # 20. tools
        50,                               # 21. topP (permille)
        8192,                             # 22. maxOutputTokens
        "",                               # 23. systemPromptOverride
    ]

    # ── 5. Schedule config ──
    schedule = (
        scheduler_gas,                  # schedulerGas
        frequency,                      # frequency (blocks)
        500,                            # schedulerTtl (hard cap 500)
        w3.to_wei(max_fee_gwei, "gwei"),      # maxFeePerGas
        w3.to_wei(priority_fee_gwei, "gwei"), # maxPriorityFeePerGas
        0,                        # value
    )

    # ── 6. Rolling config ──
    rolling = (
        window_calls,     # windowNumCalls
        rollover_bps,     # rolloverThresholdBps
        rollover_retry,   # rolloverRetryEveryCalls
    )

    # ── 7. ABI-encode ──
    schedule_tuple = "(uint32,uint32,uint32,uint256,uint256,uint256)"
    rolling_tuple = "(uint32,uint16,uint16)"

    encoded_args = encode(
        [f"({','.join(SOVEREIGN_REQUEST_TYPES)})", schedule_tuple, rolling_tuple, "uint256"],
        [params, schedule, rolling, lock_duration]
    )

    calldata = SELECTOR + encoded_args
    calldata_hex = "0x" + calldata.hex()

    return {
        "calldata": calldata_hex,
        "executor": executor,
        "encryptedSize": encrypted_size,
        "calldataSize": len(calldata),
    }


class handler(BaseHTTPRequestHandler):
    def do_POST(self):
        try:
            content_length = int(self.headers.get("Content-Length", 0))
            body_bytes = self.rfile.read(content_length)
            body = json.loads(body_bytes)

            result = encode_calldata(body)

            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            self.send_header("Access-Control-Allow-Origin", "*")
            self.end_headers()
            self.wfile.write(json.dumps(result).encode())

        except Exception as e:
            self.send_response(400)
            self.send_header("Content-Type", "application/json")
            self.send_header("Access-Control-Allow-Origin", "*")
            self.end_headers()
            self.wfile.write(json.dumps({"error": str(e)}).encode())

    def do_OPTIONS(self):
        self.send_response(204)
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Access-Control-Allow-Methods", "POST, OPTIONS")
        self.send_header("Access-Control-Allow-Headers", "Content-Type")
        self.end_headers()
