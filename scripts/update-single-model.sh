#!/bin/bash
# Update a single model ID
set -e

source .env

CONTRACT="0xfb1C8d204139D95A592Faf67276600b30a8E2632"
RPC="https://rpc.ritualfoundation.org"

MODEL_NAME=$1
MODEL_ID=$2

if [ -z "$MODEL_NAME" ] || [ -z "$MODEL_ID" ]; then
    echo "Usage: $0 <modelName> <modelId>"
    exit 1
fi

# Convert model ID to bytes (hex)
MODEL_HEX="0x$(echo -n "$MODEL_ID" | xxd -p)"

echo "Updating $MODEL_NAME..."
echo "  Model ID: $MODEL_ID"
echo "  Hex: $MODEL_HEX"

# Use cast with proper encoding
~/.foundry/bin/cast send --rpc-url $RPC --private-key $PRIVATE_KEY $CONTRACT \
    --calldata "updateModel(string,bytes)" "$MODEL_NAME" "$MODEL_HEX"

echo "✓ Updated $MODEL_NAME"
