#!/usr/bin/env python3
"""
Hive × Nillion nilDB — Private KYC Storage Prototype

Steps:
1. Connect to nilDB testnet cluster (3 nodes)
2. Register as builder
3. Create KYC collection with encrypted fields
4. Store sample KYC data (name, DOB, country, doc hash = encrypted)
5. Query back (wallet_address, kyc_level = plaintext queryable)

Encrypted fields: full_name, date_of_birth, country_code, document_hash
Plaintext fields: wallet_address, kyc_level, verified_at, _id
"""

import os
import sys
import asyncio
import json
import uuid
import time
from datetime import datetime

from dotenv import load_dotenv

load_dotenv(os.path.join(os.path.dirname(__file__), ".env"))

from secretvaults.common.keypair import Keypair
from secretvaults.builder import SecretVaultBuilderClient
from secretvaults.common.blindfold import BlindfoldFactoryConfig, BlindfoldOperation
from secretvaults.dto.builders import RegisterBuilderRequest
from secretvaults.dto.collections import CreateCollectionRequest
from secretvaults.dto.data import (
    CreateStandardDataRequest,
    FindDataRequest,
)
from secretvaults.dto.common import Name


def check_env():
    required = ["BUILDER_PRIVATE_KEY", "NILCHAIN_URL", "NILAUTH_URL", "NILDB_NODES"]
    missing = [v for v in required if not os.getenv(v)]
    if missing:
        print(f"❌ Missing env vars: {missing}")
        sys.exit(1)


async def main():
    check_env()

    config = {
        "NILCHAIN_URL": os.getenv("NILCHAIN_URL"),
        "NILAUTH_URL": os.getenv("NILAUTH_URL"),
        "NILDB_NODES": os.getenv("NILDB_NODES", "").split(","),
        "BUILDER_PRIVATE_KEY": os.getenv("BUILDER_PRIVATE_KEY"),
    }

    print("=" * 60)
    print("🐝 Hive × Nillion nilDB — Private KYC Prototype")
    print("=" * 60)

    # Step 1: Create keypair
    print("\n[1/7] Creating keypair from builder private key...")
    pk = config["BUILDER_PRIVATE_KEY"]
    if pk.startswith("0x"):
        pk = pk[2:]
    keypair = Keypair.from_hex(pk)
    print(f"  ✅ DID: {keypair.to_did_string()}")

    # Step 2: Connect to nilDB cluster
    print("\n[2/7] Connecting to nilDB testnet cluster...")
    urls = {
        "chain": [config["NILCHAIN_URL"]],
        "auth": config["NILAUTH_URL"],
        "dbs": config["NILDB_NODES"],
    }
    print(f"  Chain: {config['NILCHAIN_URL']}")
    print(f"  Auth:  {config['NILAUTH_URL']}")
    print(f"  Nodes: {len(urls['dbs'])} nilDB nodes")

    async with await SecretVaultBuilderClient.from_options(
        keypair=keypair,
        urls=urls,
        blindfold=BlindfoldFactoryConfig(
            operation=BlindfoldOperation.STORE,
            use_cluster_key=True,
        ),
    ) as builder_client:

        # Step 3: Get root token
        print("\n[3/7] Refreshing root token...")
        await builder_client.refresh_root_token()
        print("  ✅ Root token obtained")

        # Step 4: Register builder
        print("\n[4/7] Registering builder...")
        try:
            register_req = RegisterBuilderRequest(
                did=builder_client.keypair.to_did_string(),
                name=Name("hive-kyc-builder"),
            )
            resp = await builder_client.register(register_req)
            print("  ✅ Builder registered")
        except Exception as e:
            print(f"  ℹ️  Already registered or: {e}")

        # Step 5: Create KYC collection
        print("\n[5/7] Creating KYC collection with encrypted fields...")
        collection_id = str(uuid.uuid4())

        with open(os.path.join(os.path.dirname(__file__), "kyc_schema.json"), "r") as f:
            schema = json.load(f)

        create_req = CreateCollectionRequest(
            id=collection_id,
            type=schema["type"],
            name="hive-kyc-collection",
            schema=schema["schema"],
        )

        try:
            await builder_client.create_collection(create_req)
            print(f"  ✅ Collection created: {collection_id}")
        except Exception as e:
            print(f"  ⚠️  Collection creation: {e}")
            # Try to read existing profile to find existing collections
            try:
                profile = await builder_client.read_profile()
                collections = getattr(profile, 'collections', []) or getattr(getattr(profile, 'data', profile), 'collections', [])
                if collections:
                    collection_id = str(collections[0])
                    print(f"  ℹ️  Using existing collection: {collection_id}")
                else:
                    print("  ❌ No collections found, aborting")
                    return
            except Exception as e2:
                print(f"  ❌ Cannot read profile: {e2}")
                return

        # Step 6: Store sample KYC data
        print("\n[6/7] Storing sample KYC records (encrypted fields)...")
        sample_users = [
            {
                "_id": str(uuid.uuid4()),
                "wallet_address": "0x4b171E1217b71E37777B7F56d89cCB441C1De301",
                "kyc_level": 2,
                "verified_at": int(time.time()),
                "full_name": {"%allot": "Frian Kurniawan"},
                "date_of_birth": {"%allot": "1995-03-15"},
                "country_code": {"%allot": "ID"},
                "document_hash": {"%allot": "sha256:abc123def456"},
            },
            {
                "_id": str(uuid.uuid4()),
                "wallet_address": "0xd450caB1dCe65ac7bB089Cf8dA9F20f37544B1B6",
                "kyc_level": 1,
                "verified_at": int(time.time()),
                "full_name": {"%allot": "Alice DeFi"},
                "date_of_birth": {"%allot": "1990-07-22"},
                "country_code": {"%allot": "US"},
                "document_hash": {"%allot": "sha256:xyz789ghi012"},
            },
        ]

        try:
            create_data_req = CreateStandardDataRequest(
                collection=collection_id,
                data=sample_users,
            )
            await builder_client.create_standard_data(create_data_req)
            print(f"  ✅ Stored {len(sample_users)} KYC records")
            for u in sample_users:
                print(f"     → {u['wallet_address'][:10]}... (level {u['kyc_level']})")
        except Exception as e:
            print(f"  ❌ Failed to store data: {e}")
            return

        # Step 7: Query back
        print("\n[7/7] Querying KYC data back...")
        try:
            find_req = FindDataRequest(collection=collection_id, filter={})
            results = await builder_client.find_data(find_req)

            if results:
                print(f"  ✅ Found {len(results)} records:")
                for i, record in enumerate(results, 1):
                    if isinstance(record, dict):
                        print(f"\n  Record {i}:")
                        print(f"    Wallet:  {record.get('wallet_address', 'N/A')}")
                        print(f"    Level:   {record.get('kyc_level', 'N/A')}")
                        print(f"    Name:    {record.get('full_name', '[encrypted]')}")
                        print(f"    Country: {record.get('country_code', '[encrypted]')}")
                    else:
                        print(f"\n  Record {i}: {record}")
            else:
                print("  ⚠️  No records found")
        except Exception as e:
            print(f"  ❌ Query failed: {e}")

        print("\n" + "=" * 60)
        print("🎉 Prototype complete!")
        print(f"Collection ID: {collection_id}")
        print("=" * 60)

        # Save collection ID for future use
        with open(os.path.join(os.path.dirname(__file__), "collection_id.txt"), "w") as f:
            f.write(collection_id)
        print(f"\nCollection ID saved to nillion/collection_id.txt")


if __name__ == "__main__":
    asyncio.run(main())
