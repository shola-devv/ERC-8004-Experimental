// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.24;

/// @title IValidationRegistry
/// @notice Interface for the ERC-8004 Validation Registry.
/// @dev    Agents post validation requests; validator contracts post cryptographically
///         committed responses. Enables stake-secured re-execution, zkML, TEE oracles, etc.
interface IValidationRegistry {
    // ─────────────────────────────────────────────────────────────────────────────
    // Events
    // ─────────────────────────────────────────────────────────────────────────────

    /// @notice Emitted when an agent requests validation.
    event ValidationRequest(
        address indexed validatorAddress,
        uint256 indexed agentId,
        string  requestURI,
        bytes32 indexed requestHash
    );

    /// @notice Emitted when a validator submits a response.
    event ValidationResponse(
        address indexed validatorAddress,
        uint256 indexed agentId,
        bytes32 indexed requestHash,
        uint8   response,
        string  responseURI,
        bytes32 responseHash,
        string  tag
    );

    // ─────────────────────────────────────────────────────────────────────────────
    // Initialisation
    // ─────────────────────────────────────────────────────────────────────────────

    /// @notice Return the IdentityRegistry this contract is paired with.
    function getIdentityRegistry() external view returns (address identityRegistry);

    // ─────────────────────────────────────────────────────────────────────────────
    // Write Functions
    // ─────────────────────────────────────────────────────────────────────────────

    /// @notice Request validation from a specific validator contract.
    /// @dev    MUST be called by the owner or approved operator of agentId.
    /// @param validatorAddress  Address of the validator smart contract.
    /// @param agentId           The agent requesting validation.
    /// @param requestURI        Off-chain URI with all inputs/outputs for the validator.
    /// @param requestHash       keccak256 commitment of the request payload.
    function validationRequest(
        address validatorAddress,
        uint256 agentId,
        string  calldata requestURI,
        bytes32 requestHash
    ) external;

    /// @notice Submit a validation response for a prior request.
    /// @dev    MUST be called by the validatorAddress from the original request.
    ///         response is 0-100 (0 = fail, 100 = pass, intermediates for partial).
    ///         May be called multiple times per requestHash for progressive finality.
    /// @param requestHash   The commitment hash from the original validationRequest.
    /// @param response      Score 0-100 indicating validation outcome.
    /// @param responseURI   Optional off-chain evidence URI.
    /// @param responseHash  keccak256 of responseURI content (omit for IPFS).
    /// @param tag           Optional categorization (e.g. "soft-finality", "hard-finality").
    function validationResponse(
        bytes32 requestHash,
        uint8   response,
        string  calldata responseURI,
        bytes32 responseHash,
        string  calldata tag
    ) external;

    // ─────────────────────────────────────────────────────────────────────────────
    // Read Functions
    // ─────────────────────────────────────────────────────────────────────────────

    /// @notice Return the latest stored validation state for a request.
    function getValidationStatus(bytes32 requestHash)
        external
        view
        returns (
            address validatorAddress,
            uint256 agentId,
            uint8   response,
            bytes32 responseHash,
            string  memory tag,
            uint256 lastUpdate
        );

    /// @notice Aggregate validation results for an agent.
    /// @dev    agentId is mandatory; validatorAddresses and tag are optional filters.
    function getSummary(
        uint256  agentId,
        address[] calldata validatorAddresses,
        string   calldata tag
    ) external view returns (uint64 count, uint8 averageResponse);

    /// @notice Return all requestHashes associated with an agent.
    function getAgentValidations(uint256 agentId) external view returns (bytes32[] memory);

    /// @notice Return all requestHashes submitted to a validator.
    function getValidatorRequests(address validatorAddress) external view returns (bytes32[] memory);
}
