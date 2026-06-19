// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {RitualPrecompileConsumer} from "../libraries/RitualPrecompileConsumer.sol";

/// @title HoneyPot — Hive Treasury Management
/// @notice Holds capital, enforces allocation limits, rebalances via LLM

contract HoneyPot is RitualPrecompileConsumer {
    // ═══ State ═══

    address public queen;
    bool public paused;

    struct Allocation {
        uint256 scoutBps;    // Venture allocation (basis points)
        uint256 workerBps;   // Market maker allocation
        uint256 voiceBps;    // Governance allocation
        uint256 reserveBps;  // Emergency reserve
    }

    struct RiskParams {
        uint256 maxDrawdownBps;       // Max drawdown before pause (2000 = 20%)
        uint256 maxPositionBps;       // Max single position (1000 = 10%)
        uint256 maxSingleAssetBps;    // Max in single asset (3000 = 30%)
        uint256 minReserveBps;        // Min reserve (1000 = 10%)
        uint256 drawdownWindow;       // Drawdown measurement window
    }

    Allocation public allocation;
    RiskParams public riskParams;

    uint256 public peakValue;          // Peak HoneyPot value
    uint256 public lastRebalance;      // Last rebalance timestamp
    uint256 public totalInflow;        // Total ETH deposited
    uint256 public totalOutflow;       // Total ETH withdrawn

    mapping(address => uint256) public divisionBalances; // Division balances
    uint256 public reserveBalance;

    // ═══ Events ═══

    event Deposited(address indexed from, uint256 amount);
    event Withdrawn(address indexed to, uint256 amount, string reason);
    event Rebalanced(Allocation newAllocation);
    event RiskTriggered(string reason, uint256 value);
    event PauseToggled(bool paused);

    // ═══ Modifiers ═══

    modifier onlyQueen() {
        require(msg.sender == queen, "HoneyPot: not queen");
        _;
    }

    modifier whenNotPaused() {
        require(!paused, "HoneyPot: paused");
        _;
    }

    // ═══ Constructor ═══

    constructor(address _queen) {
        queen = _queen;

        // Default allocation: 40/40/10/10
        allocation = Allocation({
            scoutBps: 4000,
            workerBps: 4000,
            voiceBps: 1000,
            reserveBps: 1000
        });

        // Default risk params
        riskParams = RiskParams({
            maxDrawdownBps: 2000,      // 20%
            maxPositionBps: 1000,      // 10%
            maxSingleAssetBps: 3000,   // 30%
            minReserveBps: 1000,       // 10%
            drawdownWindow: 1 days
        });
    }

    // ═══ Deposits ═══

    receive() external payable {
        totalInflow += msg.value;
        reserveBalance += msg.value;

        if (address(this).balance > peakValue) {
            peakValue = address(this).balance;
        }

        emit Deposited(msg.sender, msg.value);
    }

    // ═══ Allocation ═══

    /// @notice Get total managed balance
    function totalBalance() public view returns (uint256) {
        return address(this).balance;
    }

    /// @notice Get allocated amount for a division
    function allocatedFor(address division) external view returns (uint256) {
        uint256 total = totalBalance();
        if (division == queen) return (total * allocation.reserveBps) / 10_000;
        // Division-specific allocations would be mapped
        return divisionBalances[division];
    }

    /// @notice Transfer capital to a division (queen only)
    function allocate(address division, uint256 amount) external onlyQueen whenNotPaused {
        require(amount <= reserveBalance, "HoneyPot: insufficient reserve");

        // Check position limits
        uint256 total = totalBalance();
        require(
            divisionBalances[division] + amount <= (total * riskParams.maxPositionBps) / 10_000,
            "HoneyPot: position limit"
        );

        reserveBalance -= amount;
        divisionBalances[division] += amount;

        (bool success, ) = division.call{value: amount}("");
        require(success, "HoneyPot: transfer failed");
    }

    /// @notice Return capital from a division
    function returnCapital(address division, uint256 amount) external {
        require(divisionBalances[division] >= amount, "HoneyPot: insufficient balance");
        divisionBalances[division] -= amount;
        reserveBalance += amount;
    }

    // ═══ Rebalance ═══

    /// @notice Rebalance allocation using LLM
    function rebalance() external onlyQueen {
        string memory prompt = string(abi.encodePacked(
            "You are Hive's treasury manager. Current state: ",
            "Total balance: ", _uint2str(totalBalance()), " wei. ",
            "Reserve: ", _uint2str(reserveBalance), " wei. ",
            "Peak: ", _uint2str(peakValue), " wei. ",
            "Current allocation: Scout=", _uint2str(allocation.scoutBps), "bps, ",
            "Worker=", _uint2str(allocation.workerBps), "bps, ",
            "Voice=", _uint2str(allocation.voiceBps), "bps, ",
            "Reserve=", _uint2str(allocation.reserveBps), "bps. ",
            "Reply with 4 numbers separated by commas: scout,worker,voice,reserve (in bps, must sum to 10000)."
        ));

        bytes memory llmInput = _encodeLlmCall(prompt);
        (bool success, bytes memory output) = LLM_PRECOMPILE.staticcall(llmInput);

        if (success && output.length > 0) {
            string memory response = abi.decode(output, (string));
            (uint256 s, uint256 w, uint256 v, uint256 r) = _parseAllocation(response);

            // Validate
            if (s + w + v + r == 10_000 && s >= 1000 && w >= 1000 && r >= riskParams.minReserveBps) {
                allocation = Allocation({
                    scoutBps: s,
                    workerBps: w,
                    voiceBps: v,
                    reserveBps: r
                });
                lastRebalance = block.timestamp;
                emit Rebalanced(allocation);
            }
        }
    }

    // ═══ Risk Management ═══

    /// @notice Check drawdown and pause if exceeded
    function checkRisk() external {
        uint256 current = totalBalance();
        if (peakValue == 0) return;

        uint256 drawdown = ((peakValue - current) * 10_000) / peakValue;

        if (drawdown >= riskParams.maxDrawdownBps) {
            paused = true;
            emit RiskTriggered("max_drawdown", drawdown);
            emit PauseToggled(true);
        }
    }

    /// @notice Emergency pause
    function emergencyPause() external onlyQueen {
        paused = true;
        emit PauseToggled(true);
    }

    /// @notice Unpause (queen only, after risk resolved)
    function unpause() external onlyQueen {
        paused = false;
        peakValue = totalBalance(); // Reset peak
        emit PauseToggled(false);
    }

    // ═══ Admin ═══

    function setRiskParams(RiskParams calldata params) external onlyQueen {
        riskParams = params;
    }

    function setAllocation(Allocation calldata alloc) external onlyQueen {
        require(alloc.scoutBps + alloc.workerBps + alloc.voiceBps + alloc.reserveBps == 10_000, "HoneyPot: invalid allocation");
        allocation = alloc;
        emit Rebalanced(alloc);
    }

    // ═══ Internal ═══

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

    function _parseAllocation(string memory s) internal pure returns (uint256, uint256, uint256, uint256) {
        bytes memory b = bytes(s);
        uint256[4] memory values;
        uint256 idx = 0;
        uint256 current = 0;

        for (uint256 i = 0; i < b.length; i++) {
            if (b[i] >= '0' && b[i] <= '9') {
                current = current * 10 + (uint8(b[i]) - 48);
            } else if (b[i] == ',' && idx < 3) {
                values[idx++] = current;
                current = 0;
            }
        }
        values[3] = current;

        return (values[0], values[1], values[2], values[3]);
    }
}
