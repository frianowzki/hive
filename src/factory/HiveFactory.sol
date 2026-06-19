// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "../identity/HiveID.sol";
import "../verifier/HiveVerifier.sol";
import "../reputation/HiveReputation.sol";
import "../oracle/HiveOracle.sol";
import "../referral/HiveReferral.sol";
import "../portfolio/HivePortfolio.sol";
import "../relayer/HiveRelayer.sol";

/// @title HiveFactory — Master wiring contract
/// @notice Connects all Hive modules into a unified system
/// @dev Single entry point for cross-contract operations

contract HiveFactory {
    // ═══ Module References ═══

    HiveID public hiveID;
    HiveVerifier public verifier;
    HiveReputation public reputation;
    HiveOracle public oracle;
    HiveReferral public referral;
    HivePortfolio public portfolio;
    HiveRelayer public relayer;

    address public owner;
    bool public initialized;

    // ═══ Events ═══

    event ModuleUpdated(string moduleName, address moduleAddress);
    event SystemInitialized();

    // ═══ Constructor ═══

    constructor() {
        owner = msg.sender;
    }

    // ═══ Initialization ═══

    /// @notice Initialize all modules (called once)
    function initialize(
        address _hiveID,
        address _verifier,
        address _reputation,
        address _oracle,
        address _referral,
        address _portfolio,
        address _relayer
    ) external {
        require(msg.sender == owner, "Factory: not owner");
        require(!initialized, "Factory: already initialized");

        hiveID = HiveID(_hiveID);
        verifier = HiveVerifier(_verifier);
        reputation = HiveReputation(_reputation);
        oracle = HiveOracle(payable(_oracle));
        referral = HiveReferral(payable(_referral));
        portfolio = HivePortfolio(_portfolio);
        relayer = HiveRelayer(payable(_relayer));

        // Wire modules together
        // Wire modules together
        // NOTE: hiveID.addVerifier() and reputation.authorize() must be called
        // by their respective owners separately

        initialized = true;
        emit SystemInitialized();
    }

    // ═══ Cross-Module Operations ═══

    /// @notice Complete onboarding after user has registered on HiveID
    /// @dev User must call hiveID.register() first, then this for referral + reputation
    /// @param usernameHash The registered username hash
    /// @param username The username string
    /// @param referralCode Optional referral code
    function completeOnboarding(
        bytes32 usernameHash,
        string calldata username,
        bytes32 referralCode
    ) external {
        require(hiveID.isRegistered(msg.sender), "Factory: not registered on HiveID");

        // Record referral if code provided
        if (referralCode != bytes32(0)) {
            referral.registerReferral(usernameHash, referralCode);

            // Record referral activity for reputation
            bytes32 referrerHash = referral.getReferrer(usernameHash);
            if (referrerHash != bytes32(0)) {
                reputation.recordActivity(
                    referrerHash,
                    HiveReputation.ActivityType.Referral,
                    username
                );
            }
        }

        // Record early adopter bonus
        reputation.recordActivity(
            usernameHash,
            HiveReputation.ActivityType.EarlyAdopter,
            "registered"
        );
    }

    /// @notice Verify user and update reputation
    function verifyAndUpdateReputation(
        bytes32 usernameHash,
        HiveVerifier.ProofType proofType,
        bytes calldata proof,
        bytes calldata publicSignals,
        bytes32 nullifierHash
    ) external {
        // Verify proof
        verifier.verifyProof(usernameHash, proofType, proof, publicSignals, nullifierHash);

        // Update HiveID verification status
        // (In production, this would be called by the verifier contract)
        // For now, emit event
    }

    /// @notice Record a sale participation and update all relevant modules
    function recordSaleParticipation(
        bytes32 usernameHash,
        address token,
        uint256 amount,
        uint256 price
    ) external {
        // Record in reputation
        reputation.recordActivity(
            usernameHash,
            HiveReputation.ActivityType.SaleParticipation,
            string(abi.encodePacked("bought ", token))
        );

        // Record in portfolio
        portfolio.recordAcquisition(usernameHash, token, amount, price);

        // Distribute referral fee if applicable
        // referral.distributeFeeShare(usernameHash, feeAmount);
    }

    /// @notice Record a trade and update modules
    function recordTrade(
        bytes32 usernameHash,
        address token,
        uint256 amount,
        uint256 price,
        bool isBuy
    ) external {
        if (isBuy) {
            portfolio.recordAcquisition(usernameHash, token, amount, price);
        } else {
            portfolio.recordDisposal(usernameHash, token, amount, price);

            // Record successful trade for reputation
            reputation.recordActivity(
                usernameHash,
                HiveReputation.ActivityType.SuccessfulTrade,
                string(abi.encodePacked("sold ", token))
            );
        }
    }

    /// @notice Record governance vote
    function recordGovernanceVote(
        bytes32 usernameHash,
        bytes32 proposalId
    ) external {
        reputation.recordActivity(
            usernameHash,
            HiveReputation.ActivityType.GovernanceVote,
            string(abi.encodePacked("voted on ", proposalId))
        );
    }

    // ═══ Module Update ═══

    function updateModule(string calldata moduleName, address newAddr) external {
        require(msg.sender == owner, "Factory: not owner");

        if (keccak256(bytes(moduleName)) == keccak256("hiveID")) {
            hiveID = HiveID(newAddr);
        } else if (keccak256(bytes(moduleName)) == keccak256("verifier")) {
            verifier = HiveVerifier(newAddr);
        } else if (keccak256(bytes(moduleName)) == keccak256("reputation")) {
            reputation = HiveReputation(newAddr);
        } else if (keccak256(bytes(moduleName)) == keccak256("oracle")) {
            oracle = HiveOracle(payable(newAddr));
        } else if (keccak256(bytes(moduleName)) == keccak256("referral")) {
            referral = HiveReferral(payable(newAddr));
        } else if (keccak256(bytes(moduleName)) == keccak256("portfolio")) {
            portfolio = HivePortfolio(newAddr);
        } else if (keccak256(bytes(moduleName)) == keccak256("relayer")) {
            relayer = HiveRelayer(payable(newAddr));
        }

        emit ModuleUpdated(moduleName, newAddr);
    }

    // ═══ View — System Info ═══

    function getSystemInfo() external view returns (
        address[7] memory modules,
        bool _initialized
    ) {
        modules[0] = address(hiveID);
        modules[1] = address(verifier);
        modules[2] = address(reputation);
        modules[3] = address(oracle);
        modules[4] = address(referral);
        modules[5] = address(portfolio);
        modules[6] = address(relayer);
        _initialized = initialized;
    }

    // ═══ Admin ═══

    function transferOwnership(address newOwner) external {
        require(msg.sender == owner, "Factory: not owner");
        owner = newOwner;
    }

    receive() external payable {}
}
