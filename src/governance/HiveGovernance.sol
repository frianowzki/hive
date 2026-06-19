// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "../interfaces/IHive.sol";

/**
 * @title HiveGovernance
 * @notice DAO governance for the Hive platform
 * @dev Voting power based on staked RITUAL, executes via multi-sig
 * @author Hive Team
 */

contract HiveGovernance {
    // ═══════════════════════════════════════════════════════════════
    //                           STATE
    // ═══════════════════════════════════════════════════════════════

    address public owner;
    IStaking public staking;
    IMultiSig public multiSig;

    /// @notice Minimum staked RITUAL to create proposal (in wei)
    uint256 public proposalThreshold = 1000 ether;

    /// @notice Quorum as percentage of total staked (basis points)
    uint256 public quorumBps = 1000; // 10%

    /// @notice Emergency quorum (basis points)
    uint256 public emergencyQuorumBps = 3000; // 30%

    /// @notice Voting period in seconds
    uint256 public votingPeriod = 3 days;

    /// @notice Emergency voting period
    uint256 public emergencyVotingPeriod = 1 days;

    /// @notice Time delay before execution (seconds)
    uint256 public executionDelay = 24 hours;

    /// @notice Proposal counter
    uint256 public proposalCount;

    /// @notice Proposal types
    enum ProposalType {
        PARAMETER_CHANGE,
        MODULE_UPGRADE,
        FEE_CHANGE,
        STRATEGY_APPROVAL,
        EMERGENCY
    }

    /// @notice Proposal state
    enum ProposalState {
        Pending,
        Active,
        Passed,
        Failed,
        Executed,
        Cancelled
    }

    /// @notice Proposal struct
    struct Proposal {
        uint256 id;
        address proposer;
        ProposalType proposalType;
        string description;
        address target;
        bytes data;
        uint256 forVotes;
        uint256 againstVotes;
        uint256 abstainVotes;
        uint256 startTime;
        uint256 endTime;
        uint256 executionTime;
        bool executed;
        bool cancelled;
        bool emergency;
    }

    mapping(uint256 => Proposal) public proposals;

    /// @notice Vote record
    struct Vote {
        bool hasVoted;
        uint8 support; // 0 = against, 1 = for, 2 = abstain
        uint256 weight;
        uint256 timestamp;
    }

    /// @notice proposalId => voter => Vote
    mapping(uint256 => mapping(address => Vote)) public votes;

    /// @notice Delegation: delegator => delegate
    mapping(address => address) public delegates;

    /// @notice Delegate voting power: delegate => totalPower
    mapping(address => uint256) public delegatePower;

    // ═══════════════════════════════════════════════════════════════
    //                          EVENTS
    // ═══════════════════════════════════════════════════════════════

    event ProposalCreated(
        uint256 indexed id,
        address indexed proposer,
        ProposalType proposalType,
        string description,
        address target,
        bool emergency
    );

    event VoteCast(
        uint256 indexed proposalId,
        address indexed voter,
        uint8 support,
        uint256 weight
    );

    event DelegateChanged(address indexed delegator, address indexed newDelegate);
    event ProposalExecuted(uint256 indexed id);
    event ProposalCancelled(uint256 indexed id);
    event ParametersUpdated(string param, uint256 oldValue, uint256 newValue);

    // ═══════════════════════════════════════════════════════════════
    //                         MODIFIERS
    // ═══════════════════════════════════════════════════════════════

    modifier onlyOwner() {
        require(msg.sender == owner, "HiveGovernance: not owner");
        _;
    }

    modifier proposalExists(uint256 proposalId) {
        require(proposalId < proposalCount, "HiveGovernance: invalid proposal");
        _;
    }

    // ═══════════════════════════════════════════════════════════════
    //                        CONSTRUCTOR
    // ═══════════════════════════════════════════════════════════════

    constructor(address _staking, address _multiSig) {
        owner = msg.sender;
        staking = IStaking(_staking);
        multiSig = IMultiSig(_multiSig);
    }

    // ═══════════════════════════════════════════════════════════════
    //                      DELEGATION
    // ═══════════════════════════════════════════════════════════════

    /// @notice Delegate voting power to another address
    /// @param delegate Address to delegate to
    function delegate(address delegate) external {
        require(delegate != address(0), "HiveGovernance: zero address");
        require(delegate != msg.sender, "HiveGovernance: self-delegate");

        address oldDelegate = delegates[msg.sender];

        // Remove from old delegate
        if (oldDelegate != address(0)) {
            uint256 oldPower = _getVotingPower(msg.sender);
            delegatePower[oldDelegate] -= oldPower;
        }

        // Add to new delegate
        delegates[msg.sender] = delegate;
        uint256 newPower = _getVotingPower(msg.sender);
        delegatePower[delegate] += newPower;

        emit DelegateChanged(msg.sender, delegate);
    }

    /// @notice Remove delegation
    function undelegate() external {
        address oldDelegate = delegates[msg.sender];
        require(oldDelegate != address(0), "HiveGovernance: not delegated");

        uint256 oldPower = _getVotingPower(msg.sender);
        delegatePower[oldDelegate] -= oldPower;
        delete delegates[msg.sender];

        emit DelegateChanged(msg.sender, address(0));
    }

    // ═══════════════════════════════════════════════════════════════
    //                    PROPOSAL CREATION
    // ═══════════════════════════════════════════════════════════════

    /// @notice Create a new proposal
    /// @param proposalType Type of proposal
    /// @param description Human-readable description
    /// @param target Contract to execute on
    /// @param data Calldata for execution
    /// @param emergency Whether this is an emergency proposal
    function propose(
        ProposalType proposalType,
        string calldata description,
        address target,
        bytes calldata data,
        bool emergency
    ) external returns (uint256) {
        uint256 votingPower = _getEffectiveVotingPower(msg.sender);
        require(votingPower >= proposalThreshold, "HiveGovernance: insufficient voting power");

        uint256 proposalId = proposalCount++;
        uint256 duration = emergency ? emergencyVotingPeriod : votingPeriod;

        Proposal storage p = proposals[proposalId];
        p.id = proposalId;
        p.proposer = msg.sender;
        p.proposalType = proposalType;
        p.description = description;
        p.target = target;
        p.data = data;
        p.startTime = block.timestamp;
        p.endTime = block.timestamp + duration;
        p.executionTime = block.timestamp + duration + executionDelay;
        p.emergency = emergency;

        emit ProposalCreated(proposalId, msg.sender, proposalType, description, target, emergency);

        return proposalId;
    }

    // ═══════════════════════════════════════════════════════════════
    //                         VOTING
    // ═══════════════════════════════════════════════════════════════

    /// @notice Cast a vote on a proposal
    /// @param proposalId Proposal to vote on
    /// @param support 0 = against, 1 = for, 2 = abstain
    function castVote(uint256 proposalId, uint8 support) external proposalExists(proposalId) {
        Proposal storage p = proposals[proposalId];

        require(block.timestamp >= p.startTime, "HiveGovernance: voting not started");
        require(block.timestamp <= p.endTime, "HiveGovernance: voting ended");
        require(!p.cancelled, "HiveGovernance: proposal cancelled");

        Vote storage existingVote = votes[proposalId][msg.sender];
        require(!existingVote.hasVoted, "HiveGovernance: already voted");

        uint256 weight = _getEffectiveVotingPower(msg.sender);
        require(weight > 0, "HiveGovernance: no voting power");

        // Record vote
        votes[proposalId][msg.sender] = Vote({
            hasVoted: true,
            support: support,
            weight: weight,
            timestamp: block.timestamp
        });

        // Add to vote tally
        if (support == 0) {
            p.againstVotes += weight;
        } else if (support == 1) {
            p.forVotes += weight;
        } else {
            p.abstainVotes += weight;
        }

        emit VoteCast(proposalId, msg.sender, support, weight);
    }

    // ═══════════════════════════════════════════════════════════════
    //                       EXECUTION
    // ═══════════════════════════════════════════════════════════════

    /// @notice Execute a passed proposal
    /// @param proposalId Proposal to execute
    function execute(uint256 proposalId) external proposalExists(proposalId) {
        Proposal storage p = proposals[proposalId];

        require(!p.executed, "HiveGovernance: already executed");
        require(!p.cancelled, "HiveGovernance: cancelled");
        require(block.timestamp >= p.endTime, "HiveGovernance: voting not ended");
        require(block.timestamp >= p.executionTime, "HiveGovernance: execution delay not met");
        require(_isPassed(proposalId), "HiveGovernance: proposal not passed");

        p.executed = true;

        // Execute via multi-sig
        if (p.target != address(0) && p.data.length > 0) {
            multiSig.submitTransaction(p.target, p.data);
        }

        emit ProposalExecuted(proposalId);
    }

    /// @notice Cancel a proposal (owner only)
    function cancel(uint256 proposalId) external proposalExists(proposalId) {
        require(
            msg.sender == owner || msg.sender == proposals[proposalId].proposer,
            "HiveGovernance: not authorized"
        );

        Proposal storage p = proposals[proposalId];
        require(!p.executed, "HiveGovernance: already executed");
        require(!p.cancelled, "HiveGovernance: already cancelled");

        p.cancelled = true;

        emit ProposalCancelled(proposalId);
    }

    // ═══════════════════════════════════════════════════════════════
    //                      VIEW FUNCTIONS
    // ═══════════════════════════════════════════════════════════════

    /// @notice Get proposal state
    function state(uint256 proposalId) external view proposalExists(proposalId) returns (ProposalState) {
        Proposal storage p = proposals[proposalId];

        if (p.cancelled) return ProposalState.Cancelled;
        if (p.executed) return ProposalState.Executed;
        if (block.timestamp < p.startTime) return ProposalState.Pending;
        if (block.timestamp <= p.endTime) return ProposalState.Active;

        if (_isPassed(proposalId)) {
            return ProposalState.Passed;
        }

        return ProposalState.Failed;
    }

    /// @notice Check if proposal passed
    function _isPassed(uint256 proposalId) internal view returns (bool) {
        Proposal storage p = proposals[proposalId];

        uint256 totalStaked = staking.totalStaked();
        if (totalStaked == 0) return false;

        uint256 requiredQuorum = p.emergency
            ? (totalStaked * emergencyQuorumBps) / 10000
            : (totalStaked * quorumBps) / 10000;

        uint256 totalVotes = p.forVotes + p.againstVotes + p.abstainVotes;

        // Check quorum
        if (totalVotes < requiredQuorum) return false;

        // Check majority
        return p.forVotes > p.againstVotes;
    }

    /// @notice Get effective voting power (own + delegated)
    function _getEffectiveVotingPower(address voter) internal view returns (uint256) {
        return _getVotingPower(voter) + delegatePower[voter];
    }

    /// @notice Get own voting power (staked * multiplier)
    function _getVotingPower(address voter) internal view returns (uint256) {
        uint256 staked = staking.stakedAmount(voter);
        if (staked == 0) return 0;

        uint256 multiplier = staking.lockMultiplier(voter);
        return staked * multiplier / 1e18;
    }

    /// @notice Get proposal details
    function getProposal(uint256 proposalId) external view proposalExists(proposalId) returns (Proposal memory) {
        return proposals[proposalId];
    }

    /// @notice Get vote details
    function getVote(uint256 proposalId, address voter) external view returns (Vote memory) {
        return votes[proposalId][voter];
    }

    /// @notice Check if address has voted on proposal
    function hasVoted(uint256 proposalId, address voter) external view returns (bool) {
        return votes[proposalId][voter].hasVoted;
    }

    // ═══════════════════════════════════════════════════════════════
    //                      ADMIN FUNCTIONS
    // ═══════════════════════════════════════════════════════════════

    /// @notice Update proposal threshold
    function setProposalThreshold(uint256 _threshold) external onlyOwner {
        uint256 old = proposalThreshold;
        proposalThreshold = _threshold;
        emit ParametersUpdated("proposalThreshold", old, _threshold);
    }

    /// @notice Update quorum
    function setQuorum(uint256 _quorumBps) external onlyOwner {
        require(_quorumBps <= 5000, "HiveGovernance: quorum too high");
        uint256 old = quorumBps;
        quorumBps = _quorumBps;
        emit ParametersUpdated("quorumBps", old, _quorumBps);
    }

    /// @notice Update emergency quorum
    function setEmergencyQuorum(uint256 _emergencyQuorumBps) external onlyOwner {
        require(_emergencyQuorumBps <= 5000, "HiveGovernance: quorum too high");
        uint256 old = emergencyQuorumBps;
        emergencyQuorumBps = _emergencyQuorumBps;
        emit ParametersUpdated("emergencyQuorumBps", old, _emergencyQuorumBps);
    }

    /// @notice Update voting period
    function setVotingPeriod(uint256 _votingPeriod) external onlyOwner {
        require(_votingPeriod >= 1 hours, "HiveGovernance: period too short");
        uint256 old = votingPeriod;
        votingPeriod = _votingPeriod;
        emit ParametersUpdated("votingPeriod", old, _votingPeriod);
    }

    /// @notice Update execution delay
    function setExecutionDelay(uint256 _executionDelay) external onlyOwner {
        uint256 old = executionDelay;
        executionDelay = _executionDelay;
        emit ParametersUpdated("executionDelay", old, _executionDelay);
    }

    /// @notice Update staking contract
    function setStaking(address _staking) external onlyOwner {
        staking = IStaking(_staking);
    }

    /// @notice Update multi-sig
    function setMultiSig(address _multiSig) external onlyOwner {
        multiSig = IMultiSig(_multiSig);
    }

    /// @notice Transfer ownership
    function transferOwnership(address newOwner) external onlyOwner {
        require(newOwner != address(0), "HiveGovernance: zero address");
        owner = newOwner;
    }
}
