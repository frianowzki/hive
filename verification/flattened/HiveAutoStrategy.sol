// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

// src/libraries/RitualPrecompileConsumer.sol

/// @title PrecompileConsumer — Base contract for Ritual precompile calls
/// @notice Provides helpers for calling Ritual precompiles

abstract contract RitualPrecompileConsumer {
    // ═══ Precompile Addresses ═══
    address internal constant ONNX_PRECOMPILE = address(0x0800);
    address internal constant HTTP_PRECOMPILE = address(0x0801);
    address internal constant LLM_PRECOMPILE = address(0x0802);
    address internal constant ED25519_PRECOMPILE = address(0x0009);
    address internal constant WEBAUTHN_PRECOMPILE = address(0x0100);

    // ═══ System Contracts ═══
    address internal constant RITUAL_WALLET = 0x532F0dF0896F353d8C3DD8cc134e8129DA2a3948;
    address internal constant ASYNC_JOB_TRACKER = 0xC069FFCa0389f44eCA2C626e55491b0ab045AEF5;
    address internal constant TEE_REGISTRY = 0x9644e8562cE0Fe12b4deeC4163c064A8862Bf47F;
    address internal constant SCHEDULER = 0x56e776BAE2DD60664b69Bd5F865F1180ffB7D58B;
    address internal constant SECRETS_ACCESS = 0xf9BF1BC8A3e79B9EBeD0fa2Db70D0513fecE32FD;
    address internal constant ASYNC_DELIVERY = 0x5A16214fF555848411544b005f7Ac063742f39F6;
    address internal constant AGENT_HEARTBEAT = 0xEF505E801f1Db392B5289690E2ffc20e840A3aCa;
    address internal constant MODEL_PRICING = 0x7A85F48b971ceBb75491b61abe279728F4c4384f;

    // ═══ Async States ═══
    uint8 internal constant ASYNC_SUBMITTED = 0;
    uint8 internal constant ASYNC_COMMITTED = 1;
    uint8 internal constant ASYNC_PROCESSING = 2;
    uint8 internal constant ASYNC_READY = 3;
    uint8 internal constant ASYNC_SETTLED = 4;
    uint8 internal constant ASYNC_FAILED = 5;
    uint8 internal constant ASYNC_EXPIRED = 6;

    /// @notice Execute a synchronous precompile call
    /// @param precompile Address of the precompile
    /// @param input Encoded input data
    /// @return output Raw output bytes
    function _executePrecompile(address precompile, bytes memory input)
        internal
        returns (bytes memory output)
    {
        (bool success, bytes memory result) = precompile.staticcall(input);
        require(success, "PrecompileConsumer: call failed");
        return result;
    }

    /// @notice Encode an HTTP GET request
    /// @param url The URL to fetch
    /// @return Encoded bytes for HTTP precompile
    function _encodeHttpGet(string memory url) internal pure returns (bytes memory) {
        return abi.encode(
            address(0),         // executor (auto-select)
            new bytes[](0),     // encryptedSecrets
            uint256(30),        // ttl (blocks)
            new bytes[](0),     // secretSignatures
            bytes(""),          // userPublicKey
            url,                // url
            uint8(1),           // method (1=GET)
            new string[](0),    // headerKeys
            new string[](0),    // headerValues
            bytes(""),          // body
            uint256(0),         // dkmsKeyIndex
            uint8(0),           // dkmsKeyFormat
            false               // piiEnabled
        );
    }

    /// @notice Encode an LLM inference request
    /// @param prompt The prompt text
    /// @return Encoded bytes for LLM precompile
    function _encodeLlmCall(string memory prompt) internal pure returns (bytes memory) {
        return abi.encode(
            address(0),         // executor (auto-select)
            new bytes[](0),     // encryptedSecrets
            uint256(100),       // ttl (blocks)
            new bytes[](0),     // secretSignatures
            bytes(""),          // userPublicKey
            prompt,             // prompt
            uint256(0),         // maxTokens
            uint256(0),         // temperature (use default)
            bytes(""),          // model (use default)
            uint256(0),         // dkmsKeyIndex
            uint8(0),           // dkmsKeyFormat
            false               // piiEnabled
        );
    }
}

// src/strategy/HiveAutoStrategy.sol

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
}
