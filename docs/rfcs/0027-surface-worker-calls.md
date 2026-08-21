---
title: "Calling a product's worker from its app"
owner: "@BigTava"
---

# RFC 0027: Calling a product's worker from its app

|                 |                                                                                                                |
| --------------- | -------------------------------------------------------------------------------------------------------------- |
| **RFC Number**  | 27                                                                                                             |
| **Start Date**  | 2026-08-20                                                                                                     |
| **Description** | A `Worker` method letting a product's rendered executable invoke a named export of that same product's worker. |
| **Authors**     | Tiago Tavares                                                                                                  |

## Summary

Add one method to a new `Worker` trait. `call_worker` takes an export name and a JSON payload, dispatches to the calling product's own worker, and returns the export's answer. The Host supplies the caller's product identity — the request carries no product field — and a worker opts in by declaring which rendered executables may reach it in its manifest `includes`. The call is request/response, one direction, and carries data only.

## Motivation

A product ships two kinds of executable: the web applications a Host renders (`app`, `widget`, `funding`) and a single background `worker`. They run in separate sandboxes, and no protocol connects them. The product-manifest RFC defines both and explicitly defers runtime APIs to per-modality contracts, so today nothing specifies how a rendered executable and a worker exchange anything at all.

**Work that outlives the view has nowhere to live.** A funding surface starts a settlement that runs for minutes across several chain interactions. The user closes the sheet halfway through. The worker is the right home for that job — it holds the product's full Host-API surface and its lifetime is independent of any view — but the surface cannot start it. So the job goes in the page, where it dies with the view, competes with rendering, and runs outside the deadline, backoff and quarantine machinery a Host applies to worker code.

**A surface cannot ask what its own product is doing.** The two executables already share one storage namespace and one product account, so a worker's results are readable by the surface once written. What is missing is the request. A surface reopened mid-job can only wait for the next write to land; it cannot ask for the current state, and cannot distinguish "still working" from "the worker was never started".

**Products will otherwise ask for the unsafe version.** The obvious shortcut is to let the page hand the worker a function to run. That must not be built — see [Alternatives](#alternatives) — and the cheapest way to prevent it is to ship the bounded version first.

## Detailed Design

### `worker.callWorker`

````rust
/// Invoke a named export of the calling product's own worker.
///
/// The export must be declared by the worker module in the product's
/// verified archive. An undeclared name is `Invalid`; nothing is loaded on
/// demand. See [RFC 0027].
///
/// [RFC 0027]: https://github.com/paritytech/host-rust-core/blob/main/docs/rfcs/0027-surface-worker-calls.md
///
/// ```ts
/// const result = await truapi.worker.callWorker({
///   apiName: "startSettlement",
///   payload: JSON.stringify({ rail: "BANK", intentId }),
/// });
/// assert(result.isOk(), "callWorker failed:", result);
/// console.log("job:", JSON.parse(result.value.payload));
/// ```
#[wire(request_id = 174)]
async fn call_worker(
    &self,
    cx: &CallContext,
    request: WorkerCallRequest,
) -> Result<WorkerCallResponse, CallError<WorkerCallError>>;
````

```rust
/// Request to invoke one worker export.
struct WorkerCallRequest {
    /// Export declared by the worker module. Not a path, not a module
    /// specifier — the Host resolves it against the already-loaded module.
    api_name: String,
    /// JSON arguments, bounded by the worker protocol's payload ceiling.
    payload: String,
    /// Per-call wall-clock budget. `None` selects the Host default; values
    /// are clamped to the Host's own window. Caller-expressible because the
    /// budgets genuinely differ: an interactive status check wants to fail
    /// fast, a settlement start wants the full window.
    deadline_ms: Option<u32>,
}

/// The export's answer.
struct WorkerCallResponse {
    /// JSON returned by the export, under the same payload ceiling.
    payload: String,
}

/// Error from call_worker.
enum WorkerCallError {
    /// No worker is running for this product. Covers a product with no
    /// worker, a worker the user stopped, a manifest that declares no
    /// ceiling for this surface, a quarantined worker, and a host that runs
    /// no workers at all.
    Unavailable,
    /// No such export, or the payload is malformed or over the ceiling.
    Invalid(GenericError),
    /// The call outlived its deadline and was revoked.
    Timeout,
    /// The worker threw, or died handling the call.
    Crashed,
    /// Worker and Host disagree on the protocol.
    Version,
}
```

**The request carries no product identifier, and that is the security property.** The Host knows which product's surface it is rendering. If the caller named the product, page JavaScript could address a different product's worker by passing a different string, and no downstream validation could recover the true caller. The worker's own execution context is Host-issued for the same reason: identity that JavaScript can state is identity JavaScript can forge.

**Data crosses, never code.** `api_name` selects an export the verified archive already declared. The call cannot widen what the worker is able to do — it asks a worker that already holds its own authority to act, and the answer comes back as bytes.

**`Unavailable` is deliberately undifferentiated.** A surface must not be able to tell "this product has no worker" from "the user stopped it" from "the manifest does not permit you". Splitting those would turn the method into a probe for a control the user owns.

### Manifest declaration

Reaching a worker is opt-in, declared on chain rather than requested at runtime, so "what can call this worker" is answerable from the manifest before any code runs. `includes` already names which surfaces a worker serves, and this extends the same vocabulary:

```ts
interface WorkerIncludes {
  chat: boolean;
  pocket: boolean;
  /** Rendered executables permitted to call this worker. Absent means none. */
  app?: boolean;
  widget?: boolean;
  funding?: boolean;
}
```

Per-surface rather than a single flag: a product may want its funding sheet to drive a settlement while its widget, rendered on a dashboard nobody is looking at, cannot. Collapsing the three into one boolean makes the narrower policy unexpressible, and widening a ceiling later is additive while narrowing one is breaking. Unknown keys stay ignored, so a record published before this RFC reads as "no surface may call me" rather than failing to resolve.

Note the asymmetry with `chat`. That flag widens the worker's own authority — a worker declaring it is issued a trusted execution kind that unlocks the chat service surface. These three grant the worker nothing; they only admit a caller that otherwise has no path.

### Semantics and invariants

- **Same limits, new caller.** Surface calls reuse the worker protocol's existing bounds: capped payloads, per-call deadlines with typed expiry, serialized dispatch per worker, a bounded queue whose overflow is `Unavailable`, and crash backoff into quarantine. A surface calling in a loop degrades into typed errors rather than unbounded work. A surface call is a new _caller_, not a new _path_.
- **Starting is the Host's business.** A surface does not start or stop a worker. If the worker is not running and the manifest permits the call, the Host may start it; if the user has stopped it, the answer is `Unavailable` and stays that way until the user says otherwise.
- **No ambient state.** Two calls share nothing beyond what the worker itself persists. Callers that need continuity pass an identifier the worker minted.
- **One identity beneath both.** Every rendered surface — `funding.<product>` included — runs under the base product identity; the subnames are resolution names, never runtime identities. Caller and worker therefore share one storage namespace and one product account. A Host that gives a surface subname its own namespace breaks this method outright: the worker's answers name state the caller cannot read or persist against.

### Typical product flow

```ts
const started = await truapi.worker.callWorker({
  apiName: "startSettlement",
  payload: JSON.stringify({ rail: "BANK", intentId }),
});
if (!started.isOk()) return renderUnavailable();
const { jobId } = JSON.parse(started.value.payload);

// Reopening the surface later: ask, rather than wait for the next write.
const status = await truapi.worker.callWorker({
  apiName: "status",
  payload: JSON.stringify({ jobId }),
});
assert(status.isOk(), "status failed:", status);
```

The job survives the surface closing because it never lived there. The surface holds an identifier, not a process.

### Implementation shape

The core does not own worker execution. A Host already implements the worker engine behind a platform seam, and the runtime that owns correlation, payload bounds, serialized dispatch and quarantine sits above it. This RFC adds a caller, so it follows the delegation pattern RFC 0026 uses:

- `truapi-platform` gains one syscall carrying the calling product's identity, the export name, the payload and the deadline.
- `truapi-server` answers `call_worker` in-core by checking the manifest ceiling for the calling surface's kind and delegating to that syscall, mapping a missing worker, a refused ceiling and a stopped worker alike onto `Unavailable`.

Hosts that already run workers implement one callback over machinery they have. Hosts that do not run workers return `Unavailable` and are conformant.

Two requirements on a conforming Host that runs workers, easy to miss because each fails far from its cause:

- **Async exports need a reactor.** A Host embedding the core over UniFFI must export the worker-facing async callbacks with `async_runtime = "tokio"`; an export that reaches storage without one fails as a host-process abort, not a typed error.
- **Launch parameters must reach archive-served surfaces.** The reopen in [Typical product flow](#typical-product-flow) assumes a relaunched surface can carry an identifier back in through its launch query; a Host that drops the query for archive-served executables strands the caller with no way to name its job.

The change is purely additive: one new trait, one fresh wire id, no changes to existing calls or types.

## Non-goals

- **Push to the surface.** Request/response only. A surface follows a long job by polling a `status`-shaped export or by reading the storage the worker writes. A subscription needs its own cancellation and lifetime semantics and should not hold this up.
- **Worker-initiated calls.** The worker cannot call the surface. It has no view, the surface may not exist, and what it wants to say belongs in product storage where a surface can read it afterwards.
- **Cross-product calls.** A surface reaches its own worker and no other. Product-to-product interaction is the permission model's business, not this method's.
- **Worker lifecycle control.** Starting, stopping and disclosing workers is a Host concern with a user-facing control surface; this RFC neither extends nor bypasses it.

## Drawbacks

- Two executables that could not previously interact now can, which is new surface area for review. Authority does not move — the worker's capabilities are unchanged and the surface gains none of its own — but the interaction itself has to be reasoned about.
- The worker becomes a soft dependency of a surface's flows. A product must still work when the answer is `Unavailable`, because a user can stop the worker at any time. That burden is real, and it is why `Unavailable` is specified as an ordinary outcome rather than a fault.
- Polling for status is less efficient than a subscription, and this ships without one. The cost is bounded by the same queue and deadline limits as any other call.

## Alternatives

- **Let the surface pass the code to run.** This was discarded, and is recorded because it is the request this RFC pre-empts. Worker code resolves only from one pinned, verified archive; code arriving from a page has no CID and no signature. The worker's execution kind authorizes more than the surface's, so anything able to inject into the page — a cross-site scripting bug, a compromised dependency — would execute with worker authority. The bounded version costs a redeploy to change worker logic, which is the intended price.
- **A symmetric message channel between the two sandboxes.** This was discarded because it invites the worker to depend on a surface being present, which is the coupling the worker exists to avoid. The lifetimes are asymmetric, so the protocol should be too.
- **Product storage as the only mechanism** — the surface writes a request record and the worker picks it up. Products should still keep durable job state there, but as the sole mechanism it cannot start a stopped worker, gives no typed failure, and turns every request into a poll with no bound on latency.
- **A single `includes` flag rather than one per surface.** This was discarded because it cannot express "my funding sheet may, my widget may not", and a ceiling can be widened additively later but never narrowed.
- **Do nothing.** This was discarded because it is the status quo the motivation describes: long jobs run in pages, where they die with the view.

## Prior Art and References

- [RFC — Product Manifest Format](product-manifest.md) — the two-level manifest, the `worker.<product>` subname, `includes`, and the one-worker-per-product rule this RFC extends.
- [RFC 0026 — Host chain discovery and name resolution](0026-supported-chains.md) — the platform-syscall delegation pattern [Implementation shape](#implementation-shape) follows.
- [RFC-0024 — Proof of Personhood as a Product](0024-personhood-as-product.md) — also extends `WorkerIncludes`, with `onLoad`; see [Unresolved Questions](#unresolved-questions).
- [RFC 0002 — Permission Model](0002-permission-model.md) — owns product-to-product interaction, which is why cross-product calls are a non-goal here.
- [Brevity pocket modality contract](https://github.com/paritytech/brevity-dozer/blob/main/docs/pocket-modality-contract.md) — §6 specifies the worker protocol's bounds this method reuses (payload ceiling, serialized dispatch, bounded queue, crash backoff into quarantine) and §7 the identity rules behind [Semantics and invariants](#semantics-and-invariants); neither is specified in this repo.

## Unresolved Questions

- **Coordination with RFC 0024**, which also extends `WorkerIncludes`, with `onLoad`. That key is a lifecycle request rather than a surface, so `includes` would carry two different kinds of thing. Whether lifecycle belongs there at all is worth settling once rather than in two RFCs separately.
