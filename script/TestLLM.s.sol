// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";

/// @title TestLLM - Direct LLM precompile test on Ritual Testnet
contract TestLLM is Script {
    address constant LLM_PRECOMPILE = 0x0000000000000000000000000000000000000802;
    address constant RITUAL_WALLET = 0x532F0dF0896F353d8C3DD8cc134e8129DA2a3948;

    // Live executor from TEEServiceRegistry (LLM capability=1)
    address constant EXECUTOR = 0xeC6a6C7ebd08616C805e18cDeA6bF9C54950C77D;

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        console.log("Deployer:", deployer);
        console.log("Balance:", deployer.balance);

        vm.startBroadcast(deployerPrivateKey);

        // Step 1: Ensure RitualWallet has enough deposit
        uint256 walletBalance;
        (bool balOk, bytes memory balRes) = RITUAL_WALLET.staticcall(
            abi.encodeWithSignature("balanceOf(address)", deployer)
        );
        if (balOk && balRes.length >= 32) {
            walletBalance = abi.decode(balRes, (uint256));
        }
        console.log("RitualWallet deposit:", walletBalance);

        if (walletBalance < 0.4 ether) {
            console.log("Depositing 0.5 RITUAL...");
            (bool ok,) = RITUAL_WALLET.call{value: 0.5 ether}(
                abi.encodeWithSignature("deposit(uint256)", 5000)
            );
            require(ok, "Deposit failed");
            console.log("Deposited!");
        }

        // Step 2: Build and send LLM request
        string memory messagesJson = '[{"role":"user","content":"Say hello in exactly 5 words."}]';

        bytes memory input = abi.encode(
            EXECUTOR,                    // executor
            new bytes[](0),              // encryptedSecrets
            uint256(300),                // ttl
            new bytes[](0),              // secretSignatures
            bytes(""),                   // userPublicKey
            messagesJson,                // messagesJson
            "zai-org/GLM-4.7-FP8",      // model
            int256(0),                   // frequencyPenalty
            "",                          // logitBiasJson
            false,                       // logprobs
            int256(4096),                // maxCompletionTokens
            "",                          // metadataJson
            "",                          // modalitiesJson
            uint256(1),                  // n
            true,                        // parallelToolCalls
            int256(0),                   // presencePenalty
            "medium",                    // reasoningEffort
            bytes(""),                   // responseFormatData
            int256(-1),                  // seed
            "auto",                      // serviceTier
            "",                          // stopJson
            false,                       // stream
            int256(700),                 // temperature
            bytes(""),                   // toolChoiceData
            bytes(""),                   // toolsData
            int256(-1),                  // topLogprobs
            int256(1000),                // topP
            "",                          // user
            false,                       // piiEnabled
            abi.encode("", "", "")       // convoHistory
        );

        console.log("Sending LLM request...");

        (bool success, bytes memory result) = LLM_PRECOMPILE.call{gas: 5_000_000}(input);

        vm.stopBroadcast();

        if (success) {
            console.log("LLM call landed on-chain!");
            console.log("Result length:", result.length);

            // Try to decode the async envelope
            if (result.length >= 64) {
                (bytes memory simmed, bytes memory actual) = abi.decode(result, (bytes, bytes));
                console.log("Actual output length:", actual.length);

                if (actual.length >= 96) {
                    (bool hasError, bytes memory completionData,, string memory errMsg,) =
                        abi.decode(actual, (bool, bytes, bytes, string, string[3]));

                    if (hasError) {
                        console.log("LLM error:", errMsg);
                    } else {
                        console.log("LLM SUCCESS! Completion data:", completionData.length, "bytes");
                    }
                } else {
                    console.log("Output too short to decode, raw hex:");
                    _printHex(actual, 320);
                }
            } else {
                console.log("Result too short, raw hex:");
                _printHex(result, 320);
            }
        } else {
            console.log("LLM call reverted!");
            _printHex(result, 320);
        }
    }

    function _printHex(bytes memory data, uint256 maxLen) internal pure {
        uint256 len = data.length > maxLen ? maxLen : data.length;
        uint256 fullChunks = len / 32;
        for (uint256 i = 0; i < fullChunks; i++) {
            bytes32 chunk;
            assembly {
                chunk := add(data, add(32, mul(i, 32)))
            }
            console.logBytes32(chunk);
        }
        uint256 remaining = len % 32;
        if (remaining > 0) {
            bytes memory tail = new bytes(remaining);
            for (uint256 i = 0; i < remaining; i++) {
                tail[i] = data[fullChunks * 32 + i];
            }
            console.logBytes(tail);
        }
    }
}
