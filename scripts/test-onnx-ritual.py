#!/usr/bin/env python3
"""
Test ONNX precompile with Ritual's test model
"""

from web3 import Web3
from eth_abi.abi import encode, decode
import struct

# Connect
w3 = Web3(Web3.HTTPProvider('https://rpc.ritualfoundation.org'))
print(f"Connected: {w3.is_connected()}")

# ONNX Precompile address
ONNX_PRECOMPILE = '0x0000000000000000000000000000000000000800'

# Ritual's test model (from docs)
model_id = b"hf/Ritual-Net/sample_linreg/linreg_10_features.onnx@fd0501654c4144a9900a670c5c9a074b6bd3d4ef"

# Create tensor data for 10-feature linear regression
# dtype=5 (FLOAT32), shape=[1,10], values=[0.5, -0.14, 0.65, 1.52, -0.23, -0.23, 1.58, 0.77, -0.47, 0.54]
def float_to_int32(f):
    """Convert float to int32 bit pattern"""
    uint_val = struct.unpack('I', struct.pack('f', f))[0]
    # Convert to signed int32
    if uint_val >= 0x80000000:
        return uint_val - 0x100000000
    return uint_val

input_values = [0.5, -0.14, 0.65, 1.52, -0.23, -0.23, 1.58, 0.77, -0.47, 0.54]
values = [float_to_int32(v) for v in input_values]

# Encode tensor
tensor_data = encode(
    ['uint8', 'uint16[]', 'int32[]'],
    [5, [1, 10], values]
)

# Encode full ONNX call
onnx_input = encode(
    ['bytes', 'bytes', 'uint8', 'uint8', 'uint8', 'uint8', 'uint8'],
    [model_id, tensor_data, 2, 0, 2, 0, 1]
)

print(f"Model: {model_id.decode()}")
print(f"Input values: {input_values}")

def decode_output(data):
    """Decode ONNX output"""
    tensor_data, output_arith, output_scale, rounding = decode(
        ['bytes', 'uint8', 'uint8', 'uint8'],
        data
    )
    dtype, shape, values = decode(
        ['uint8', 'uint16[]', 'int32[]'],
        tensor_data
    )
    # Convert int32 back to float
    float_values = []
    for v in values:
        if v < 0:
            uint_val = v + 0x100000000
        else:
            uint_val = v
        float_val = struct.unpack('f', struct.pack('I', uint_val))[0]
        float_values.append(float_val)
    return {
        'dtype': dtype,
        'shape': shape,
        'values': float_values
    }

# Test 1: Try Ritual's test model
print("\n--- Test 1: Ritual's test model ---")
try:
    result = w3.eth.call({
        'to': ONNX_PRECOMPILE,
        'data': onnx_input
    })
    print(f"Result length: {len(result)} bytes")
    if len(result) > 0:
        decoded = decode_output(result)
        print(f"Output: {decoded['values']}")
except Exception as e:
    print(f"Error: {e}")

# Test 2: Try our model with simpler input
print("\n--- Test 2: Our model ---")
our_model_id = b"hf/frianowzki/hive-onnx-models/risk_scoring.onnx@6171ecf05ed5ffcec9056bc24ba7519b63c80829"

# Simple 6-feature input
our_values = [float_to_int32(1.0), float_to_int32(100.0), float_to_int32(0.3), 
              float_to_int32(500.0), float_to_int32(10.0), float_to_int32(2.0)]
our_tensor = encode(['uint8', 'uint16[]', 'int32[]'], [5, [1, 6], our_values])
our_input = encode(['bytes', 'bytes', 'uint8', 'uint8', 'uint8', 'uint8', 'uint8'],
                   [our_model_id, our_tensor, 2, 0, 2, 0, 1])

try:
    result = w3.eth.call({
        'to': ONNX_PRECOMPILE,
        'data': our_input
    })
    print(f"Result length: {len(result)} bytes")
    if len(result) > 0:
        decoded = decode_output(result)
        print(f"Risk Score: {decoded['values'][0]:.2f}")
except Exception as e:
    print(f"Error: {e}")
    print("Model might still be downloading...")
