// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.24;

/// @title IIdentityRegistry
/// @notice Interface for the ERC-8004 Identity Registry — the on-chain NFT-based agent identity layer.
/// @dev Agents are ERC-721 tokens. Each token's URI resolves to a JSON registration file.
///      The owner of a token is the owner of the agent. Operators may update the agentURI.
interface IIdentityRegistry {
    // ─────────────────────────────────────────────────────────────────────────────
    // Structs
    // ─────────────────────────────────────────────────────────────────────────────

    /// @notice Arbitrary on-chain metadata attached to an agent.
    struct MetadataEntry {
        string metadataKey;
        bytes  metadataValue;
    }

    // ─────────────────────────────────────────────────────────────────────────────
    // Events
    // ─────────────────────────────────────────────────────────────────────────────

    /// @notice Emitted when a new agent is registered (minted).
    event Registered(uint256 indexed agentId, string agentURI, address indexed owner);

    /// @notice Emitted when the agentURI is updated.
    event URIUpdated(uint256 indexed agentId, string newURI, address indexed updatedBy);

    /// @notice Emitted when arbitrary metadata is written for an agent.
    event MetadataSet(
        uint256 indexed agentId,
        string indexed indexedMetadataKey,
        string metadataKey,
        bytes  metadataValue
    );

    // ─────────────────────────────────────────────────────────────────────────────
    // Registration
    // ─────────────────────────────────────────────────────────────────────────────

    /// @notice Register a new agent with a URI and optional initial metadata.
    /// @param agentURI  The URI resolving to the JSON registration file.
    /// @param metadata  Array of initial metadata key/value pairs.
    /// @return agentId  The minted token ID.
    function register(string calldata agentURI, MetadataEntry[] calldata metadata)
        external
        returns (uint256 agentId);

    /// @notice Register a new agent with only a URI.
    function register(string calldata agentURI) external returns (uint256 agentId);

    /// @notice Register a new agent with no URI (URI can be set later via setAgentURI).
    function register() external returns (uint256 agentId);

    // ─────────────────────────────────────────────────────────────────────────────
    // URI Management
    // ─────────────────────────────────────────────────────────────────────────────

    /// @notice Update the agentURI for an existing agent.
    /// @dev Caller MUST be owner or approved operator of agentId.
    function setAgentURI(uint256 agentId, string calldata newURI) external;

    // ─────────────────────────────────────────────────────────────────────────────
    // Metadata
    // ─────────────────────────────────────────────────────────────────────────────

    /// @notice Read on-chain metadata for an agent.
    /// @param agentId     The agent whose metadata to read.
    /// @param metadataKey The metadata key.
    /// @return            The raw bytes stored for that key.
    function getMetadata(uint256 agentId, string memory metadataKey)
        external
        view
        returns (bytes memory);

    /// @notice Write on-chain metadata for an agent.
    /// @dev    The key "agentWallet" is RESERVED and MUST NOT be set via this function.
    ///         Caller MUST be owner or approved operator of agentId.
    function setMetadata(uint256 agentId, string calldata metadataKey, bytes calldata metadataValue)
        external;

    // ─────────────────────────────────────────────────────────────────────────────
    // Agent Wallet (reserved metadata)
    // ─────────────────────────────────────────────────────────────────────────────

    /// @notice Return the currently set agent payment wallet.
    /// @dev    Returns address(0) if none is set or after a transfer (which clears it).
    function getAgentWallet(uint256 agentId) external view returns (address);

    /// @notice Set a verified agent wallet via EIP-712 signature.
    /// @dev    The new wallet proves control by signing an EIP-712 typed-data message.
    ///         Caller MUST be owner or approved operator of agentId.
    /// @param agentId    The agent to update.
    /// @param newWallet  The wallet address being registered.
    /// @param deadline   Unix timestamp after which the signature is invalid.
    /// @param signature  EIP-712 signature from newWallet (EOA) or ERC-1271 sig (smart wallet).
    function setAgentWallet(
        uint256 agentId,
        address newWallet,
        uint256 deadline,
        bytes calldata signature
    ) external;

    /// @notice Clear the agent wallet for an agent.
    /// @dev    Caller MUST be owner or approved operator.
    function unsetAgentWallet(uint256 agentId) external;
}
