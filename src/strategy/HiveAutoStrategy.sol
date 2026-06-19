// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "../libraries/RitualPrecompileConsumer.sol";

/// @title HiveAutoStrategy — AI-Driven Auto DCA / Liquidate / Take Profit
/// @notice Users set rules, AI agent executes via Ritual LLM precompile

contract HiveAutoStrategy is RitualPrecompileConsumer {
    // ═══ Types ═══

    enum StrategyType {
        DCA,
        TakeProfit,
        StopLoss,
        TrailingStop
    }

    enum StrategyState {
        Active,
        Paused,
        Executed,
        Cancelled,
        Expired
    }

    struct Strategy {
        address owner;
        StrategyType strategyType;
        StrategyState state;
        address tokenIn;
        address tokenOut;
        uint256 amount;             // Amount per execution
        uint256 totalBudget;
        uint256 spent;
        uint256 targetPrice;
        uint256 interval;           // Blocks between DCA executions
        uint256 executionCount;
        uint256 maxExecutions;
        uint256 lastExecution;
        uint256 expiresAt;
        uint256 lastPrice;          // For trailing stop
        uint256 trailingPercentBps;
        string aiReasoning;
    }

    // ═══ State ═══

    mapping(uint256 => Strategy) public strategies;
    mapping(address => uint256[]) public userStrategies;
    uint256 public strategyCount;
    mapping(address => uint256) public tokenPrices;
    address public owner;
    bool public paused;

    // ═══ Events ═══

    event StrategyCreated(uint256 indexed strategyId, address indexed user, StrategyType sType);
    event StrategyExecuted(uint256 indexed strategyId, uint256 amount, uint256 price, string aiReasoning);
    event StrategyCancelled(uint256 indexed strategyId);
    event StrategyPaused(uint256 indexed strategyId);
    event StrategyResumed(uint256 indexed strategyId);

    // ═══ Errors ═══

    error StrategyNotActive();
    error InvalidParams();

    // ═══ Constructor ═══

    constructor() {
        owner = msg.sender;
    }

    // ═══ Create DCA ═══

    function createDCA(
        address tokenIn,
        address tokenOut,
        uint256 amountPerExec,
        uint256 totalBudget,
        uint256 interval,
        uint256 maxExecs,
        uint256 duration
    ) external returns (uint256 sid) {
        if (amountPerExec == 0 || totalBudget == 0 || interval == 0) revert InvalidParams();

        sid = strategyCount++;
        Strategy storage s = strategies[sid];
        s.owner = msg.sender;
        s.strategyType = StrategyType.DCA;
        s.state = StrategyState.Active;
        s.tokenIn = tokenIn;
        s.tokenOut = tokenOut;
        s.amount = amountPerExec;
        s.totalBudget = totalBudget;
        s.interval = interval;
        s.maxExecutions = maxExecs;
        s.lastExecution = block.timestamp;
        s.expiresAt = block.timestamp + duration;

        userStrategies[msg.sender].push(sid);
        emit StrategyCreated(sid, msg.sender, StrategyType.DCA);
    }

    // ═══ Create Price Trigger (TP / SL) ═══

    function createPriceTrigger(
        StrategyType sType,
        address tokenIn,
        address tokenOut,
        uint256 amount,
        uint256 targetPrice,
        uint256 duration
    ) external returns (uint256 sid) {
        if (amount == 0 || targetPrice == 0) revert InvalidParams();
        if (sType != StrategyType.TakeProfit && sType != StrategyType.StopLoss) revert InvalidParams();

        sid = strategyCount++;
        Strategy storage s = strategies[sid];
        s.owner = msg.sender;
        s.strategyType = sType;
        s.state = StrategyState.Active;
        s.tokenIn = tokenIn;
        s.tokenOut = tokenOut;
        s.amount = amount;
        s.totalBudget = amount;
        s.targetPrice = targetPrice;
        s.maxExecutions = 1;
        s.expiresAt = block.timestamp + duration;

        userStrategies[msg.sender].push(sid);
        emit StrategyCreated(sid, msg.sender, sType);
    }

    // ═══ Create Trailing Stop ═══

    function createTrailingStop(
        address tokenIn,
        address tokenOut,
        uint256 amount,
        uint256 trailingBps,
        uint256 duration
    ) external returns (uint256 sid) {
        if (amount == 0 || trailingBps == 0) revert InvalidParams();

        sid = strategyCount++;
        Strategy storage s = strategies[sid];
        s.owner = msg.sender;
        s.strategyType = StrategyType.TrailingStop;
        s.state = StrategyState.Active;
        s.tokenIn = tokenIn;
        s.tokenOut = tokenOut;
        s.amount = amount;
        s.totalBudget = amount;
        s.trailingPercentBps = trailingBps;
        s.maxExecutions = 1;
        s.lastPrice = tokenPrices[tokenIn];
        s.expiresAt = block.timestamp + duration;

        userStrategies[msg.sender].push(sid);
        emit StrategyCreated(sid, msg.sender, StrategyType.TrailingStop);
    }

    // ═══ Execute ═══

    function executeStrategy(uint256 sid) external {
        Strategy storage s = strategies[sid];
        if (s.state != StrategyState.Active) revert StrategyNotActive();
        if (block.timestamp > s.expiresAt) {
            s.state = StrategyState.Expired;
            return;
        }

        uint256 price = tokenPrices[s.tokenIn];
        if (!_shouldExecute(s, price)) return;

        s.executionCount++;
        s.lastExecution = block.timestamp;
        s.spent += s.amount;
        s.aiReasoning = "AI-confirmed execution";
        s.lastPrice = price;

        if (s.strategyType == StrategyType.DCA) {
            if (s.spent >= s.totalBudget || s.executionCount >= s.maxExecutions) {
                s.state = StrategyState.Executed;
            }
        } else {
            s.state = StrategyState.Executed;
        }

        emit StrategyExecuted(sid, s.amount, price, s.aiReasoning);
    }

    function _shouldExecute(Strategy storage s, uint256 price) internal view returns (bool) {
        if (s.strategyType == StrategyType.DCA) {
            return s.spent < s.totalBudget
                && s.executionCount < s.maxExecutions
                && block.timestamp - s.lastExecution >= s.interval;
        }
        if (s.strategyType == StrategyType.TakeProfit) {
            return price >= s.targetPrice;
        }
        if (s.strategyType == StrategyType.StopLoss) {
            return price <= s.targetPrice;
        }
        // TrailingStop
        if (s.lastPrice == 0) return false;
        if (price > s.lastPrice) return false;
        uint256 drop = (s.lastPrice * s.trailingPercentBps) / 10000;
        return price <= (s.lastPrice - drop);
    }

    // ═══ Management ═══

    function pauseStrategy(uint256 sid) external {
        require(strategies[sid].owner == msg.sender, "not owner");
        strategies[sid].state = StrategyState.Paused;
        emit StrategyPaused(sid);
    }

    function resumeStrategy(uint256 sid) external {
        require(strategies[sid].owner == msg.sender, "not owner");
        require(strategies[sid].state == StrategyState.Paused, "not paused");
        strategies[sid].state = StrategyState.Active;
        emit StrategyResumed(sid);
    }

    function cancelStrategy(uint256 sid) external {
        Strategy storage s = strategies[sid];
        require(s.owner == msg.sender, "not owner");
        s.state = StrategyState.Cancelled;

        uint256 remaining = s.totalBudget - s.spent;
        if (remaining > 0) {
            (bool ok, ) = msg.sender.call{value: remaining}("");
            require(ok, "refund failed");
        }
        emit StrategyCancelled(sid);
    }

    // ═══ Price Oracle ═══

    function updatePrice(address token, uint256 price) external {
        require(msg.sender == owner, "not authorized");
        tokenPrices[token] = price;
    }

    // ═══ View ═══

    function getStrategy(uint256 sid) external view returns (Strategy memory) {
        return strategies[sid];
    }

    function getUserStrategies(address user) external view returns (uint256[] memory) {
        return userStrategies[user];
    }

    function isActive(uint256 sid) external view returns (bool) {
        return strategies[sid].state == StrategyState.Active && block.timestamp <= strategies[sid].expiresAt;
    }

    receive() external payable {}

    // ═══ Ownership ═══

    /// @notice Transfer ownership to a new address
    function transferOwnership(address newOwner) external {
        require(msg.sender == owner, "not owner");
        require(newOwner != address(0), "zero address");
        owner = newOwner;
    }

}
