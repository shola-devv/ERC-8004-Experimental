// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {IdentityRegistry} from "../src/core/IdentityRegistry.sol";
import {ReputationRegistry} from "../src/core/ReputationRegistry.sol";
import {IReputationRegistry} from "../src/interfaces/IReputationRegistry.sol";

/// @title ReputationRegistryTest
/// @notice Comprehensive Foundry test suite for the ReputationRegistry contract.
contract ReputationRegistryTest is Test {
    IdentityRegistry  public idReg;
    ReputationRegistry public repReg;

    address internal agentOwner = makeAddr("agentOwner");
    address internal client1    = makeAddr("client1");
    address internal client2    = makeAddr("client2");
    address internal client3    = makeAddr("client3");

    uint256 internal agentId;

    function setUp() public {
        idReg  = new IdentityRegistry();
        repReg = new ReputationRegistry(address(idReg));

        vm.prank(agentOwner);
        agentId = idReg.register("ipfs://agent1");
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Initialisation
    // ─────────────────────────────────────────────────────────────────────────

    function test_getIdentityRegistry() public view {
        assertEq(repReg.getIdentityRegistry(), address(idReg));
    }

    // ─────────────────────────────────────────────────────────────────────────
    // giveFeedback
    // ─────────────────────────────────────────────────────────────────────────

    function test_giveFeedback_basic() public {
        vm.prank(client1);
        repReg.giveFeedback(agentId, 90, 0, "starred", "", "", "", bytes32(0));

        (int128 value, uint8 dec, string memory t1, string memory t2, bool revoked) =
            repReg.readFeedback(agentId, client1, 1);

        assertEq(value, 90);
        assertEq(dec, 0);
        assertEq(t1, "starred");
        assertEq(t2, "");
        assertFalse(revoked);
    }

    function test_giveFeedback_multipleFromSameClient() public {
        vm.startPrank(client1);
        repReg.giveFeedback(agentId, 80, 0, "starred", "", "", "", bytes32(0));
        repReg.giveFeedback(agentId, 9977, 2, "uptime", "", "", "", bytes32(0));
        vm.stopPrank();

        assertEq(repReg.getLastIndex(agentId, client1), 2);

        (int128 v1,,,,) = repReg.readFeedback(agentId, client1, 1);
        (int128 v2,,,,) = repReg.readFeedback(agentId, client1, 2);
        assertEq(v1, 80);
        assertEq(v2, 9977);
    }

    function test_giveFeedback_emitsEvent() public {
        vm.expectEmit(true, true, false, false);
        emit IReputationRegistry.NewFeedback(
            agentId, client1, 1, 90, 0, "starred", "starred", "", "", "", bytes32(0)
        );

        vm.prank(client1);
        repReg.giveFeedback(agentId, 90, 0, "starred", "", "", "", bytes32(0));
    }

    function test_giveFeedback_revert_ownerCannotReview() public {
        vm.expectRevert("ReputationRegistry: agent owner/operator cannot give feedback");
        vm.prank(agentOwner);
        repReg.giveFeedback(agentId, 100, 0, "starred", "", "", "", bytes32(0));
    }

    function test_giveFeedback_revert_operatorCannotReview() public {
        vm.prank(agentOwner);
        idReg.setApprovalForAll(client1, true);

        vm.expectRevert("ReputationRegistry: agent owner/operator cannot give feedback");
        vm.prank(client1);
        repReg.giveFeedback(agentId, 100, 0, "starred", "", "", "", bytes32(0));
    }

    function test_giveFeedback_revert_valueDecimalsTooHigh() public {
        vm.expectRevert("ReputationRegistry: valueDecimals > 18");
        vm.prank(client1);
        repReg.giveFeedback(agentId, 1, 19, "", "", "", "", bytes32(0));
    }

    function test_giveFeedback_revert_invalidAgent() public {
        vm.expectRevert();
        vm.prank(client1);
        repReg.giveFeedback(999, 1, 0, "", "", "", "", bytes32(0));
    }

    // ─────────────────────────────────────────────────────────────────────────
    // revokeFeedback
    // ─────────────────────────────────────────────────────────────────────────

    function test_revokeFeedback() public {
        vm.prank(client1);
        repReg.giveFeedback(agentId, 90, 0, "starred", "", "", "", bytes32(0));

        vm.prank(client1);
        repReg.revokeFeedback(agentId, 1);

        (,,,,bool revoked) = repReg.readFeedback(agentId, client1, 1);
        assertTrue(revoked);
    }

    function test_revokeFeedback_emitsEvent() public {
        vm.prank(client1);
        repReg.giveFeedback(agentId, 90, 0, "starred", "", "", "", bytes32(0));

        vm.expectEmit(true, true, true, true);
        emit IReputationRegistry.FeedbackRevoked(agentId, client1, 1);

        vm.prank(client1);
        repReg.revokeFeedback(agentId, 1);
    }

    function test_revokeFeedback_revert_notFound() public {
        vm.expectRevert("ReputationRegistry: feedback not found");
        vm.prank(client1);
        repReg.revokeFeedback(agentId, 999);
    }

    function test_revokeFeedback_revert_alreadyRevoked() public {
        vm.prank(client1);
        repReg.giveFeedback(agentId, 90, 0, "", "", "", "", bytes32(0));

        vm.prank(client1);
        repReg.revokeFeedback(agentId, 1);

        vm.expectRevert("ReputationRegistry: already revoked");
        vm.prank(client1);
        repReg.revokeFeedback(agentId, 1);
    }

    // ─────────────────────────────────────────────────────────────────────────
    // appendResponse
    // ─────────────────────────────────────────────────────────────────────────

    function test_appendResponse() public {
        vm.prank(client1);
        repReg.giveFeedback(agentId, 50, 0, "starred", "", "", "", bytes32(0));

        vm.prank(agentOwner);
        repReg.appendResponse(agentId, client1, 1, "ipfs://refund-proof", bytes32(0));

        assertEq(repReg.getResponseCount(agentId, client1, 1, new address[](0)), 1);
    }

    function test_appendResponse_anyoneCanAppend() public {
        vm.prank(client1);
        repReg.giveFeedback(agentId, 50, 0, "", "", "", "", bytes32(0));

        // Totally unrelated address appends
        vm.prank(client3);
        repReg.appendResponse(agentId, client1, 1, "ipfs://spam-tag", bytes32(0));

        assertEq(repReg.getResponseCount(agentId, client1, 1, new address[](0)), 1);
    }

    // ─────────────────────────────────────────────────────────────────────────
    // getSummary
    // ─────────────────────────────────────────────────────────────────────────

    function test_getSummary_basic() public {
        vm.prank(client1);
        repReg.giveFeedback(agentId, 80, 0, "starred", "", "", "", bytes32(0));

        vm.prank(client2);
        repReg.giveFeedback(agentId, 60, 0, "starred", "", "", "", bytes32(0));

        address[] memory clients = new address[](2);
        clients[0] = client1;
        clients[1] = client2;

        (uint64 count, int128 summary, uint8 dec) = repReg.getSummary(agentId, clients, "starred", "");
        assertEq(count, 2);
        assertEq(summary, 140); // 80 + 60
        assertEq(dec, 0);
    }

    function test_getSummary_excludesRevoked() public {
        vm.prank(client1);
        repReg.giveFeedback(agentId, 80, 0, "starred", "", "", "", bytes32(0));

        vm.prank(client1);
        repReg.revokeFeedback(agentId, 1);

        address[] memory clients = new address[](1);
        clients[0] = client1;

        (uint64 count,,) = repReg.getSummary(agentId, clients, "starred", "");
        assertEq(count, 0);
    }

    function test_getSummary_filtersByTag() public {
        vm.prank(client1);
        repReg.giveFeedback(agentId, 80, 0, "starred", "", "", "", bytes32(0));

        vm.prank(client2);
        repReg.giveFeedback(agentId, 9977, 2, "uptime", "", "", "", bytes32(0));

        address[] memory clients = new address[](2);
        clients[0] = client1;
        clients[1] = client2;

        (uint64 count,,) = repReg.getSummary(agentId, clients, "starred", "");
        assertEq(count, 1);
    }

    function test_getSummary_revert_emptyClients() public {
        address[] memory empty = new address[](0);
        vm.expectRevert("ReputationRegistry: clientAddresses required");
        repReg.getSummary(agentId, empty, "", "");
    }

    // ─────────────────────────────────────────────────────────────────────────
    // readAllFeedback
    // ─────────────────────────────────────────────────────────────────────────

    function test_readAllFeedback_noFilter() public {
        vm.prank(client1);
        repReg.giveFeedback(agentId, 80, 0, "starred", "", "", "", bytes32(0));

        vm.prank(client2);
        repReg.giveFeedback(agentId, 60, 0, "uptime", "", "", "", bytes32(0));

        (
            address[] memory clients,
            uint64[]  memory indexes,
            int128[]  memory values,
            ,,,
        ) = repReg.readAllFeedback(agentId, new address[](0), "", "", false);

        assertEq(clients.length, 2);
        assertEq(indexes[0], 1);
        assertEq(values[0], 80);
    }

    function test_readAllFeedback_excludesRevokedByDefault() public {
        vm.prank(client1);
        repReg.giveFeedback(agentId, 80, 0, "", "", "", "", bytes32(0));
        vm.prank(client1);
        repReg.revokeFeedback(agentId, 1);

        (address[] memory clients,,,,,, ) =
            repReg.readAllFeedback(agentId, new address[](0), "", "", false);

        assertEq(clients.length, 0);
    }

    // ─────────────────────────────────────────────────────────────────────────
    // getClients
    // ─────────────────────────────────────────────────────────────────────────

    function test_getClients_tracksUnique() public {
        vm.prank(client1);
        repReg.giveFeedback(agentId, 80, 0, "", "", "", "", bytes32(0));

        // Same client again — should NOT duplicate
        vm.prank(client1);
        repReg.giveFeedback(agentId, 70, 0, "", "", "", "", bytes32(0));

        vm.prank(client2);
        repReg.giveFeedback(agentId, 60, 0, "", "", "", "", bytes32(0));

        address[] memory clients = repReg.getClients(agentId);
        assertEq(clients.length, 2);
        assertEq(clients[0], client1);
        assertEq(clients[1], client2);
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Fuzz
    // ─────────────────────────────────────────────────────────────────────────

    function testFuzz_giveFeedback_valueRange(int128 value, uint8 dec) public {
        vm.assume(dec <= 18);
        vm.prank(client1);
        repReg.giveFeedback(agentId, value, dec, "", "", "", "", bytes32(0));

        (int128 stored, uint8 storedDec,,,) = repReg.readFeedback(agentId, client1, 1);
        assertEq(stored, value);
        assertEq(storedDec, dec);
    }
}
