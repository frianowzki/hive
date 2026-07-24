#!/usr/bin/env python3
"""
Test ONNX precompile directly on Ritual Chain
"""

from web3 import Web3
from eth_abi.abi import encode, decode
import struct
import os
from dotenv import load_dotenv

# Load env
load_dotenv(os.path.expanduser('~/hive/.env'))

# Connect
w3 = Web3(Web3.HTTPProvider('https://rpc.ritualfoundation.org'))
print(f"Connected: {w3.is_connected()}")

# ONNX Precompile address
ONNX_PRECOMPILE = '0x0000000000000000000000000000000000000800'

# Model ID
model_id = b"hf/frianowzki/hive-onnx-models/risk_scoring.onnx@6171ecf05ed5ffcec9056bc24ba7519b63c80829"

# Create simple tensor data
# dtype=5 (FLOAT32), shape=[1,6], values=[1.0, 100, 0.3, 500, 10, 2.0]
def float_to_uint32(f):
    return struct.unpack('I', struct.pack('f', f))[0]

values = [
    float_to_uint32(1.0),      # buySellRatio
    float_to_uint32(100.0),    # holderCount
    float_to_uint32(0.3),      # topHolderPct
    float_to_uint32(500.0),    # ageBlocks
    float_to_uint32(10.0),     # volumeRitual
    float_to_uint32(2.0),      # liquidityDepth
]

# Encode tensor: (uint8 dtype, uint16[] shape, int32[] values)
tensor_data = encode(
    ['uint8', 'uint16[]', 'int32[]'],
    [5, [1, 6], values]
)

# Encode full ONNX call
# (bytes mlModelId, bytes tensorData, uint8 inputArithmetic, uint8 inputFixedPointScale, 
#  uint8 outputArithmetic, uint8 outputFixedPointScale, uint8 rounding)
onnx_input = encode(
    ['bytes', 'bytes', 'uint8', 'uint8', 'uint8', 'uint8', 'uint8'],
    [model_id, tensor_data, 2, 0, 2, 0, 1]
)

print(f"Model ID: {model_id.decode()}")
print(f"Tensor data length: {len(tensor_data)} bytes")
print(f"ONNX input length: {len(onnx_input)} bytes")

def decode_output(data):
    """Decode ONNX output"""
    # Decode outer envelope
    tensor_data, output_arith, output_scale, rounding = decode(
        ['bytes', 'uint8', 'uint8', 'uint8'],
        data
    )
    # Decode inner tensor
    dtype, shape, values = decode(
        ['uint8', 'uint16[]', 'int32[]'],
        tensor_data
    )
    return {
        'dtype': dtype,
        'shape': shape,
        'values': [struct.unpack('f', struct.pack('I', v))[0] if dtype == 5 else v for v in values]
    }

# Make eth_call to ONNX precompile
print("\nCalling ONNX precompile...")
try:
    result = w3.eth.call({
        'to': ONNX_PRECOMPILE,
        'data': onnx_input
    })
    print(f"Result length: {len(result)} bytes")
    
    if len(result) > 0:
        decoded = decode_output(result)
        print(f"\nDecoded result:")
        print(f"  Dtype: {decoded['dtype']}")
        print(f"  Shape: {decoded['shape']}")
        print(f"  Risk Score: {decoded['values'][0]:.2f}")
except Exception as e:
    print(f"Error: {e}")
    print("\nNote: First call triggers model download (1-5 blocks).")
    print("The model might still be downloading. Try again in a moment.")
