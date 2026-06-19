import { BigInt, Bytes } from "@graphprotocol/graph-ts";
import {
  RelayExecuted,
  RelayFailed
} from "../generated/HiveRelayer/HiveRelayer";
import { RelayedTransaction } from "../generated/schema";

export function handleRelayExecuted(event: RelayExecuted): void {
  let tx = new RelayedTransaction(event.params.requestHash.toHex());
  tx.requestHash = event.params.requestHash;
  tx.primaryWallet = event.params.primaryWallet;
  tx.hiveWallet = event.params.hiveWallet;
  tx.to = event.params.to;
  tx.value = event.params.value;
  tx.success = true;
  tx.timestamp = event.block.timestamp;
  tx.save();
}

export function handleRelayFailed(event: RelayFailed): void {
  let tx = new RelayedTransaction(event.params.requestHash.toHex());
  tx.requestHash = event.params.requestHash;
  tx.primaryWallet = Bytes.empty();
  tx.hiveWallet = Bytes.empty();
  tx.to = Bytes.empty();
  tx.value = BigInt.fromI32(0);
  tx.success = false;
  tx.timestamp = event.block.timestamp;
  tx.save();
}
