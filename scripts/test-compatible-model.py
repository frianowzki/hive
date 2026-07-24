#!/usr/bin/env python3
"""
Test compatible ONNX model
"""

from web3 import Web3
from eth_abi.abi import encode, decode
import struct

# Connect
w3 = Web3(Web3.HTTPProvider('https://rpc.ritualfoundation.org'))
print(f"Connected: {w3.is_connected()}")

# ONNX Precompile address
ONNX_PRECOMPILE = '0x0000000000000000000000000000000000000800'

# Our compatible model
model_id = b"hf/frianowzki/hive-onnx-models/linear_v8.onnx@e3471c37caaf71514e1713f31b4aaa248392130d"

# Create tensor data
def float_to_int32(f):
    """Convert float to int32 bit pattern"""
    uint_val = struct.unpack('I', struct.pack('f', f))[0]
    if uint_val >= 0x80000000:
        return uint_val - 0x100000000
    return uint_val

# Simple 6-feature input
input_values = [1.0, 100.0, 0.3, 500.0, 10.0, 2.0]
values = [float_to_int32(v) for v in input_values]

# Encode tensor
tensor_data = encode(
    ['uint8', 'uint16[]', 'int32[]'],
    [5, [1, 6], values]
)

# Encode full ONNX call
onnx_input = encode(
    ['bytes', 'bytes', 'uint8', 'uint8', 'uint8', 'uint8', 'uint8'],
    [model_id, tensor_data, 2, 0, 2, 0, 1]
)

print(f"Model: {model_id.decode()}")
print(f"Input: {input_values}")

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

# Test
print("\nCalling ONNX precompile...")
try:
    result = w3.eth.call({
        'to': ONNX_PRECOMPILE,
        'data': onnx_input
    })
    print(f"Result length: {len(result)} bytes")
    if len(result) > 0:
        decoded = decode_output(result)
        print(f"Output: {decoded['values']}")
        print(f"\n✓ ONNX inference successful!")
except Exception as e:
    print(f"Error: {e}")
    print("First call triggers model download. Try again in a moment.")
