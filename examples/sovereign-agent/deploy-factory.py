#!/usr/bin/env python3
"""Deploy sovereign agent via factory-backed harness mode."""
import json
import os
import sys

from ecies import encrypt as ecies_encrypt
from ecies.config import ECIES_CONFIG
from eth_abi.abi import encode
from web3 import Web3

ECIES_CONFIG.symmetric_nonce_length = 12

RPC = "https://rpc.ritualfoundation.org"
FACTORY = "0x9dC4C054e53bCc4Ce0A0Ff09E890A7a8e817f304"
HARNESS = "0x5BEC1b6481D1524Ce8C03C3bD00A8cd4972EAA56"
REGISTRY = "0x9644e8562cE0Fe12b4deeC4163c064A8862Bf47F"

GEMINI_API_KEY = os.environ["GEMINI_API_KEY"]
HF_TOKEN = os.environ["HF_TOKEN"]
HF_REPO_ID = os.environ["HF_REPO_ID"]
MODEL = os.environ.get("MODEL", "gemini-2.5-flash")

# TEE Service Registry ABI
TEE_ABI = [{
    "name": "getServicesByCapability",
    "type": "function",
    "stateMutability": "view",
    "inputs": [{"name": "capability", "type": "uint8"}, {"name": "checkValidity", "type": "bool"}],
    "outputs": [{
        "name": "", "type": "tuple[]",
        "components": [
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
        ],
    }],
}]

# Harness ABI - configureFundAndStart
HARNESS_ABI = [
    {
        "name": "configureFundAndStart",
        "type": "function",
        "inputs": [
            {"name": "params", "type": "tuple", "components": [
                {"name": "executor", "type": "address"},
                {"name": "ttl", "type": "uint256"},
                {"name": "userPublicKey", "type": "bytes"},
                {"name": "pollIntervalBlocks", "type": "uint64"},
                {"name": "maxPollBlock", "type": "uint64"},
                {"name": "taskIdMarker", "type": "string"},
                {"name": "deliveryTarget", "type": "address"},
                {"name": "deliverySelector", "type": "bytes4"},
                {"name": "deliveryGasLimit", "type": "uint256"},
                {"name": "deliveryMaxFeePerGas", "type": "uint256"},
                {"name": "deliveryMaxPriorityFeePerGas", "type": "uint256"},
                {"name": "agentType", "type": "uint16"},
                {"name": "prompt", "type": "string"},
                {"name": "encryptedSecrets", "type": "bytes"},
                {"name": "convoHistory", "type": "tuple", "components": [
                    {"name": "platform", "type": "string"},
                    {"name": "path", "type": "string"},
                    {"name": "keyRef", "type": "string"},
                ]},
                {"name": "output", "type": "tuple", "components": [
                    {"name": "platform", "type": "string"},
                    {"name": "path", "type": "string"},
                    {"name": "keyRef", "type": "string"},
                ]},
                {"name": "skills", "type": "tuple[]", "components": [
                    {"name": "platform", "type": "string"},
                    {"name": "path", "type": "string"},
                    {"name": "keyRef", "type": "string"},
                ]},
                {"name": "systemPrompt", "type": "tuple", "components": [
                    {"name": "platform", "type": "string"},
                    {"name": "path", "type": "string"},
                    {"name": "keyRef", "type": "string"},
                ]},
                {"name": "model", "type": "string"},
                {"name": "tools", "type": "string[]"},
                {"name": "maxTurns", "type": "uint16"},
                {"name": "maxTokens", "type": "uint32"},
                {"name": "rpcUrls", "type": "string"},
            ]},
            {"name": "schedule", "type": "tuple", "components": [
                {"name": "schedulerGas", "type": "uint32"},
                {"name": "frequency", "type": "uint32"},
                {"name": "schedulerTtl", "type": "uint32"},
                {"name": "maxFeePerGas", "type": "uint256"},
                {"name": "maxPriorityFeePerGas", "type": "uint256"},
                {"name": "value", "type": "uint256"},
            ]},
            {"name": "rolling", "type": "tuple", "components": [
                {"name": "windowNumCalls", "type": "uint32"},
                {"name": "rolloverThresholdBps", "type": "uint16"},
                {"name": "rolloverRetryEveryCalls", "type": "uint16"},
            ]},
            {"name": "lockDuration", "type": "uint256"},
        ],
    },
    {
        "name": "getHarnessInfo",
        "type": "function",
        "stateMutability": "view",
        "inputs": [],
        "outputs": [
            {"name": "owner_", "type": "address"},
            {"name": "factory_", "type": "address"},
            {"name": "dkmsAddress_", "type": "address"},
            {"name": "isRunning_", "type": "bool"},
        ],
    },
]


def main():
    w3 = Web3(Web3.HTTPProvider(RPC))
    
    # 1. Get executor
    print("Finding executor...")
    registry = w3.eth.contract(address=Web3.to_checksum_address(REGISTRY), abi=TEE_ABI)
    services = registry.functions.getServicesByCapability(0, True).call()
    if not services:
        print("ERROR: No executors found")
        sys.exit(1)
    
    node = services[0][0]
    executor = Web3.to_checksum_address(node[1])
    pub_key = bytes(node[3])
    print(f"Executor: {executor}")
    
    # 2. Encrypt secrets
    print("Encrypting secrets...")
    secrets = json.dumps({
        "LLM_PROVIDER": "gemini",
        "GEMINI_API_KEY": GEMINI_API_KEY,
        "HF_TOKEN": HF_TOKEN,
    })
    encrypted = ecies_encrypt(pub_key.hex(), secrets.encode())
    print(f"Encrypted: {len(encrypted)} bytes")
    
    # 3. Build delivery selector
    delivery_selector = Web3.keccak(text="onSovereignAgentResult(bytes32,bytes)")[:4]
    
    # 4. Build params
    harness = w3.eth.contract(address=Web3.to_checksum_address(HARNESS), abi=HARNESS_ABI)
    
    params = (
        executor,                          # executor
        500,                               # ttl
        b"",                               # userPublicKey
        5,                                 # pollIntervalBlocks
        6000,                              # maxPollBlock
        "SOVEREIGN_AGENT_TASK",            # taskIdMarker
        Web3.to_checksum_address(HARNESS), # deliveryTarget (harness itself)
        delivery_selector,                 # deliverySelector
        3_000_000,                         # deliveryGasLimit
        1_000_000_000,                     # deliveryMaxFeePerGas
        100_000_000,                       # deliveryMaxPriorityFeePerGas
        5,                                 # agentType (cliType=5, Crush)
        "You are Hive, a sovereign AI agent on Ritual Chain. You have access to HTTP tools. Fetch the current price of RITUAL token from CoinGecko and provide a brief market analysis.",  # prompt
        encrypted,                         # encryptedSecrets
        ("hf", f"{HF_REPO_ID}/sessions/session-001.jsonl", "HF_TOKEN"),  # convoHistory
        ("hf", f"{HF_REPO_ID}/artifacts/", "HF_TOKEN"),                   # output
        [],                                                                # skills
        ("hf", f"{HF_REPO_ID}/prompts/default-system.md", ""),            # systemPrompt
        MODEL,                           # model
        [],                               # tools
        50,                               # maxTurns
        8192,                             # maxTokens
        "",                               # rpcUrls
    )
    
    schedule = (
        800_000,      # schedulerGas
        2000,         # frequency (~11.7 min)
        500,          # schedulerTtl
        1_000_000_000, # maxFeePerGas
        100_000_000,   # maxPriorityFeePerGas
        0,             # value
    )
    
    rolling = (
        5,     # windowNumCalls
        5000,  # rolloverThresholdBps (50%)
        1,     # rolloverRetryEveryCalls
    )
    
    lock_duration = 50_000  # blocks
    
    # 5. Encode calldata
    print("Encoding calldata...")
    func = harness.functions.configureFundAndStart(params, schedule, rolling, lock_duration)
    tx_data = func.build_transaction({"from": "0x63C5341454F66a32553CE598e06861E11095d39C", "gas": 0, "nonce": 0})
    calldata = tx_data["data"]
    if isinstance(calldata, str):
        calldata = calldata[2:] if calldata.startswith("0x") else calldata
    else:
        calldata = calldata.hex()
    
    print(f"\nHARNESS={HARNESS}")
    print(f"CALLDATA_LEN={len(calldata)//2}")
    
    # 6. Write calldata to file for cast
    with open("/tmp/configure-and-start.bin", "w") as f:
        f.write("0x" + calldata)
    
    print("\nCalldata written to /tmp/configure-and-start.bin")
    print("Ready to send!")


if __name__ == "__main__":
    main()
