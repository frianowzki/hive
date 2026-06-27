#!/usr/bin/env python3
"""Schedule recurring sovereign agent calls via Ritual Scheduler."""
import sys
from eth_abi.abi import encode
from web3 import Web3

RPC = "https://rpc.ritualfoundation.org"
SCHEDULER = "0x56e776BAE2DD60664b69Bd5F865F1180ffB7D58B"
CONSUMER = "0x0C6C6Ee6b985e6684eAb271aDBCe91dc0e9518f6"

# Read the sovereign agent calldata from helpers.py
calldata_hex = open("/tmp/sovereign-calldata.txt").read().strip()
if calldata_hex.startswith("CALLDATA="):
    calldata_hex = calldata_hex[len("CALLDATA="):]
calldata = bytes.fromhex(calldata_hex[2:] if calldata_hex.startswith("0x") else calldata_hex)

# Scheduler.schedule(
#   bytes callData,
#   uint256 gasLimit,
#   uint32 startBlock,
#   uint32 retrySlots,
#   uint32 frequency,
#   uint32 ttl,
#   uint256 maxFeePerGas,
#   uint256 minFeePerGas,
#   uint256 priorityFee,
#   address payer
# )

w3 = Web3(Web3.HTTPProvider(RPC))
current_block = w3.eth.block_number

# Build the calldata for the Scheduler
# The Scheduler will call CONSUMER.callSovereignAgent(bytes) every `frequency` blocks
schedule_calldata = calldata  # The calldata to execute on each wake

gas_limit = 900_000
start_block = current_block + 10  # Start 10 blocks from now
retry_slots = 3
frequency = 2000  # ~12 min
ttl = 500
max_fee = 1_000_000_000  # 1 gwei
min_fee = 1_000_000_000
priority_fee = 100_000_000
payer = "0x63C5341454F66a32553CE598e06861E11095d39C"

# Encode the schedule call
# schedule(bytes,uint256,uint32,uint32,uint32,uint32,uint256,uint256,uint256,address)
selector = Web3.keccak(text="schedule(bytes,uint256,uint32,uint32,uint32,uint32,uint256,uint256,uint256,address)")[:4]

encoded_params = encode(
    ["bytes", "uint256", "uint32", "uint32", "uint32", "uint32", "uint256", "uint256", "uint256", "address"],
    [schedule_calldata, gas_limit, start_block, retry_slots, frequency, ttl, max_fee, min_fee, priority_fee, payer]
)

full_calldata = "0x" + (selector + encoded_params).hex()

with open("/tmp/schedule-calldata.txt", "w") as f:
    f.write(full_calldata)

print(f"Current block: {current_block}")
print(f"Start block: {start_block}")
print(f"Frequency: {frequency} blocks (~{frequency * 0.35 / 60:.0f} min)")
print(f"Gas limit: {gas_limit}")
print(f"Schedule calldata written to /tmp/schedule-calldata.txt")
print(f"Calldata length: {len(full_calldata)//2 - 1} bytes")
