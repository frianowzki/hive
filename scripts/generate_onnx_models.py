#!/usr/bin/env python3
"""
Hive ONNX Models Generator
Creates ML models for on-chain inference via Ritual's ONNX precompile (0x0800)

Models:
1. Risk Scoring - classify token risk (0-100)
2. Anomaly Detection - detect suspicious trading patterns
3. Scam Classification - classify tokens as scam/legit
4. Volatility Prediction - predict price volatility
"""

import numpy as np
import onnx
from onnx import helper, TensorProto
from sklearn.ensemble import RandomForestClassifier, RandomForestRegressor
from sklearn.preprocessing import StandardScaler
import os

# ============================================================
# Model 1: Risk Scoring (0-100)
# ============================================================
def create_risk_scoring_model():
    """
    Input features:
    - buy_sell_ratio: ratio of buys to sells (higher = more buys)
    - holder_count: number of unique holders
    - top_holder_pct: percentage held by top holder
    - age_blocks: token age in blocks
    - volume_ritual: total volume in RITUAL
    - liquidity_depth: order book depth
    
    Output: risk_score (0-100, higher = riskier)
    """
    print("Creating Risk Scoring Model...")
    
    # Generate synthetic training data
    np.random.seed(42)
    n_samples = 10000
    
    # Features: [buy_sell_ratio, holder_count, top_holder_pct, age_blocks, volume_ritual, liquidity_depth]
    X = np.random.rand(n_samples, 6).astype(np.float32)
    X[:, 0] = np.random.uniform(0.1, 5.0, n_samples)  # buy_sell_ratio
    X[:, 1] = np.random.randint(1, 1000, n_samples)     # holder_count
    X[:, 2] = np.random.uniform(0.01, 0.9, n_samples)   # top_holder_pct
    X[:, 3] = np.random.randint(1, 10000, n_samples)     # age_blocks
    X[:, 4] = np.random.uniform(0.001, 100, n_samples)   # volume_ritual
    X[:, 5] = np.random.uniform(0.001, 10, n_samples)    # liquidity_depth
    
    # Risk score logic (synthetic labels)
    # High risk: low holders, high top holder %, low age, low volume
    y = (
        (1.0 - X[:, 1] / 1000) * 30 +  # holder risk
        X[:, 2] * 25 +                   # concentration risk
        (1.0 - X[:, 3] / 10000) * 20 +  # age risk
        (1.0 - np.clip(X[:, 4], 0, 1)) * 15 +  # volume risk
        (1.0 - np.clip(X[:, 5], 0, 1)) * 10     # liquidity risk
    ).clip(0, 100).astype(np.float32)
    
    # Train model
    model = RandomForestRegressor(n_estimators=50, max_depth=10, random_state=42)
    model.fit(X, y)
    
    # Convert to ONNX
    from skl2onnx import convert_sklearn
    from skl2onnx.common.data_types import FloatTensorType
    
    initial_type = [('input', FloatTensorType([None, 6]))]
    onnx_model = convert_sklearn(model, initial_types=initial_type)
    
    # Save
    os.makedirs('onnx_models', exist_ok=True)
    onnx.save(onnx_model, 'onnx_models/risk_scoring.onnx')
    print(f"  Saved: onnx_models/risk_scoring.onnx")
    return onnx_model


# ============================================================
# Model 2: Anomaly Detection
# ============================================================
def create_anomaly_detection_model():
    """
    Input features:
    - volume_spike: volume compared to average
    - buy_pressure: % of buys in recent trades
    - unique_buyers: number of unique buyers
    - trade_size_avg: average trade size
    - time_between_trades: avg time between trades (seconds)
    
    Output: is_suspicious (0 or 1), confidence (0-1)
    """
    print("Creating Anomaly Detection Model...")
    
    np.random.seed(42)
    n_samples = 10000
    
    # Features: [volume_spike, buy_pressure, unique_buyers, trade_size_avg, time_between_trades]
    X = np.random.rand(n_samples, 5).astype(np.float32)
    X[:, 0] = np.random.uniform(0.1, 10.0, n_samples)    # volume_spike
    X[:, 1] = np.random.uniform(0.0, 1.0, n_samples)     # buy_pressure
    X[:, 2] = np.random.randint(1, 500, n_samples)        # unique_buyers
    X[:, 3] = np.random.uniform(0.001, 10, n_samples)     # trade_size_avg
    X[:, 4] = np.random.uniform(1, 3600, n_samples)       # time_between_trades
    
    # Anomaly labels (1 = suspicious)
    # Suspicious: high volume spike, high buy pressure, few unique buyers, large trades, fast trades
    anomaly_score = (
        np.clip(X[:, 0] - 3, 0, 7) / 7 * 30 +  # volume spike
        np.clip(X[:, 1] - 0.7, 0, 0.3) / 0.3 * 25 +  # buy pressure
        (1.0 - X[:, 2] / 500) * 20 +  # few buyers
        np.clip(X[:, 3] - 5, 0, 5) / 5 * 15 +  # large trades
        (1.0 - np.clip(X[:, 4], 0, 60) / 60) * 10  # fast trades
    )
    y = (anomaly_score > 50).astype(np.int32)
    
    # Train model
    model = RandomForestClassifier(n_estimators=50, max_depth=10, random_state=42)
    model.fit(X, y)
    
    # Convert to ONNX
    from skl2onnx import convert_sklearn
    from skl2onnx.common.data_types import FloatTensorType
    
    initial_type = [('input', FloatTensorType([None, 5]))]
    onnx_model = convert_sklearn(model, initial_types=initial_type)
    
    # Save
    onnx.save(onnx_model, 'onnx_models/anomaly_detection.onnx')
    print(f"  Saved: onnx_models/anomaly_detection.onnx")
    return onnx_model


# ============================================================
# Model 3: Scam Classification
# ============================================================
def create_scam_classification_model():
    """
    Input features:
    - has_renounce: 1 if ownership renounced
    - has_honeypot: 1 if honeypot detected
    - max_tx_pct: max transaction % of supply
    - liquidity_locked: 1 if liquidity locked
    - contract_verified: 1 if contract verified
    - fee_pct: trading fee percentage
    - has_blacklist: 1 if contract has blacklist function
    - has_pause: 1 if contract can pause trading
    
    Output: is_scam (0 or 1)
    """
    print("Creating Scam Classification Model...")
    
    np.random.seed(42)
    n_samples = 10000
    
    # Features: [has_renounce, has_honeypot, max_tx_pct, liquidity_locked, contract_verified, fee_pct, has_blacklist, has_pause]
    X = np.random.rand(n_samples, 8).astype(np.float32)
    X[:, 0] = np.random.choice([0, 1], n_samples, p=[0.3, 0.7])  # has_renounce
    X[:, 1] = np.random.choice([0, 1], n_samples, p=[0.8, 0.2])  # has_honeypot
    X[:, 2] = np.random.uniform(0.01, 0.5, n_samples)             # max_tx_pct
    X[:, 3] = np.random.choice([0, 1], n_samples, p=[0.4, 0.6])  # liquidity_locked
    X[:, 4] = np.random.choice([0, 1], n_samples, p=[0.3, 0.7])  # contract_verified
    X[:, 5] = np.random.uniform(0.01, 0.2, n_samples)             # fee_pct
    X[:, 6] = np.random.choice([0, 1], n_samples, p=[0.7, 0.3])  # has_blacklist
    X[:, 7] = np.random.choice([0, 1], n_samples, p=[0.8, 0.2])  # has_pause
    
    # Scam labels (1 = scam)
    scam_score = (
        (1 - X[:, 0]) * 15 +  # no renounce
        X[:, 1] * 30 +         # honeypot
        np.clip(X[:, 2] - 0.1, 0, 0.4) / 0.4 * 20 +  # high max tx
        (1 - X[:, 3]) * 10 +  # not locked
        (1 - X[:, 4]) * 10 +  # not verified
        np.clip(X[:, 5] - 0.05, 0, 0.15) / 0.15 * 10 +  # high fee
        X[:, 6] * 5 +         # blacklist
        X[:, 7] * 5           # pause
    )
    y = (scam_score > 40).astype(np.int32)
    
    # Train model
    model = RandomForestClassifier(n_estimators=50, max_depth=10, random_state=42)
    model.fit(X, y)
    
    # Convert to ONNX
    from skl2onnx import convert_sklearn
    from skl2onnx.common.data_types import FloatTensorType
    
    initial_type = [('input', FloatTensorType([None, 8]))]
    onnx_model = convert_sklearn(model, initial_types=initial_type)
    
    # Save
    onnx.save(onnx_model, 'onnx_models/scam_classification.onnx')
    print(f"  Saved: onnx_models/scam_classification.onnx")
    return onnx_model


# ============================================================
# Model 4: Volatility Prediction
# ============================================================
def create_volatility_prediction_model():
    """
    Input features:
    - price_change_1h: price change in last hour
    - price_change_24h: price change in last 24h
    - volume_1h: volume in last hour
    - volume_24h: volume in last 24h
    - trade_count_1h: number of trades in last hour
    
    Output: volatility_score (0-1, higher = more volatile)
    """
    print("Creating Volatility Prediction Model...")
    
    np.random.seed(42)
    n_samples = 10000
    
    # Features: [price_change_1h, price_change_24h, volume_1h, volume_24h, trade_count_1h]
    X = np.random.rand(n_samples, 5).astype(np.float32)
    X[:, 0] = np.random.uniform(-0.5, 0.5, n_samples)    # price_change_1h
    X[:, 1] = np.random.uniform(-0.9, 0.9, n_samples)    # price_change_24h
    X[:, 2] = np.random.uniform(0.001, 10, n_samples)     # volume_1h
    X[:, 3] = np.random.uniform(0.01, 100, n_samples)     # volume_24h
    X[:, 4] = np.random.randint(1, 1000, n_samples)       # trade_count_1h
    
    # Volatility score (0-1)
    volatility = (
        np.abs(X[:, 0]) * 0.3 +  # short-term change
        np.abs(X[:, 1]) * 0.3 +  # long-term change
        np.clip(X[:, 2] / 10, 0, 1) * 0.2 +  # volume spike
        np.clip(X[:, 4] / 1000, 0, 1) * 0.2   # trade frequency
    ).clip(0, 1).astype(np.float32)
    
    # Train model
    model = RandomForestRegressor(n_estimators=50, max_depth=10, random_state=42)
    model.fit(X, volatility)
    
    # Convert to ONNX
    from skl2onnx import convert_sklearn
    from skl2onnx.common.data_types import FloatTensorType
    
    initial_type = [('input', FloatTensorType([None, 5]))]
    onnx_model = convert_sklearn(model, initial_types=initial_type)
    
    # Save
    onnx.save(onnx_model, 'onnx_models/volatility_prediction.onnx')
    print(f"  Saved: onnx_models/volatility_prediction.onnx")
    return onnx_model


# ============================================================
# Main
# ============================================================
if __name__ == "__main__":
    print("=" * 60)
    print("Hive ONNX Models Generator")
    print("=" * 60)
    
    create_risk_scoring_model()
    create_anomaly_detection_model()
    create_scam_classification_model()
    create_volatility_prediction_model()
    
    print("=" * 60)
    print("All models generated!")
    print("=" * 60)
