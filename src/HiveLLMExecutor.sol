// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @title HiveLLMExecutor - Ritual native LLM via precompile 0x0802
/// @notice Forwards pre-encoded 25-field LLM input to the precompile
/// @dev Encoding is done off-chain; contract forwards + stores raw result
contract HiveLLMExecutor {
    address public constant LLM_PRECOMPILE = 0x0000000000000000000000000000000000000802;

    address public owner;

    struct LLMResponse {
        address requester;
        bool completed;
        bool hasError;
        string result;
        string errorMessage;
    }

    uint256 public requestCount;
    mapping(uint256 => LLMResponse) public responses;
    mapping(address => uint256) public lastRequest;

    event LLMRequested(uint256 indexed requestId, address indexed requester);
    event LLMCompleted(uint256 indexed requestId, string result);
    event LLMFailed(uint256 indexed requestId, string reason);

    constructor() {
        owner = msg.sender;
    }

    /// @notice Execute LLM inference synchronously via precompile
    /// @param llmInput Pre-encoded 25-field ABI bytes (encoded off-chain)
    /// @return requestId ID of the request
    function ask(bytes calldata llmInput) external returns (uint256 requestId) {
        requestId = requestCount++;
        lastRequest[msg.sender] = requestId;

        responses[requestId] = LLMResponse({
            requester: msg.sender,
            completed: false,
            hasError: false,
            result: "",
            errorMessage: ""
        });

        emit LLMRequested(requestId, msg.sender);

        // Forward to LLM precompile
        bytes memory output = _executePrecompile(llmInput);

        // Decode the response entirely in assembly
        (bool hasError, string memory resultText, string memory errorMessage) = _decodeLLMOutput(output);

        responses[requestId].completed = true;
        responses[requestId].hasError = hasError;

        if (hasError) {
            responses[requestId].errorMessage = errorMessage;
            emit LLMFailed(requestId, errorMessage);
        } else {
            responses[requestId].result = resultText;
            emit LLMCompleted(requestId, resultText);
        }
    }

    /// @notice Get response details
    function getResponse(uint256 requestId) external view returns (
        address requester,
        bool completed,
        bool hasError,
        string memory result,
        string memory errorMessage
    ) {
        LLMResponse storage r = responses[requestId];
        return (r.requester, r.completed, r.hasError, r.result, r.errorMessage);
    }

    /// @notice Get the last request for a user
    function getLastRequest(address user) external view returns (uint256) {
        return lastRequest[user];
    }

    /// @dev Forward pre-encoded bytes to LLM precompile
    function _executePrecompile(bytes calldata input) internal returns (bytes memory) {
        address precompile = LLM_PRECOMPILE;
        bytes memory output;
        bytes memory inputMem = new bytes(input.length);
        for (uint256 i = 0; i < input.length; i++) {
            inputMem[i] = input[i];
        }
        assembly {
            let success := call(gas(), precompile, 0, add(inputMem, 0x20), mload(inputMem), 0, 0)
            returndatacopy(0, 0, returndatasize())
            if iszero(success) {
                revert(0, returndatasize())
            }
            output := mload(0)
        }
        return output;
    }

    /// @dev Decode LLM output: (bool, bytes, bytes, string, (string,string,string))
    /// Returns (hasError, completionText, errorMessage)
    function _decodeLLMOutput(bytes memory output) internal pure returns (
        bool hasError,
        string memory resultText,
        string memory errorMessage
    ) {
        // The output is ABI-encoded as a 5-element tuple
        // We read each field's offset/value from the output
        assembly {
            // Field 0: bool hasError (at offset 0, value in first 32 bytes)
            hasError := eq(mload(add(output, 32)), 1)

            // Field 1: offset to bytes completionData
            let compDataOff := mload(add(output, 64))
            // Read the bytes data (length + data)
            let compDataLen := mload(add(add(output, 32), compDataOff))

            // Field 3: offset to string errorMessage
            let errOff := mload(add(output, 128))
            let errLen := mload(add(add(output, 32), errOff))

            // Extract errorMessage
            errorMessage := ""
            if gt(errLen, 0) {
                let errPtr := add(add(output, 32), add(errOff, 32))
                errorMessage := mload(errPtr)
            }

            // Extract completionData as bytes, then try to decode as string
            resultText := ""
            if gt(compDataLen, 0) {
                // completionData is abi.encode(string completionText)
                // So it's: [32-byte offset][32-byte length][string data]
                // The offset points to where the string starts within completionData
                let innerOff := mload(add(add(output, 32), add(compDataOff, 32)))
                let innerLen := mload(add(add(output, 32), add(compDataOff, add(32, innerOff))))

                if gt(innerLen, 0) {
                    let strPtr := add(add(output, 32), add(compDataOff, add(64, innerOff)))
                    resultText := mload(strPtr)
                }
            }
        }
    }

    receive() external payable {}
}
