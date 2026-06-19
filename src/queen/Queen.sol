// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {RitualPrecompileConsumer} from "../libraries/RitualPrecompileConsumer.sol";

/// @title Queen — Hive Sovereign Agent Brain
/// @notice The central orchestrator: holds treasury, spawns drones, runs strategy cycles
/// @dev Refactored to use interfaces — dependencies deployed separately and wired via constructor

interface IHoneyPot {
    function allocate(address to, uint256 amount) external;
    function balanceOf(address account) external view returns (uint256);
}

interface IQueenStrategy {
    function generateStrategy(string calldata state) external returns (uint256);
    function executeCycle(uint256 cycleId) external;
}

interface IDrone {
    function returnProfits() external;
    function terminate() external;
    function purpose() external view returns (string memory);
    function droneType() external view returns (uint8);
    function alive() external view returns (bool);
}

interface IHiveRegistry {
    function register(string calldata name, uint256 interval) external;
    function heartbeat() external;
}

interface IHiveLaunchPad {
    function createSale(
        address project, address token, uint256 price,
        uint256 hardCap, uint256 softCap, uint256 minBuy, uint256 maxBuy,
        uint256 startTime, uint256 endTime,
        uint256 vestingCliff, uint256 vestingDuration, bool whitelistOnly
    ) external returns (uint256);
}

interface IHiveMarketMaker {
    function createPool(address token, uint256 spreadBps, uint256 feeBps) external;
}

interface IHiveCouncil {
    function propose(
        string calldata title, string calldata description,
        uint8 proposalType, address target, bytes calldata executionData
    ) external returns (uint256);
}

contract Queen is RitualPrecompileConsumer {
    // ═══ State ═══

    address public owner;
    string public name;
    uint256 public birthBlock;
    uint256 public lastCycleBlock;
    uint256 public cycleInterval;

    // Division addresses (wired externally)
    IHoneyPot public honeypot;
    IQueenStrategy public strategy;
    IHiveRegistry public registry;
    IHiveLaunchPad public launchPad;
    IHiveMarketMaker public marketMaker;
    IHiveCouncil public council;

    // AI Layer references
    address public brain;           // HiveBrain
    address public oracle;          // HiveOracle
    address public flock;           // HiveFLock

    // Drones
    address[] public drones;
    uint256 public droneCount;

    // Lifecycle
    bool public alive;
    bool public hibernating;
    uint256 public totalCycles;

    // Timelock for critical operations
    uint256 public constant TIMELOCK_DELAY = 24 hours;
    mapping(bytes32 => uint256) public pendingActions; // action hash => execute after

    // ═══ Events ═══

    event Born(string name, uint256 blockNumber);
    event CycleExecuted(uint256 indexed cycleId, uint256 actionsCount);
    event DroneSpawned(address indexed drone, string purpose);
    event Upgraded(address indexed newStrategy);
    event Hibernated(bool status);
    event Died(string reason);
    event ActionScheduled(bytes32 indexed actionHash, uint256 executeAfter);
    event DivisionSet(string name, address addr);

    // ═══ Constructor ═══

    constructor(
        string memory _name,
        uint256 _cycleInterval,
        address _honeypot,
        address _strategy,
        address _registry,
        address _launchPad,
        address _marketMaker,
        address _council
    ) payable {
        owner = msg.sender;
        name = _name;
        birthBlock = block.number;
        cycleInterval = _cycleInterval > 0 ? _cycleInterval : 100;
        alive = true;

        // Wire divisions
        if (_honeypot != address(0)) honeypot = IHoneyPot(_honeypot);
        if (_strategy != address(0)) strategy = IQueenStrategy(_strategy);
        if (_registry != address(0)) registry = IHiveRegistry(_registry);
        if (_launchPad != address(0)) launchPad = IHiveLaunchPad(_launchPad);
        if (_marketMaker != address(0)) marketMaker = IHiveMarketMaker(_marketMaker);
        if (_council != address(0)) council = IHiveCouncil(_council);

        // Register self
        if (address(registry) != address(0)) {
            registry.register(name, cycleInterval);
        }

        // Fund honeypot
        if (msg.value > 0 && address(honeypot) != address(0)) {
            (bool success, ) = address(honeypot).call{value: msg.value}("");
            require(success, "Queen: honeypot funding failed");
        }

        emit Born(name, block.number);
    }

    // ═══ Division Wiring ═══

    function setDivision(string calldata divName, address addr) external onlyOwner {
        if (keccak256(bytes(divName)) == keccak256("honeypot")) honeypot = IHoneyPot(addr);
        else if (keccak256(bytes(divName)) == keccak256("strategy")) strategy = IQueenStrategy(addr);
        else if (keccak256(bytes(divName)) == keccak256("registry")) registry = IHiveRegistry(addr);
        else if (keccak256(bytes(divName)) == keccak256("launchPad")) launchPad = IHiveLaunchPad(addr);
        else if (keccak256(bytes(divName)) == keccak256("marketMaker")) marketMaker = IHiveMarketMaker(addr);
        else if (keccak256(bytes(divName)) == keccak256("council")) council = IHiveCouncil(addr);
        else if (keccak256(bytes(divName)) == keccak256("brain")) brain = addr;
        else if (keccak256(bytes(divName)) == keccak256("oracle")) oracle = addr;
        else if (keccak256(bytes(divName)) == keccak256("flock")) flock = addr;
        else revert("Queen: unknown division");
        emit DivisionSet(divName, addr);
    }

    // ═══ Strategy Cycle ═══

    function runCycle() external {
        require(alive, "Queen: not alive");
        require(!hibernating, "Queen: hibernating");
        require(block.number >= lastCycleBlock + cycleInterval, "Queen: too early");

        lastCycleBlock = block.number;
        totalCycles++;

        string memory currentState = _buildState();

        // Ask Brain to think (if wired)
        if (brain != address(0)) {
            (bool _ok, ) = brain.call(
                abi.encodeWithSignature("think(string)", currentState)
            );
            _ok;
        }

        uint256 cycleId = strategy.generateStrategy(currentState);
        strategy.executeCycle(cycleId);

        if (address(registry) != address(0)) {
            registry.heartbeat();
        }

        emit CycleExecuted(cycleId, 0);
    }

    // ═══ AI Integration ═══

    function getOraclePrice(address token) external returns (uint256 price) {
        require(msg.sender == owner, "Queen: not owner");
        require(oracle != address(0), "Queen: no oracle");
        (bool success, bytes memory data) = oracle.staticcall(
            abi.encodeWithSignature("getBestPrice(address)", token)
        );
        if (success && data.length >= 32) {
            price = abi.decode(data, (uint256));
        }
    }

    function think(string calldata context) external returns (uint256 thoughtId) {
        require(msg.sender == owner, "Queen: not owner");
        require(brain != address(0), "Queen: no brain");
        (bool success, bytes memory data) = brain.call(
            abi.encodeWithSignature("think(string)", context)
        );
        if (success && data.length >= 32) {
            thoughtId = abi.decode(data, (uint256));
        }
    }

    // ═══ Drone Management ═══

    function spawnDrone(
        string calldata purpose,
        uint8 droneType,
        uint256 capital
    ) external onlyOwner returns (address droneAddress) {
        // Drone must be deployed externally and added via addDrone
        revert("Queen: deploy drone externally, then addDrone()");
    }

    function addDrone(address drone) external onlyOwner {
        drones.push(drone);
        droneCount++;
        emit DroneSpawned(drone, "added");
    }

    function recallDrone(uint256 droneIdx) external onlyOwner {
        require(droneIdx < droneCount, "Queen: invalid drone");
        IDrone(drones[droneIdx]).returnProfits();
    }

    function terminateDrone(uint256 droneIdx) external onlyOwner {
        require(droneIdx < droneCount, "Queen: invalid drone");
        IDrone(drones[droneIdx]).terminate();
    }

    // ═══ Division Operations ═══

    function allocateToDivision(address division, uint256 amount) external onlyOwner {
        honeypot.allocate(division, amount);
    }

    function createSale(
        address project, address token, uint256 price,
        uint256 hardCap, uint256 softCap, uint256 minBuy, uint256 maxBuy,
        uint256 startTime, uint256 endTime,
        uint256 vestingCliff, uint256 vestingDuration, bool whitelistOnly
    ) external onlyOwner returns (uint256) {
        return launchPad.createSale(
            project, token, price, hardCap, softCap,
            minBuy, maxBuy, startTime, endTime,
            vestingCliff, vestingDuration, whitelistOnly
        );
    }

    function createPool(address token, uint256 spreadBps, uint256 feeBps) external onlyOwner {
        marketMaker.createPool(token, spreadBps, feeBps);
    }

    function propose(
        string calldata title, string calldata description,
        uint8 proposalType, address target, bytes calldata executionData
    ) external onlyOwner returns (uint256) {
        return council.propose(title, description, proposalType, target, executionData);
    }

    // ═══ Lifecycle ═══

    function hibernate() external onlyOwner {
        hibernating = true;
        emit Hibernated(true);
    }

    function wake() external onlyOwner {
        hibernating = false;
        if (address(registry) != address(0)) registry.heartbeat();
        emit Hibernated(false);
    }

    /// @notice Schedule Queen shutdown (timelocked)
    function scheduleShutdown(string calldata reason) external onlyOwner {
        bytes32 actionHash = keccak256(abi.encodePacked("shutdown", reason));
        pendingActions[actionHash] = block.timestamp + TIMELOCK_DELAY;
        emit ActionScheduled(actionHash, block.timestamp + TIMELOCK_DELAY);
    }

    /// @notice Execute scheduled shutdown
    function executeShutdown(string calldata reason) external onlyOwner {
        bytes32 actionHash = keccak256(abi.encodePacked("shutdown", reason));
        require(pendingActions[actionHash] > 0, "Queen: not scheduled");
        require(block.timestamp >= pendingActions[actionHash], "Queen: timelock active");
        require(block.timestamp <= pendingActions[actionHash] + 24 hours, "Queen: expired");

        delete pendingActions[actionHash];
        alive = false;
        hibernating = false;
        uint256 balance = address(this).balance;
        if (balance > 0) {
            (bool success, ) = owner.call{value: balance}("");
            require(success, "Queen: transfer failed");
        }
        emit Died(reason);
    }

    /// @notice Emergency die (only if not alive — already shut down)
    function die(string memory reason) external onlyOwner {
        require(!alive, "Queen: use scheduleShutdown for live queens");
        hibernating = false;
        uint256 balance = address(this).balance;
        if (balance > 0) {
            (bool success, ) = owner.call{value: balance}("");
            require(success, "Queen: transfer failed");
        }
        emit Died(reason);
    }

    function selfUpgrade() external onlyOwner {
        string memory prompt = string(abi.encodePacked(
            "You are Hive. Current state: ", _buildState(), ". ",
            "Analyze your performance and suggest improvements."
        ));
        bytes memory llmInput = _encodeLlmCall(prompt);
        (bool success, bytes memory output) = LLM_PRECOMPILE.staticcall(llmInput);
        if (success && output.length > 0) {
            emit Upgraded(address(strategy));
        }
    }

    // ═══ Internal ═══

    function _buildState() internal view returns (string memory) {
        return string(abi.encodePacked(
            "Queen balance: ", _uint2str(address(this).balance), " wei. ",
            "Drones: ", _uint2str(droneCount), ". ",
            "Cycles: ", _uint2str(totalCycles), ". ",
            "Block: ", _uint2str(block.number), ". ",
            "Alive: ", alive ? "yes" : "no"
        ));
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

    // ═══ Modifiers ═══

    modifier onlyOwner() {
        require(msg.sender == owner, "Queen: not owner");
        _;
    }

    // ═══ View ═══

    function hiveBalance() external view returns (uint256) {
        uint256 potBal = address(honeypot) != address(0) ? address(honeypot).balance : 0;
        return potBal + address(this).balance;
    }

    function getDrone(uint256 idx) external view returns (address) {
        require(idx < droneCount, "Queen: invalid drone");
        return drones[idx];
    }

    receive() external payable {}

    // ═══ Ownership ═══

    /// @notice Transfer ownership to a new address
    function transferOwnership(address newOwner) external onlyOwner {
        require(newOwner != address(0), "zero address");
        owner = newOwner;
    }

}
