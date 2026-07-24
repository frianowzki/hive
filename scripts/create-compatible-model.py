#!/usr/bin/env python3
"""
Create ONNX model with compatible IR version and opset
"""

import numpy as np
import onnx
from onnx import helper, TensorProto
from sklearn.linear_model import LinearRegression
import os

# Create simple linear regression model
np.random.seed(42)
X = np.random.rand(100, 6).astype(np.float32)
y = np.random.rand(100).astype(np.float32)

model = LinearRegression()
model.fit(X, y)

# Convert to ONNX with specific opset
from skl2onnx import convert_sklearn
from skl2onnx.common.data_types import FloatTensorType

initial_type = [('input', FloatTensorType([None, 6]))]
onnx_model = convert_sklearn(model, initial_types=initial_type, target_opset=17)

# Set IR version to 8
onnx_model.ir_version = 8

# Save
os.makedirs('onnx_models', exist_ok=True)
onnx.save(onnx_model, 'onnx_models/linear_v8.onnx')
print("Created: onnx_models/linear_v8.onnx")

# Check model
print(f"IR version: {onnx_model.ir_version}")
print(f"Opset: {[o.version for o in onnx_model.opset_import]}")
