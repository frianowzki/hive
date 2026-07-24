#!/usr/bin/env python3
"""
Test ONNX precompile on Ritual Chain
"""

from web3 import Web3
import json

# Connect to Ritual Chain
w3 = Web3(Web3.HTTPProvider('https://rpc.ritualfoundation.org'))
print(f"Connected: {w3.is_connected()}")
print(f"Block: {w3.eth.block_number}")

# Load private key
import os
from dotenv import load_dotenv
load_dotenv(os.path.expanduser('~/hive/.env'))
private_key = os.getenv('PRIVATE_KEY')
account = w3.eth.account.from_key(private_key)
print(f"Account: {account.address}")

# Contract address
ONNX_CONSUMER = '0xfb1C8d204139D95A592Faf67276600b30a8E2632'

# Simple ABI for testing
abi = [
    {
        "inputs": [
            {"name": "token", "type": "address"},
            {"name": "buySellRatio", "type": "uint256"},
            {"name": "holderCount", "type": "uint256"},
            {"name": "topHolderPct", "type": "uint256"},
            {"name": "ageBlocks", "type": "uint256"},
            {"name": "volumeRitual", "type": "uint256"},
            {"name": "liquidityDepth", "type": "uint256"}
        ],
        "name": "getRiskScore",
        "outputs": [{"name": "riskScore", "type": "uint256"}],
        "stateMutability": "nonpayable",
        "type": "function"
    },
    {
        "inputs": [],
        "name": "riskScoringModelId",
        "outputs": [{"name": "", "type": "bytes"}],
        "stateMutability": "view",
        "type": "function"
    }
]

contract = w3.eth.contract(address=ONNX_CONSUMER, abi=abi)

# Check model ID
model_id = contract.functions.riskScoringModelId().call()
print(f"Model ID: {model_id.decode()}")

# Try to call getRiskScore with small values
print("\nTesting getRiskScore...")
try:
    # Build transaction
    tx = contract.functions.getRiskScore(
        '0x0000000000000000000000000000000000000001',  # token
        1000000000000000000,  # buySellRatio (1.0)
        100,                   # holderCount
        30,                    # topHolderPct (30%)
        500,                   # ageBlocks
        1000000000000000000,   # volumeRitual (1.0)
        2000000000000000000    # liquidityDepth (2.0)
    ).build_transaction({
        'from': account.address,
        'nonce': w3.eth.get_transaction_count(account.address),
        'gas': 500000,
        'gasPrice': w3.eth.gas_price
    })
    
    # Sign and send
    signed_tx = w3.eth.account.sign_transaction(tx, private_key)
    tx_hash = w3.eth.send_raw_transaction(signed_tx.raw_transaction)
    print(f"TX Hash: {tx_hash.hex()}")
    
    # Wait for receipt
    receipt = w3.eth.wait_for_transaction_receipt(tx_hash)
    print(f"Status: {'Success' if receipt['status'] == 1 else 'Failed'}")
    print(f"Gas Used: {receipt['gasUsed']}")
    
except Exception as e:
    print(f"Error: {e}")
