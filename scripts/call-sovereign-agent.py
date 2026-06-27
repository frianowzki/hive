#!/usr/bin/env python3
"""Call SimpleSovereignAgent contract to trigger sovereign agent execution."""
import json
import os
from web3 import Web3

RPC = 'https://rpc.ritualfoundation.org'
CONTRACT = '0xB002F437A674C42aDDD6AdD5E8A592D225245890'
WALLET = '0x63c5341454f66a32553ce598e06861e11095d39c'
CHAIN_ID = 1979

# Reference agent encoding (block 37338740)
REF_BLOCK = 37338740
REF_AGENT = '0x66364BfC5F33Fe1C345926F769349177274d1B0a'

def main():
    w3 = Web3(Web3.HTTPProvider(RPC))
    contract = w3.to_checksum_address(CONTRACT)
    wallet = w3.to_checksum_address(WALLET)
    
    # Check balance
    bal = float(w3.from_wei(w3.eth.get_balance(wallet), 'ether'))
    if bal < 0.005:
        print(f"Low balance: {bal} RITUAL. Skipping.")
        return
    
    # Get reference encoding
    block = w3.eth.get_block(REF_BLOCK, full_transactions=True)
    ref_input = None
    for tx in block.transactions:
        if tx.get('to', '').lower() == REF_AGENT.lower():
            ref_input = tx['input']
            break
    
    if not ref_input:
        print("Reference tx not found")
        return
    
    # Build calldata
    selector = w3.keccak(text="callSovereignAgent(bytes)")[:4]
    calldata = selector + ref_input[4:]
    
    # Estimate gas
    try:
        gas = w3.eth.estimate_gas({
            'from': wallet,
            'to': contract,
            'data': calldata
        })
    except Exception as e:
        print(f"Gas estimate failed: {e}")
        return
    
    # Read private key
    env_path = os.path.expanduser('~/hive/.env')
    pk = None
    with open(env_path) as f:
        for line in f:
            if line.startswith('PRIVATE_KEY='):
                pk = line.strip().split('=')[1]
                break
    
    if not pk:
        print("No private key found")
        return
    
    # Send tx
    nonce = w3.eth.get_transaction_count(wallet)
    tx = {
        'from': wallet,
        'to': contract,
        'data': calldata,
        'gas': gas + 50000,
        'maxFeePerGas': w3.to_wei(20, 'gwei'),
        'maxPriorityFeePerGas': w3.to_wei(1, 'gwei'),
        'nonce': nonce,
        'chainId': CHAIN_ID,
    }
    
    signed = w3.eth.account.sign_transaction(tx, pk)
    tx_hash = w3.eth.send_raw_transaction(signed.raw_transaction)
    
    receipt = w3.eth.wait_for_transaction_receipt(tx_hash, timeout=60)
    
    if receipt['status'] == 1:
        count_sel = w3.keccak(text="executionCount()")[:4]
        count = int.from_bytes(w3.eth.call({'to': contract, 'data': count_sel}), 'big')
        remaining = float(w3.from_wei(w3.eth.get_balance(wallet), 'ether'))
        print(f"✅ Agent called. Executions: {count}. Balance: {remaining} RITUAL. Tx: {tx_hash.hex()}")
    else:
        print(f"❌ Tx failed: {tx_hash.hex()}")

if __name__ == '__main__':
    main()
