// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {RitualPrecompileConsumer} from "../libraries/RitualPrecompileConsumer.sol";
import {HivePoints} from "../points/HivePoints.sol";

/// @title Council — Hive DAO Governance
/// @notice Enables sale participants to govern the platform

contract HiveCouncil is RitualPrecompileConsumer {
    // ═══ State ═══

    address public admin;
    HivePoints public points;

    struct Proposal {
        address proposer;
        string title;
        string description;
        ProposalType proposalType;
        uint256 forVotes;
        uint256 againstVotes;
        uint256 abstainVotes;
        uint256 endTime;
        bool executed;
        bool cancelled;
        bytes executionData;
        address target;
    }

    enum ProposalType {
        General,        // Non-binding poll
        ParameterChange, // Change protocol parameters
        TreasurySpend,   // Spend from treasury
        EmergencyAction  // Emergency action (shorter voting)
    }

    struct Vote {
        uint8 support;      // 0 = against, 1 = for, 2 = abstain
        uint256 weight;     // Voting weight (points)
        bool voted;
    }

    mapping(uint256 => Proposal) public proposals;
    mapping(uint256 => mapping(address => Vote)) public votes;

    uint256 public proposalCount;
    uint256 public constant VOTING_PERIOD = 3 days;
    uint256 public constant EMERGENCY_PERIOD = 1 days;
    uint256 public constant QUORUM_DEFAULT = 1000; // 1000 points minimum
    uint256 public constant PROPOSAL_THRESHOLD = 100; // 100 points to propose

    // ═══ Events ═══

    event ProposalCreated(uint256 indexed id, address proposer, string title, ProposalType proposalType);
    event VoteCast(uint256 indexed id, address voter, uint8 support, uint256 weight);
    event ProposalExecuted(uint256 indexed id);
    event ProposalCancelled(uint256 indexed id);

    // ═══ Modifiers ═══

    modifier onlyAdmin() {
        require(msg.sender == admin, "Council: not admin");
        _;
    }

    modifier proposalExists(uint256 id) {
        require(id < proposalCount, "Council: proposal not found");
        _;
    }

    // ═══ Constructor ═══

    constructor(address _points) {
        admin = msg.sender;
        points = HivePoints(_points);
    }

    // ═══ Proposal Creation ═══

    /// @notice Create a new proposal
    function propose(
        string calldata title,
        string calldata description,
        ProposalType proposalType,
        address target,
        bytes calldata executionData
    ) external returns (uint256 id) {
        require(points.totalFor(msg.sender) >= PROPOSAL_THRESHOLD, "Council: insufficient points");

        id = proposalCount++;
        uint256 duration = proposalType == ProposalType.EmergencyAction
            ? EMERGENCY_PERIOD
            : VOTING_PERIOD;

        proposals[id] = Proposal({
            proposer: msg.sender,
            title: title,
            description: description,
            proposalType: proposalType,
            forVotes: 0,
            againstVotes: 0,
            abstainVotes: 0,
            endTime: block.timestamp + duration,
            executed: false,
            cancelled: false,
            executionData: executionData,
            target: target
        });

        emit ProposalCreated(id, msg.sender, title, proposalType);
    }

    // ═══ Voting ═══

    /// @notice Cast a vote
    function vote(uint256 id, uint8 support) external proposalExists(id) {
        Proposal storage proposal = proposals[id];
        require(block.timestamp <= proposal.endTime, "Council: voting ended");
        require(!votes[id][msg.sender].voted, "Council: already voted");
        require(support <= 2, "Council: invalid vote");

        uint256 weight = points.totalFor(msg.sender);
        require(weight > 0, "Council: no voting power");

        votes[id][msg.sender] = Vote({
            support: support,
            weight: weight,
            voted: true
        });

        if (support == 0) {
            proposal.againstVotes += weight;
        } else if (support == 1) {
            proposal.forVotes += weight;
        } else {
            proposal.abstainVotes += weight;
        }

        // Award governance points
        points.awardGov(msg.sender);

        emit VoteCast(id, msg.sender, support, weight);
    }

    // ═══ Execution ═══

    /// @notice Execute a passed proposal
    function execute(uint256 id) external proposalExists(id) {
        Proposal storage proposal = proposals[id];
        require(!proposal.executed && !proposal.cancelled, "Council: already resolved");
        require(block.timestamp > proposal.endTime, "Council: voting not ended");
        require(proposal.forVotes + proposal.againstVotes + proposal.abstainVotes >= QUORUM_DEFAULT, "Council: quorum not reached");
        require(proposal.forVotes > proposal.againstVotes, "Council: proposal rejected");

        proposal.executed = true;

        if (proposal.target != address(0) && proposal.executionData.length > 0) {
            (bool success, ) = proposal.target.call(proposal.executionData);
            require(success, "Council: execution failed");
        }

        emit ProposalExecuted(id);
    }

    /// @notice Cancel a proposal (admin or proposer)
    function cancel(uint256 id) external proposalExists(id) {
        Proposal storage proposal = proposals[id];
        require(msg.sender == admin || msg.sender == proposal.proposer, "Council: unauthorized");
        require(!proposal.executed, "Council: already executed");

        proposal.cancelled = true;
        emit ProposalCancelled(id);
    }

    // ═══ AI Integration (Ritual) ═══

    /// @notice Analyze a proposal using LLM
    function analyzeProposal(uint256 id) external view proposalExists(id) returns (string memory) {
        Proposal storage proposal = proposals[id];

        string memory prompt = string(abi.encodePacked(
            "Analyze this governance proposal for a DeFi platform. ",
            "Title: ", proposal.title, ". ",
            "Description: ", proposal.description, ". ",
            "Type: ", _proposalTypeStr(proposal.proposalType), ". ",
            "Votes for: ", _uint2str(proposal.forVotes), ". ",
            "Votes against: ", _uint2str(proposal.againstVotes), ". ",
            "Should users vote for or against? Reply with: {recommendation: FOR/AGAINST/ABSTAIN, reasoning: ...}"
        ));

        bytes memory llmInput = _encodeLlmCall(prompt);
        (bool success, bytes memory output) = LLM_PRECOMPILE.staticcall(llmInput);

        if (success && output.length > 0) {
            return abi.decode(output, (string));
        }
        return "[LLM unavailable]";
    }

    // ═══ Internal ═══

    function _proposalTypeStr(ProposalType t) internal pure returns (string memory) {
        if (t == ProposalType.General) return "General";
        if (t == ProposalType.ParameterChange) return "ParameterChange";
        if (t == ProposalType.TreasurySpend) return "TreasurySpend";
        return "EmergencyAction";
    }

    function _uint2str(uint256 value) internal pure returns (string memory) {
        if (value == 0) return "0";
        uint256 temp = value;
        uint256 digits;
        while (temp != 0) { digits++; temp /= 10; }
        bytes memory buffer = new bytes(digits);
        while (value != 0) {
            digits -= 1;
            buffer[digits] = bytes1(uint8(48 + uint256(value % 10)));
            value /= 10;
        }
        return string(buffer);
    }

    // ═══ View ═══

    function getProposal(uint256 id) external view returns (Proposal memory) {
        return proposals[id];
    }

    function hasVoted(uint256 id, address voter) external view returns (bool) {
        return votes[id][voter].voted;
    }

    function getVote(uint256 id, address voter) external view returns (Vote memory) {
        return votes[id][voter];
    }

    function proposalState(uint256 id) external view returns (string memory) {
        Proposal storage proposal = proposals[id];
        if (proposal.cancelled) return "Cancelled";
        if (proposal.executed) return "Executed";
        if (block.timestamp <= proposal.endTime) return "Active";
        if (proposal.forVotes + proposal.againstVotes + proposal.abstainVotes < QUORUM_DEFAULT) return "QuorumNotReached";
        if (proposal.forVotes > proposal.againstVotes) return "Passed";
        return "Rejected";
    }

    receive() external payable {}
}
