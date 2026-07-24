#!/usr/bin/env python3
"""
Hive ONNX Models Deployment Script
Deploys ONNX models to HuggingFace for Ritual Chain ONNX precompile
"""

import os
import json
from huggingface_hub import HfApi, create_repo
from pathlib import Path

# Configuration
HF_REPO = "frianowzki/hive-onnx-models"  # Change this to your repo
MODELS_DIR = Path("onnx_models")
MODEL_FILES = [
    "risk_scoring.onnx",
    "anomaly_detection.onnx",
    "scam_classification.onnx",
    "volatility_prediction.onnx"
]

def get_hf_token():
    """Get HuggingFace token from environment or .env file"""
    token = os.environ.get("HF_TOKEN")
    if token:
        return token
    
    # Try to read from .env file
    env_file = Path.home() / ".hermes" / ".env"
    if env_file.exists():
        with open(env_file) as f:
            for line in f:
                if line.startswith("HF_TOKEN="):
                    return line.split("=", 1)[1].strip()
    
    return None

def deploy_models():
    """Deploy ONNX models to HuggingFace"""
    token = get_hf_token()
    if not token:
        print("Error: No HuggingFace token found!")
        print("Set HF_TOKEN environment variable or add to ~/.hermes/.env")
        print("\nTo create a token:")
        print("1. Go to https://huggingface.co/settings/tokens")
        print("2. Create a new token with write access")
        print("3. Set: export HF_TOKEN=hf_xxxxx")
        return False
    
    api = HfApi(token=token)
    
    # Create repo if it doesn't exist
    try:
        create_repo(HF_REPO, token=token, repo_type="model", exist_ok=True)
        print(f"Repo: https://huggingface.co/{HF_REPO}")
    except Exception as e:
        print(f"Error creating repo: {e}")
        return False
    
    # Upload each model
    model_ids = {}
    for model_file in MODEL_FILES:
        model_path = MODELS_DIR / model_file
        if not model_path.exists():
            print(f"Error: Model not found: {model_path}")
            continue
        
        print(f"Uploading {model_file}...")
        try:
            # Upload file
            api.upload_file(
                path_or_fileobj=str(model_path),
                path_in_repo=model_file,
                repo_id=HF_REPO,
                repo_type="model"
            )
            
            # Get commit hash
            repo_info = api.repo_info(HF_REPO, repo_type="model")
            commit_hash = repo_info.sha[:40]
            
            # Create model ID
            model_id = f"hf/frianowzki/hive-onnx-models/{model_file}@{commit_hash}"
            model_ids[model_file.replace(".onnx", "")] = model_id
            
            print(f"  ✓ Uploaded: {model_file}")
            print(f"  Model ID: {model_id}")
            
        except Exception as e:
            print(f"  ✗ Error uploading {model_file}: {e}")
            continue
    
    # Save model IDs
    output_file = "deployed-model-ids.json"
    with open(output_file, "w") as f:
        json.dump(model_ids, f, indent=2)
    
    print(f"\n{'='*60}")
    print("Deployment Complete!")
    print(f"{'='*60}")
    print(f"\nModel IDs saved to: {output_file}")
    print("\nUse these IDs in your Solidity contracts:")
    for name, model_id in model_ids.items():
        print(f"  {name}: {model_id}")
    
    return True

if __name__ == "__main__":
    print("="*60)
    print("Hive ONNX Models Deployment")
    print("="*60)
    deploy_models()
