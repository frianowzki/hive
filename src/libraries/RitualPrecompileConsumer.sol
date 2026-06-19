// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

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
        if (!success) {
            // Propagate revert reason if available
            if (result.length > 0) {
                assembly {
                    revert(add(result, 32), mload(result))
                }
            }
            revert("PrecompileConsumer: call failed");
        }
        return result;
    }

    /// @notice Execute a precompile call and return success status
    /// @param precompile Address of the precompile
    /// @param input Encoded input data
    /// @return success Whether the call succeeded
    /// @return output Raw output bytes
    function _tryExecutePrecompile(address precompile, bytes memory input)
        internal
        returns (bool success, bytes memory output)
    {
        (success, output) = precompile.staticcall(input);
        if (!success && output.length > 0) {
            // Include revert reason in output for debugging
            return (false, output);
        }
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
