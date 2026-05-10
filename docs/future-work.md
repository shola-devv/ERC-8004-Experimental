# Future Work

This document tracks planned improvements and research directions for the ERC-8004 experimental implementation.

---

## Protocol Extensions

### Upgradeability (UUPS Proxy)
The current implementation deploys contracts as immutable. A future production-grade deployment should use the UUPS (Universal Upgradeable Proxy Standard) pattern, allowing the protocol to incorporate spec changes without breaking existing agent IDs.

### Cross-chain Identity Linking
The spec supports `registrations[]` in the agent file pointing to registrations on other chains. A future extension could add an on-chain cross-chain registry link verifier using LayerZero or Axelar.

### Subgraph Integration
A The Graph subgraph manifest (`subgraph.yaml`) would enable indexed queries over:
- All agents registered per address
- Reputation time-series per agent
- Validation pass-rate histograms per validator

### Validator Contract Templates
Ship example validator implementations:
- `StakeSecuredValidator.sol` — requires ETH stake, slashes on challenge
- `MultiSigJudge.sol` — N-of-M trusted signers vote on validation
- `MockValidator.sol` — For testing only

### zkML Integration
A ZK-proof-based validator that accepts a Groth16 or PLONK proof from a zkML framework (e.g. EZKL) and posts `response = 100` only on valid proof verification.

---

## Protocol Maturity

### Formal Verification
Write Certora or Halmos invariant specs for:
- `agentWallet` is never set without a valid signature
- `feedbackIndex` is strictly monotonically increasing per `(agentId, clientAddress)`
- A revoked feedback record's `isRevoked` is never reset to `false`

### Gas Optimisation
Current targets for optimisation:
- `readAllFeedback()` double-loop allocates dynamic arrays — consider pagination
- `getSummary()` in ReputationRegistry does keccak-based tag comparison in loops — consider `bytes32` tags
- Packing `FeedbackRecord` fields tighter in storage

### L2 Deployment Optimisation
Optimise for L2 calldata costs:
- Use compact encodings for `tag1` / `tag2` (short strings or `bytes32`)
- Batch registration + metadata in a single transaction

---

## Ecosystem

### Off-chain Agent SDK
A TypeScript/Python SDK for:
- Signing agent registration files
- Constructing EIP-712 signatures for `setAgentWallet`
- Querying `getSummary` with a pre-built trusted reviewer list
- Posting feedback from MCP/A2A task results

### DAO-governed Validation Rules
A governance module where token holders vote on:
- Approved validator contracts
- Required minimum validation score thresholds
- Reputation weighting formulas

### Insurance Pool Integration
Reputation data feeds into an insurance pool where agents with high reputation can offer coverage for failed tasks, funded by fees.

---

## Roadmap

- [x] Minimal registry implementation (Identity, Reputation, Validation)
- [x] Full interface separation (`IIdentityRegistry`, `IReputationRegistry`, `IValidationRegistry`)
- [x] Foundry test suite with fuzz tests
- [x] EIP-712 agent wallet binding
- [x] Security model documentation
- [ ] UUPS proxy upgrade pattern
- [ ] Subgraph manifest
- [ ] Cross-agent reputation weighting
- [ ] DAO-governed validation rules
- [ ] Off-chain agent SDK (TypeScript)
- [ ] L2 deployment optimisation
- [ ] zkML validator template
- [ ] Formal invariant verification (Certora/Halmos)

## corrections/contribution/suggestions
if you have suggstions reach out to me here [shola Emmanuel Fayinminu](https://sholaemmanuel.dev)