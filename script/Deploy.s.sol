// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.24;

import {Script, console2} from "forge-std/Script.sol";
import {IdentityRegistry}   from "../src/core/IdentityRegistry.sol";
import {ReputationRegistry}  from "../src/core/ReputationRegistry.sol";
import {ValidationRegistry}  from "../src/core/ValidationRegistry.sol";

/// @title Deploy
/// @notice Deploys all three ERC-8004 registries in dependency order.
///
/// Usage (local anvil):
///   anvil &
///   forge script script/Deploy.s.sol:Deploy \
///     --rpc-url http://127.0.0.1:8545 \
///     --private-key <PRIVATE_KEY> \
///     --broadcast -vvvv
///
/// Usage (testnet — e.g. Base Sepolia):
///   forge script script/Deploy.s.sol:Deploy \
///     --rpc-url $BASE_SEPOLIA_RPC \
///     --private-key $PRIVATE_KEY \
///     --broadcast --verify --etherscan-api-key $ETHERSCAN_KEY -vvvv
contract Deploy is Script {
    function run() external {
        vm.startBroadcast();

        // 1. Deploy IdentityRegistry (standalone ERC-721)
        IdentityRegistry idReg = new IdentityRegistry();
        console2.log("IdentityRegistry deployed at:", address(idReg));

        // 2. Deploy ReputationRegistry, passing IdentityRegistry address
        ReputationRegistry repReg = new ReputationRegistry(address(idReg));
        console2.log("ReputationRegistry deployed at:", address(repReg));

        // 3. Deploy ValidationRegistry, passing IdentityRegistry address
        ValidationRegistry valReg = new ValidationRegistry(address(idReg));
        console2.log("ValidationRegistry deployed at:", address(valReg));

        vm.stopBroadcast();

        // Print summary for .env / documentation
        console2.log("\n=== ERC-8004 Deployment Summary ===");
        console2.log("IDENTITY_REGISTRY=", address(idReg));
        console2.log("REPUTATION_REGISTRY=", address(repReg));
        console2.log("VALIDATION_REGISTRY=", address(valReg));
    }
}
