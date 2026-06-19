import { BigInt, Bytes } from "@graphprotocol/graph-ts";
import {
  ActionExecuted
} from "../generated/HiveBrain/HiveBrain";
import { BrainAction } from "../generated/schema";

export function handleActionExecuted(event: ActionExecuted): void {
  let action = new BrainAction(event.params.actionId.toHex());
  action.brain = event.params.brain;
  action.contextHash = Bytes.empty(); // Would need to extract from event data
  action.confidence = BigInt.fromI32(0); // Would need to extract from event data
  action.executed = true;
  action.success = event.params.success;
  action.timestamp = event.block.timestamp;

  // Map action type
  let actionType = event.params.actionType;
  if (actionType == 0) {
    action.actionType = "ANALYZE";
  } else if (actionType == 1) {
    action.actionType = "PLAN";
  } else if (actionType == 2) {
    action.actionType = "EXECUTE";
  } else if (actionType == 3) {
    action.actionType = "BUY";
  } else if (actionType == 4) {
    action.actionType = "SELL";
  } else if (actionType == 5) {
    action.actionType = "SWAP";
  } else if (actionType == 6) {
    action.actionType = "STAKE";
  } else if (actionType == 7) {
    action.actionType = "UNSTAKE";
  } else {
    action.actionType = "ALERT";
  }

  action.save();
}
