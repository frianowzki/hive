#!/usr/bin/env python3
"""HiveBondingCurveV6 On-Chain Test"""
import subprocess, json, sys

RPC = "https://rpc.ritualfoundation.org"
FACTORY = "0xDC2F743FeDc12FC234df3528747ed54BEa1a3D3f"
CURVE = "0x6D5cD5F47c578348716D8B32a2B12F731143F6CE"
TOKEN = "0xA9F13f90d46c4d2678EdA4B7A69812823d676d6D"

def cast_call(sig, *args):
    cmd = ["cast", "call", "--json", CURVE, sig, "--rpc-url", RPC] + [str(a) for a in args]
    r = subprocess.run(cmd, capture_output=True, text=True, timeout=30)
    if r.returncode != 0:
        return None
    try:
        data = json.loads(r.stdout)
        return data
    except:
        return r.stdout.strip()

def to_ether(wei):
    return f"{int(wei) / 1e18:.6f}"

print("=" * 50)
print("  HiveBondingCurveV6 On-Chain Test")
print("=" * 50)
print()

# 1. State
print("📋 1. Contract State...")
vr = int(cast_call("virtualRitualReserve()(uint256)"))
vt = int(cast_call("virtualTokenReserve()(uint256)"))
rr = int(cast_call("realRitualSold()(uint256)"))
rt = int(cast_call("realTokensSold()(uint256)"))
paused = cast_call("tradingPaused()(bool)")
price = int(cast_call("getCurrentPrice()(uint256)"))
token_addr = cast_call("token()(address)")

print(f"  Virtual Ritual Reserve:  {to_ether(vr)} RITUAL")
print(f"  Virtual Token Reserve:   {to_ether(vt)} HIVE")
print(f"  Real Ritual Sold:        {to_ether(rr)} RITUAL")
print(f"  Real Tokens Sold:        {to_ether(rt)} HIVE")
print(f"  Trading Paused:          {paused}")
print(f"  Token:                   {token_addr}")
print()

# 2. Price
print("📊 2. Current Price...")
print(f"  Price: {price} raw ({price / 1e18:.10f} RITUAL/HIVE)")
print()

# 3. Buy calc
print("🛒 3. Calculate Buy (0.001 RITUAL)...")
buy_in = 10**15
out = cast_call("calculateBuy(uint256)(uint256,uint256)", buy_in)
tokens_out, fee = int(out[0]), int(out[1])
print(f"  Ritual In:     0.001 RITUAL")
print(f"  Tokens Out:    {to_ether(tokens_out)} HIVE")
print(f"  Fee:           {to_ether(fee)} RITUAL")
print(f"  Fee Rate:      {fee * 10000 / buy_in:.1f} bps")
print()

# 4. Sell calc
print("💰 4. Calculate Sell (100 HIVE)...")
sell_in = 100 * 10**18
out = cast_call("calculateSell(uint256)(uint256,uint256)", sell_in)
ritual_out, sell_fee = int(out[0]), int(out[1])
print(f"  Tokens In:     100 HIVE")
print(f"  Ritual Out:    {to_ether(ritual_out)} RITUAL")
print(f"  Fee:           {to_ether(sell_fee)} RITUAL")
print()

# 5. Graduation
print("📈 5. Graduation Progress...")
progress = int(cast_call("getProgress()(uint256)"))
ready = cast_call("isReadyForGraduation()(bool)")
print(f"  Progress:      {progress} / 10000 ({progress/100:.2f}%)")
print(f"  Threshold:     0.1 RITUAL")
print(f"  Ready:         {ready}")
print()

# 6. Token balance
print("🏦 6. Curve Token Balance...")
cmd = ["cast", "call", "--json", TOKEN, "balanceOf(address)(uint256)", CURVE, "--rpc-url", RPC]
r = subprocess.run(cmd, capture_output=True, text=True, timeout=30)
balance = int(json.loads(r.stdout))
print(f"  Curve holds:   {to_ether(balance)} HIVE")
print()

print("=" * 50)
print("  ✅ All read-only tests passed!")
print("=" * 50)
print()
print("Contract Addresses:")
print(f"  Factory:   {FACTORY}")
print(f"  Curve:     {CURVE}")
print(f"  Token:     {TOKEN}")
