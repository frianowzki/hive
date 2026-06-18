// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {RitualPrecompileConsumer} from "../libraries/RitualPrecompileConsumer.sol";
import {HoneyPot} from "../treasury/HoneyPot.sol";
import {Strategy} from "../strategy/Strategy.sol";
import {Drone} from "../drone/Drone.sol";
import {HiveRegistry} from "../registry/HiveRegistry.sol";
import {HiveLaunchPad} from "../launch/HiveLaunchPad.sol";
import {HiveMarketMaker} from "../maker/HiveMarketMaker.sol";
import {HiveCouncil} from "../council/HiveCouncil.sol";

/// @title Queen — Hive Sovereign Agent Brain
/// @notice The central orchestrator: holds treasury, spawns drones, runs strategy cycles

contract Queen is RitualPrecompileConsumer {
    // ═══ State ═══

    address public owner;
    string public name;
    uint256 public birthBlock;
    uint256 public lastCycleBlock;
    uint256 public cycleInterval; // blocks between cycles

    // Divisions
    HoneyPot public honeypot;
    Strategy public strategy;
    HiveRegistry public registry;
    HiveLaunchPad public launchPad;
    HiveMarketMaker public marketMaker;
    HiveCouncil public council;

    // Drones
    Drone[] public drones;
    uint256 public droneCount;

    // Lifecycle
    bool public alive;
    bool public hibernating;
    uint256 public totalCycles;

    // ═══ Events ═══

    event Born(string name, uint256 blockNumber);
    event CycleExecuted(uint256 indexed cycleId, uint256 actionsCount);
    event DroneSpawned(address indexed drone, string purpose);
    event Upgraded(address indexed newStrategy);
    event Hibernated(bool status);
    event Died(string reason);

    // ═══ Constructor ═══

    constructor(
        string memory _name,
        uint256 _cycleInterval
    ) payable {
        owner = msg.sender;
        name = _name;
        birthBlock = block.number;
        cycleInterval = _cycleInterval > 0 ? _cycleInterval : 100; // default 100 blocks
        alive = true;

        // Deploy divisions
        registry = new HiveRegistry();
        honeypot = new HoneyPot(address(this));
        strategy = new Strategy(address(this));
        launchPad = new HiveLaunchPad(address(0)); // points not needed for now
        marketMaker = new HiveMarketMaker(address(0));
        council = new HiveCouncil(address(0));

        // Register self
        registry.register(name, cycleInterval);

        // Fund honeypot
        if (msg.value > 0) {
            (bool success, ) = address(honeypot).call{value: msg.value}("");
            require(success, "Queen: honeypot funding failed");
        }

        emit Born(name, block.number);
    }

    // ═══ Strategy Cycle ═══

    /// @notice Run a strategy cycle (called by Scheduler or manually)
    function runCycle() external {
        require(alive, "Queen: not alive");
        require(!hibernating, "Queen: hibernating");
        require(
            block.number >= lastCycleBlock + cycleInterval,
            "Queen: too early"
        );

        lastCycleBlock = block.number;
        totalCycles++;

        // Build current state for LLM
        string memory currentState = _buildState();

        // Generate strategy
        uint256 cycleId = strategy.generateStrategy(currentState);

        // Execute strategy
        strategy.executeCycle(cycleId);

        // Heartbeat
        registry.heartbeat();

        emit CycleExecuted(cycleId, 0);
    }

    // ═══ Drone Management ═══

    /// @notice Spawn a new drone
    function spawnDrone(
        string calldata purpose,
        Drone.DroneType droneType,
        uint256 capital
    ) external onlyOwner returns (address droneAddress) {
        Drone drone = new Drone{value: capital}(
            address(this),
            purpose,
            droneType,
            capital
        );

        droneAddress = address(drone);
        drones.push(drone);
        droneCount++;

        emit DroneSpawned(droneAddress, purpose);
    }

    /// @notice Recall drone (returns profits)
    function recallDrone(uint256 droneIdx) external onlyOwner {
        require(droneIdx < droneCount, "Queen: invalid drone");
        Drone drone = drones[droneIdx];
        drone.returnProfits();
    }

    /// @notice Terminate drone
    function terminateDrone(uint256 droneIdx) external onlyOwner {
        require(droneIdx < droneCount, "Queen: invalid drone");
        Drone drone = drones[droneIdx];
        drone.terminate();
    }

    // ═══ Division Operations ═══

    /// @notice Allocate capital to a division
    function allocateToDivision(address division, uint256 amount) external onlyOwner {
        honeypot.allocate(division, amount);
    }

    /// @notice Create a token sale
    function createSale(
        address project,
        address token,
        uint256 price,
        uint256 hardCap,
        uint256 softCap,
        uint256 minBuy,
        uint256 maxBuy,
        uint256 startTime,
        uint256 endTime,
        uint256 vestingCliff,
        uint256 vestingDuration,
        bool whitelistOnly
    ) external onlyOwner returns (uint256) {
        return launchPad.createSale(
            project, token, price, hardCap, softCap,
            minBuy, maxBuy, startTime, endTime,
            vestingCliff, vestingDuration, whitelistOnly
        );
    }

    /// @notice Create a liquidity pool
    function createPool(address token, uint256 spreadBps, uint256 feeBps) external onlyOwner {
        marketMaker.createPool(token, spreadBps, feeBps);
    }

    /// @notice Create a governance proposal
    function propose(
        string calldata title,
        string calldata description,
        HiveCouncil.ProposalType proposalType,
        address target,
        bytes calldata executionData
    ) external onlyOwner returns (uint256) {
        return council.propose(title, description, proposalType, target, executionData);
    }

    // ═══ Lifecycle ═══

    /// @notice Hibernate (pause operations)
    function hibernate() external onlyOwner {
        hibernating = true;
        emit Hibernated(true);
    }

    /// @notice Wake from hibernation
    function wake() external onlyOwner {
        hibernating = false;
        registry.heartbeat();
        emit Hibernated(false);
    }

    /// @notice Wind down permanently
    function die(string memory reason) external onlyOwner {
        alive = false;
        hibernating = false;

        // Return all funds to owner
        uint256 balance = address(this).balance;
        if (balance > 0) {
            (bool success, ) = owner.call{value: balance}("");
            require(success, "Queen: transfer failed");
        }

        emit Died(reason);
    }

    /// @notice Self-upgrade: deploy new strategy and migrate
    function selfUpgrade() external onlyOwner {
        // Generate upgrade plan via LLM
        string memory prompt = string(abi.encodePacked(
            "You are Hive. Current state: ", _buildState(), ". ",
            "Analyze your performance and suggest improvements. ",
            "Reply with: {improvements: [...], reasoning: ...}"
        ));

        bytes memory llmInput = _encodeLlmCall(prompt);
        (bool success, bytes memory output) = LLM_PRECOMPILE.staticcall(llmInput);

        if (success && output.length > 0) {
            string memory improvements = abi.decode(output, (string));
            // Store upgrade reasoning (in production, deploy new strategy contract)
            emit Upgraded(address(strategy));
        }
    }

    // ═══ Internal ═══

    function _buildState() internal view returns (string memory) {
        return string(abi.encodePacked(
            "HoneyPot balance: ", _uint2str(address(honeypot).balance), " wei. ",
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
        return address(honeypot).balance + address(this).balance;
    }

    function getDrone(uint256 idx) external view returns (Drone) {
        require(idx < droneCount, "Queen: invalid drone");
        return drones[idx];
    }

    receive() external payable {}
}
