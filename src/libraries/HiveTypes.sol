// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

/// @title HiveTypes — Data structures for Hive protocol
library HiveTypes {
    // ═══ Enums ═══

    enum Division {
        Scout,      // Venture fund
        Worker,     // Market maker
        Voice       // Governance
    }

    enum AgentState {
        Unborn,     // Not yet created
        Alive,      // Active and running
        Hibernating,// Paused, waiting for conditions
        Dead        // Terminated
    }

    enum DroneType {
        Sniper,     // Fast execution, single-purpose
        Researcher, // Deep analysis
        Negotiator, // OTC deals, partnerships
        Guardian    // Threat monitoring
    }

    // ═══ Structs ═══

    struct Portfolio {
        address token;
        uint256 amount;
        uint256 avgEntryPrice;
        uint256 entryBlock;
        Division source; // Which division acquired this
    }

    struct VentureDeal {
        address project;
        uint256 amount;
        uint256 valuation;
        uint256 entryBlock;
        uint256 holdingPeriod;
        bool active;
        string memo; // LLM analysis notes
    }

    struct MarketPosition {
        address pair;
        uint256 baseAmount;
        uint256 quoteAmount;
        uint256 spreadBps;
        uint256 lastRebalance;
        bool active;
    }

    struct GovernanceVote {
        address dao;
        bytes32 proposalId;
        bool support;
        uint256 votingPower;
        uint256 timestamp;
        string rationale; // LLM reasoning
    }

    struct Drone {
        address droneAddress;
        DroneType droneType;
        string purpose;
        uint256 capitalAllocated;
        uint256 spawnBlock;
        bool active;
    }

    struct Strategy {
        uint256 scoutAllocationBps;   // 4000 = 40%
        uint256 workerAllocationBps;  // 4000 = 40%
        uint256 voiceAllocationBps;   // 1000 = 10%
        uint256 reserveBps;           // 1000 = 10%
        uint256 maxDrawdownBps;       // 2000 = 20%
        uint256 maxPositionBps;       // 1000 = 10%
        uint256 rebalanceInterval;    // blocks
        uint256 heartbeatInterval;    // blocks
    }

    struct HiveState {
        AgentState state;
        uint256 birthBlock;
        uint256 lastActionBlock;
        uint256 totalEarnings;
        uint256 totalDistributions;
        uint256 cycleCount;
    }

    // ═══ HiveID Types ═══

    enum VerificationType {
        None,
        KYC,    // Individual
        KYB     // Organization
    }

    enum AccountType {
        User,       // Regular user (buy/sell)
        Project,    // Token launcher
        Investor    // VC / institutional
    }

    struct HiveIdentity {
        bytes32 usernameHash;
        address primaryWallet;
        address hiveWallet;
        AccountType accountType;
        VerificationType verification;
        bytes32 zkProofHash;
        uint256 createdAt;
        uint256 nonce;
        bool exists;
    }

    // ═══ Constants ═══

    uint256 internal constant BPS_MAX = 10_000;
    uint256 internal constant RITUAL_CHAIN_ID = 1979;
}
