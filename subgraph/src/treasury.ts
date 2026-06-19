import { BigInt } from "@graphprotocol/graph-ts";
import {
  DistributionExecuted
} from "../generated/HiveTreasury/HiveTreasury";
import { TreasuryDistribution } from "../generated/schema";

export function handleDistributionExecuted(event: DistributionExecuted): void {
  let distribution = new TreasuryDistribution(event.params.round.toString());
  distribution.round = event.params.round;
  distribution.totalAmount = event.params.totalAmount;
  distribution.stakerAmount = event.params.stakerAmount;
  distribution.referrerAmount = event.params.referrerAmount;
  distribution.reserveAmount = event.params.reserveAmount;
  distribution.stakerCount = event.params.stakerCount;
  distribution.referrerCount = event.params.referrerCount;
  distribution.timestamp = event.block.timestamp;
  distribution.save();
}
