# Security Model

> This implementation is experimental and has not been audited. Do not use in production without a professional security review.

---

## Threat Model

### 1. Sybil Attacks on Reputation

**Risk:** An agent owner creates many addresses to inflate their own feedback score.

**Mitigations:**
- `getSummary()` **requires** a curated `clientAddresses[]` from the caller. The protocol never aggregates all feedback — it only aggregates feedback from addresses the caller trusts.
- Agent owners and their operators are **explicitly barred** from submitting feedback on their own agents (`giveFeedback()` checks `ownerOf` and `isApprovedForAll`).
- Revoked feedback is preserved (not deleted) to deter spam-and-revoke attacks.

**Residual risk:** Attackers who acquire many non-operator addresses can still submit feedback. Mitigation is expected from off-chain reputation systems for reviewers (the protocol makes this possible by emitting all data on-chain).

---

### 2. Agent Wallet Hijacking

**Risk:** An attacker binds an arbitrary payment wallet to an agent they don't control.

**Mitigations:**
- `setAgentWallet()` requires an **EIP-712 signature from `newWallet`** — proving the submitter controls the wallet being registered.
- EOAs are verified via `ECDSA.recover`. Smart contract wallets via `IERC1271.isValidSignature`.
- Signatures include a `deadline` — expired signatures are rejected.
- On token transfer, `agentWallet` is **automatically cleared** and must be re-bound by the new owner.

---

### 3. Validation Oracle Manipulation

**Risk:** A malicious validator contract posts fraudulent `validationResponse()` calls.

**Mitigations:**
- Only the `validatorAddress` specified in the original `validationRequest()` may post responses. Validator contracts must implement their own access controls and slashing.
- The `requestHash` is a keccak256 commitment — validators must commit to input/output data off-chain before responding.
- The `responseHash` allows off-chain verification that `responseURI` content was not tampered with.

**Design note:** Validator incentives and slashing are **outside the scope** of ERC-8004. The registry is trust-model agnostic — it records whatever validators say.

---

### 4. URI Pointer Attacks

**Risk:** An agent updates its `agentURI` to point to malicious content.

**Mitigations:**
- Only the **token owner or approved operator** can call `setAgentURI()`.
- All URI changes emit `URIUpdated` events, creating an immutable audit trail.
- Clients SHOULD verify the `agentURI` points to content matching the on-chain agent before interacting.

**Optional domain verification:** Agents MAY publish `https://{domain}/.well-known/agent-registration.json` with their `agentRegistry` + `agentId` to prove domain control.

---

### 5. Metadata Key Collisions

**Risk:** A user writes to the reserved `agentWallet` key via `setMetadata()`.

**Mitigations:**
- `setMetadata()` explicitly reverts if `metadataKey == "agentWallet"`.
- `register()` with a `MetadataEntry[]` also checks this for every entry.

---

### 6. Integer Overflow in getSummary

**Risk:** Aggregating many large `int128` values overflows.

**Mitigation:** `getSummary()` accumulates into `int256` (256-bit signed integer), which cannot overflow given `int128` inputs within realistic feedback counts.

---

### 7. Re-entrancy

**Risk:** Malicious ERC-721 receiver hooks on `_safeMint` re-enter the registry.

**Mitigation:** `_mintAgent()` is called first, state is written, then the `Registered` event is emitted. `_safeMint` from OpenZeppelin calls `onERC721Received` on the receiver — callers should avoid complex logic in their receive hooks. Future versions may add a `nonReentrant` guard.

---

## Audit Checklist

Before production deployment, verify:

- [ ] All `require` messages are preserved in all Solidity optimisation configurations
- [ ] EIP-712 domain separator is chain-specific (replay protection across chains)
- [ ] `_requireOwned()` is called before any metadata read (reverts on non-existent tokens)
- [ ] `agentWallet` cleared correctly on token transfer in all ERC-721 transfer paths
- [ ] `getSummary()` decimal normalisation handles edge cases (all same decimals, all different)
- [ ] `validationResponse()` can only be called by designated validator (immutable in `_requests`)
- [ ] No unbounded loops in user-controlled arrays (mitigated by `clientAddresses` being caller-supplied)
