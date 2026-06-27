#!/usr/bin/env python3
import os, json
from ecies import encrypt as ecies_encrypt
from ecies.config import ECIES_CONFIG
from eth_abi.abi import encode
from web3 import Web3

ECIES_CONFIG.symmetric_nonce_length = 12

w3 = Web3(Web3.HTTPProvider('https://rpc.ritualfoundation.org'))
PRIVATE_KEY = os.environ["PRIVATE_KEY"]
HF_TOKEN = os.environ["HF_TOKEN"]
OPENROUTER_API_KEY = os.environ["OPENROUTER_API_KEY"]

HARNESS = "0xEc87F4Cf6f1AD2fd47bfbB25b7FDAE093Fb6b097"
REGISTRY = "0x9644e8562cE0Fe12b4deeC4163c064A8862Bf47F"
HF_REPO_ID = "frianowzki/frio-ritual"
MODEL = "gemini-2.5-flash"
PROMPT = "You are Hive, a sovereign AI agent on Ritual Chain. Fetch the current alt tokens price from CoinGecko and provide a brief market analysis."

account = w3.eth.account.from_key(PRIVATE_KEY)
SENDER = account.address

# Get executor
REGISTRY_ABI = [{'name': 'getServicesByCapability', 'type': 'function', 'stateMutability': 'view', 'inputs': [{'name': 'capability', 'type': 'uint8'}, {'name': 'checkValidity', 'type': 'bool'}], 'outputs': [{'name': '', 'type': 'tuple[]', 'components': [{'name': 'node', 'type': 'tuple', 'components': [{'name': 'paymentAddress', 'type': 'address'}, {'name': 'teeAddress', 'type': 'address'}, {'name': 'teeType', 'type': 'uint8'}, {'name': 'publicKey', 'type': 'bytes'}, {'name': 'endpoint', 'type': 'string'}, {'name': 'certPubKeyHash', 'type': 'bytes32'}, {'name': 'capability', 'type': 'uint8'}]}, {'name': 'isValid', 'type': 'bool'}, {'name': 'workloadId', 'type': 'bytes32'}]}]}]
registry = w3.eth.contract(address=REGISTRY, abi=REGISTRY_ABI)
services = registry.functions.getServicesByCapability(0, True).call()
node = services[0][0]
executor = Web3.to_checksum_address(node[1])
pub_key_bytes = bytes(node[3])

# Encrypt secrets
secrets_json = json.dumps({'LLM_PROVIDER': 'openrouter', 'OPENROUTER_API_KEY': OPENROUTER_API_KEY, 'HF_TOKEN': HF_TOKEN})
encrypted = ecies_encrypt(pub_key_bytes.hex(), secrets_json.encode())

delivery_selector = Web3.keccak(text='onSovereignAgentResult(bytes32,bytes)')[:4]

SOVEREIGN_REQUEST_TYPES = ['address', 'uint256', 'bytes', 'uint64', 'uint64', 'string', 'address', 'bytes4', 'uint256', 'uint256', 'uint256', 'uint16', 'string', 'bytes', '(string,string,string)', '(string,string,string)', '(string,string,string)[]', '(string,string,string)', 'string', 'string[]', 'uint16', 'uint32', 'string']

params = [
    executor, 500, b'', 5, 6000, 'SOVEREIGN_AGENT_TASK',
    Web3.to_checksum_address(HARNESS), delivery_selector,
    3_000_000, 1_000_000_000, 100_000_000,
    5, PROMPT, encrypted,
    ('hf', f'{HF_REPO_ID}/sessions/session-001.jsonl', 'HF_TOKEN'),
    ('hf', f'{HF_REPO_ID}/artifacts/', 'HF_TOKEN'),
    [],
    ('hf', f'{HF_REPO_ID}/prompts/default-system.md', ''),
    MODEL, [], 50, 8192, '',
]

schedule = (500000, 2000, 500, w3.to_wei(20, 'gwei'), w3.to_wei(1, 'gwei'), 0)
rolling = (5, 5000, 1)
lock_duration = 100000000

selector = bytes.fromhex('b1906702')
schedule_tuple = '(uint32,uint32,uint32,uint256,uint256,uint256)'
rolling_tuple = '(uint32,uint16,uint16)'
encoded_args = encode([f"({','.join(SOVEREIGN_REQUEST_TYPES)})", schedule_tuple, rolling_tuple, 'uint256'], [params, schedule, rolling, lock_duration])
calldata = selector + encoded_args

print(f'0x{calldata.hex()}')
