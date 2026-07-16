// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "../src/HiveFactory.sol";

/// @title DeployHive - Production deploy script with chain detection
/// @notice Deploys HiveFactory to Ritual Testnet (1979) or Anvil (31337)
/// @dev Auto-detects chain, deploys mocks on local, writes deployed-addresses.json
contract DeployHive is Script {
    function run() external {
        uint256 chainId = block.chainid;
        uint256 deployerKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerKey);
        address platformTreasury = vm.envAddress("PLATFORM_TREASURY");

        console.log("=== HIVE DEPLOY ===");
        console.log("Chain ID:", chainId);
        console.log("Deployer:", deployer);
        console.log("Platform Treasury:", platformTreasury);

        if (chainId == 31337) {
            console.log("Network: Anvil (Local)");
            _deployLocal(platformTreasury);
        } else if (chainId == 1979) {
            console.log("Network: Ritual Testnet");
            _deployRitual(platformTreasury, deployerKey, deployer);
        } else {
            revert("Unsupported chain");
        }
    }

    function _deployLocal(address platformTreasury) internal {
        vm.startBroadcast();
        HiveFactory factory = new HiveFactory(platformTreasury, address(0));
        console.log("Factory deployed (local):", address(factory));
        vm.stopBroadcast();
    }

    function _deployRitual(
        address platformTreasury,
        uint256 deployerKey,
        address deployer
    ) internal {
        vm.startBroadcast(deployerKey);

        // 1. Deploy factory
        HiveFactory factory = new HiveFactory(platformTreasury, address(0));
        address factoryAddr = address(factory);
        console.log("Factory deployed:", factoryAddr);

        // 2. Verify owner
        require(factory.owner() == deployer, "Owner mismatch");
        console.log("Owner verified:", deployer);

        vm.stopBroadcast();

        // 4. Write deployed-addresses.json
        _writeJson(factoryAddr, platformTreasury);

        console.log("=== DEPLOY COMPLETE ===");
        console.log("Factory:", factoryAddr);
    }

    function _writeJson(address factory, address treasury) internal {
        string memory json = string(abi.encodePacked(
            '{\n',
            '  "chainId": 1979,\n',
            '  "network": "Ritual Testnet",\n',
            '  "rpcUrl": "https://rpc.ritualfoundation.org",\n',
            '  "explorerUrl": "https://explorer.ritualfoundation.org",\n',
            '  "contracts": {\n',
            '    "factory": "', _addrStr(factory), '",\n',
            '    "platformTreasury": "', _addrStr(treasury), '",\n',
            '    "ritualWallet": "0x532F0dF0896F353d8C3DD8cc134e8129DA2a3948",\n',
            '    "asyncDelivery": "0x5A16214fF555848411544b005f7Ac063742f39F6",\n',
            '    "teeServiceRegistry": "0x9644e8562cE0Fe12b4deeC4163c064A8862Bf47F"\n',
            '  },\n',
            '  "precompiles": {\n',
            '    "llm": "0x0000000000000000000000000000000000000802",\n',
            '    "http": "0x0000000000000000000000000000000000000801",\n',
            '    "imageGen": "0x0000000000000000000000000000000000000805"\n',
            '  },\n',
            '  "params": {\n',
            '    "virtualRitual": "5000000000000000000",\n',
            '    "virtualToken": "1000000000000000000000000000",\n',
            '    "launchCost": "10000000000000000"\n',
            '  },\n',
            '  "llmExecutor": "0xB42e435c4252A5a2E7440e37B609F00c61a0c91B",\n',
            '  "llmModel": "zai-org/GLM-4.7-FP8"\n',
            '}\n'
        ));

        vm.writeFile("deployed-addresses.json", json);
        console.log("Written: deployed-addresses.json");
    }

    function _addrStr(address a) internal pure returns (string memory) {
        return vm.toString(a);
    }
}
