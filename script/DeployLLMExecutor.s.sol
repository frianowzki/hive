// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "../src/HiveLLMExecutor.sol";

/// @title DeployLLMExecutor - Deploy HiveLLMExecutor to Ritual Testnet
contract DeployLLMExecutor is Script {
    function run() external {
        uint256 deployerKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerKey);

        console.log("=== HIVE LLM EXECUTOR DEPLOY ===");
        console.log("Deployer:", deployer);

        vm.startBroadcast(deployerKey);

        HiveLLMExecutor llm = new HiveLLMExecutor();
        address llmAddr = address(llm);
        console.log("HiveLLMExecutor deployed:", llmAddr);

        // Fund with 0.01 RITUAL for precompile calls
        (bool funded,) = llmAddr.call{value: 0.01 ether}("");
        require(funded, "Funding failed");
        console.log("Funded: 0.01 RITUAL");

        vm.stopBroadcast();

        console.log("=== DEPLOY COMPLETE ===");
        console.log("HiveLLMExecutor:", llmAddr);
    }
}
