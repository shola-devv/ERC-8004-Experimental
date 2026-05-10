// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.24;

import {IValidationRegistry} from "../interfaces/IValidationRegistry.sol";
import {IIdentityRegistry} from "../interfaces/IIdentityRegistry.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";

/// @title ValidationRegistry
/// @author ERC-8004 Experimental Implementation
/// @notice Tracks cryptographic validation requests and responses for ERC-8004 agents.
///
/// ─── Concept ────────────────────────────────────────────────────────────────
/// Think of this as "third-party auditors for autonomous agents."
///
/// An agent (or its operator) posts a validation request targeting a specific
/// validator contract — a smart contract that knows how to verify a class of
/// work outputs. The request commits to its data via a keccak256 hash
/// (requestHash), which becomes the primary key.
///
/// Validator contracts then post one or more responses per requestHash.
/// The response field is 0-100 (binary-friendly: 0 = fail, 100 = pass;
/// intermediate values for partial/probabilistic outcomes).
///
/// Progressive finality is supported: the same validator can call
/// validationResponse() multiple times on the same requestHash
/// (e.g. "soft-finality" → "hard-finality" tags).
///
/// Examples of validator implementations (out of scope here):
///   • Stake-secured re-execution (optimistic, slashable)
///   • zkML verifiers (ZK proof of correct inference)
///   • TEE oracles (trusted execution environment attestations)
///   • Trusted human judges (multisig-gated)
///
/// Storage layout:
///   _requests[requestHash]           → ValidationRecord
///   _agentValidations[agentId]       → bytes32[] requestHashes
///   _validatorRequests[validator]    → bytes32[] requestHashes
/// ────────────────────────────────────────────────────────────────────────────
contract ValidationRegistry is IValidationRegistry {

    // ─────────────────────────────────────────────────────────────────────────
    // Structs
    // ─────────────────────────────────────────────────────────────────────────

    struct ValidationRecord {
        address validatorAddress;
        uint256 agentId;
        uint8   response;
        bytes32 responseHash;
        string  tag;
        uint256 lastUpdate;
        bool    exists;
    }

    // ─────────────────────────────────────────────────────────────────────────
    // State
    // ─────────────────────────────────────────────────────────────────────────

    address private immutable _identityRegistry;

    /// @dev requestHash → ValidationRecord
    mapping(bytes32 => ValidationRecord) private _requests;

    /// @dev agentId → list of requestHashes (for enumeration)
    mapping(uint256 => bytes32[]) private _agentValidations;

    /// @dev validatorAddress → list of requestHashes
    mapping(address => bytes32[]) private _validatorRequests;

    // ─────────────────────────────────────────────────────────────────────────
    // Constructor
    // ─────────────────────────────────────────────────────────────────────────

    /// @param identityRegistry_ Address of the deployed IdentityRegistry contract.
    constructor(address identityRegistry_) {
        require(identityRegistry_ != address(0), "ValidationRegistry: zero address");
        _identityRegistry = identityRegistry_;
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Initialisation read
    // ─────────────────────────────────────────────────────────────────────────

    /// @inheritdoc IValidationRegistry
    function getIdentityRegistry() external view override returns (address) {
        return _identityRegistry;
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Write: validationRequest
    // ─────────────────────────────────────────────────────────────────────────

    /// @inheritdoc IValidationRegistry
    function validationRequest(
        address validatorAddress,
        uint256 agentId,
        string  calldata requestURI,
        bytes32 requestHash
    ) external override {
        require(validatorAddress != address(0), "ValidationRegistry: zero validator");

        // agentId must exist — ownerOf reverts if not
        address agentOwner = IERC721(_identityRegistry).ownerOf(agentId);

        // Caller must be owner or operator of the agent
        require(
            msg.sender == agentOwner
                || IERC721(_identityRegistry).isApprovedForAll(agentOwner, msg.sender)
                || IERC721(_identityRegistry).getApproved(agentId) == msg.sender,
            "ValidationRegistry: not agent owner or operator"
        );

        require(requestHash != bytes32(0), "ValidationRegistry: empty requestHash");
        require(
            !_requests[requestHash].exists,
            "ValidationRegistry: requestHash already used"
        );

        // Store the request skeleton (response fields populated on response)
        _requests[requestHash] = ValidationRecord({
            validatorAddress: validatorAddress,
            agentId:          agentId,
            response:         0,
            responseHash:     bytes32(0),
            tag:              "",
            lastUpdate:       0,
            exists:           true
        });

        _agentValidations[agentId].push(requestHash);
        _validatorRequests[validatorAddress].push(requestHash);

        emit ValidationRequest(validatorAddress, agentId, requestURI, requestHash);
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Write: validationResponse
    // ─────────────────────────────────────────────────────────────────────────

    /// @inheritdoc IValidationRegistry
    function validationResponse(
        bytes32 requestHash,
        uint8   response,
        string  calldata responseURI,
        bytes32 responseHash,
        string  calldata tag
    ) external override {
        ValidationRecord storage rec = _requests[requestHash];
        require(rec.exists, "ValidationRegistry: unknown requestHash");
        require(
            rec.validatorAddress == msg.sender,
            "ValidationRegistry: caller is not the designated validator"
        );
        require(response <= 100, "ValidationRegistry: response > 100");

        // Update stored state (supports multiple calls for progressive finality)
        rec.response     = response;
        rec.responseHash = responseHash;
        rec.tag          = tag;
        rec.lastUpdate   = block.timestamp;

        emit ValidationResponse(
            msg.sender,
            rec.agentId,
            requestHash,
            response,
            responseURI,
            responseHash,
            tag
        );
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Read: getValidationStatus
    // ─────────────────────────────────────────────────────────────────────────

    /// @inheritdoc IValidationRegistry
    function getValidationStatus(bytes32 requestHash)
        external
        view
        override
        returns (
            address validatorAddress,
            uint256 agentId,
            uint8   response,
            bytes32 responseHash,
            string  memory tag,
            uint256 lastUpdate
        )
    {
        ValidationRecord storage rec = _requests[requestHash];
        require(rec.exists, "ValidationRegistry: unknown requestHash");
        return (
            rec.validatorAddress,
            rec.agentId,
            rec.response,
            rec.responseHash,
            rec.tag,
            rec.lastUpdate
        );
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Read: getSummary
    // ─────────────────────────────────────────────────────────────────────────

    /// @inheritdoc IValidationRegistry
    function getSummary(
        uint256  agentId,
        address[] calldata validatorAddresses,
        string   calldata tag
    )
        external
        view
        override
        returns (uint64 count, uint8 averageResponse)
    {
        bytes32[] storage hashes = _agentValidations[agentId];
        bool filterValidator = validatorAddresses.length > 0;
        bool filterTag       = bytes(tag).length > 0;

        uint256 total;
        uint256 sum;

        for (uint256 i; i < hashes.length; ) {
            ValidationRecord storage rec = _requests[hashes[i]];
            if (rec.lastUpdate == 0) { unchecked { ++i; } continue; } // no response yet

            if (filterValidator && !_inList(rec.validatorAddress, validatorAddresses)) {
                unchecked { ++i; }
                continue;
            }
            if (filterTag && keccak256(bytes(rec.tag)) != keccak256(bytes(tag))) {
                unchecked { ++i; }
                continue;
            }

            unchecked {
                sum += rec.response;
                ++total;
                ++i;
            }
        }

        count           = uint64(total);
        averageResponse = total > 0 ? uint8(sum / total) : 0;
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Read: getAgentValidations / getValidatorRequests
    // ─────────────────────────────────────────────────────────────────────────

    /// @inheritdoc IValidationRegistry
    function getAgentValidations(uint256 agentId)
        external
        view
        override
        returns (bytes32[] memory)
    {
        return _agentValidations[agentId];
    }

    /// @inheritdoc IValidationRegistry
    function getValidatorRequests(address validatorAddress)
        external
        view
        override
        returns (bytes32[] memory)
    {
        return _validatorRequests[validatorAddress];
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Internal helpers
    // ─────────────────────────────────────────────────────────────────────────

    function _inList(address target, address[] calldata list)
        internal
        pure
        returns (bool)
    {
        for (uint256 i; i < list.length; ) {
            if (list[i] == target) return true;
            unchecked { ++i; }
        }
        return false;
    }
}
