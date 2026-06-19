import { BigInt } from "@graphprotocol/graph-ts";
import {
  Registered,
  Verified,
  WalletLinked
} from "../generated/HiveID/HiveID";
import { HiveIdentity } from "../generated/schema";

export function handleRegistered(event: Registered): void {
  let identity = new HiveIdentity(event.params.usernameHash.toHex());
  identity.username = event.params.username;
  identity.primaryWallet = event.params.primaryWallet;
  identity.verified = false;
  identity.kycProof = false;
  identity.kybProof = false;
  identity.registeredAt = event.block.timestamp;
  identity.lastUpdated = event.block.timestamp;
  identity.save();
}

export function handleVerified(event: Verified): void {
  let identity = HiveIdentity.load(event.params.usernameHash.toHex());
  if (identity) {
    identity.verified = true;
    identity.kycProof = event.params.kyc;
    identity.kybProof = event.params.kyb;
    identity.lastUpdated = event.block.timestamp;
    identity.save();
  }
}

export function handleWalletLinked(event: WalletLinked): void {
  let identity = HiveIdentity.load(event.params.usernameHash.toHex());
  if (identity) {
    identity.hiveWallet = event.params.wallet;
    identity.lastUpdated = event.block.timestamp;
    identity.save();
  }
}
