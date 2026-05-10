# Architecture

## Overview

This is an experimental implementation of [ERC-8004: Trustless Agents](https://eips.ethereum.org/EIPS/eip-8004).

The protocol is composed of **three independent but interconnected registries**, all deployable as per-chain singletons. The `ReputationRegistry` and `ValidationRegistry` reference the `IdentityRegistry` at construction time and are stateless with respect to each other.

```
┌──────────────────────────────────────────────────────────────┐
│                       ERC-8004 Protocol                      │
│                                                              │
│  ┌─────────────────────┐                                     │
│  │  IdentityRegistry   │  ←── ERC-721 + URIStorage           │
│  │  (per-chain NFT)    │       + EIP-712 wallet binding       │
│  └─────────┬───────────┘                                     │
│            │ referenced by                                   │
│     ┌──────┴──────┐                                          │
│     ▼             ▼                                          │
│  ┌──────────┐  ┌─────────────┐                               │
│  │Reputation│  │ Validation  │                               │
│  │Registry  │  │ Registry    │                               │
│  └──────────┘  └─────────────┘                               │
└──────────────────────────────────────────────────────────────┘
```

---

## IdentityRegistry

**Pattern:** ERC-721 with `URIStorage`  
**Primary key:** `agentId` (auto-incremented `uint256`, 1-based)

### How registration works

1. Caller invokes `register(agentURI)` (or an overload).
2. A new ERC-721 token is minted to the caller (`agentId = _nextId++`).
3. `agentWallet` is initialised to the caller's address (stored separately in `_agentWallets`).
4. Optional `MetadataEntry[]` batch-writes arbitrary key→bytes values into `_metadata[agentId][key]`.

### Agent URI

The `agentURI` resolves to a JSON registration file. Any URI scheme is valid:

| Scheme | Example | Notes |
|---|---|---|
| `ipfs://` | `ipfs://QmXyz...` | Decentralised, content-addressed |
| `https://` | `https://myagent.com/reg.json` | Centralised, verifiable via domain check |
| `data:` | `data:application/json;base64,...` | Fully on-chain |

### Agent Wallet binding (EIP-712)

The `agentWallet` metadata key is **reserved**. To set it:

1. The owner calls `setAgentWallet(agentId, newWallet, deadline, signature)`.
2. The contract reconstructs the EIP-712 digest: `SetAgentWallet(uint256 agentId, address newWallet, uint256 deadline)`.
3. If `newWallet` is an EOA, it verifies via `ECDSA.recover`.
4. If `newWallet` is a contract, it delegates to `IERC1271.isValidSignature`.
5. On any token transfer, `agentWallet` is **automatically cleared** (reset to `address(0)`) and must be re-verified by the new owner.

---

## ReputationRegistry

**Pattern:** Feedback ledger keyed by `(agentId, clientAddress, feedbackIndex)`  
**Primary storage:** `_feedback[agentId][clientAddress][feedbackIndex] → FeedbackRecord`

### Feedback flow

```
clientAddress → giveFeedback() → FeedbackRecord stored + NewFeedback event
                                 (endpoint, feedbackURI, feedbackHash emitted only)
             → revokeFeedback() → isRevoked = true (record preserved for audit)
anyone        → appendResponse() → ResponseAppended event (count incremented)
```

### Sybil resistance

`getSummary()` **requires a non-empty `clientAddresses[]`**. The spec intentionally puts curation responsibility on the caller — clients build their own "trusted reviewer" lists off-chain (via subgraphs, attestation protocols, etc.) and pass them in for on-chain aggregation.

### Fixed-point arithmetic

Values use `int128` with a `uint8 valueDecimals` field. The `getSummary()` function normalises all entries to the first-seen decimal scale before accumulating.

---

## ValidationRegistry

**Pattern:** Commitment-based request/response ledger  
**Primary key:** `requestHash` (keccak256 of the off-chain payload)

### Validation flow

```
agentOwner → validationRequest(validatorAddress, agentId, uri, hash)
                → stored in _requests[hash]
                → ValidationRequest event

validatorContract → validationResponse(hash, score, responseURI, responseHash, tag)
                → overwrites stored record (supports multiple calls)
                → ValidationResponse event
```

### Progressive finality

A validator may call `validationResponse()` multiple times for the same `requestHash`. The `tag` field distinguishes finality stages (e.g. `"soft-finality"` → `"hard-finality"`). Each call emits a new event, preserving the full audit trail on-chain.

### Validator contract interface

Any contract may act as a validator — the registry only checks that `msg.sender == validatorAddress` from the original request. Validator contracts are responsible for their own incentive/slashing mechanisms (out of scope for ERC-8004).

---

## Cross-registry data flow (full lifecycle)

```
1. Developer deploys agent → IdentityRegistry.register()
   → agentId = 1, tokenURI = "ipfs://registration.json"

2. Client uses agent, posts feedback → ReputationRegistry.giveFeedback()
   → value = 87, tag1 = "starred"

3. Agent requests re-execution verification → ValidationRegistry.validationRequest()
   → validator = StakeSecuredValidator, requestHash = keccak256(inputs+outputs)

4. Validator verifies and responds → ValidationRegistry.validationResponse()
   → response = 100, tag = "hard-finality"

5. Off-chain aggregator reads events and getSummary()
   → scores agents, publishes curated clientAddress lists
```
