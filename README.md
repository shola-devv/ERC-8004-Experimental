# ERC-8004: Trustless Agents — Experimental Implementation

> ⚠️ **Status:** This is an experimental implementation.
> It is intended for research, prototyping, and community feedback. Not audited. Do not use in production without a professional security review.

An experimental Solidity implementation of [ERC-8004](https://eips.ethereum.org/EIPS/eip-8004): a protocol for discovering, choosing, and interacting with autonomous AI agents across organisational boundaries without pre-existing trust.

---

## What This Implements

ERC-8004 defines three lightweight on-chain registries that together enable an open-ended agent economy:

| Registry | Analogy | What it does |
|---|---|---|
| **IdentityRegistry** | Business registration | Mints an ERC-721 NFT per agent, resolving to a JSON registration file with service endpoints |
| **ReputationRegistry** | Yelp for agents | Lets clients post fixed-point feedback signals; on-chain composable, off-chain aggregatable |
| **ValidationRegistry** | Third-party auditors | Lets agents request cryptographic/economic verification of their work from validator contracts |

### Protocol Requirements Implemented

- ERC-721 with `URIStorage` for agent identity (per spec)
- `agentWallet` reserved metadata key with EIP-712 + ERC-1271 signature verification
- `agentWallet` auto-cleared on token transfer
- `getSummary()` requires non-empty `clientAddresses[]` (Sybil resistance)
- `feedbackIndex` is 1-based per `(agentId, clientAddress)` pair
- Revoked feedback preserved (never deleted) for audit trail
- `appendResponse()` is permissionless
- `validationResponse()` supports multiple calls per `requestHash` (progressive finality)
- All events match the spec exactly

---

## Project Structure

```
erc8004/
├── src/
│   ├── interfaces/
│   │   ├── IIdentityRegistry.sol     ← Full NatDoc interface
│   │   ├── IReputationRegistry.sol
│   │   └── IValidationRegistry.sol
│   └── core/
│       ├── IdentityRegistry.sol      ← ERC-721 + EIP-712 agent identity
│       ├── ReputationRegistry.sol    ← Feedback ledger
│       └── ValidationRegistry.sol   ← Validation request/response store
├── test/
│   ├── IdentityRegistry.t.sol        ← Unit + fuzz tests
│   ├── ReputationRegistry.t.sol
│   └── ValidationRegistry.t.sol
├── script/
│   └── Deploy.s.sol                  ← Foundry broadcast script
├── docs/
│   ├── architecture.md               ← Deep dive on design decisions
│   ├── security-model.md             ← Threat model and mitigations
│   └── future-work.md               ← Roadmap
└── foundry.toml
```

See [docs/architecture.md](docs/architecture.md) for full architecture.
---

## Getting Started

### Prerequisites

- [Foundry](https://getfoundry.sh/) (`forge`, `anvil`, `cast`)
- OpenZeppelin Contracts v5

### Install

```bash
git clone https://github.com/shola-devv/ERC-8004-Experimental.git
cd ERC-8004-Experimental
forge install OpenZeppelin/openzeppelin-contracts
```

### Build

```bash
forge build
```

### Test

```bash
# Run all tests
forge test -vvv

# Run fuzz tests with more runs
forge test --match-test testFuzz -vvv --fuzz-runs 1000

# Run a specific test file
forge test --match-path test/IdentityRegistry.t.sol -vvv
```

### Deploy (local Anvil)

```bash
anvil &
forge script script/Deploy.s.sol:Deploy \
  --rpc-url http://127.0.0.1:8545 \
  --private-key 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80 \
  --broadcast -vvvv
```

---

## Key Design Decisions

### Why ERC-721 for identity?

The spec mandates it. NFT ownership = agent ownership. This makes agents immediately compatible with wallets, marketplaces, and transfer mechanisms. Operators can update agent metadata without owning the token, mirroring how companies have employees.

### Why require `clientAddresses[]` in getSummary?

Open aggregation is trivially Sybil-attackable. The protocol's contribution is making all signals public in a standard schema. Callers build trust in reviewer addresses through off-chain mechanisms (other reputation protocols, attestations, staking) and pass curated lists to `getSummary()`. This is the spec's explicit design.

### Why is `agentWallet` reserved?

Payment addresses require cryptographic proof of control — you can't just write any address. The EIP-712 signature scheme ensures only the true controller of a wallet can bind it to an agent. This is critical for x402 payment flows referenced in the spec.

### Why does `feedbackIndex` start at 1?

A 0-index would be ambiguous with "no feedback" state. 1-based indexing means `getLastIndex()` returning 0 unambiguously means no feedback has been submitted.

---


## Security

See [docs/security-model.md](docs/security-model.md) for the full threat model.

**This code has not been audited. Do not deploy to mainnet or handle real value without a professional audit.**

---

## Roadmap

- [x] Minimal registry implementation
- [x] Full interface separation
- [x] Foundry test suite with fuzz tests
- [x] EIP-712 agent wallet binding
- [x] Architecture + security documentation
- [ ] UUPS proxy upgrade pattern
- [ ] Cross-agent reputation weighting
- [ ] DAO-governed validation rules
- [ ] Off-chain agent SDK (TypeScript)
- [ ] L2 deployment optimisation
- [ ] Subgraph manifest

See [docs/future-work.md](docs/future-work.md) for full roadmap.
---

## Related Standards

- [ERC-8004](https://eips.ethereum.org/EIPS/eip-8004) — the spec this implements
- [EIP-721](https://eips.ethereum.org/EIPS/eip-721) — NFT standard (agent identity)
- [EIP-712](https://eips.ethereum.org/EIPS/eip-712) — typed structured data signing (wallet binding)
- [ERC-1271](https://eips.ethereum.org/EIPS/eip-1271) — smart contract signatures
- [EIP-155](https://eips.ethereum.org/EIPS/eip-155) — chain ID (replay protection)

---

## License

[CC0-1.0](LICENSE) — waived to the public domain, matching the ERC-8004 specification.

## Author

[Shola Emmanuel Fayinminu](https://sholaemmanuel.dev)

- For contributions, corrections or suggestions reach out tme with the above link
