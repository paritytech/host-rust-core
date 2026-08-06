---
title: "Host chain discovery and name resolution"
owner: "@valentinfernandez1"
---

# RFC 0026: Host chain discovery and name resolution

|                 |                                                                                                    |
| --------------- | -------------------------------------------------------------------------------------------------- |
| **RFC Number**  | 26                                                                                                 |
| **Start Date**  | 2026-08-06                                                                                         |
| **Description** | Two `Chain` methods letting products enumerate the chains a host serves and resolve stable names to genesis hashes. |
| **Authors**     | Valentin Fernandez                                                                                 |

## Summary

Add two methods to the `Chain` trait. `get_supported_chains` returns the ecosystem the host is configured for (for example `"paseo"`) and the complete set of chains it will serve, each as a descriptor carrying a stable machine name (for example `"asset-hub"`) and the chain's genesis hash. `resolve_chain` maps one name to its genesis hash, resolved against that same environment, or fails with `NotFound`. Both are answered in-core from a single new platform syscall, so each host implements exactly one callback over configuration it already has.

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
/// console.log("network:", result.value.network);
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
    /// Ecosystem the host is configured for, e.g. "polkadot", "kusama", "paseo".
    network: String,
    /// Complete set of chains available through this host.
    chains: Vec<HostChainDescriptor>,
}

/// One chain a host serves.
struct HostChainDescriptor {
    /// Stable machine key for the chain's role, e.g. "asset-hub".
    name: String,
    /// Genesis hash identifying the chain in all chain-scoped calls.
    genesis_hash: Vec<u8>,
}
```

A host serves exactly one environment, so `network` appears once on the response rather than repeated per entry. A response looks like `{ network: "paseo", chains: [{ name: "asset-hub", genesisHash: "0xbf04..." }, { name: "bulletin", genesisHash: "0x..." }, ...] }`.

The error is the plain `GenericError` catch-all, matching the neighboring `getSpec*` methods.

### `chain.resolveChain`

```rust
/// Resolve a chain name to its genesis hash.
///
/// ```ts
/// const result = await truapi.chain.resolveChain({
///   name: "asset-hub",
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
/// Request to resolve a named chain.
struct RemoteChainResolveChainRequest {
    /// Stable machine key, e.g. "asset-hub".
    name: String,
}

/// Response carrying the resolved genesis hash.
struct RemoteChainResolveChainResponse {
    /// Genesis hash of the resolved chain.
    genesis_hash: Vec<u8>,
}

/// Error from resolve_chain.
enum RemoteChainResolveChainError {
    /// No supported chain matches the requested name.
    NotFound,
    /// Catch-all.
    Unknown(GenericError),
}
```

The request deliberately carries no network selector. A product does not get to choose which network it operates on; the host is configured for exactly one environment (polkadot in production), and `resolve_chain` resolves the name against that. Asking the product to name the environment would reintroduce the guessing this RFC removes.

Both methods land in `v01` (the single unfrozen wire) beside the existing chain-metadata methods `getSpecGenesisHash` (94), `getSpecChainName` (96), and `getSpecProperties` (98), taking the next free wire ids, and are re-exported through `truapi::latest`.

### Semantics and invariants

- **Completeness.** The returned list is the complete set of chains the host will serve `chain.*` and `signing.*` calls for. A genesis hash absent from the list will not be served, and every listed hash will be.
- **Uniqueness.** `name` is unique within one host's response, so `resolve_chain` is a plain lookup with a single answer.
- **Name stability.** Names are stable machine keys across sessions. A product that persisted `"asset-hub"` resolves it again after any wipe and receives the current genesis hash.
- **Fixed per connection.** The list does not change for the lifetime of a connection. There is no subscription; a product observes host-side changes by reconnecting.

`network` appears only on the discovery response and is informational, not a selector: it tells a product or SDK which environment the host is running, so tooling can derive the environment from the host instead of asking the developer to configure it. It is an open ecosystem string ("polkadot", "kusama", "paseo", "devnet"), not a `Mainnet`/`Testnet` enum, because a binary flag cannot distinguish two testnets. No host serves more than one environment at a time; if one ever does, it disambiguates in its name strings (`"paseo-asset-hub"`), which the open registry already permits with no wire change.

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

- `truapi-platform` gains one syscall on `Features`, shaped like `supported_chains() -> Result<RemoteChainSupportedChainsResponse, GenericError>` (the host's network plus its chain descriptors).
- `truapi-server` answers **both** wire methods in-core from that single syscall: `get_supported_chains` returns the list as-is, and `resolve_chain` looks up the name in it, mapping a miss to `NotFound`.

Hosts therefore implement exactly one callback, backed by configuration they already maintain. dotli's per-environment named slots (`relay`, `assethub`, `bulletin`, `people`, each with a genesis hash) map directly onto descriptors; the iOS `TrUAPIHost` and the host CLI expose their equivalent config the same way. Because `resolve_chain` is answered in-core over the same data, the completeness invariant holds by construction: the two methods cannot disagree.

The change is purely additive: two new methods with fresh wire ids, no changes to existing calls or types. Existing products keep working unchanged, including their hard-coded constants, and can migrate to discovery at their own pace.

## Non-goals

- Changing the `genesisHash` parameter on existing chain-scoped calls. Genesis hashes stay the wire-level chain identifier everywhere else.
- Product SDK integration. The SDK will wrap these calls behind its own chain-selection API in its own repo, hiding the raw methods from application code.

## Drawbacks

- Name and network strings are minted by host configuration, not by the protocol. Two hosts could use different names for the same chain until a spec-level registry exists, which can follow as a separate RFC.
- No change notification. A host that reconfigures mid-session cannot inform connected products; they observe the change only on reconnect. This keeps the API subscription-free and matches how host config changes actually roll out (host restarts).

## Alternatives

- **Take chain names instead of `genesisHash` in every chain-scoped call.** This was discarded as it is a breaking change across the Rust trait, codegen, the TS client, dotli, the iOS host, and the product SDK. The genesis hash also remains necessary internally, since connections are keyed by it and signed payloads embed it via `CheckGenesis`.
- **A protocol-defined closed enum of chains.** This was discarded as adding a chain would require a protocol release, which is exactly the coupling this RFC removes.
- **A `network` selector on `resolve_chain`.** This was discarded because the product does not choose its network, the host's configuration does. Asking for `(name, network)` would make products encode the environment again, which is the hard-coding this RFC removes.
