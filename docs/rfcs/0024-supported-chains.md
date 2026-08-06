---
title: "Host chain discovery and name resolution"
owner: "@valentinfernandez1"
---

# RFC 0024: Host chain discovery and name resolution

|                 |                                                                                                    |
| --------------- | -------------------------------------------------------------------------------------------------- |
| **RFC Number**  | 24                                                                                                 |
| **Start Date**  | 2026-08-06                                                                                         |
| **Description** | Two `Chain` methods letting products enumerate the chains a host serves and resolve stable names to genesis hashes. |
| **Authors**     | Valentin Fernandez                                                                                 |

## Summary

Add two methods to the `Chain` trait. `get_supported_chains` returns the complete set of chains the host will serve, each as a descriptor carrying a stable machine name (for example `"asset-hub"`), an ecosystem network string (for example `"paseo"`), and the chain's genesis hash. `resolve_chain` maps one `(name, network)` pair to its genesis hash, or fails with `NotFound`. Both are answered in-core from a single new platform syscall, so each host implements exactly one callback over configuration it already has.

## Motivation

Every chain-scoped TrUAPI call is keyed by `genesisHash`, and today products obtain those hashes by hard-coding them: `@parity/truapi` ships constants like `PASEO_NEXT_V2_ASSET_HUB` in `well-known-chains.ts`, and the product SDK carries its own `WellKnownChain` table. Hard-coded hashes fail in three recurring ways.

**Testnet wipes.** When a testnet is wiped or restarted its genesis hash changes. Every product's baked-in constant goes stale at once, and nothing recovers until each product ships a new bundle with the new hash. The host already knows the new hash the moment its own configuration updates, but products have no way to ask for it.

**Guessing the host's network.** A product cannot ask which environment the host is on, so it guesses. If the product assumes one network and the host is configured for another, every chain call fails at runtime with no better diagnostic than an unsupported genesis hash.

**Environment moves.** Pointing a product at a different environment (a new testnet iteration, a devnet) means editing constants and shipping a new build, even though the host-side change is a config edit.

The fix is to make the host's chain set discoverable over the wire. Hosts already hold this data in enumerable form: dotli's network config has named slots (`relay`, `assethub`, `bulletin`, `people`) per environment, each with a genesis hash and RPC endpoints. This RFC exposes that mapping to products. Tracking issue: [paritytech/truapi#352](https://github.com/paritytech/truapi/issues/352).

## Detailed Design

### `chain.getSupportedChains`

```rust
/// Enumerate the chains this host serves.
///
/// ```ts
/// const result = await truapi.chain.getSupportedChains();
/// assert(result.isOk(), "getSupportedChains failed:", result);
/// console.log("supported chains:", result.value.chains);
/// ```
#[wire(request_id = 166)]
async fn get_supported_chains(
    &self,
    _cx: &CallContext,
    _request: RemoteChainSupportedChainsRequest,
) -> Result<RemoteChainSupportedChainsResponse, CallError<RemoteChainSupportedChainsError>> {
    Err(CallError::unavailable())
}
```

The request carries no payload (a payload-less `V1` envelope on the wire, a no-argument call in the TS client). The response:

```rust
/// Response listing every chain the host serves.
struct RemoteChainSupportedChainsResponse {
    /// Complete set of chains available through this host.
    chains: Vec<HostChainDescriptor>,
}

/// One chain a host serves.
struct HostChainDescriptor {
    /// Stable machine key for the chain's role, e.g. "asset-hub".
    name: String,
    /// Ecosystem the chain belongs to, e.g. "polkadot", "kusama", "paseo", "devnet".
    network: String,
    /// Genesis hash identifying the chain in all chain-scoped calls.
    genesis_hash: Vec<u8>,
}
```

The error is the plain `GenericError` catch-all, matching the neighboring `getSpec*` methods.

### `chain.resolveChain`

```rust
/// Resolve a (name, network) pair to the chain's genesis hash.
///
/// ```ts
/// const result = await truapi.chain.resolveChain({
///   name: "asset-hub",
///   network: "paseo",
/// });
/// assert(result.isOk(), "resolveChain failed:", result);
/// console.log("genesis hash:", result.value.genesisHash);
/// ```
#[wire(request_id = 168)]
async fn resolve_chain(
    &self,
    _cx: &CallContext,
    _request: RemoteChainResolveChainRequest,
) -> Result<RemoteChainResolveChainResponse, CallError<RemoteChainResolveChainError>> {
    Err(CallError::unavailable())
}
```

```rust
/// Request to resolve a named chain within a network.
struct RemoteChainResolveChainRequest {
    /// Stable machine key, e.g. "asset-hub".
    name: String,
    /// Ecosystem string, e.g. "polkadot", "paseo".
    network: String,
}

/// Response carrying the resolved genesis hash.
struct RemoteChainResolveChainResponse {
    /// Genesis hash of the resolved chain.
    genesis_hash: Vec<u8>,
}

/// Error from resolve_chain.
enum RemoteChainResolveChainError {
    /// No supported chain matches the requested (name, network) pair.
    NotFound,
    /// Catch-all.
    Unknown(GenericError),
}
```

Both methods land in `v01` (the single unfrozen wire) beside the existing chain-metadata methods `getSpecGenesisHash` (94), `getSpecChainName` (96), and `getSpecProperties` (98), taking the next free wire ids, and are re-exported through `truapi::latest`.

### Semantics and invariants

- **Completeness.** The returned list is the complete set of chains the host will serve `chain.*` and `signing.*` calls for. A genesis hash absent from the list will not be served, and every listed hash will be.
- **Uniqueness.** `(name, network)` is unique within one host's response, so `resolve_chain` is a plain lookup with a single answer.
- **Name stability.** Names are stable machine keys across sessions. A product that persisted `"asset-hub"` resolves it again after any wipe and receives the current genesis hash.
- **Fixed per connection.** The list does not change for the lifetime of a connection. There is no subscription; a product observes host-side changes by reconnecting.

`network` is an open ecosystem string, not a `Mainnet`/`Testnet` enum, because a binary flag cannot distinguish two testnets: a host serving both a Paseo asset hub and a devnet asset hub needs `("asset-hub", "paseo")` and `("asset-hub", "devnet")` to be different keys.

Descriptors deliberately exclude display names and token properties. Once a product holds the genesis hash, that metadata is already reachable through `getSpecChainName` and `getSpecProperties`.

### Typical product flow

```ts
const supported = await truapi.chain.getSupportedChains();
assert(supported.isOk(), "getSupportedChains failed:", supported);

const hub = supported.value.chains.find((c) => c.name === "asset-hub");
assert(hub !== undefined, "host serves no asset hub");

const name = await truapi.chain.getSpecChainName({ genesisHash: hub.genesisHash });
assert(name.isOk(), "getSpecChainName failed:", name);
console.log("connected to:", name.value.chainName);
```

The product never embeds a hash. After a testnet wipe the host updates its config, the product reconnects, and the same code path picks up the new hash.

### Implementation shape

The core does not own the chain set. `system.featureSupported(Chain { genesis_hash })` is already a thin shim in `rust/crates/truapi-server/src/host_logic/features.rs` delegating to `truapi_platform::Features`, and `ChainProvider::connect(genesis_hash)` opens JSON-RPC pipes on demand. This RFC follows the same delegation pattern:

- `truapi-platform` gains one syscall on `Features`, shaped like `supported_chains() -> Result<Vec<HostChainDescriptor>, GenericError>`.
- `truapi-server` answers **both** wire methods in-core from that single syscall: `get_supported_chains` returns the list as-is, and `resolve_chain` filters it by `(name, network)`, mapping a miss to `NotFound`.

Hosts therefore implement exactly one callback, backed by configuration they already maintain. dotli's per-environment named slots (`relay`, `assethub`, `bulletin`, `people`, each with a genesis hash) map directly onto descriptors; the iOS `TrUAPIHost` and the host CLI expose their equivalent config the same way. Because `resolve_chain` is answered in-core over the same data, the completeness invariant holds by construction: the two methods cannot disagree.

The change is purely additive: two new methods with fresh wire ids, no changes to existing calls or types. Existing products keep working unchanged, including their hard-coded constants, and can migrate to discovery at their own pace.

## Non-goals

- Changing the `genesisHash` parameter on existing chain-scoped calls. Genesis hashes stay the wire-level chain identifier everywhere else.
- Product SDK integration. The SDK will wrap these calls behind its own chain-selection API in its own repo, hiding the raw methods from application code.

## Drawbacks

- Name and network strings are minted by host configuration, not by the protocol. Two hosts could use different names for the same chain until a spec-level registry exists (see Unresolved Questions).
- No change notification. A host that reconfigures mid-session cannot inform connected products; they observe the change only on reconnect. This keeps the API subscription-free and matches how host config changes actually roll out (host restarts).

## Alternatives

- **Take chain names instead of `genesisHash` in every chain-scoped call.** Was discartes as this is a breaking change across the Rust trait, codegen, the TS client, dotli, the iOS host, and the product SDK. The genesis hash also remains necessary internally, since connections are keyed by it and signed payloads embed it via `CheckGenesis`.
- **A protocol-defined closed enum of chains.** This was discarded as adding a chain would require a protocol release, which is exactly the coupling this RFC removes.
