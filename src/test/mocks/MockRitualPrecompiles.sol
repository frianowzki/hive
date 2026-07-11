// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @title MockLLMPrecompile - Simulates Ritual LLM precompile (0x0802) for testing
/// @notice Returns mock JSON responses simulating LLM-generated token metadata
contract MockLLMPrecompile {
    struct LLMRequest {
        address caller;
        string messagesJson;
        string model;
    }

    uint256 public requestCount;
    mapping(uint256 => LLMRequest) public requests;

    // Mock response: token metadata as JSON
    string public mockName;
    string public mockSymbol;
    string public mockLore;

    event InferenceRequested(uint256 indexed requestId, address indexed caller, string model);
    event InferenceFulfilled(uint256 indexed requestId, string response);

    constructor() {
        mockName = "Mock Token";
        mockSymbol = "MOCK";
        mockLore = "A mock token for testing";
    }

    /// @notice Set mock response data
    function setMockResponse(string calldata name_, string calldata symbol_, string calldata lore_) external {
        mockName = name_;
        mockSymbol = symbol_;
        mockLore = lore_;
    }

    /// @notice Simulate LLM inference call
    /// @dev Called by factory contract, returns encoded response
    function infer(bytes calldata input) external returns (uint256 requestId) {
        requestId = requestCount++;

        // Decode the LLM call to extract caller info
        // Input is ABI-encoded: (executor, encryptedSecrets, ttl, ..., messagesJson, model, ...)
        // We just need to log it and return a requestId
        requests[requestId] = LLMRequest({
            caller: msg.sender,
            messagesJson: "", // Would be decoded from input in production
            model: "mock-model"
        });

        emit InferenceRequested(requestId, msg.sender, "mock-model");
    }

    /// @notice Fulfill a pending inference request with mock data
    /// @dev Test helper - simulates the Ritual executor returning results
    function fulfillInference(
        address consumer,
        uint256 requestId,
        string calldata name_,
        string calldata symbol_,
        string calldata lore_
    ) external {
        // Build mock LLM response JSON
        string memory response = string(abi.encodePacked(
            '{"name":"', name_,
            '","symbol":"', symbol_,
            '","lore":"', lore_,
            '"}'
        ));

        // In production, this would be ABI-encoded LLM response
        // For testing, we just call a callback on the consumer
        bytes memory result = abi.encode(response);

        // Simulate the precompile returning the result
        // The actual Ritual flow injects this into spcCalls
        // For mock testing, we call a known callback function
        (bool ok,) = consumer.call(
            abi.encodeWithSignature("onLLMResult(uint256,bytes)", requestId, result)
        );

        emit InferenceFulfilled(requestId, response);
    }

    /// @notice Fallback - return mock response for any call
    fallback() external {
        // Return a mock ABI-encoded LLM response
        // Format: (bool hasError, bytes completionData, bytes modelMetadata, string errorMessage, (string,string,string) updatedConvoHistory)
        string memory mockContent = string(abi.encodePacked(
            '{"name":"', mockName,
            '","symbol":"', mockSymbol,
            '","lore":"', mockLore,
            '"}'
        ));

        bytes memory completionData = abi.encode(mockContent);

        // Revert so the caller knows this mock needs explicit infer() call
        revert("use infer() for mock testing");
    }

    receive() external payable {}
}

/// @title MockHTTPPrecompile - Simulates Ritual HTTP precompile (0x0801) for testing
/// @notice Returns mock HTTP responses
contract MockHTTPPrecompile {
    uint256 public requestCount;
    mapping(uint256 => bytes) public responses;

    event HTTPRequested(uint256 indexed requestId, address indexed caller, string url);
    event HTTPFulfilled(uint256 indexed requestId, uint16 statusCode, string body);

    /// @notice Set mock response for a specific request
    function setMockResponse(uint256 requestId, uint16 statusCode, string calldata body) external {
        responses[requestId] = abi.encode(
            statusCode,
            new string[](0),     // headerKeys
            new string[](0),     // headerValues
            bytes(body),         // body
            ""                   // errorMessage
        );
    }

    /// @notice Fallback - return mock HTTP response
    fallback() external {
        // Revert so the caller knows this mock needs explicit setup
        revert("use setMockResponse() for mock testing");
    }

    receive() external payable {}
}

/// @title MockScheduler - Simulates Ritual Scheduler for testing
/// @notice Allows manual triggering of scheduled tasks
contract MockScheduler {
    struct ScheduledTask {
        address target;
        bytes data;
        uint32 frequency;
        uint32 numCalls;
        bool active;
        uint256 lastExecuted;
    }

    uint256 public taskCount;
    mapping(uint256 => ScheduledTask) public tasks;

    event TaskScheduled(uint256 indexed taskId, address indexed target, uint32 frequency);
    event TaskTriggered(uint256 indexed taskId, address indexed target);

    /// @notice Schedule a task (mock)
    function schedule(
        address target,
        bytes calldata data,
        uint32 frequency,
        uint32 numCalls
    ) external returns (uint256 taskId) {
        taskId = taskCount++;
        tasks[taskId] = ScheduledTask({
            target: target,
            data: data,
            frequency: frequency,
            numCalls: numCalls,
            active: true,
            lastExecuted: block.number
        });

        emit TaskScheduled(taskId, target, frequency);
    }

    /// @notice Manually trigger a scheduled task (test helper)
    function triggerTask(uint256 taskId) external {
        ScheduledTask storage task = tasks[taskId];
        require(task.active, "task not active");

        task.lastExecuted = block.number;

        // Execute the callback
        (bool ok,) = task.target.call(task.data);
        require(ok, "task execution failed");

        emit TaskTriggered(taskId, task.target);
    }

    /// @notice Cancel a scheduled task
    function cancelTask(uint256 taskId) external {
        tasks[taskId].active = false;
    }

    receive() external payable {}
}

/// @title MockAsyncDelivery - Simulates Ritual AsyncDelivery for callback testing
contract MockAsyncDelivery {
    address public constant ASYNC_DELIVERY = 0x5A16214fF555848411544b005f7Ac063742f39F6;

    event CallbackDelivered(address indexed target, bytes32 indexed jobId, bool success);

    /// @notice Deliver a callback to a target contract
    /// @dev Simulates AsyncDelivery.deliver() for testing
    function deliver(
        address target,
        bytes32 jobId,
        bytes calldata result
    ) external returns (bool) {
        // Call the target's callback function
        (bool ok,) = target.call(
            abi.encodeWithSignature("onAgentResult(bytes32,bytes)", jobId, result)
        );

        emit CallbackDelivered(target, jobId, ok);
        return ok;
    }

    receive() external payable {}
}
