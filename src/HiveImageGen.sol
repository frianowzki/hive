// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @title HiveImageGen - Ritual native image generation with async callback
/// @notice Calls the image generation precompile and receives results via AsyncDelivery
/// @dev Uses 18-field ABI encoding per Ritual Multimodal Processing spec
contract HiveImageGen {
    // --- Ritual System Contracts ---
    address public constant IMAGE_GEN_PRECOMPILE = 0x0000000000000000000000000000000000000818;
    address public constant ASYNC_DELIVERY = 0x5A16214fF555848411544b005f7Ac063742f39F6;
    address public constant TEESERVICE_REGISTRY = 0x9644e8562cE0Fe12b4deeC4163c064A8862Bf47F;

    // --- State ---
    address public owner;

    struct ImageRequest {
        address requester;      // who requested the image
        string prompt;          // the generation prompt
        string model;           // model used (e.g., "dall-e-3")
        uint256 maxWidth;       // output width
        uint256 maxHeight;      // output height
        bool completed;         // whether callback received
        string outputUri;       // result URI
        bytes32 outputHash;     // content hash
        string errorMessage;    // error if failed
    }

    mapping(uint256 => ImageRequest) public requests;
    uint256 public requestCount;

    mapping(bytes32 => uint256) public jobToRequest; // jobId => requestId

    // --- Events ---
    event ImageRequested(
        uint256 indexed requestId,
        address indexed requester,
        string prompt,
        string model
    );
    event ImageGenerated(
        uint256 indexed requestId,
        string outputUri,
        bytes32 outputHash
    );
    event ImageFailed(
        uint256 indexed requestId,
        string reason
    );

    // --- Modifiers ---
    modifier onlyOwner() {
        require(msg.sender == owner, "not owner");
        _;
    }

    modifier onlyAsyncDelivery() {
        require(msg.sender == ASYNC_DELIVERY, "only async delivery");
        _;
    }

    constructor() {
        owner = msg.sender;
    }

    /// @notice Request image generation via Ritual's native precompile
    /// @param prompt Text description of the image to generate
    /// @param model Model name (e.g., "dall-e-3")
    /// @param maxWidth Maximum output width
    /// @param maxHeight Maximum output height
    /// @return requestId ID of the image request
    function requestImage(
        string calldata prompt,
        string calldata model,
        uint256 maxWidth,
        uint256 maxHeight
    ) external returns (uint256 requestId) {
        require(bytes(prompt).length > 0, "empty prompt");

        requestId = requestCount++;

        // Store request
        requests[requestId] = ImageRequest({
            requester: msg.sender,
            prompt: prompt,
            model: model,
            maxWidth: maxWidth,
            maxHeight: maxHeight,
            completed: false,
            outputUri: "",
            outputHash: bytes32(0),
            errorMessage: ""
        });

        // Query executor from TEEServiceRegistry
        address executor = _getExecutor();
        if (executor == address(0)) {
            // No executor available — mark as failed
            requests[requestId].completed = true;
            requests[requestId].errorMessage = "No available executor";
            emit ImageFailed(requestId, "No available executor");
            return requestId;
        }

        // Build the 18-field ABI encoding for image generation
        bytes memory imageInput = _encodeImageRequest(
            executor,
            prompt,
            model,
            maxWidth,
            maxHeight
        );

        // Submit to image gen precompile
        (bool ok,) = IMAGE_GEN_PRECOMPILE.call(imageInput);
        if (ok) {
            bytes32 jobId = keccak256(abi.encode(requestId));
            jobToRequest[jobId] = requestId;
            emit ImageRequested(requestId, msg.sender, prompt, model);
        } else {
            requests[requestId].completed = true;
            requests[requestId].errorMessage = "Precompile call failed";
            emit ImageFailed(requestId, "Precompile call failed");
        }
    }

    /// @notice Callback from AsyncDelivery when image generation completes
    /// @param jobId The job identifier
    /// @param result ABI-encoded result: (hasError, completionData, outputUri, contentHash, encrypted, sizeBytes, width, height, errorMessage)
    function onLongRunningResult(
        bytes32 jobId,
        bytes calldata result
    ) external onlyAsyncDelivery {
        uint256 requestId = jobToRequest[jobId];
        require(requestId != 0, "unknown job");

        ImageRequest storage req = requests[requestId];

        // Decode the result
        // Result format: (bool hasError, bytes completionData, string outputUri, 
        //                 bytes32 outputContentHash, bool outputEncrypted, 
        //                 uint32 outputSizeBytes, uint32 outputWidth, uint32 outputHeight,
        //                 string errorMessage)
        try this._decodeResult(result) returns (
            bool hasError,
            string memory outputUri,
            bytes32 outputHash,
            string memory errorMessage
        ) {
            req.completed = true;
            if (hasError) {
                req.errorMessage = errorMessage;
                emit ImageFailed(requestId, errorMessage);
            } else {
                req.outputUri = outputUri;
                req.outputHash = outputHash;
                emit ImageGenerated(requestId, outputUri, outputHash);
            }
        } catch {
            req.completed = true;
            req.errorMessage = "Failed to decode result";
            emit ImageFailed(requestId, "Failed to decode result");
        }
    }

    /// @notice Get image request details
    function getRequest(uint256 requestId) external view returns (
        address requester,
        string memory prompt,
        string memory model,
        uint256 maxWidth,
        uint256 maxHeight,
        bool completed,
        string memory outputUri,
        bytes32 outputHash,
        string memory errorMessage
    ) {
        ImageRequest storage r = requests[requestId];
        return (
            r.requester,
            r.prompt,
            r.model,
            r.maxWidth,
            r.maxHeight,
            r.completed,
            r.outputUri,
            r.outputHash,
            r.errorMessage
        );
    }

    /// @notice Check if a request is complete
    function isComplete(uint256 requestId) external view returns (bool) {
        return requests[requestId].completed;
    }

    // --- Internal Functions ---

    /// @dev Decode the async result from image generation
    function _decodeResult(bytes calldata result) external pure returns (
        bool hasError,
        string memory outputUri,
        bytes32 outputHash,
        string memory errorMessage
    ) {
        // Result is ABI-encoded as a tuple
        // (bool hasError, bytes completionData, string outputUri, 
        //  bytes32 outputContentHash, bool outputEncrypted,
        //  uint32 outputSizeBytes, uint32 outputWidth, uint32 outputHeight,
        //  string errorMessage)
        (
            hasError,
            ,
            outputUri,
            outputHash,
            ,
            ,
            ,
            ,
            errorMessage
        ) = abi.decode(result, (bool, bytes, string, bytes32, bool, uint32, uint32, uint32, string));
    }

    /// @dev Get an available executor from TEEServiceRegistry
    function _getExecutor() internal view returns (address) {
        bytes memory registryCall = abi.encodeWithSignature(
            "getServicesByCapability(uint8,bool)",
            uint8(4), // Image generation capability
            false     // don't check validity (testnet may not have active registrations)
        );

        (bool regOk, bytes memory regResult) = TEESERVICE_REGISTRY.staticcall(registryCall);
        if (!regOk || regResult.length < 96) return address(0);

        // Decode first executor's teeAddress
        if (regResult.length < 128) return address(0);

        uint256 length;
        assembly {
            length := mload(add(regResult, 32))
        }
        if (length == 0) return address(0);

        uint256 elemOffset;
        assembly {
            elemOffset := mload(add(regResult, 64))
        }

        if (regResult.length < elemOffset + 64) return address(0);

        address teeAddress;
        assembly {
            teeAddress := mload(add(add(regResult, 32), add(elemOffset, 32)))
        }

        // Validate executor
        if (teeAddress == address(0) || uint160(teeAddress) < 0x100) return address(0);

        return teeAddress;
    }

    /// @dev Encode the 18-field image generation request
    function _encodeImageRequest(
        address executor,
        string calldata prompt,
        string calldata model,
        uint256 maxWidth,
        uint256 maxHeight
    ) internal pure returns (bytes memory) {
        // Convert prompt to bytes for ModalInput
        bytes memory promptBytes = bytes(prompt);

        // ModalInput: (uint8 inputType, bytes data, string uri, bytes32 contentHash, uint32 param1, uint32 param2, bool encrypted)
        // inputType 0 = TEXT
        bytes memory modalInput = abi.encode(
            uint8(0),              // inputType: TEXT
            promptBytes,           // data: prompt bytes
            "",                    // uri: empty
            bytes32(0),           // contentHash: empty
            uint32(0),            // param1
            uint32(0),            // param2
            false                 // encrypted
        );

        // Wrap in array
        bytes[] memory modalInputs = new bytes[](1);
        modalInputs[0] = modalInput;

        // OutputConfig: (uint8 outputType, uint32 maxWidth, uint32 maxHeight, uint32 maxParam3, bool encryptOutput, uint16 numInferenceSteps, uint16 guidanceScaleX100, uint32 seed, uint8 fps, string negativePrompt)
        // outputType 1 = IMAGE
        bytes memory outputConfig = abi.encode(
            uint8(1),                          // outputType: IMAGE
            uint32(maxWidth),                  // maxWidth
            uint32(maxHeight),                 // maxHeight
            uint32(0),                         // maxParam3
            false,                             // encryptOutput
            uint16(50),                        // numInferenceSteps
            uint16(750),                       // guidanceScaleX100 (7.5)
            uint32(0),                         // seed (0 = random)
            uint8(0),                          // fps (not used for images)
            ""                                 // negativePrompt
        );

        // 18-field ABI encoding
        // Fields 0-4: base executor
        // Fields 5-13: polling + delivery config
        // Field 14: model
        // Field 15: ModalInput[]
        // Field 16: OutputConfig
        // Field 17: encryptedStoragePayment
        return abi.encode(
            executor,                          // 0: executor address
            new bytes[](0),                    // 1: encryptedSecrets
            uint256(300),                      // 2: ttl (300 blocks)
            new bytes[](0),                    // 3: secretSignatures
            hex"",                             // 4: userPublicKey
            uint256(1),                        // 5: pollInterval
            uint256(100),                      // 6: maxPollBlock
            bytes32(0),                        // 7: taskIdMarker
            address(0),                        // 8: callbackAddr (not used, we use AsyncDelivery)
            bytes4(0),                         // 9: selector
            uint256(500000),                   // 10: gasLimit
            uint256(0),                        // 11: maxFee
            uint256(0),                        // 12: maxPriority
            uint256(0),                        // 13: value
            model,                             // 14: model name
            abi.encode(modalInputs),           // 15: ModalInput[]
            outputConfig,                      // 16: OutputConfig
            hex""                              // 17: encryptedStoragePayment
        );
    }

    receive() external payable {}
}
