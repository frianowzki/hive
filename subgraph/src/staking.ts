import { BigInt } from "@graphprotocol/graph-ts";
import {
  Staked,
  Unstaked,
  RewardsClaimed,
  RewardsCompounded
} from "../generated/HiveStaking/HiveStaking";
import { Staker } from "../generated/schema";

export function handleStaked(event: Staked): void {
  let staker = Staker.load(event.params.user.toHex());
  if (!staker) {
    staker = new Staker(event.params.user.toHex());
    staker.address = event.params.user;
    staker.stakedAmount = BigInt.fromI32(0);
    staker.rewardsAccrued = BigInt.fromI32(0);
    staker.autoCompound = false;
    staker.stakedAt = event.block.timestamp;
    staker.lastCompoundAt = event.block.timestamp;
  }

  staker.stakedAmount = staker.stakedAmount.plus(event.params.amount);
  staker.lockMultiplier = event.params.multiplier;
  staker.lockedUntil = event.block.timestamp.plus(event.params.lockPeriod);

  // Calculate tier
  let amount = staker.stakedAmount;
  if (amount.ge(BigInt.fromString("100000000000000000000000"))) {
    staker.tier = "DIAMOND";
  } else if (amount.ge(BigInt.fromString("10000000000000000000000"))) {
    staker.tier = "GOLD";
  } else if (amount.ge(BigInt.fromString("1000000000000000000000"))) {
    staker.tier = "SILVER";
  } else {
    staker.tier = "BRONZE";
  }

  staker.save();
}

export function handleUnstaked(event: Unstaked): void {
  let staker = Staker.load(event.params.user.toHex());
  if (staker) {
    staker.stakedAmount = staker.stakedAmount.minus(event.params.amount);
    if (staker.stakedAmount.le(BigInt.fromI32(0))) {
      staker.tier = "BRONZE";
      staker.lockMultiplier = BigInt.fromI32(0);
    }
    staker.save();
  }
}

export function handleRewardsClaimed(event: RewardsClaimed): void {
  let staker = Staker.load(event.params.user.toHex());
  if (staker) {
    staker.rewardsAccrued = BigInt.fromI32(0);
    staker.save();
  }
}

export function handleRewardsCompounded(event: RewardsCompounded): void {
  let staker = Staker.load(event.params.user.toHex());
  if (staker) {
    staker.stakedAmount = staker.stakedAmount.plus(event.params.amount);
    staker.rewardsAccrued = BigInt.fromI32(0);
    staker.lastCompoundAt = event.block.timestamp;
    staker.save();
  }
}
