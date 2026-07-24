#!/bin/bash
# Update ONNX model IDs in deployed contract
set -e

source .env

CONTRACT="0xfb1C8d204139D95A592Faf67276600b30a8E2632"
RPC="https://rpc.ritualfoundation.org"

echo "Updating model IDs in HiveONNXConsumer..."
echo "  Contract: $CONTRACT"

# Model IDs
RISK="hf/frianowzki/hive-onnx-models/risk_scoring.onnx@6171ecf05ed5ffcec9056bc24ba7519b63c80829"
ANOMALY="hf/frianowzki/hive-onnx-models/anomaly_detection.onnx@4a41c6ea0d03fb66143c769ff9ea5e525f981b49"
SCAM="hf/frianowzki/hive-onnx-models/scam_classification.onnx@201dc216b4e9ac3c1afafe21d55841b68591819c"
VOLATILITY="hf/frianowzki/hive-onnx-models/volatility_prediction.onnx@7965dfc446a42f62b28176c9502e0e3fb9f0b022"

# Convert to hex
RISK_HEX="0x$(echo -n "$RISK" | xxd -p)"
ANOMALY_HEX="0x$(echo -n "$ANOMALY" | xxd -p)"
SCAM_HEX="0x$(echo -n "$SCAM" | xxd -p)"
VOLATILITY_HEX="0x$(echo -n "$VOLATILITY" | xxd -p)"

echo ""
echo "Updating risk_scoring..."
~/.foundry/bin/cast send --rpc-url $RPC --private-key $PRIVATE_KEY $CONTRACT \
    "updateModel(string,bytes)" "riskScoring" "$RISK_HEX" 2>&1

echo ""
echo "Updating anomaly_detection..."
~/.foundry/bin/cast send --rpc-url $RPC --private-key $PRIVATE_KEY $CONTRACT \
    "updateModel(string,bytes)" "anomalyDetection" "$ANOMALY_HEX" 2>&1

echo ""
echo "Updating scam_classification..."
~/.foundry/bin/cast send --rpc-url $RPC --private-key $PRIVATE_KEY $CONTRACT \
    "updateModel(string,bytes)" "scamClassification" "$SCAM_HEX" 2>&1

echo ""
echo "Updating volatility_prediction..."
~/.foundry/bin/cast send --rpc-url $RPC --private-key $PRIVATE_KEY $CONTRACT \
    "updateModel(string,bytes)" "volatilityPrediction" "$VOLATILITY_HEX" 2>&1

echo ""
echo "✓ All models updated!"
