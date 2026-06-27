#!/usr/bin/env python3
"""
Sovereign Agent V3 — FIFA World Cup 2026 Predictor
FIXED: configureFundAndStart sends to HARNESS, not factory!
"""
import os, json, sys
from dotenv import load_dotenv
from ecies import encrypt as ecies_encrypt
from ecies.config import ECIES_CONFIG
from eth_abi.abi import encode
from web3 import Web3

ECIES_CONFIG.symmetric_nonce_length = 12

load_dotenv(os.path.expanduser('~/hive/.env'))

PRIVATE_KEY = os.environ.get('PRIVATE_KEY')
HF_TOKEN = os.environ.get('HF_TOKEN')
OPENROUTER_API_KEY = os.environ.get('OPENROUTER_API_KEY')

if not all([PRIVATE_KEY, HF_TOKEN, OPENROUTER_API_KEY]):
    print("ERROR: Missing .env variables")
    sys.exit(1)

w3 = Web3(Web3.HTTPProvider('https://rpc.ritualfoundation.org'))
account = w3.eth.account.from_key(PRIVATE_KEY)
SENDER = account.address
print(f"Wallet: {SENDER}")
print(f"Balance: {w3.from_wei(w3.eth.get_balance(SENDER), 'ether'):.6f} RITUAL")

# ═══ Addresses ═══
HARNESS_ADDRESS = Web3.to_checksum_address('0x0D84085b764E5D58fa9C65dFC0Bc4e1f814c26Db')
REGISTRY = Web3.to_checksum_address('0x9644e8562cE0Fe12b4deeC4163c064A8862Bf47F')

# Check harness exists
code = w3.eth.get_code(HARNESS_ADDRESS)
print(f"Harness code: {len(code)} bytes")
if len(code) == 0:
    print("ERROR: Harness not deployed!")
    sys.exit(1)

# ═══ ABIs ═══
REGISTRY_ABI = [
    {'name': 'getServicesByCapability', 'type': 'function', 'stateMutability': 'view',
     'inputs': [
         {'name': 'capability', 'type': 'uint8'},
         {'name': 'checkValidity', 'type': 'bool'}
     ],
     'outputs': [
         {'name': '', 'type': 'tuple[]', 'components': [
             {'name': 'node', 'type': 'tuple', 'components': [
                 {'name': 'paymentAddress', 'type': 'address'},
                 {'name': 'teeAddress', 'type': 'address'},
                 {'name': 'teeType', 'type': 'uint8'},
                 {'name': 'publicKey', 'type': 'bytes'},
                 {'name': 'endpoint', 'type': 'string'},
                 {'name': 'certPubKeyHash', 'type': 'bytes32'},
                 {'name': 'capability', 'type': 'uint8'}
             ]},
             {'name': 'isValid', 'type': 'bool'},
             {'name': 'workloadId', 'type': 'bytes32'}
         ]}
     ]}
]

# ═══ Helper: send tx ═══
def send_tx(to, data, value=0, gas_limit=5_000_000):
    tx_data = data
    if isinstance(tx_data, str):
        tx_data = bytes.fromhex(tx_data[2:]) if tx_data.startswith('0x') else bytes.fromhex(tx_data)
    
    tx = {
        'from': SENDER,
        'to': to,
        'data': tx_data,
        'value': value,
        'gas': gas_limit,
        'maxFeePerGas': w3.to_wei(2, 'gwei'),
        'maxPriorityFeePerGas': w3.to_wei(1, 'gwei'),
        'nonce': w3.eth.get_transaction_count(SENDER),
        'type': 2,
        'chainId': 1979,
    }
    signed = w3.eth.account.sign_transaction(tx, PRIVATE_KEY)
    tx_hash = w3.eth.send_raw_transaction(signed.raw_transaction)
    print(f"  TX sent: {tx_hash.hex()}")
    receipt = w3.eth.wait_for_transaction_receipt(tx_hash, timeout=120)
    print(f"  Status: {'SUCCESS' if receipt.status == 1 else 'FAILED'} | Gas: {receipt.gasUsed:,}")
    return receipt

# ═══ Step 1: Get Executor + Encrypt Secrets ═══
print("\n═══ STEP 1: Get Executor + Encrypt Secrets ═══")
registry = w3.eth.contract(address=REGISTRY, abi=REGISTRY_ABI)
services = registry.functions.getServicesByCapability(0, True).call()
node = services[0][0]
executor = Web3.to_checksum_address(node[1])
pub_key_bytes = bytes(node[3])
print(f"Executor: {executor}")
print(f"Public key: {pub_key_bytes[:20].hex()}...")

secrets_json = json.dumps({
    'LLM_PROVIDER': 'openrouter',
    'OPENROUTER_API_KEY': OPENROUTER_API_KEY,
    'HF_TOKEN': HF_TOKEN,
})
encrypted = ecies_encrypt(pub_key_bytes.hex(), secrets_json.encode())
print(f"Secrets encrypted: {len(encrypted)} bytes")

# ═══ Step 2: Build Params ═══
print("\n═══ STEP 2: Build SovereignAgentParams ═══")
HF_REPO_ID = "frianowzki/frio-ritual"
MODEL = "google/gemini-2.5-flash"

PROMPT = """You are a sovereign AI agent on Ritual Chain named Frio. Your task is to analyze FIFA World Cup 2026 data and provide actionable insights for predictors.

Instructions:
1. Check the current team conditions and opponents
2. Analyze recent performance on the FIFA World Cup 2026
3. Identify any unusual on squads (like injuries or suspension)
4. Provide a brief prediction summary with key takeaways
5. You must give me answer every 3 hours

Format your response as a concise report with:
- Selection (reason, prediction, trends)
- Notable FIFA World Cup 2026 activities 
- squads insights (opportunities, risks)
- One actionable recommendation

Be concise. Focus on data over noise."""

delivery_selector = Web3.keccak(text='onSovereignAgentResult(bytes32,bytes)')[:4]
print(f"Delivery selector: {delivery_selector.hex()}")

SOVEREIGN_REQUEST_TYPES = [
    'address', 'uint256', 'bytes', 'uint64', 'uint64', 'string',
    'address', 'bytes4', 'uint256', 'uint256', 'uint256', 'uint16',
    'string', 'bytes',
    '(string,string,string)', '(string,string,string)',
    '(string,string,string)[]', '(string,string,string)',
    'string', 'string[]', 'uint16', 'uint32', 'string',
]

params = [
    executor,                                        # 1. executor
    500,                                             # 2. ttl
    b'',                                             # 3. userPublicKey
    5,                                               # 4. pollIntervalBlocks
    6000,                                            # 5. maxPollBlock
    'SOVEREIGN_AGENT_TASK',                          # 6. taskIdMarker
    HARNESS_ADDRESS,                                 # 7. deliveryTarget (MUST be harness!)
    delivery_selector,                               # 8. bytes4
    3_000_000,                                       # 9. deliveryGasLimit
    1_000_000_000,                                   # 10. deliveryMaxFeePerGas
    100_000_000,                                     # 11. deliveryMaxPriorityFeePerGas
    5,                                               # 12. cliType (5=crush)
    PROMPT,                                          # 13. prompt
    encrypted,                                       # 14. encryptedSecrets
    ('hf', f'{HF_REPO_ID}/sessions/session-001.jsonl', 'HF_TOKEN'),  # 15. convoHistory
    ('hf', f'{HF_REPO_ID}/artifacts/', 'HF_TOKEN'),                  # 16. output
    [],                                              # 17. skills
    ('hf', f'{HF_REPO_ID}/prompts/default-system.md', ''),           # 18. systemPrompt
    MODEL,                                           # 19. model
    [],                                              # 20. tools
    50,                                              # 21. maxTurns
    8192,                                            # 22. maxTokens
    '',                                              # 23. rpcUrls
]

# ═══ Step 3: Schedule + Rolling + Lock ═══
print("\n═══ STEP 3: Build Schedule + Rolling + Lock ═══")
schedule = (
    500000,                    # schedulerGas
    2000,                      # frequency (blocks, ~11.7 min)
    500,                       # schedulerTtl
    w3.to_wei(2, 'gwei'),      # maxFeePerGas
    w3.to_wei(1, 'gwei'),      # maxPriorityFeePerGas
    0,                         # value
)

rolling = (
    5,     # windowNumCalls
    5000,  # rolloverThresholdBps (50%)
    1,     # rolloverRetryEveryCalls
)

lock_duration = 3_700_000  # 15 days in blocks

print(f"Frequency: {schedule[1]} blocks (~{schedule[1] * 0.35 / 60:.1f} min)")
print(f"NumCalls: {rolling[0]}")
print(f"Lock duration: {lock_duration:,} blocks (~{lock_duration * 0.35 / 86400:.1f} days)")

# ═══ Step 4: configureFundAndStart TO HARNESS ═══
print("\n═══ STEP 4: configureFundAndStart (TO HARNESS) ═══")
selector = bytes.fromhex('b1906702')
schedule_tuple = '(uint32,uint32,uint32,uint256,uint256,uint256)'
rolling_tuple = '(uint32,uint16,uint16)'

encoded_args = encode(
    [f"({','.join(SOVEREIGN_REQUEST_TYPES)})", schedule_tuple, rolling_tuple, 'uint256'],
    [params, schedule, rolling, lock_duration]
)
calldata = selector + encoded_args

# Budget: 0.1 RITUAL total
# Gas cost: ~0.016 RITUAL (at 1 gwei)
# Fund: ~0.084 RITUAL
fund_amount = w3.to_wei(0.1, 'ether')
print(f"Total value: {w3.from_wei(fund_amount, 'ether')} RITUAL")
print(f"Sending to HARNESS: {HARNESS_ADDRESS}")

receipt = send_tx(HARNESS_ADDRESS, calldata, value=fund_amount, gas_limit=5_000_000)
if receipt.status != 1:
    print("FAILED to configureFundAndStart!")
    # Try to get revert reason
    try:
        tx = w3.eth.get_transaction(receipt.transactionHash)
        w3.eth.call({
            'from': SENDER,
            'to': HARNESS_ADDRESS,
            'data': tx.input,
            'value': tx.value,
            'gas': tx.gas,
        }, block_identifier=receipt.blockNumber - 1)
    except Exception as e:
        print(f"Revert reason: {e}")
    sys.exit(1)

print(f"\n✅ Harness configured and funded!")
print(f"Address: {HARNESS_ADDRESS}")
print(f"Explorer: https://explorer.ritualfoundation.org/address/{HARNESS_ADDRESS}")

# Save address for Fase 2
with open(os.path.expanduser('~/hive/scripts/harness-v3-address.txt'), 'w') as f:
    f.write(HARNESS_ADDRESS)

print(f"\nSaved to ~/hive/scripts/harness-v3-address.txt")
print("Next: Wait for 1 heartbeat (~12 min), then check explorer for 'Sovereign + Monitored' status")
