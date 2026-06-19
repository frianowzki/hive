import { BigInt } from "@graphprotocol/graph-ts";
import {
  ProposalCreated,
  VoteCast,
  ProposalExecuted,
  ProposalCancelled
} from "../generated/HiveGovernance/HiveGovernance";
import {
  GovernanceProposal,
  Vote
} from "../generated/schema";

export function handleProposalCreated(event: ProposalCreated): void {
  let proposal = new GovernanceProposal(event.params.id.toString());
  proposal.proposalId = event.params.id;
  proposal.proposer = event.params.proposer;
  proposal.description = event.params.description;
  proposal.target = event.params.target;
  proposal.forVotes = BigInt.fromI32(0);
  proposal.againstVotes = BigInt.fromI32(0);
  proposal.abstainVotes = BigInt.fromI32(0);
  proposal.startTime = event.block.timestamp;
  proposal.endTime = event.block.timestamp.plus(BigInt.fromI32(3 * 24 * 60 * 60)); // 3 days
  proposal.executionTime = proposal.endTime.plus(BigInt.fromI32(24 * 60 * 60)); // +1 day
  proposal.executed = false;
  proposal.cancelled = false;
  proposal.emergency = event.params.emergency;
  proposal.state = "ACTIVE";

  // Map proposal type
  let proposalType = event.params.proposalType;
  if (proposalType == 0) {
    proposal.proposalType = "PARAMETER_CHANGE";
  } else if (proposalType == 1) {
    proposal.proposalType = "MODULE_UPGRADE";
  } else if (proposalType == 2) {
    proposal.proposalType = "FEE_CHANGE";
  } else if (proposalType == 3) {
    proposal.proposalType = "STRATEGY_APPROVAL";
  } else {
    proposal.proposalType = "EMERGENCY";
  }

  proposal.save();
}

export function handleVoteCast(event: VoteCast): void {
  let voteId = event.params.proposalId.toString() + "-" + event.params.voter.toHex();
  let vote = new Vote(voteId);
  vote.proposal = event.params.proposalId.toString();
  vote.voter = event.params.voter;
  vote.support = event.params.support;
  vote.weight = event.params.weight;
  vote.timestamp = event.block.timestamp;
  vote.save();

  // Update proposal vote counts
  let proposal = GovernanceProposal.load(event.params.proposalId.toString());
  if (proposal) {
    if (event.params.support == 0) {
      proposal.againstVotes = proposal.againstVotes.plus(event.params.weight);
    } else if (event.params.support == 1) {
      proposal.forVotes = proposal.forVotes.plus(event.params.weight);
    } else {
      proposal.abstainVotes = proposal.abstainVotes.plus(event.params.weight);
    }
    proposal.save();
  }
}

export function handleProposalExecuted(event: ProposalExecuted): void {
  let proposal = GovernanceProposal.load(event.params.id.toString());
  if (proposal) {
    proposal.executed = true;
    proposal.state = "EXECUTED";
    proposal.save();
  }
}

export function handleProposalCancelled(event: ProposalCancelled): void {
  let proposal = GovernanceProposal.load(event.params.id.toString());
  if (proposal) {
    proposal.cancelled = true;
    proposal.state = "CANCELLED";
    proposal.save();
  }
}
