---
title: "Host chain discovery and name resolution"
owner: "@valentinfernandez1"
---

# RFC 0026: Host chain discovery and name resolution

|                 |                                                                                                    |
| --------------- | -------------------------------------------------------------------------------------------------- |
| **RFC Number**  | 26                                                                                                 |
| **Start Date**  | 2026-08-06                                                                                         |
| **Description** | A `Chain` method resolving protocol-defined chain identifiers to genesis hashes against the host's environment. |
| **Authors**     | Valentin Fernandez                                                                                 |

## Summary

Add one method to the `Chain` trait. `get_chain_info` takes the chain identifiers a product wants to use, drawn from a closed role enum (`Relay`, `AssetHub`, `People`, `Bulletin`), and returns the ecosystem the host is configured for (for example `"paseo"`) plus one `ChainInfo` (name and genesis hash) per requested identifier, resolved against that environment. It is answered in-core from a single new platform syscall, so each host implements exactly one callback over configuration it already has.

## Motivation

Every chain-scoped TrUAPI call is keyed by `genesisHash`, and today products obtain those hashes by hard-coding them: `@parity/truapi` ships constants like `PASEO_NEXT_V2_ASSET_HUB` in `well-known-chains.ts`, and the product SDK carries its own `WellKnownChain` table. Hard-coded hashes fail in three recurring ways.

**Testnet wipes.** When a testnet is wiped or restarted its genesis hash changes. Every product's baked-in constant goes stale at once, and nothing recovers until each product ships a new bundle with the new hash. The host already knows the new hash the moment its own configuration updates, but products have no way to ask for it.

**Guessing the host's network.** A product cannot ask which environment the host is on, so it guesses. If the product assumes one network and the host is configured for another, every chain call fails at runtime with no better diagnostic than an unsupported genesis hash.

**Environment moves.** Pointing a product at a different environment (a new testnet iteration, a devnet) means editing constants and shipping a new build, even though the host-side change is a config edit.

The fix is to make the host's chain set discoverable over the wire. Hosts already hold this data in enumerable form: dotli's network config has named slots (`relay`, `assethub`, `bulletin`, `people`) per environment, each with a genesis hash and RPC endpoints. This RFC exposes that mapping to products. Tracking issue: [paritytech/truapi#352](https://github.com/paritytech/truapi/issues/352).

## Detailed Design

### `chain.getChainInfo`

```rust
/// Resolve chain identifiers to genesis hashes against the host's
/// configured environment.
///
/// ```ts
/// const result = await truapi.chain.getChainInfo({
///   chains: ["AssetHub"],
/// });
/// assert(result.isOk(), "getChainInfo failed:", result);
/// console.log("network:", result.value.network);
/// console.log("asset hub genesis:", result.value.chains[0].genesisHash);
/// ```
#[wire(request_id = 166)]
async fn get_chain_info(
    &self,
    _cx: &CallContext,
    _request: RemoteChainInfoRequest,
) -> Result<RemoteChainInfoResponse, CallError<RemoteChainInfoError>> {
    Err(CallError::unavailable())
}
```

```rust
/// Role of a chain within the host's configured environment.
enum ChainIdentifier {
    /// The relay chain.
    Relay,
    /// The asset hub system chain.
    AssetHub,
    /// The people chain.
    People,
    /// The bulletin chain.
    Bulletin,
}

/// Resolved chain data for one requested ChainIdentifier.
struct ChainInfo {
    /// Host-assigned chain name, e.g. "asset-hub".
    name: String,
    /// Genesis hash identifying the chain in all chain-scoped calls.
    genesis_hash: [u8; 32],
}

/// Request to resolve chain identifiers against the host's environment.
struct RemoteChainInfoRequest {
    /// Chains to resolve.
    chains: Vec<ChainIdentifier>,
}

/// Response carrying one ChainInfo per requested identifier, in request order.
struct RemoteChainInfoResponse {
    /// Ecosystem the host is configured for, e.g. "polkadot", "kusama", "paseo".
    network: String,
    /// Resolved chains, aligned with the request's `chains`.
    chains: Vec<ChainInfo>,
}

/// Error from get_chain_info.
enum RemoteChainInfoError {
    /// The host does not serve one of the requested chains.
    NotSupported {
        /// First requested identifier the host does not serve.
        chain: ChainIdentifier,
    },
    /// Catch-all.
    Unknown(GenericError),
}
```

The request is a batch: a product names every chain it needs in one call and gets them all back in one round trip. `ChainIdentifier` is a closed protocol enum of chain roles, not chain instances; the host maps each role to the concrete chain of its configured environment. Adding a new role is an additive enum variant.

The request deliberately carries no network selector. A product does not get to choose which network it operates on; the host is configured for exactly one environment (polkadot in production), and every identifier resolves against that. Asking the product to name the environment would reintroduce the guessing this RFC removes.

### Semantics and invariants

- **Serviceability.** Every genesis hash returned by `get_chain_info` is a chain the host will serve `chain.*` and `signing.*` calls for. A `NotSupported` identifier will not be served.
- **Alignment.** The response's `chains` has exactly one entry per requested identifier, in request order, so products index it positionally.
- **All or nothing.** If any requested identifier is not served, the whole call fails with `NotSupported` naming the first such identifier; there are no partial responses.
- **Stability.** An identifier resolves to the same chain for the lifetime of a connection. There is no subscription; a product observes host-side changes (such as a testnet wipe) by reconnecting.

`network` is informational, not a selector: it tells a product or SDK which environment the host is running, so tooling can derive the environment from the host instead of asking the developer to configure it. It is an open ecosystem string ("polkadot", "kusama", "paseo", "devnet"), not a `Mainnet`/`Testnet` enum, because a binary flag cannot distinguish two testnets.

`ChainInfo` deliberately excludes display names and token properties. Once a product holds the genesis hash, that metadata is already reachable through `getSpecChainName` and `getSpecProperties`.

### Typical product flow

```ts
const info = await truapi.chain.getChainInfo({ chains: ["AssetHub", "People"] });
assert(info.isOk(), "getChainInfo failed:", info);

const [assetHub, people] = info.value.chains;

const name = await truapi.chain.getSpecChainName({ genesisHash: assetHub.genesisHash });
assert(name.isOk(), "getSpecChainName failed:", name);
console.log(`connected to ${name.value.chainName} on ${info.value.network}`);
```

The product never embeds a hash. After a testnet wipe the host updates its config, the product reconnects, and the same code path picks up the new hash.

### Implementation shape

The core does not own the chain set. `system.featureSupported(Chain { genesis_hash })` is already a thin shim in `rust/crates/truapi-server/src/host_logic/features.rs` delegating to `truapi_platform::Features`, and `ChainProvider::connect(genesis_hash)` opens JSON-RPC pipes on demand. This RFC follows the same delegation pattern:

- `truapi-platform` gains one syscall on `Features` returning the host's network string and its full identifier-to-chain mapping.
- `truapi-server` answers `get_chain_info` in-core from that syscall, resolving each requested identifier and mapping the first miss to `NotSupported`.

Hosts therefore implement exactly one callback, backed by configuration they already maintain. dotli's per-environment named slots (`relay`, `assethub`, `bulletin`, `people`, each with a genesis hash) map one-to-one onto `ChainIdentifier` variants; the iOS `TrUAPIHost` and the host CLI expose their equivalent config the same way.

The change is purely additive: one new method with a fresh wire id, no changes to existing calls or types. Existing products keep working unchanged, including their hard-coded constants, and can migrate at their own pace.

## Non-goals

- Changing the `genesisHash` parameter on existing chain-scoped calls. Genesis hashes stay the wire-level chain identifier everywhere else.
- Product SDK integration. The SDK will wrap these calls behind its own chain-selection API in its own repo, hiding the raw methods from application code.

## Drawbacks

- Adding a new chain role requires a protocol release (an additive `ChainIdentifier` variant) and host support for it. The closed enum trades that coupling for typo-proof, host-portable identifiers.
- No change notification. A host that reconfigures mid-session cannot inform connected products; they observe the change only on reconnect. This keeps the API subscription-free and matches how host config changes actually roll out (host restarts).

## Alternatives

- **Take chain names instead of `genesisHash` in every chain-scoped call.** This was discarded as it is a breaking change across the Rust trait, codegen, the TS client, dotli, the iOS host, and the product SDK. The genesis hash also remains necessary internally, since connections are keyed by it and signed payloads embed it via `CheckGenesis`.
- **Separate discovery and lookup methods (`getSupportedChains` + `resolveChain`).** This was discarded during review: a product that needs one chain should not fetch and filter the host's full mapping, and the batch request already covers the multi-chain case in one round trip.
- **Free-form string identifiers.** This was discarded because names minted by host configuration form a de facto registry with no governance: two hosts could name the same chain differently, and typos fail only at runtime. The closed role enum is typo-proof, identical across hosts, and versioned with the protocol.
- **A `network` selector on the request.** This was discarded because the product does not choose its network, the host's configuration does. Asking the product to name the environment would make it encode the environment again, which is the hard-coding this RFC removes.
