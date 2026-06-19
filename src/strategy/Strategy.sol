// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {RitualPrecompileConsumer} from "../libraries/RitualPrecompileConsumer.sol";

/// @title Strategy — LLM Strategy Engine
/// @notice Generates and executes strategies via Ritual LLM precompile

contract Strategy is RitualPrecompileConsumer {
    // ═══ State ═══

    address public queen;

    enum ActionType { Invest, Trade, Vote, Rebalance, SpawnDrone, DoNothing }

    struct Action {
        ActionType actionType;
        address target;        // Target contract/address
        uint256 value;         // ETH to send
        bytes data;            // Calldata
        string reasoning;      // LLM reasoning
    }

    struct StrategyCycle {
        uint256 blockNumber;
        uint256 timestamp;
        string stateHash;      // Hash of current state
        Action[] actions;
        bool executed;
    }

    StrategyCycle[] public cycles;
    uint256 public cycleCount;

    // Performance tracking
    uint256 public totalCycles;
    uint256 public successfulActions;
    uint256 public failedActions;

    // ═══ Events ═══

    event CycleStarted(uint256 indexed cycleId, uint256 blockNumber);
    event ActionExecuted(uint256 indexed cycleId, ActionType actionType, address target, bool success);
    event CycleCompleted(uint256 indexed cycleId, uint256 actionsExecuted);

    // ═══ Modifiers ═══

    modifier onlyQueen() {
        require(msg.sender == queen, "Strategy: not queen");
        _;
    }

    // ═══ Constructor ═══

    constructor(address _queen) {
        queen = _queen;
    }

    // ═══ Strategy Generation ═══

    /// @notice Generate a strategy cycle using LLM
    function generateStrategy(string calldata currentState) external onlyQueen returns (uint256 cycleId) {
        cycleId = cycleCount++;

        string memory prompt = string(abi.encodePacked(
            "You are Hive, a sovereign AI agent on Ritual Chain. ",
            "Current state: ", currentState, ". ",
            "Generate an action plan. Reply with JSON: ",
            '{"actions": [{"type": "invest|trade|vote|rebalance|spawn|nothing", ',
            '"target": "0x...", "value": 0, "data": "0x", ',
            '"reasoning": "..."}]}'
        ));

        bytes memory llmInput = _encodeLlmCall(prompt);
        (bool success, bytes memory output) = LLM_PRECOMPILE.staticcall(llmInput);

        Action[] memory actions;

        if (success && output.length > 0) {
            string memory response = abi.decode(output, (string));
            actions = _parseActions(response);
        } else {
            // Fallback: do nothing
            actions = new Action[](1);
            actions[0] = Action({
                actionType: ActionType.DoNothing,
                target: address(0),
                value: 0,
                data: "",
                reasoning: "LLM unavailable"
            });
        }

        cycles.push(StrategyCycle({
            blockNumber: block.number,
            timestamp: block.timestamp,
            stateHash: "",
            actions: actions,
            executed: false
        }));

        emit CycleStarted(cycleId, block.number);
    }

    // ═══ Execution ═══

    /// @notice Execute a strategy cycle
    function executeCycle(uint256 cycleId) external onlyQueen {
        require(cycleId < cycleCount, "Strategy: invalid cycle");
        StrategyCycle storage cycle = cycles[cycleId];
        require(!cycle.executed, "Strategy: already executed");

        uint256 executed = 0;

        for (uint256 i = 0; i < cycle.actions.length; i++) {
            Action memory action = cycle.actions[i];

            if (action.actionType == ActionType.DoNothing) {
                continue;
            }

            bool success = false;

            if (action.target != address(0)) {
                (success, ) = action.target.call{value: action.value}(action.data);
            }

            if (success) {
                successfulActions++;
            } else {
                failedActions++;
            }

            emit ActionExecuted(cycleId, action.actionType, action.target, success);
            executed++;
        }

        cycle.executed = true;
        totalCycles++;

        emit CycleCompleted(cycleId, executed);
    }

    // ═══ View ═══

    function getCycle(uint256 cycleId) external view returns (StrategyCycle memory) {
        require(cycleId < cycleCount, "Strategy: invalid cycle");
        return cycles[cycleId];
    }

    function getCycleActions(uint256 cycleId) external view returns (Action[] memory) {
        require(cycleId < cycleCount, "Strategy: invalid cycle");
        return cycles[cycleId].actions;
    }

    function successRate() external view returns (uint256) {
        uint256 total = successfulActions + failedActions;
        if (total == 0) return 0;
        return (successfulActions * 10_000) / total;
    }

    // ═══ Internal ═══

    function _parseActions(string memory response) internal pure returns (Action[] memory) {
        // Simple parser: extract action type from response
        // In production, this would use JQ precompile or more robust parsing
        bytes memory b = bytes(response);
        Action[] memory actions = new Action[](1);

        ActionType actionType = ActionType.DoNothing;

        if (_contains(response, "invest")) {
            actionType = ActionType.Invest;
        } else if (_contains(response, "trade")) {
            actionType = ActionType.Trade;
        } else if (_contains(response, "vote")) {
            actionType = ActionType.Vote;
        } else if (_contains(response, "rebalance")) {
            actionType = ActionType.Rebalance;
        } else if (_contains(response, "spawn")) {
            actionType = ActionType.SpawnDrone;
        }

        actions[0] = Action({
            actionType: actionType,
            target: address(0),
            value: 0,
            data: "",
            reasoning: response
        });

        return actions;
    }

    function _contains(string memory s, string memory sub) internal pure returns (bool) {
        bytes memory sb = bytes(s);
        bytes memory subb = bytes(sub);

        if (subb.length > sb.length) return false;

        for (uint256 i = 0; i <= sb.length - subb.length; i++) {
            bool found = true;
            for (uint256 j = 0; j < subb.length; j++) {
                if (sb[i + j] != subb[j]) {
                    found = false;
                    break;
                }
            }
            if (found) return true;
        }
        return false;
    }
}
