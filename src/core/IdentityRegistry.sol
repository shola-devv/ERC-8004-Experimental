// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.24;

import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import {ERC721URIStorage} from "@openzeppelin/contracts/token/ERC721/extensions/ERC721URIStorage.sol";
import {IERC1271} from "@openzeppelin/contracts/interfaces/IERC1271.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {EIP712} from "@openzeppelin/contracts/utils/cryptography/EIP712.sol";
import {IIdentityRegistry} from "../interfaces/IIdentityRegistry.sol";

/// @title IdentityRegistry
/// @author ERC-8004 Experimental Implementation
/// @notice ERC-721–based agent identity registry conforming to ERC-8004.
///
/// ─── Concept ────────────────────────────────────────────────────────────────
/// Every autonomous agent is minted as an ERC-721 NFT. The token URI resolves
/// to a JSON registration file containing the agent's description, service
/// endpoints (MCP, A2A, ENS, DID, …), and the trust models it supports.
///
/// Ownership = control of the agent's on-chain identity.
/// Operators (approved via ERC-721 approve / setApprovalForAll) may update
/// the agentURI and write metadata without owning the token.
///
/// The reserved key "agentWallet" points to the wallet that receives payments.
/// Setting it requires an EIP-712 signature from the wallet being registered
/// (EOA) or an ERC-1271 signature (smart contract wallet), ensuring only the
/// true controller of that address can bind it to an agent.
/// On ERC-721 transfer, agentWallet is cleared automatically.
/// ────────────────────────────────────────────────────────────────────────────
contract IdentityRegistry is ERC721URIStorage, EIP712, IIdentityRegistry {
    using ECDSA for bytes32;

    // ─────────────────────────────────────────────────────────────────────────
    // Constants
    // ─────────────────────────────────────────────────────────────────────────

    /// @dev Reserved metadata key — cannot be written via setMetadata().
    string private constant AGENT_WALLET_KEY = "agentWallet";

    /// @dev EIP-712 type hash for the agentWallet binding message.
    bytes32 private constant AGENT_WALLET_TYPEHASH =
        keccak256(
            "SetAgentWallet(uint256 agentId,address newWallet,uint256 deadline)"
        );

    /// @dev Magic value returned by ERC-1271 on successful validation.
    bytes4 private constant ERC1271_MAGIC = bytes4(keccak256("isValidSignature(bytes32,bytes)"));

    // ─────────────────────────────────────────────────────────────────────────
    // State
    // ─────────────────────────────────────────────────────────────────────────

    /// @dev Auto-incrementing token ID counter. Starts at 1 so 0 is never a valid agentId.
    uint256 private _nextId = 1;

    /// @dev agentId → metadataKey → raw bytes value
    mapping(uint256 => mapping(string => bytes)) private _metadata;

    /// @dev agentId → agent wallet address (reserved key, stored separately for type safety)
    mapping(uint256 => address) private _agentWallets;

    // ─────────────────────────────────────────────────────────────────────────
    // Constructor
    // ─────────────────────────────────────────────────────────────────────────

    constructor()
        ERC721("ERC8004 Agent Identity", "AGENT")
        EIP712("ERC8004IdentityRegistry", "1")
    {}

    // ─────────────────────────────────────────────────────────────────────────
    // Registration
    // ─────────────────────────────────────────────────────────────────────────

    /// @inheritdoc IIdentityRegistry
    function register(string calldata agentURI, MetadataEntry[] calldata metadata)
        external
        override
        returns (uint256 agentId)
    {
        agentId = _mintAgent(msg.sender, agentURI);
        _bulkSetMetadata(agentId, metadata);
    }

    /// @inheritdoc IIdentityRegistry
    function register(string calldata agentURI)
        external
        override
        returns (uint256 agentId)
    {
        agentId = _mintAgent(msg.sender, agentURI);
    }

    /// @inheritdoc IIdentityRegistry
    function register() external override returns (uint256 agentId) {
        agentId = _mintAgent(msg.sender, "");
    }

    // ─────────────────────────────────────────────────────────────────────────
    // URI Management
    // ─────────────────────────────────────────────────────────────────────────

    /// @inheritdoc IIdentityRegistry
    function setAgentURI(uint256 agentId, string calldata newURI)
        external
        override
        onlyAuthorized(agentId)
    {
        _setTokenURI(agentId, newURI);
        emit URIUpdated(agentId, newURI, msg.sender);
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Metadata
    // ─────────────────────────────────────────────────────────────────────────

    /// @inheritdoc IIdentityRegistry
    function getMetadata(uint256 agentId, string memory metadataKey)
        external
        view
        override
        returns (bytes memory)
    {
        _requireOwned(agentId); // reverts if token doesn't exist
        return _metadata[agentId][metadataKey];
    }

    /// @inheritdoc IIdentityRegistry
    function setMetadata(
        uint256 agentId,
        string calldata metadataKey,
        bytes calldata metadataValue
    ) external override onlyAuthorized(agentId) {
        require(
            keccak256(bytes(metadataKey)) != keccak256(bytes(AGENT_WALLET_KEY)),
            "IdentityRegistry: agentWallet key is reserved"
        );
        _writeMetadata(agentId, metadataKey, metadataValue);
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Agent Wallet (reserved)
    // ─────────────────────────────────────────────────────────────────────────

    /// @inheritdoc IIdentityRegistry
    function getAgentWallet(uint256 agentId)
        external
        view
        override
        returns (address)
    {
        _requireOwned(agentId);
        return _agentWallets[agentId];
    }

    /// @inheritdoc IIdentityRegistry
    function setAgentWallet(
        uint256 agentId,
        address newWallet,
        uint256 deadline,
        bytes calldata signature
    ) external override onlyAuthorized(agentId) {
        require(block.timestamp <= deadline, "IdentityRegistry: signature expired");
        require(newWallet != address(0), "IdentityRegistry: zero address");

        bytes32 structHash = keccak256(
            abi.encode(AGENT_WALLET_TYPEHASH, agentId, newWallet, deadline)
        );
        bytes32 digest = _hashTypedDataV4(structHash);

        // Try ERC-1271 first (smart contract wallets), fall back to ECDSA (EOAs)
        if (_isContract(newWallet)) {
            require(
                IERC1271(newWallet).isValidSignature(digest, signature) == ERC1271_MAGIC,
                "IdentityRegistry: invalid ERC-1271 signature"
            );
        } else {
            require(
                digest.recover(signature) == newWallet,
                "IdentityRegistry: invalid ECDSA signature"
            );
        }

        _agentWallets[agentId] = newWallet;
        // Emit as reserved metadata event for indexing consistency
        emit MetadataSet(agentId, AGENT_WALLET_KEY, AGENT_WALLET_KEY, abi.encode(newWallet));
    }

    /// @inheritdoc IIdentityRegistry
    function unsetAgentWallet(uint256 agentId)
        external
        override
        onlyAuthorized(agentId)
    {
        _agentWallets[agentId] = address(0);
        emit MetadataSet(agentId, AGENT_WALLET_KEY, AGENT_WALLET_KEY, abi.encode(address(0)));
    }

    // ─────────────────────────────────────────────────────────────────────────
    // EIP-712 Domain Separator (exposed for wallets)
    // ─────────────────────────────────────────────────────────────────────────

    /// @notice Returns the EIP-712 domain separator for this registry.
    function domainSeparator() external view returns (bytes32) {
        return _domainSeparatorV4();
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Internal Helpers
    // ─────────────────────────────────────────────────────────────────────────

    function _mintAgent(address owner, string memory agentURI)
        internal
        returns (uint256 agentId)
    {
        agentId = _nextId++;
        _safeMint(owner, agentId);
        if (bytes(agentURI).length > 0) {
            _setTokenURI(agentId, agentURI);
        }
        // Set agentWallet to owner address by default; stored outside _metadata mapping
        _agentWallets[agentId] = owner;
        emit MetadataSet(agentId, AGENT_WALLET_KEY, AGENT_WALLET_KEY, abi.encode(owner));
        emit Registered(agentId, agentURI, owner);
    }

    function _bulkSetMetadata(uint256 agentId, MetadataEntry[] calldata entries) internal {
        for (uint256 i; i < entries.length; ) {
            require(
                keccak256(bytes(entries[i].metadataKey)) != keccak256(bytes(AGENT_WALLET_KEY)),
                "IdentityRegistry: agentWallet key is reserved"
            );
            _writeMetadata(agentId, entries[i].metadataKey, entries[i].metadataValue);
            unchecked { ++i; }
        }
    }

    function _writeMetadata(
        uint256 agentId,
        string memory metadataKey,
        bytes memory metadataValue
    ) internal {
        _metadata[agentId][metadataKey] = metadataValue;
        emit MetadataSet(agentId, metadataKey, metadataKey, metadataValue);
    }

    function _isContract(address account) internal view returns (bool) {
        return account.code.length > 0;
    }

    // ─────────────────────────────────────────────────────────────────────────
    // ERC-721 Override: clear agentWallet on transfer
    // ─────────────────────────────────────────────────────────────────────────

    /// @dev Hook called before every token transfer. Clears agentWallet on transfer
    ///      (but NOT on mint, where from == address(0)).
    function _update(address to, uint256 tokenId, address auth)
        internal
        override
        returns (address)
    {
        address from = _ownerOf(tokenId);
        // Clear agentWallet on transfer (not on mint)
        if (from != address(0) && to != address(0)) {
            _agentWallets[tokenId] = address(0);
            emit MetadataSet(tokenId, AGENT_WALLET_KEY, AGENT_WALLET_KEY, abi.encode(address(0)));
        }
        return super._update(to, tokenId, auth);
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Modifiers
    // ─────────────────────────────────────────────────────────────────────────

    /// @dev Restricts to token owner or ERC-721 approved operator.
    modifier onlyAuthorized(uint256 agentId) {
        address owner = _requireOwned(agentId);
        require(
            msg.sender == owner
                || isApprovedForAll(owner, msg.sender)
                || getApproved(agentId) == msg.sender,
            "IdentityRegistry: not owner or operator"
        );
        _;
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Introspection
    // ─────────────────────────────────────────────────────────────────────────

    function supportsInterface(bytes4 interfaceId)
        public
        view
        override(ERC721URIStorage)
        returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }
}
