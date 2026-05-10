// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.24;

/// @title IReputationRegistry
/// @notice Interface for the ERC-8004 Reputation Registry.
/// @dev    Clients post signed fixed-point feedback signals for registered agents.
///         On-chain storage enables composability; off-chain aggregation handles
///         sophisticated scoring algorithms.
interface IReputationRegistry {
    // ─────────────────────────────────────────────────────────────────────────────
    // Events
    // ─────────────────────────────────────────────────────────────────────────────

    /// @notice Emitted when new feedback is submitted.
    event NewFeedback(
        uint256 indexed agentId,
        address indexed clientAddress,
        uint64  feedbackIndex,
        int128  value,
        uint8   valueDecimals,
        string indexed indexedTag1,
        string  tag1,
        string  tag2,
        string  endpoint,
        string  feedbackURI,
        bytes32 feedbackHash
    );

    /// @notice Emitted when feedback is revoked by the original submitter.
    event FeedbackRevoked(
        uint256 indexed agentId,
        address indexed clientAddress,
        uint64  indexed feedbackIndex
    );

    /// @notice Emitted when a response is appended to existing feedback.
    event ResponseAppended(
        uint256 indexed agentId,
        address indexed clientAddress,
        uint64  feedbackIndex,
        address indexed responder,
        string  responseURI,
        bytes32 responseHash
    );

    // ─────────────────────────────────────────────────────────────────────────────
    // Initialisation
    // ─────────────────────────────────────────────────────────────────────────────

    /// @notice Return the IdentityRegistry this contract is paired with.
    function getIdentityRegistry() external view returns (address identityRegistry);

    // ─────────────────────────────────────────────────────────────────────────────
    // Write Functions
    // ─────────────────────────────────────────────────────────────────────────────

    /// @notice Submit feedback for an agent.
    /// @dev    The caller (clientAddress) MUST NOT be the agent owner or approved operator.
    ///         valueDecimals MUST be in [0, 18].
    ///         tag1, tag2, endpoint, feedbackURI, feedbackHash are all OPTIONAL (pass "" / bytes32(0)).
    /// @param agentId       Target agent's token ID.
    /// @param value         Fixed-point score value.
    /// @param valueDecimals Number of decimals for `value` (0-18).
    /// @param tag1          Primary classification tag (e.g. "starred", "uptime").
    /// @param tag2          Secondary classification tag.
    /// @param endpoint      The specific endpoint this feedback concerns.
    /// @param feedbackURI   Off-chain feedback detail file URI.
    /// @param feedbackHash  keccak256 of feedbackURI contents (omit for IPFS).
    function giveFeedback(
        uint256 agentId,
        int128  value,
        uint8   valueDecimals,
        string  calldata tag1,
        string  calldata tag2,
        string  calldata endpoint,
        string  calldata feedbackURI,
        bytes32 feedbackHash
    ) external;

    /// @notice Revoke a previously submitted feedback entry.
    /// @dev    Caller MUST be the original clientAddress for that feedbackIndex.
    function revokeFeedback(uint256 agentId, uint64 feedbackIndex) external;

    /// @notice Append a response to existing feedback (anyone may call).
    /// @dev    Useful for agents posting refund proofs or spam-tagging aggregators.
    function appendResponse(
        uint256 agentId,
        address clientAddress,
        uint64  feedbackIndex,
        string  calldata responseURI,
        bytes32 responseHash
    ) external;

    // ─────────────────────────────────────────────────────────────────────────────
    // Read Functions
    // ─────────────────────────────────────────────────────────────────────────────

    /// @notice Aggregate feedback summary filtered by client addresses and tags.
    /// @dev    clientAddresses MUST be non-empty (Sybil-resistance: callers curate the list).
    function getSummary(
        uint256  agentId,
        address[] calldata clientAddresses,
        string   calldata tag1,
        string   calldata tag2
    ) external view returns (uint64 count, int128 summaryValue, uint8 summaryValueDecimals);

    /// @notice Read a single feedback entry.
    function readFeedback(uint256 agentId, address clientAddress, uint64 feedbackIndex)
        external
        view
        returns (
            int128  value,
            uint8   valueDecimals,
            string  memory tag1,
            string  memory tag2,
            bool    isRevoked
        );

    /// @notice Return all feedback entries matching optional filters.
    function readAllFeedback(
        uint256  agentId,
        address[] calldata clientAddresses,
        string   calldata tag1,
        string   calldata tag2,
        bool     includeRevoked
    )
        external
        view
        returns (
            address[] memory clients,
            uint64[]  memory feedbackIndexes,
            int128[]  memory values,
            uint8[]   memory valueDecimals,
            string[]  memory tag1s,
            string[]  memory tag2s,
            bool[]    memory revokedStatuses
        );

    /// @notice Count how many responses exist for a specific feedback entry.
    function getResponseCount(
        uint256  agentId,
        address  clientAddress,
        uint64   feedbackIndex,
        address[] calldata responders
    ) external view returns (uint64 count);

    /// @notice Return all client addresses that have given feedback to an agent.
    function getClients(uint256 agentId) external view returns (address[] memory);

    /// @notice Return the last feedbackIndex for a given (agentId, clientAddress) pair.
    function getLastIndex(uint256 agentId, address clientAddress) external view returns (uint64);
}
