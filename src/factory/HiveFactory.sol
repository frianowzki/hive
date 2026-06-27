// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "../identity/HiveID.sol";
import "../verifier/HiveVerifier.sol";
import "../reputation/HiveReputation.sol";
import "../oracle/HiveOracle.sol";
import "../referral/HiveReferral.sol";
import "../portfolio/HivePortfolio.sol";
import "../relayer/HiveRelayer.sol";
import "../privacy/HiveDKMS.sol";
import "../treasury/HoneyPot.sol";

/// @title HiveFactory — Master wiring contract
/// @notice Connects ALL Hive modules into a unified system
/// @dev Single entry point for cross-contract operations and module wiring

contract HiveFactory {
    // ═══ Module References ═══

    // Layer 1: Identity & Verification
    HiveID public hiveID;
    HiveVerifier public verifier;
    HiveReputation public reputation;
    HiveDKMS public dkms;

    // Layer 2: Core DeFi
    address public launchPad;
    address public marketMaker;
    address public clearing;
    address public staking;
    address public treasury;
    address public honeyPot;

    // Layer 3: AI & Intelligence
    address public brain;
    address public agent;
    address public strategy;
    address public autoStrategy;

    // Layer 4: Federated Learning
    address public flock;
    // DEPRECATED: EigenLayer removed — not implementable on Ritual Testnet
    // address public eigenLayer;

    // Layer 5: Governance & Social
    address public governance;
    address public council;
    address public multiSig;

    // Layer 6: User Features
    HiveOracle public oracle;
    HiveReferral public referral;
    HivePortfolio public portfolio;
    address public chat;
    address public points;
    address public notification;
    HiveRelayer public relayer;

    // Layer 7: Orchestration
    address public queen;
    address public registry;

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

        initialized = true;
        emit SystemInitialized();
    }

    /// @notice Wire all extended modules (AI, DeFi, Governance layers)
    function wireExtended(
        address _launchPad,
        address _marketMaker,
        address _clearing,
        address _staking,
        address _treasury,
        address _dkms,
        address _honeyPot,
        address _brain,
        address _agent,
        address _strategy,
        address _autoStrategy,
        address _flock,
        // eigenLayer removed
        address _governance,
        address _council,
        address _multiSig,
        address _chat,
        address _points,
        address _notification,
        address _queen,
        address _registry
    ) external {
        require(msg.sender == owner, "Factory: not owner");

        launchPad = _launchPad;
        marketMaker = _marketMaker;
        clearing = _clearing;
        staking = _staking;
        treasury = _treasury;
        dkms = HiveDKMS(payable(_dkms));
        honeyPot = _honeyPot;
        brain = _brain;
        agent = _agent;
        strategy = _strategy;
        autoStrategy = _autoStrategy;
        flock = _flock;
        // eigenLayer removed
        governance = _governance;
        council = _council;
        multiSig = _multiSig;
        chat = _chat;
        points = _points;
        notification = _notification;
        queen = _queen;
        registry = _registry;

        emit ModuleUpdated("wireExtended", _brain);
    }

    // ═══ Cross-Module Wiring ═══

    function wireAILayer() external {
        require(msg.sender == owner, "Factory: not owner");
        if (brain != address(0) && address(oracle) != address(0)) {
            (bool _ok, ) = brain.call(abi.encodeWithSignature("setOracle(address)", address(oracle)));
            _ok;
        }
        if (brain != address(0) && flock != address(0)) {
            (bool _ok, ) = brain.call(abi.encodeWithSignature("setFlock(address)", flock));
            _ok;
        }
        if (flock != address(0) && brain != address(0)) {
            (bool _ok, ) = flock.call(abi.encodeWithSignature("setBrain(address)", brain));
            _ok;
        }
    }

    function wireSecurityLayer() external {
        require(msg.sender == owner, "Factory: not owner");
        // EigenLayer removed — not implementable on Ritual Testnet
        if (staking != address(0) && treasury != address(0)) {
            (bool _ok, ) = staking.call(abi.encodeWithSignature("setTreasury(address)", treasury));
            _ok;
        }
    }

    function wireFeeEconomy() external {
        require(msg.sender == owner, "Factory: not owner");
        // HoneyPot → Staking (for reward distribution)
        if (honeyPot != address(0) && staking != address(0)) {
            (bool _ok, ) = honeyPot.call(abi.encodeWithSignature("setStaking(address)", staking));
            _ok;
        }
        // HoneyPot → Treasury (for fee notifications)
        if (honeyPot != address(0) && treasury != address(0)) {
            (bool _ok, ) = honeyPot.call(abi.encodeWithSignature("setTreasury(address)", treasury));
            _ok;
        }
        // Staking → Treasury (fee notifications)
        if (staking != address(0) && treasury != address(0)) {
            (bool _ok, ) = staking.call(abi.encodeWithSignature("setTreasury(address)", treasury));
            _ok;
        }
    }

    function wireDKMS() external {
        require(msg.sender == owner, "Factory: not owner");
        // DKMS is standalone — no cross-contract wiring needed
        if (address(dkms) != address(0)) {
            emit ModuleUpdated("dkms", address(dkms));
        }
    }

    function wireQueen() external {
        require(msg.sender == owner, "Factory: not owner");
        require(queen != address(0), "Factory: no queen");

        if (brain != address(0)) {
            (bool _ok, ) = queen.call(abi.encodeWithSignature("setDivision(string,address)", "brain", brain));
            _ok;
        }
        if (address(oracle) != address(0)) {
            (bool _ok, ) = queen.call(abi.encodeWithSignature("setDivision(string,address)", "oracle", address(oracle)));
            _ok;
        }
        if (flock != address(0)) {
            (bool _ok, ) = queen.call(abi.encodeWithSignature("setDivision(string,address)", "flock", flock));
            _ok;
        }
        if (registry != address(0)) {
            (bool _ok, ) = queen.call(abi.encodeWithSignature("setDivision(string,address)", "registry", registry));
            _ok;
        }
        if (launchPad != address(0)) {
            (bool _ok, ) = queen.call(abi.encodeWithSignature("setDivision(string,address)", "launchPad", launchPad));
            _ok;
        }
        if (marketMaker != address(0)) {
            (bool _ok, ) = queen.call(abi.encodeWithSignature("setDivision(string,address)", "marketMaker", marketMaker));
            _ok;
        }
        if (council != address(0)) {
            (bool _ok, ) = queen.call(abi.encodeWithSignature("setDivision(string,address)", "council", council));
            _ok;
        }
    }

    function wireAutoStrategy() external {
        require(msg.sender == owner, "Factory: not owner");
        if (autoStrategy != address(0) && address(oracle) != address(0)) {
            (bool _ok, ) = autoStrategy.call(abi.encodeWithSignature("setOracle(address)", address(oracle)));
            _ok;
        }
    }

    function wireAll() external {
        require(msg.sender == owner, "Factory: not owner");
        this.wireAILayer();
        this.wireSecurityLayer();
        this.wireFeeEconomy();
        this.wireDKMS();
        this.wireQueen();
        this.wireAutoStrategy();
    }

    // ═══ Cross-Module Operations ═══

    function completeOnboarding(
        bytes32 usernameHash,
        string calldata username,
        bytes32 referralCode
    ) external {
        require(hiveID.isRegistered(msg.sender), "Factory: not registered on HiveID");

        if (referralCode != bytes32(0)) {
            referral.registerReferral(usernameHash, referralCode);
            bytes32 referrerHash = referral.getReferrer(usernameHash);
            if (referrerHash != bytes32(0)) {
                reputation.recordActivity(referrerHash, HiveReputation.ActivityType.Referral, username);
            }
        }

        reputation.recordActivity(usernameHash, HiveReputation.ActivityType.EarlyAdopter, "registered");
    }

    function verifyAndUpdateReputation(
        bytes32 usernameHash,
        HiveVerifier.ProofType proofType,
        bytes calldata proof,
        bytes calldata publicSignals,
        bytes32 nullifierHash
    ) external {
        verifier.verifyProof(usernameHash, proofType, proof, publicSignals, nullifierHash);
    }

    function recordSaleParticipation(bytes32 usernameHash, address token, uint256 amount, uint256 price) external {
        reputation.recordActivity(usernameHash, HiveReputation.ActivityType.SaleParticipation, string(abi.encodePacked("bought ", token)));
        portfolio.recordAcquisition(usernameHash, token, amount, price);
    }

    function recordTrade(bytes32 usernameHash, address token, uint256 amount, uint256 price, bool isBuy) external {
        if (isBuy) {
            portfolio.recordAcquisition(usernameHash, token, amount, price);
        } else {
            portfolio.recordDisposal(usernameHash, token, amount, price);
            reputation.recordActivity(usernameHash, HiveReputation.ActivityType.SuccessfulTrade, string(abi.encodePacked("sold ", token)));
        }
    }

    function recordGovernanceVote(bytes32 usernameHash, bytes32 proposalId) external {
        reputation.recordActivity(usernameHash, HiveReputation.ActivityType.GovernanceVote, string(abi.encodePacked("voted on ", proposalId)));
    }

    // ═══ Module Update ═══

    function updateModule(string calldata moduleName, address newAddr) external {
        require(msg.sender == owner, "Factory: not owner");

        if (keccak256(bytes(moduleName)) == keccak256("hiveID")) hiveID = HiveID(newAddr);
        else if (keccak256(bytes(moduleName)) == keccak256("verifier")) verifier = HiveVerifier(newAddr);
        else if (keccak256(bytes(moduleName)) == keccak256("reputation")) reputation = HiveReputation(newAddr);
        else if (keccak256(bytes(moduleName)) == keccak256("oracle")) oracle = HiveOracle(payable(newAddr));
        else if (keccak256(bytes(moduleName)) == keccak256("referral")) referral = HiveReferral(payable(newAddr));
        else if (keccak256(bytes(moduleName)) == keccak256("portfolio")) portfolio = HivePortfolio(newAddr);
        else if (keccak256(bytes(moduleName)) == keccak256("relayer")) relayer = HiveRelayer(payable(newAddr));
        else if (keccak256(bytes(moduleName)) == keccak256("brain")) brain = newAddr;
        else if (keccak256(bytes(moduleName)) == keccak256("flock")) flock = newAddr;
        else if (keccak256(bytes(moduleName)) == keccak256("dkms")) dkms = HiveDKMS(payable(newAddr));
        else if (keccak256(bytes(moduleName)) == keccak256("honeyPot")) honeyPot = newAddr;
        // eigenLayer removed
        else if (keccak256(bytes(moduleName)) == keccak256("staking")) staking = newAddr;
        else if (keccak256(bytes(moduleName)) == keccak256("treasury")) treasury = newAddr;
        else if (keccak256(bytes(moduleName)) == keccak256("queen")) queen = newAddr;
        else if (keccak256(bytes(moduleName)) == keccak256("launchPad")) launchPad = newAddr;
        else if (keccak256(bytes(moduleName)) == keccak256("marketMaker")) marketMaker = newAddr;
        else if (keccak256(bytes(moduleName)) == keccak256("governance")) governance = newAddr;
        else if (keccak256(bytes(moduleName)) == keccak256("council")) council = newAddr;

        emit ModuleUpdated(moduleName, newAddr);
    }

    // ═══ View ═══

    function getSystemInfo() external view returns (address[27] memory modules, bool _initialized) {
        modules[0] = address(hiveID);
        modules[1] = address(verifier);
        modules[2] = address(reputation);
        modules[3] = address(oracle);
        modules[4] = address(referral);
        modules[5] = address(portfolio);
        modules[6] = address(relayer);
        modules[7] = launchPad;
        modules[8] = marketMaker;
        modules[9] = clearing;
        modules[10] = staking;
        modules[11] = treasury;
        modules[12] = brain;
        modules[13] = agent;
        modules[14] = strategy;
        modules[15] = autoStrategy;
        modules[16] = flock;
        modules[17] = address(0); // eigenLayer removed
        modules[18] = governance;
        modules[19] = council;
        modules[20] = multiSig;
        modules[21] = chat;
        modules[22] = points;
        modules[23] = queen;
        modules[24] = registry;
        modules[25] = address(dkms);
        modules[26] = honeyPot;
        _initialized = initialized;
    }

    // ═══ Admin ═══

    function transferOwnership(address newOwner) external {
        require(msg.sender == owner, "Factory: not owner");
        owner = newOwner;
    }

    receive() external payable {}
}
