---
title: "Product storage subscriptions and worker pending operations"
owner: "Sergey Zhuravlev"
---

# RFC 0027: Product storage subscriptions and worker pending operations

|                 |                                          |
| --------------- | ---------------------------------------- |
| **RFC Number**  | 27                                       |
| **Start Date**  | 2026-08-25                               |
| **Description** | Two small TrUAPI additions so a background worker can finish a multi-step task and coordinate with the app through storage. |
| **Authors**     | Sergey Zhuravlev                         |

## Summary

Two additions to TrUAPI:

- `localStorage.subscribe(key)` streams a key's value on every change, within the product's own namespace.
- `worker.beginOperation()` / `worker.endOperation(id)` declare a pending operation; the host keeps the worker running while any operation is open.

Both come from one flow: a funding operation, part of a safety-net release, runs in a worker, submits a transaction, and needs to finish and report progress even after the user leaves the app.

## Motivation

The product runs a funding operation, one part of a safety-net release. It builds a transaction, submits it, waits for it to be included, and records the result. Some of those steps hit a backend, so one operation can run for tens of seconds with polling in between. It runs in a worker so it continues after the user leaves the product's screen. Two things make that unsafe today.

The worker dies when the user leaves. The host disposes a worker once its on-screen surface is gone, and the in-flight submission is aborted with it (the worker's own `dispose` is a no-op that defers to the main thread, `worker-runtime.ts:182`). Being killed between submitting a funding transaction and confirming it is the worst place to stop, and the product has no way to tell the host it is mid-operation.

The UI and the worker can't see each other's progress. The on-screen product and the worker are separate runtimes over one storage namespace, but a write in one stays invisible to the other until it re-reads. So a progress view the worker feeds, or a worker that should react to what the user just did on screen, can only re-read on a timer. For a value that changes a few times a minute, that polling is both late and wasteful.

## Detailed design

### localStorage.subscribe

A subscription method on the `LocalStorage` trait, next to `read` (12), `write` (14), `clear` (16):

```rust
/// Subscribe to changes of one key in the product's own storage namespace.
///
/// Emits the current value immediately, then one item per later change.
#[wire(start_id = 198)] // exact id assigned at implementation, free range above 197
async fn subscribe(
    &self,
    cx: &CallContext,
    request: HostLocalStorageSubscribeRequest, // { key: String }
) -> Subscription<HostLocalStorageChangeItem>;
```

```rust
pub struct HostLocalStorageChangeItem {
    /// Value after the change. `Some` on write, `None` after clear.
    pub value: Option<Vec<u8>>,
}
```

The wire side is nothing new. `theme.subscribe` and `chat.list_subscribe` already return `Subscription<T>`, and the TS client already exposes them as RxJS observables.

The host emits the changes. On web and old JS hosts the app and worker are separate WASM instances with separate `RuntimeServices`, so the core alone can't carry a change from one to the other. The host can: it sits above both instances and owns the store, so it sees every write to the namespace whoever made it. The core just forwards the host's stream to the subscriber.

This adds one method to the host `ProductStorage` trait, the same shape as the existing `ChatPlatform::subscribe_chat_rooms` (`rust/crates/truapi-platform/src/lib.rs`):

```rust
/// Emit a product-scoped key's current value, then each later change,
/// from any of the product's runtimes. A write that doesn't change the
/// bytes emits nothing (see below).
fn subscribe_storage(
    &self,
    product: &ProductContext,
    key: String,
) -> BoxStream<'static, Result<HostLocalStorageChangeItem, GenericError>>;
```

The core passes the calling product's context to `subscribe_storage`, the same scoping `read` and `write` already use, so a product only ever sees its own keys. The first item is the current value, so there's no read-then-subscribe gap. After that, a write emits `Some(value)` and a clear emits `None`. This works the same on web and native, because the source is the host, not a shared core instance.

### Byte-identical writes do nothing

If `write` gets the same bytes the key already holds, the host skips the store write and the change event. Same for `clear` on an absent key. The host does this because it holds the current bytes to compare. So a runtime that rewrites unchanged state on a timer costs nothing and wakes no one.

### Pending operations

The worker begins a pending operation while it has work in flight and ends it when done. The host keeps the worker alive while any operation is open.

A `begin`/`end` pair on a new `Worker` trait:

```rust
/// Begin a pending operation. The worker is kept alive while it has at least
/// one open operation. Returns an id for `end_operation`.
///
/// Worker execution kind only.
#[wire(request_id = 202)] // exact id assigned at implementation
async fn begin_operation(
    &self,
    cx: &CallContext,
    request: HostBeginOperationRequest, // { label: Option<String> } for host UI/logs
) -> Result<HostBeginOperationResponse, CallError<HostOperationError>>;

/// End a pending operation. Idempotent: an unknown or already-ended id
/// returns `Ok`.
#[wire(request_id = 204)] // exact id assigned at implementation
async fn end_operation(
    &self,
    cx: &CallContext,
    request: HostEndOperationRequest, // { id: OperationId }
) -> Result<(), CallError<HostOperationError>>;
```

```rust
/// Opaque host-assigned operation identifier, unique per product. Mirrors
/// `NotificationId`, which is a `u32` type alias.
pub type OperationId = u32;

pub struct HostBeginOperationResponse {
    /// Pass this to `end_operation`.
    pub id: OperationId,
}

/// Domain error for the operation methods.
pub enum HostOperationError {
    /// The product already holds the host's per-product cap of open
    /// operations. `end` never returns this; it is idempotent and always
    /// succeeds.
    TooManyOpen,
}
```

Why operations and not a timer. A timer makes the worker guess the duration, and a short guess kills the transaction mid-flight. An operation ties liveness to the work itself: alive while something is open, gone when it closes. The id is session-scoped, not something the worker persists. If the host dies, the worker and the id die with it, and the leftover operation record is reconciled on the next launch (until a reaper exists, see open questions). So losing the id costs nothing.

The host owns the operations and the lifecycle. `begin_operation` and `end_operation` are thin: the core forwards each to a host platform trait, scoped to the calling product. The host stores the product's open operations and keeps its worker alive while any stand. There's no separate keep-alive signal, because the operation existing is the signal.

```rust
/// Host store for a product's pending operations. The host keeps the
/// product's worker alive while it holds at least one open operation.
/// Optional: a host that omits it answers `begin_operation` `Unsupported`.
#[async_trait]
pub trait ProductOperations: Send + Sync {
    /// Record a pending operation for this product. Returns its id.
    async fn begin_operation(
        &self,
        product: &ProductContext,
        label: Option<String>,
    ) -> Result<OperationId, GenericError>;

    /// Remove a pending operation. Idempotent: an unknown or already-ended
    /// id returns `Ok`.
    async fn end_operation(
        &self,
        product: &ProductContext,
        id: OperationId,
    ) -> Result<(), GenericError>;
}
```

Ref-counted and product-scoped. Two tasks each begin an operation, and the worker stays alive until both end. The count belongs to the product, like its storage, so any open operation holds the product's worker whichever runtime opened it.

Best-effort is the ceiling. On iOS and Android the OS can kill a backgrounded worker whatever the host does. An open operation lets the host ask for what background time the platform allows (a background task assertion on iOS, a foreground service or WorkManager on Android), but the worker still has to resume from saved state after a kill. Operations lower the odds of a mid-flight teardown. They don't remove it.

Kept generic on purpose. An operation is opaque: an optional label for logs and a future host UI, no funding or deposit typing. It's a plain liveness signal the host can build on later, not a funding session (see future directions). A `status` field and a `list_operations` read belong to that later UI, not v1. v1 is begin and end.

## Drawbacks

Both features cost host work. Each of the three hosts (web worker, iOS, Android) implements `subscribe_storage` plus the identical-write skip, and `ProductOperations` with the worker lifecycle tied to it. The operations side is the awkward one, since keeping a process alive is an OS concern with no core-only answer. `subscribe_storage` is cheaper and reuses the `subscribe_chat_rooms` shape a host has likely written already.

An open operation keeps a WASM instance resident, which costs battery. Best-effort teardown is the only guardrail in v1: a worker that never ends an operation pins itself, and with one product that's acceptable. The reaper that reclaims a stuck operation is deferred (see open questions).

## Security and privacy

The subscription's only new risk is scope leakage, and the core blocks it the same way `read` and `write` do: it passes the calling `ProductContext` to `subscribe_storage`, so there's no way to name another product's key. `begin_operation` and `end_operation` are gated to the `Worker` kind, like the Chat modality, so an app or widget can't call them, and an id from one worker means nothing to another.

Neither feature moves new data across a boundary. The subscription carries values the product already owns. The operation `label`, if a host shows it, is product text and should be bounded and screened like any other.

## Testing

The subscription tests against a fake `ProductStorage`: subscribe, check the initial value, write and check the item, write identical bytes and check nothing fires, clear and check `None`, and check product A never sees product B's writes. The operation flow tests against a fake `ProductOperations`: `begin_operation` and `end_operation` reach the host scoped to the calling product, ending an unknown id is `Ok`, and product A can't end product B's operation. Whether an open operation actually keeps the worker resident is host behavior and needs a real device.

## Compatibility

All three wire methods are additive and break nothing (`localStorage.subscribe` at 198, `worker.beginOperation` at 202, `worker.endOperation` at 204). On the host side, `subscribe_storage` lands on the required `ProductStorage` trait and `ProductOperations` is a required capability too, so every host implements both. The byte-identical skip is in the core, not the host, so every host inherits it. Target is v0.2 / latest.

## Unresolved questions

- Reaping stuck operations. What reclaims an operation a worker opened and never ended? A time cap, a count cap, or the user cancelling it through a future UI. Deferred for v1 since one product isn't critical, but it has to exist before this is load-bearing for many products.
- Rapid distinct writes. Identical writes already drop. For a burst of different values on one key, does the host emit each or only the latest? Emitting each is the literal contract; coalescing saves a progress-bar consumer work. Either way, state it in the trait doc.

## Future directions

Operations grow into a general liveness rule. The worker stays alive while `can_execute` holds, and pending operations are one term: `can_execute = has pending operations || has chats || has pocket cards || ...`. This RFC ships the first term.

Around that, a host UI listing active operations, with `status` on each and a `list_operations` read to feed it, and a user cancel that ends the operation and releases the worker. A prefix subscription instead of a single storage key, if products want to watch a set at once. All are out of scope here and none needs a wire break later.
