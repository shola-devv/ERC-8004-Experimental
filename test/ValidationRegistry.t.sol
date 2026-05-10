// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {IdentityRegistry} from "../src/core/IdentityRegistry.sol";
import {ValidationRegistry} from "../src/core/ValidationRegistry.sol";
import {IValidationRegistry} from "../src/interfaces/IValidationRegistry.sol";

/// @title ValidationRegistryTest
/// @notice Comprehensive Foundry test suite for the ValidationRegistry contract.
contract ValidationRegistryTest is Test {
    IdentityRegistry   public idReg;
    ValidationRegistry public valReg;

    address internal agentOwner = makeAddr("agentOwner");
    address internal validator1 = makeAddr("validator1");
    address internal validator2 = makeAddr("validator2");
    address internal randomUser = makeAddr("randomUser");

    uint256 internal agentId;

    bytes32 internal constant REQUEST_HASH_1 = keccak256("request1");
    bytes32 internal constant REQUEST_HASH_2 = keccak256("request2");

    function setUp() public {
        idReg  = new IdentityRegistry();
        valReg = new ValidationRegistry(address(idReg));

        vm.prank(agentOwner);
        agentId = idReg.register("ipfs://agent1");
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Initialisation
    // ─────────────────────────────────────────────────────────────────────────

    function test_getIdentityRegistry() public view {
        assertEq(valReg.getIdentityRegistry(), address(idReg));
    }

    // ─────────────────────────────────────────────────────────────────────────
    // validationRequest
    // ─────────────────────────────────────────────────────────────────────────

    function test_validationRequest_basic() public {
        vm.prank(agentOwner);
        valReg.validationRequest(validator1, agentId, "ipfs://req1", REQUEST_HASH_1);

        bytes32[] memory hashes = valReg.getAgentValidations(agentId);
        assertEq(hashes.length, 1);
        assertEq(hashes[0], REQUEST_HASH_1);
    }

    function test_validationRequest_emitsEvent() public {
        vm.expectEmit(true, true, false, true);
        emit IValidationRegistry.ValidationRequest(
            validator1, agentId, "ipfs://req1", REQUEST_HASH_1
        );

        vm.prank(agentOwner);
        valReg.validationRequest(validator1, agentId, "ipfs://req1", REQUEST_HASH_1);
    }

    function test_validationRequest_byOperator() public {
        vm.prank(agentOwner);
        idReg.setApprovalForAll(randomUser, true);

        vm.prank(randomUser);
        valReg.validationRequest(validator1, agentId, "ipfs://req1", REQUEST_HASH_1);

        bytes32[] memory hashes = valReg.getAgentValidations(agentId);
        assertEq(hashes.length, 1);
    }

    function test_validationRequest_revert_notOwnerOrOperator() public {
        vm.expectRevert("ValidationRegistry: not agent owner or operator");
        vm.prank(randomUser);
        valReg.validationRequest(validator1, agentId, "ipfs://req1", REQUEST_HASH_1);
    }

    function test_validationRequest_revert_zeroValidator() public {
        vm.expectRevert("ValidationRegistry: zero validator");
        vm.prank(agentOwner);
        valReg.validationRequest(address(0), agentId, "ipfs://req1", REQUEST_HASH_1);
    }

    function test_validationRequest_revert_emptyHash() public {
        vm.expectRevert("ValidationRegistry: empty requestHash");
        vm.prank(agentOwner);
        valReg.validationRequest(validator1, agentId, "ipfs://req1", bytes32(0));
    }

    function test_validationRequest_revert_duplicateHash() public {
        vm.prank(agentOwner);
        valReg.validationRequest(validator1, agentId, "ipfs://req1", REQUEST_HASH_1);

        vm.expectRevert("ValidationRegistry: requestHash already used");
        vm.prank(agentOwner);
        valReg.validationRequest(validator1, agentId, "ipfs://req1-dup", REQUEST_HASH_1);
    }

    function test_validationRequest_revert_invalidAgent() public {
        vm.expectRevert();
        vm.prank(agentOwner);
        valReg.validationRequest(validator1, 999, "ipfs://req1", REQUEST_HASH_1);
    }

    // ─────────────────────────────────────────────────────────────────────────
    // validationResponse
    // ─────────────────────────────────────────────────────────────────────────

    function test_validationResponse_pass() public {
        vm.prank(agentOwner);
        valReg.validationRequest(validator1, agentId, "ipfs://req1", REQUEST_HASH_1);

        vm.prank(validator1);
        valReg.validationResponse(REQUEST_HASH_1, 100, "ipfs://evidence1", bytes32(0), "hard-finality");

        (
            address vAddr,
            uint256 aId,
            uint8   resp,
            bytes32 rHash,
            string  memory tag,
            uint256 ts
        ) = valReg.getValidationStatus(REQUEST_HASH_1);

        assertEq(vAddr, validator1);
        assertEq(aId, agentId);
        assertEq(resp, 100);
        assertEq(rHash, bytes32(0));
        assertEq(tag, "hard-finality");
        assertGt(ts, 0);
    }

    function test_validationResponse_progressiveFinality() public {
        vm.prank(agentOwner);
        valReg.validationRequest(validator1, agentId, "ipfs://req1", REQUEST_HASH_1);

        // Soft finality first
        vm.prank(validator1);
        valReg.validationResponse(REQUEST_HASH_1, 50, "", bytes32(0), "soft-finality");

        (,,uint8 resp1,,string memory tag1,) = valReg.getValidationStatus(REQUEST_HASH_1);
        assertEq(resp1, 50);
        assertEq(tag1, "soft-finality");

        // Hard finality update
        vm.prank(validator1);
        valReg.validationResponse(REQUEST_HASH_1, 100, "", bytes32(0), "hard-finality");

        (,,uint8 resp2,,string memory tag2,) = valReg.getValidationStatus(REQUEST_HASH_1);
        assertEq(resp2, 100);
        assertEq(tag2, "hard-finality");
    }

    function test_validationResponse_emitsEvent() public {
        vm.prank(agentOwner);
        valReg.validationRequest(validator1, agentId, "ipfs://req1", REQUEST_HASH_1);

        vm.expectEmit(true, true, true, false);
        emit IValidationRegistry.ValidationResponse(
            validator1, agentId, REQUEST_HASH_1, 100, "", bytes32(0), ""
        );

        vm.prank(validator1);
        valReg.validationResponse(REQUEST_HASH_1, 100, "", bytes32(0), "");
    }

    function test_validationResponse_revert_wrongValidator() public {
        vm.prank(agentOwner);
        valReg.validationRequest(validator1, agentId, "ipfs://req1", REQUEST_HASH_1);

        vm.expectRevert("ValidationRegistry: caller is not the designated validator");
        vm.prank(validator2);
        valReg.validationResponse(REQUEST_HASH_1, 100, "", bytes32(0), "");
    }

    function test_validationResponse_revert_unknownHash() public {
        vm.expectRevert("ValidationRegistry: unknown requestHash");
        vm.prank(validator1);
        valReg.validationResponse(keccak256("unknown"), 100, "", bytes32(0), "");
    }

    function test_validationResponse_revert_responseOver100() public {
        vm.prank(agentOwner);
        valReg.validationRequest(validator1, agentId, "ipfs://req1", REQUEST_HASH_1);

        vm.expectRevert("ValidationRegistry: response > 100");
        vm.prank(validator1);
        valReg.validationResponse(REQUEST_HASH_1, 101, "", bytes32(0), "");
    }

    // ─────────────────────────────────────────────────────────────────────────
    // getSummary
    // ─────────────────────────────────────────────────────────────────────────

    function test_getSummary_noFilter() public {
        vm.prank(agentOwner);
        valReg.validationRequest(validator1, agentId, "ipfs://req1", REQUEST_HASH_1);
        vm.prank(agentOwner);
        valReg.validationRequest(validator2, agentId, "ipfs://req2", REQUEST_HASH_2);

        vm.prank(validator1);
        valReg.validationResponse(REQUEST_HASH_1, 100, "", bytes32(0), "");
        vm.prank(validator2);
        valReg.validationResponse(REQUEST_HASH_2, 80, "", bytes32(0), "");

        (uint64 count, uint8 avg) = valReg.getSummary(agentId, new address[](0), "");
        assertEq(count, 2);
        assertEq(avg, 90); // (100 + 80) / 2
    }

    function test_getSummary_filterByValidator() public {
        vm.prank(agentOwner);
        valReg.validationRequest(validator1, agentId, "ipfs://req1", REQUEST_HASH_1);
        vm.prank(agentOwner);
        valReg.validationRequest(validator2, agentId, "ipfs://req2", REQUEST_HASH_2);

        vm.prank(validator1);
        valReg.validationResponse(REQUEST_HASH_1, 100, "", bytes32(0), "");
        vm.prank(validator2);
        valReg.validationResponse(REQUEST_HASH_2, 80, "", bytes32(0), "");

        address[] memory filter = new address[](1);
        filter[0] = validator1;

        (uint64 count, uint8 avg) = valReg.getSummary(agentId, filter, "");
        assertEq(count, 1);
        assertEq(avg, 100);
    }

    function test_getSummary_excludesUnrespondedRequests() public {
        vm.prank(agentOwner);
        valReg.validationRequest(validator1, agentId, "ipfs://req1", REQUEST_HASH_1);
        // No response posted

        (uint64 count,) = valReg.getSummary(agentId, new address[](0), "");
        assertEq(count, 0);
    }

    // ─────────────────────────────────────────────────────────────────────────
    // getValidatorRequests
    // ─────────────────────────────────────────────────────────────────────────

    function test_getValidatorRequests() public {
        vm.prank(agentOwner);
        valReg.validationRequest(validator1, agentId, "ipfs://req1", REQUEST_HASH_1);
        vm.prank(agentOwner);
        valReg.validationRequest(validator1, agentId, "ipfs://req2", REQUEST_HASH_2);

        bytes32[] memory reqs = valReg.getValidatorRequests(validator1);
        assertEq(reqs.length, 2);
        assertEq(reqs[0], REQUEST_HASH_1);
        assertEq(reqs[1], REQUEST_HASH_2);
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Fuzz
    // ─────────────────────────────────────────────────────────────────────────

    function testFuzz_validationResponse_anyValidScore(uint8 score) public {
        vm.assume(score <= 100);

        bytes32 rHash = keccak256(abi.encode(score, "fuzz"));

        vm.prank(agentOwner);
        valReg.validationRequest(validator1, agentId, "ipfs://fuzz", rHash);

        vm.prank(validator1);
        valReg.validationResponse(rHash, score, "", bytes32(0), "");

        (,, uint8 stored,,,) = valReg.getValidationStatus(rHash);
        assertEq(stored, score);
    }
}
