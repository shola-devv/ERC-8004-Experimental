// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.24;

import {IReputationRegistry} from "../interfaces/IReputationRegistry.sol";
import {IIdentityRegistry} from "../interfaces/IIdentityRegistry.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";

/// @title ReputationRegistry
/// @author ERC-8004 Experimental Implementation
/// @notice On-chain feedback store for ERC-8004 agent reputation.
///
/// ─── Concept ────────────────────────────────────────────────────────────────
/// Think of this as "Yelp for autonomous agents."
///
/// Any address (the "clientAddress") may post a signed feedback signal for a
/// registered agent. Feedback consists of:
///   • A fixed-point signed integer `value` with `valueDecimals` precision
///     (e.g. value=9977, decimals=2 → 99.77% uptime)
///   • Optional tags for filtering (e.g. "starred", "uptime", "successRate")
///   • An optional off-chain feedback file URI + keccak256 hash for integrity
///
/// Key design choices (spec-faithful):
///   • Agent owners / operators CANNOT review their own agents (anti-gaming)
///   • getSummary() REQUIRES a non-empty clientAddresses array — callers curate
///     their trusted reviewer set, which is the protocol's primary Sybil defence
///   • Revoked feedback is NOT deleted — isRevoked flag is preserved for auditing
///   • appendResponse() is permissionless — anyone can attach a response URI
///     (e.g. agents posting refund proofs, aggregators tagging spam)
///   • feedbackIndex is 1-based per (agentId, clientAddress) pair
///
/// Storage layout:
///   _feedback[agentId][clientAddress][feedbackIndex] → FeedbackRecord
///   _clients[agentId] → address[] (for enumeration)
///   _hasGivenFeedback[agentId][clientAddress] → bool (avoids duplicate pushes)
///   _responseCounts[agentId][clientAddress][feedbackIndex] → uint64
/// ────────────────────────────────────────────────────────────────────────────
contract ReputationRegistry is IReputationRegistry {

    // ─────────────────────────────────────────────────────────────────────────
    // Structs
    // ─────────────────────────────────────────────────────────────────────────

    struct FeedbackRecord {
        int128  value;
        uint8   valueDecimals;
        string  tag1;
        string  tag2;
        bool    isRevoked;
        bool    exists;
    }

    // ─────────────────────────────────────────────────────────────────────────
    // State
    // ─────────────────────────────────────────────────────────────────────────

    address private immutable _identityRegistry;

    /// @dev agentId → clientAddress → feedbackIndex → FeedbackRecord
    ///      feedbackIndex is 1-based.
    mapping(uint256 => mapping(address => mapping(uint64 => FeedbackRecord))) private _feedback;

    /// @dev agentId → clientAddress → last feedbackIndex submitted (0 = none)
    mapping(uint256 => mapping(address => uint64)) private _lastIndex;

    /// @dev agentId → list of client addresses (for enumeration)
    mapping(uint256 => address[]) private _clients;

    /// @dev agentId → clientAddress → has ever submitted feedback (to avoid duplicate pushes)
    mapping(uint256 => mapping(address => bool)) private _hasGivenFeedback;

    /// @dev agentId → clientAddress → feedbackIndex → response count
    mapping(uint256 => mapping(address => mapping(uint64 => uint64))) private _responseCounts;

    // ─────────────────────────────────────────────────────────────────────────
    // Constructor
    // ─────────────────────────────────────────────────────────────────────────

    /// @param identityRegistry_ Address of the deployed IdentityRegistry contract.
    constructor(address identityRegistry_) {
        require(identityRegistry_ != address(0), "ReputationRegistry: zero address");
        _identityRegistry = identityRegistry_;
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Initialisation read
    // ─────────────────────────────────────────────────────────────────────────

    /// @inheritdoc IReputationRegistry
    function getIdentityRegistry() external view override returns (address) {
        return _identityRegistry;
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Write: Give Feedback
    // ─────────────────────────────────────────────────────────────────────────

    /// @inheritdoc IReputationRegistry
    function giveFeedback(
        uint256 agentId,
        int128  value,
        uint8   valueDecimals,
        string  calldata tag1,
        string  calldata tag2,
        string  calldata endpoint,
        string  calldata feedbackURI,
        bytes32 feedbackHash
    ) external override {
        // ── Guards ──────────────────────────────────────────────────────────
        require(valueDecimals <= 18, "ReputationRegistry: valueDecimals > 18");

        // agentId must be a minted token
        address agentOwner = IERC721(_identityRegistry).ownerOf(agentId);

        // Caller must not be owner or operator of the agent being reviewed
        require(
            msg.sender != agentOwner
                && !IERC721(_identityRegistry).isApprovedForAll(agentOwner, msg.sender)
                && IERC721(_identityRegistry).getApproved(agentId) != msg.sender,
            "ReputationRegistry: agent owner/operator cannot give feedback"
        );

        // ── Write ────────────────────────────────────────────────────────────
        uint64 idx = _lastIndex[agentId][msg.sender] + 1;
        _lastIndex[agentId][msg.sender] = idx;

        _feedback[agentId][msg.sender][idx] = FeedbackRecord({
            value:         value,
            valueDecimals: valueDecimals,
            tag1:          tag1,
            tag2:          tag2,
            isRevoked:     false,
            exists:        true
        });

        // Track unique clients
        if (!_hasGivenFeedback[agentId][msg.sender]) {
            _hasGivenFeedback[agentId][msg.sender] = true;
            _clients[agentId].push(msg.sender);
        }

        emit NewFeedback(
            agentId,
            msg.sender,
            idx,
            value,
            valueDecimals,
            tag1,
            tag1,
            tag2,
            endpoint,
            feedbackURI,
            feedbackHash
        );
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Write: Revoke Feedback
    // ─────────────────────────────────────────────────────────────────────────

    /// @inheritdoc IReputationRegistry
    function revokeFeedback(uint256 agentId, uint64 feedbackIndex) external override {
        FeedbackRecord storage rec = _feedback[agentId][msg.sender][feedbackIndex];
        require(rec.exists, "ReputationRegistry: feedback not found");
        require(!rec.isRevoked, "ReputationRegistry: already revoked");
        rec.isRevoked = true;
        emit FeedbackRevoked(agentId, msg.sender, feedbackIndex);
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Write: Append Response
    // ─────────────────────────────────────────────────────────────────────────

    /// @inheritdoc IReputationRegistry
    function appendResponse(
        uint256 agentId,
        address clientAddress,
        uint64  feedbackIndex,
        string  calldata responseURI,
        bytes32 responseHash
    ) external override {
        FeedbackRecord storage rec = _feedback[agentId][clientAddress][feedbackIndex];
        require(rec.exists, "ReputationRegistry: feedback not found");

        _responseCounts[agentId][clientAddress][feedbackIndex]++;

        emit ResponseAppended(
            agentId,
            clientAddress,
            feedbackIndex,
            msg.sender,
            responseURI,
            responseHash
        );
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Read: getSummary
    // ─────────────────────────────────────────────────────────────────────────

    /// @inheritdoc IReputationRegistry
    function getSummary(
        uint256  agentId,
        address[] calldata clientAddresses,
        string   calldata tag1,
        string   calldata tag2
    )
        external
        view
        override
        returns (uint64 count, int128 summaryValue, uint8 summaryValueDecimals)
    {
        require(clientAddresses.length > 0, "ReputationRegistry: clientAddresses required");

        bool filterTag1 = bytes(tag1).length > 0;
        bool filterTag2 = bytes(tag2).length > 0;

        // Accumulate in 256-bit space to avoid overflow during summation
        int256  acc;
        uint256 decimalNorm;  // We use the first non-revoked entry's decimals as canonical
        bool    decimalsSet;

        for (uint256 i; i < clientAddresses.length; ) {
            address client = clientAddresses[i];
            uint64 last = _lastIndex[agentId][client];

            for (uint64 j = 1; j <= last; ) {
                FeedbackRecord storage rec = _feedback[agentId][client][j];

                if (!rec.exists || rec.isRevoked) {
                    unchecked { ++j; }
                    continue;
                }
                if (filterTag1 && keccak256(bytes(rec.tag1)) != keccak256(bytes(tag1))) {
                    unchecked { ++j; }
                    continue;
                }
                if (filterTag2 && keccak256(bytes(rec.tag2)) != keccak256(bytes(tag2))) {
                    unchecked { ++j; }
                    continue;
                }

                if (!decimalsSet) {
                    decimalNorm = rec.valueDecimals;
                    decimalsSet = true;
                }
                // Normalise to a common decimal scale (use first seen)
                if (rec.valueDecimals >= decimalNorm) {
                    acc += int256(rec.value) * int256(10 ** (rec.valueDecimals - decimalNorm));
                } else {
                    acc += int256(rec.value) / int256(10 ** (decimalNorm - rec.valueDecimals));
                }
                unchecked { ++count; ++j; }
            }
            unchecked { ++i; }
        }

        summaryValue         = int128(acc);
        summaryValueDecimals = decimalsSet ? uint8(decimalNorm) : 0;
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Read: readFeedback
    // ─────────────────────────────────────────────────────────────────────────

    /// @inheritdoc IReputationRegistry
    function readFeedback(uint256 agentId, address clientAddress, uint64 feedbackIndex)
        external
        view
        override
        returns (
            int128  value,
            uint8   valueDecimals,
            string  memory tag1,
            string  memory tag2,
            bool    isRevoked
        )
    {
        FeedbackRecord storage rec = _feedback[agentId][clientAddress][feedbackIndex];
        require(rec.exists, "ReputationRegistry: feedback not found");
        return (rec.value, rec.valueDecimals, rec.tag1, rec.tag2, rec.isRevoked);
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Read: readAllFeedback
    // ─────────────────────────────────────────────────────────────────────────

    /// @inheritdoc IReputationRegistry
    function readAllFeedback(
        uint256  agentId,
        address[] calldata clientAddresses,
        string   calldata tag1,
        string   calldata tag2,
        bool     includeRevoked
    )
        external
        view
        override
        returns (
            address[] memory clients,
            uint64[]  memory feedbackIndexes,
            int128[]  memory values,
            uint8[]   memory valueDecimals,
            string[]  memory tag1s,
            string[]  memory tag2s,
            bool[]    memory revokedStatuses
        )
    {
        // Use all clients if none specified
        address[] memory sourceClients = clientAddresses.length > 0
            ? clientAddresses
            : _clients[agentId];

        bool filterTag1 = bytes(tag1).length > 0;
        bool filterTag2 = bytes(tag2).length > 0;

        // ── First pass: count matching entries ───────────────────────────────
        uint256 total;
        for (uint256 i; i < sourceClients.length; ) {
            uint64 last = _lastIndex[agentId][sourceClients[i]];
            for (uint64 j = 1; j <= last; ) {
                FeedbackRecord storage rec = _feedback[agentId][sourceClients[i]][j];
                if (_matchesFilter(rec, filterTag1, tag1, filterTag2, tag2, includeRevoked)) {
                    unchecked { ++total; }
                }
                unchecked { ++j; }
            }
            unchecked { ++i; }
        }

        // ── Allocate ─────────────────────────────────────────────────────────
        clients         = new address[](total);
        feedbackIndexes = new uint64[](total);
        values          = new int128[](total);
        valueDecimals   = new uint8[](total);
        tag1s           = new string[](total);
        tag2s           = new string[](total);
        revokedStatuses = new bool[](total);

        // ── Second pass: populate ─────────────────────────────────────────────
        uint256 cursor;
        for (uint256 i; i < sourceClients.length; ) {
            address client = sourceClients[i];
            uint64 last = _lastIndex[agentId][client];
            for (uint64 j = 1; j <= last; ) {
                FeedbackRecord storage rec = _feedback[agentId][client][j];
                if (_matchesFilter(rec, filterTag1, tag1, filterTag2, tag2, includeRevoked)) {
                    clients[cursor]         = client;
                    feedbackIndexes[cursor] = j;
                    values[cursor]          = rec.value;
                    valueDecimals[cursor]   = rec.valueDecimals;
                    tag1s[cursor]           = rec.tag1;
                    tag2s[cursor]           = rec.tag2;
                    revokedStatuses[cursor] = rec.isRevoked;
                    unchecked { ++cursor; }
                }
                unchecked { ++j; }
            }
            unchecked { ++i; }
        }
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Read: getResponseCount
    // ─────────────────────────────────────────────────────────────────────────

    /// @inheritdoc IReputationRegistry
    function getResponseCount(
        uint256  agentId,
        address  clientAddress,
        uint64   feedbackIndex,
        address[] calldata /* responders — filter not stored on-chain, use events */
    ) external view override returns (uint64) {
        return _responseCounts[agentId][clientAddress][feedbackIndex];
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Read: getClients / getLastIndex
    // ─────────────────────────────────────────────────────────────────────────

    /// @inheritdoc IReputationRegistry
    function getClients(uint256 agentId) external view override returns (address[] memory) {
        return _clients[agentId];
    }

    /// @inheritdoc IReputationRegistry
    function getLastIndex(uint256 agentId, address clientAddress)
        external
        view
        override
        returns (uint64)
    {
        return _lastIndex[agentId][clientAddress];
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Internal helpers
    // ─────────────────────────────────────────────────────────────────────────

    function _matchesFilter(
        FeedbackRecord storage rec,
        bool filterTag1,
        string calldata tag1,
        bool filterTag2,
        string calldata tag2,
        bool includeRevoked
    ) internal view returns (bool) {
        if (!rec.exists) return false;
        if (!includeRevoked && rec.isRevoked) return false;
        if (filterTag1 && keccak256(bytes(rec.tag1)) != keccak256(bytes(tag1))) return false;
        if (filterTag2 && keccak256(bytes(rec.tag2)) != keccak256(bytes(tag2))) return false;
        return true;
    }
}
