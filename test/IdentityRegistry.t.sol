// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.24;

import {Test, console2} from "forge-std/Test.sol";
import {IdentityRegistry} from "../src/core/IdentityRegistry.sol";
import {IIdentityRegistry} from "../src/interfaces/IIdentityRegistry.sol";
import {MessageHashUtils} from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";

/// @title IdentityRegistryTest
/// @notice Comprehensive Foundry test suite for the IdentityRegistry contract.
contract IdentityRegistryTest is Test {
    IdentityRegistry public registry;

    address internal alice = makeAddr("alice");
    address internal bob   = makeAddr("bob");
    address internal carol = makeAddr("carol");

    // EIP-712 type hash (must match contract)
    bytes32 private constant AGENT_WALLET_TYPEHASH =
        keccak256("SetAgentWallet(uint256 agentId,address newWallet,uint256 deadline)");

    function setUp() public {
        registry = new IdentityRegistry();
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Registration
    // ─────────────────────────────────────────────────────────────────────────

    function test_register_withURI() public {
        vm.prank(alice);
        uint256 id = registry.register("ipfs://Qmtest");

        assertEq(id, 1);
        assertEq(registry.ownerOf(id), alice);
        assertEq(registry.tokenURI(id), "ipfs://Qmtest");
    }

    function test_register_withoutURI() public {
        vm.prank(alice);
        uint256 id = registry.register();

        assertEq(id, 1);
        assertEq(registry.ownerOf(id), alice);
    }

    function test_register_withMetadata() public {
        IIdentityRegistry.MetadataEntry[] memory meta = new IIdentityRegistry.MetadataEntry[](1);
        meta[0] = IIdentityRegistry.MetadataEntry({
            metadataKey: "category",
            metadataValue: bytes("defi")
        });

        vm.prank(alice);
        uint256 id = registry.register("ipfs://Qmtest", meta);

        assertEq(id, 1);
        assertEq(string(registry.getMetadata(id, "category")), "defi");
    }

    function test_register_incrementsIds() public {
        vm.startPrank(alice);
        uint256 id1 = registry.register("uri-1");
        uint256 id2 = registry.register("uri-2");
        uint256 id3 = registry.register("uri-3");
        vm.stopPrank();

        assertEq(id1, 1);
        assertEq(id2, 2);
        assertEq(id3, 3);
    }

    function test_register_emitsEvent() public {
        vm.expectEmit(true, true, false, true);
        emit IIdentityRegistry.Registered(1, "ipfs://Qmtest", alice);

        vm.prank(alice);
        registry.register("ipfs://Qmtest");
    }

    function test_register_setsAgentWalletToOwner() public {
        vm.prank(alice);
        uint256 id = registry.register("ipfs://Qmtest");
        assertEq(registry.getAgentWallet(id), alice);
    }

    // ─────────────────────────────────────────────────────────────────────────
    // URI Updates
    // ─────────────────────────────────────────────────────────────────────────

    function test_setAgentURI_byOwner() public {
        vm.prank(alice);
        uint256 id = registry.register("ipfs://old");

        vm.prank(alice);
        registry.setAgentURI(id, "ipfs://new");

        assertEq(registry.tokenURI(id), "ipfs://new");
    }

    function test_setAgentURI_byOperator() public {
        vm.prank(alice);
        uint256 id = registry.register("ipfs://old");

        vm.prank(alice);
        registry.setApprovalForAll(bob, true);

        vm.prank(bob);
        registry.setAgentURI(id, "ipfs://updated-by-operator");

        assertEq(registry.tokenURI(id), "ipfs://updated-by-operator");
    }

    function test_setAgentURI_revert_unauthorized() public {
        vm.prank(alice);
        uint256 id = registry.register("ipfs://old");

        vm.expectRevert("IdentityRegistry: not owner or operator");
        vm.prank(bob);
        registry.setAgentURI(id, "ipfs://hack");
    }

    function test_setAgentURI_emitsEvent() public {
        vm.prank(alice);
        uint256 id = registry.register("ipfs://old");

        vm.expectEmit(true, false, true, true);
        emit IIdentityRegistry.URIUpdated(id, "ipfs://new", alice);

        vm.prank(alice);
        registry.setAgentURI(id, "ipfs://new");
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Metadata
    // ─────────────────────────────────────────────────────────────────────────

    function test_setMetadata_basic() public {
        vm.prank(alice);
        uint256 id = registry.register("ipfs://Qmtest");

        vm.prank(alice);
        registry.setMetadata(id, "framework", bytes("langchain"));

        assertEq(string(registry.getMetadata(id, "framework")), "langchain");
    }

    function test_setMetadata_revert_reservedKey() public {
        vm.prank(alice);
        uint256 id = registry.register("ipfs://Qmtest");

        vm.expectRevert("IdentityRegistry: agentWallet key is reserved");
        vm.prank(alice);
        registry.setMetadata(id, "agentWallet", bytes("0x1234"));
    }

    function test_setMetadata_revert_unauthorized() public {
        vm.prank(alice);
        uint256 id = registry.register("ipfs://Qmtest");

        vm.expectRevert("IdentityRegistry: not owner or operator");
        vm.prank(bob);
        registry.setMetadata(id, "key", bytes("value"));
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Agent Wallet
    // ─────────────────────────────────────────────────────────────────────────

    function test_setAgentWallet_eoa() public {
        // Create a deterministic private key for signing
        uint256 walletKey = 0xBEEF;
        address wallet = vm.addr(walletKey);

        vm.prank(alice);
        uint256 id = registry.register("ipfs://Qmtest");

        uint256 deadline = block.timestamp + 1 hours;

        bytes32 domainSep = registry.domainSeparator();
        bytes32 structHash = keccak256(abi.encode(AGENT_WALLET_TYPEHASH, id, wallet, deadline));
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", domainSep, structHash));

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(walletKey, digest);
        bytes memory sig = abi.encodePacked(r, s, v);

        vm.prank(alice);
        registry.setAgentWallet(id, wallet, deadline, sig);

        assertEq(registry.getAgentWallet(id), wallet);
    }

    function test_setAgentWallet_revert_expiredDeadline() public {
        uint256 walletKey = 0xBEEF;
        address wallet    = vm.addr(walletKey);

        vm.prank(alice);
        uint256 id = registry.register("ipfs://Qmtest");

        uint256 deadline = block.timestamp - 1; // already expired

        vm.expectRevert("IdentityRegistry: signature expired");
        vm.prank(alice);
        registry.setAgentWallet(id, wallet, deadline, bytes(""));
    }

    function test_setAgentWallet_revert_wrongSigner() public {
        uint256 walletKey    = 0xBEEF;
        uint256 imposterKey  = 0xDEAD;
        address wallet       = vm.addr(walletKey);

        vm.prank(alice);
        uint256 id = registry.register("ipfs://Qmtest");

        uint256 deadline  = block.timestamp + 1 hours;
        bytes32 domainSep = registry.domainSeparator();
        bytes32 structHash = keccak256(abi.encode(AGENT_WALLET_TYPEHASH, id, wallet, deadline));
        bytes32 digest     = keccak256(abi.encodePacked("\x19\x01", domainSep, structHash));

        // Sign with wrong key
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(imposterKey, digest);
        bytes memory sig = abi.encodePacked(r, s, v);

        vm.expectRevert("IdentityRegistry: invalid ECDSA signature");
        vm.prank(alice);
        registry.setAgentWallet(id, wallet, deadline, sig);
    }

    function test_unsetAgentWallet() public {
        vm.prank(alice);
        uint256 id = registry.register("ipfs://Qmtest");

        vm.prank(alice);
        registry.unsetAgentWallet(id);

        assertEq(registry.getAgentWallet(id), address(0));
    }

    function test_transfer_clearsAgentWallet() public {
        vm.prank(alice);
        uint256 id = registry.register("ipfs://Qmtest");
        assertEq(registry.getAgentWallet(id), alice);

        vm.prank(alice);
        registry.transferFrom(alice, bob, id);

        assertEq(registry.getAgentWallet(id), address(0));
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Fuzz Tests
    // ─────────────────────────────────────────────────────────────────────────

    function testFuzz_register_differentURIs(string calldata uri) public {
        vm.prank(alice);
        uint256 id = registry.register(uri);
        assertEq(registry.ownerOf(id), alice);
    }

    function testFuzz_setMetadata_arbitraryValues(
        string calldata key,
        bytes  calldata value
    ) public {
        vm.assume(keccak256(bytes(key)) != keccak256(bytes("agentWallet")));
        vm.assume(bytes(key).length > 0);

        vm.prank(alice);
        uint256 id = registry.register("ipfs://Qmtest");

        vm.prank(alice);
        registry.setMetadata(id, key, value);

        assertEq(registry.getMetadata(id, key), value);
    }
}
