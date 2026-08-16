---
title: "Method-level capability detection for protocol extension"
owner: "@ryanleecode"
type: rfc
status: draft
created: 2026-08-16
---

# RFC 0027 — Method-level capability detection for protocol extension

|                 |                                                                                                                                                                  |
| --------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **RFC Number**  | 27                                                                                                                                                               |
| **Start Date**  | 2026-08-16                                                                                                                                                       |
| **Description** | Enable runtime discovery of host method support on existing wire IDs, and ensure unregistered method calls fail explicitly instead of hanging indefinitely.      |
| **Authors**     | Ryan Lee                                                                                                                                                         |

## Summary

When TrUAPI adds new methods, products have no mechanism to check whether their embedding host supports them. Calling an unknown method causes the host dispatcher to silently drop the unrecognised wire discriminant. Because the client transport lacks request timeouts, the pending call hangs forever.

This RFC introduces three coordinated fixes:
1. **Backward-compatible probing:** Adds a `Method { id: u8 }` query variant to `system.feature_supported` (wire ID 2, registered by all hosts). Older hosts return a decode error (`MalformedFrame`) instead of dropping the frame, allowing products to reliably infer host capabilities even on pre-RFC deployments.
2. **Explicit failure for unregistered discriminants:** Hosts reply to unregistered wire IDs with a reserved `UNSUPPORTED_METHOD` frame instead of dropping them, settling pending client requests immediately.
3. **Typed error semantics:** Canonicalises `CallError::Unsupported` as the standard response for unwired trait methods, deprecating ambiguous `HostFailure { reason: "unavailable" }` strings.

## Motivation

Protocol extension is frequent in TrUAPI (e.g., v0.2 introduced eleven new methods across three groups). Upcoming extensions like the `Swarm` capability (BitTorrent-based content streaming) highlight critical gaps in version compatibility.

### 1. Inconsistent Observability on Unknown Features

When a product targets an older host lacking a new feature, behavior depends arbitrarily on where the unknown identifier appears:

| Call Type | Example | Host Behavior | Product Observability |
| :--- | :--- | :--- | :--- |
| **Unknown Enum Variant** | `permissions.remote_permission(Swarm)` | Decoder rejects variant index; returns `CallError::MalformedFrame`. | **Settles immediately** with error. |
| **Unknown Wire ID** | `swarm.fetch(...)` | Dispatcher finds no handler; drops frame silently (`dispatcher.rs`). | **Hangs indefinitely**; transport never resolves. |

### 2. Unbounded Client Hangs

The client transport (`js/packages/truapi/src/client.ts`) tracks requests in a `pending` map. Entries are settled only when a response matching the expected ID arrives, the transport throws, or the connection closes. Because many methods involve user interaction (e.g., wallet authorization, biometric prompts) with unbounded duration, global client timeouts cannot be safely applied. Dropped frames therefore cause indefinite hangs indistinguishable from crashed hosts.

### 3. Asymmetric Deployment Cadence

Wire IDs are append-only to preserve backward compatibility (newer hosts support older products). However, products are deployed as web bundles that update continuously, whereas native host runtimes (iOS SPM, Android Kotlin packages) update on slower native app release cycles. As a result, newer products routinely run against older hosts.

### 4. Ambiguous "Unavailable" Errors

Unimplemented default trait methods currently return `CallError::unavailable()`, which maps to `HostFailure { reason: "unavailable" }`. This conflates permanent lack of feature support with transient operational failures.

---

## Detailed Design

### 1. Capability Probing via `system.feature_supported`

`HostFeatureSupportedRequest` in `truapi::v01::system` is extended with a new variant:

```rust
pub enum HostFeatureSupportedRequest {
    /// Query whether the host supports the chain identified by genesis hash.
    Chain {
        /// Chain genesis hash.
        genesis_hash: Vec<u8>,
    },
    /// Query whether the host has registered a handler for a wire discriminant.
    Method {
        /// Request or subscription-start discriminant from the wire table.
        id: u8,
    },
}
```

Because `system.feature_supported` (`#[wire(request_id = 2)]`) is registered by all hosts across all published surface versions (`0.2.0` to `0.9.0`):

- **Modern Hosts:** Hosts implementing this RFC inspect their active dispatcher table and return `HostFeatureSupportedResponse { supported }`. The host MUST compute `supported` directly from its dispatcher registration map rather than a static list, and MUST NOT report `true` for unregistered discriminants.
- **Legacy Hosts:** Hosts predating this RFC attempt to decode payload bytes against the single-variant enum. The decoder rejects variant index 1, and the generated dispatcher wrapper returns `CallError::MalformedFrame`.

#### Conclusive Probing Protocol

To distinguish an old host from payload corruption, callers SHOULD execute a concurrent control probe:

```ts
const [methodProbe, controlProbe] = await Promise.all([
  truapi.system.featureSupported({ tag: "Method", value: { id: targetWireId } }),
  truapi.system.featureSupported({ tag: "Chain", value: { genesisHash: knownChainHash } }),
]);

// Control OK + Method MalformedFrame -> Host predates RFC 0027 (Method unsupported)
// Method OK                          -> Response value is authoritative
```

The client SDK exposes a high-level helper resolving method names to wire discriminants at codegen time:

```ts
const isAvailable = await truapi.system.supportsMethod("swarm_fetch");
```

---

### 2. Explicit Response for Unregistered Discriminants

A reserved wire discriminant `UNSUPPORTED_METHOD` is allocated in the server wire table. When `Dispatcher::dispatch` encounters an unknown discriminant, it sends an explicit error frame:

```rust
// Fall-through branch for unrecognized discriminants:
transport.send(ProtocolMessage {
    request_id: message.request_id,
    payload: Payload {
        id: wire_table::UNSUPPORTED_METHOD,
        value: encode_versioned_err_payload(CallError::<Infallible>::Unsupported, 1),
    },
});
```

- The host MUST echo the caller's `request_id`.
- The host MUST send this frame for any message that matches no registered request, subscription start, or cancel handler.
- The client transport routes `UNSUPPORTED_METHOD` frames directly to the pending request or subscription entry, rejecting the promise with `CallError::Unsupported`.

---

### 3. Canonical `Unsupported` Error Variant

The default implementation of `CallError::unavailable()` is updated across all API trait definitions:

```rust
impl<D> CallError<D> {
    /// Standard error for unwired trait method implementations.
    pub fn unavailable() -> Self {
        Self::Unsupported
    }
}
```

- A host MUST NOT return `HostFailure` for an unimplemented method.
- `Unsupported` signals that the operation is permanently unhandled on the current host session; callers MUST NOT retry.

---

### Summary of Host Reachability & Compatibility

| Mechanism | Legacy Hosts (Pre-RFC 0027) | Modern Hosts (RFC 0027) |
| :--- | :--- | :--- |
| `feature_supported(Method { id })` | Returns `MalformedFrame` (interpreted as unsupported via control probe) | Returns `HostFeatureSupportedResponse { supported }` |
| Direct Call to Unregistered Wire ID | Frame dropped; client hangs | Returns `UNSUPPORTED_METHOD` frame; client promise rejects |
| Unwired Default Trait Method | Returns `HostFailure { reason: "unavailable" }` | Returns typed `CallError::Unsupported` |

---

## Drawbacks

1. **Inference Overhead:** Legacy detection relies on interpreting `MalformedFrame` as "host predates capability". While the paired control query prevents misclassification, it requires dual queries on legacy hosts.
2. **Registration vs Implementation Gap:** A positive response (`supported: true`) indicates the method is registered in the host binary dispatcher table, but does not guarantee the host provided a custom implementation instead of the default trait fallback (`CallError::Unsupported`). Products must still handle `Unsupported` at call time.
3. **Discriminant Allocation:** Consumes one permanent `u8` discriminant (`UNSUPPORTED_METHOD`) from the finite 256-value wire table space.
4. **Behavioral Change for `unavailable()`:** Existing client code asserting on string matching for `HostFailure { reason: "unavailable" }` will observe `CallError::Unsupported`.

---

## Alternatives

- **Monolithic `system.get_capabilities` Method:** Exposing a single method returning all supported capabilities was considered. Rejected because legacy hosts drop unknown wire IDs, causing the initial capability fetch itself to hang on the very hosts requiring detection.
- **Protocol Version Negotiation Bump (`Versioned::V2`):** Bumping the root handshake version to negotiate a feature bitmap was rejected because old hosts fail the handshake completely rather than allowing graceful partial-feature fallback.
- **Client-Side Request Timeouts:** Implementing blanket client timeouts was rejected because methods requiring user interaction (biometrics, manual authorization, hardware key signing) have indefinite completion times.
- **Method Name String Queries (`Method { name: String }`):** Using method names instead of `u8` IDs in `HostFeatureSupportedRequest` was rejected to avoid wire bloat and string parsing overhead on resource-constrained embedded runtimes.

---

## Unresolved Questions

1. **Discriminant ID Assignment:** Which exact `u8` index should be assigned to `UNSUPPORTED_METHOD` in `wire_table.rs`?
2. **Implementation Introspection:** Can proc-macro code generation distinguish overridden trait methods from default trait bodies at compile time to avoid reporting `supported: true` for default `Unsupported` stubs?
3. **RFC 0002 Reconciliation:** RFC 0002 recommended returning `false` for unknown permission enum variants rather than errors. Should that recommendation be formally scoped strictly to permission evaluation?
