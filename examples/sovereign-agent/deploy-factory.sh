#!/usr/bin/env bash
# Deploy Sovereign Agent via Factory-backed harness mode
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source /home/frio/hive/.env
export PATH="$HOME/.foundry/bin:$PATH"

FACTORY="0x9dC4C054e53bCc4Ce0A0Ff09E890A7a8e817f304"
HARNESS="0x5BEC1b6481D1524Ce8C03C3bD00A8cd4972EAA56"
RPC="https://rpc.ritualfoundation.org"
REGISTRY="0x9644e8562cE0Fe12b4deeC4163c064A8862Bf47F"
SCHEDULER="0x56e776BAE2DD60664b69Bd5F865F1180ffB7D58B"

# Env vars
export GEMINI_API_KEY="AQ.Ab8RN6IVPE31AuTNqdBLIF6S-jJaatyWJBpVZloxnGS-UgRwnw"
export HF_TOKEN="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"
export HF_REPO_ID="frianowzki/frio-ritual"
export MODEL="gemini-2.5-flash"
unset OPENAI_API_KEY 2>/dev/null || true
unset ANTHROPIC_API_KEY 2>/dev/null || true

SENDER="0x63C5341454F66a32553CE598e06861E11095d39C"
PROMPT="You are Hive, a sovereign AI agent on Ritual Chain. You have access to HTTP tools. Fetch the current price of RITUAL token and provide a brief market analysis."

echo "=== Step 1: Get executor ==="
EXECUTOR=$("${HOME}/.local/bin/uv" run --quiet --with eciespy --with eth-abi --with web3 python3 -c "
from helpers import get_executor
from web3 import Web3
w3 = Web3(Web3.HTTPProvider('$RPC'))
addr, pub = get_executor(w3, '$REGISTRY')
print(addr)
" 2>&1)
echo "Executor: $EXECUTOR"

echo ""
echo "=== Step 2: Build configureAndStart calldata ==="
"${HOME}/.local/bin/uv" run --quiet --with eciespy --with eth-abi --with web3 python3 "$SCRIPT_DIR/helpers.py" \
  --rpc "$RPC" \
  --registry "$REGISTRY" \
  --consumer "$HARNESS" \
  --secrets "{\"LLM_PROVIDER\":\"gemini\",\"GEMINI_API_KEY\":\"$GEMINI_API_KEY\",\"HF_TOKEN\":\"$HF_TOKEN\"}" \
  --cli-type 5 \
  --model "$MODEL" \
  --prompt "$PROMPT" \
  --hf-repo-id "$HF_REPO_ID" 2>&1 | tee /tmp/sovereign-build.txt

echo ""
echo "=== Build complete ==="
