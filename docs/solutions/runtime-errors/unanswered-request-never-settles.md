---
title: "Timeout unanswered TrUAPI requests so an embedder's promise always settles"
date: 2026-08-14
category: runtime-errors
module: "@parity/truapi client transport (js/packages/truapi)"
problem_type: runtime_error
component: service_object
symptoms:
  - "A request the host accepts and never answers neither resolves nor rejects while the message channel stays open"
  - "A signed-in person sits on a permanently disabled button with no error logged"
  - "The pending map keeps the entry indefinitely; entries leave only on a response frame, a transport close, or a synchronous send failure"
root_cause: async_timing
resolution_type: code_fix
severity: high
related_components:
  - tooling
tags:
  - request-timeout
  - promise-hang
  - timeout-floor
  - pending-map
  - transport
  - host-deadline
---

# Timeout unanswered TrUAPI requests so an embedder's promise always settles

## Problem

A product awaiting a TrUAPI request such as `client.account.getAccount()` got no answer when the host accepted the request and then replied with nothing while the message channel stayed nominally open: the returned promise neither resolved nor rejected. Nothing timed it out, so the product waited forever and the calling code could not tell a slow host from a silent one.

## Symptoms

- A request frame the peer accepts and never answers returns a promise that stays pending indefinitely — no resolution, no rejection.
- A signed-in person is left looking at a permanently disabled button with no error to log: the hang produces no observable signal at all.
- The transport's `pending` map keeps the request entry for the lifetime of the transport. Entries left it on only three paths — a matching response frame, a transport/provider close, or a synchronous `send` failure — none of which fire when the channel simply goes silent.
- The protocol spec does not save you here: it requires exactly one response per `requestId` (`docs/design/truapi-protocol.md:124`) but mandates no client-side deadline, and names a timeout only for the handshake (`docs/design/truapi-protocol.md:150`).

## What Didn't Work

**A floor table whose inclusion rule was "the host deadline exceeds the default" silently dropped the slowest methods in the system.** Per-method floors are needed because a flat default would abort answers the host is still allowed to send — but that rule cannot express *"this call has no deadline at all"*, and those are exactly the slowest calls. In `rust/crates/truapi-server/src/runtime.rs`, `request_device_permission` (line 813) and `request_remote_permission` (line 835) ignore `_cx` entirely and await `check_or_prompt_device` / `check_or_prompt_remote`, which block on a human; `request_login` (line 1303) ignores `_cx` and delegates to an unbounded pairing loop. `rust/crates/truapi-server/src/native.rs:378-382` documents that these host callbacks "may keep the future pending arbitrarily long". Under a flat 30s default, every one of them would have been aborted mid-prompt while the host went on to record the user's answer.

The same rule also missed methods that *do* sit behind the 180s remote-authority deadline, because it was applied from the list of Rust timeout constants rather than from the call sites that use them. Six handlers route through `remote_authority_context(cx)` and were absent from the first table: `register_ring_vrf_key` (`runtime.rs:1090`), `list_ring_vrf_keys` (`:1136`), `ring_vrf_sign` (`:1184`), `sign_vrf` (`:1226`), and both statement-store proof helpers (`rust/crates/truapi-server/src/runtime/statement_store.rs:319`, `:343`). Five wire methods had no floor at all as a result; the sixth, authorized proof creation, was floored in the wrong class. Deriving the table from `remote_authority_context` call sites, and adding a class for "no host deadline", is what made it complete.

**Tests that asserted only settle ordering let a wrong precedence survive.** The first cut raced a floored request against a 5ms control and asserted the control settled first. Ordering alone is consistent with both `max(configured, floor)` and the mutant `floor ?? configured`, because every ordering test configured a bound *below* the floor, where both expressions pick the floor. A deliberately long configured bound was never exercised, so the mutant — which silently caps a product's long timeout at the floor — stayed green.

**Unref'd timers.** An earlier cut armed `setTimeout(…).unref()` so a pending request could not hold a process open. Measured on Node, an unref'd timer's rejection is dropped when the event loop is otherwise empty: the process exits before the timer fires and the rejection is lost, restoring the original hang in exactly the case the timeout exists to fix. The shipped timer is ref'd, and the tests dispose the transport instead.

## Solution

Every request gets a bound — a per-request override, else `max(configured, method floor)`. A `setTimeout` armed *before* `send` rejects with a typed error, one choke point removes pending entries, and invalid bounds are rejected at the call site.

A typed timeout error, discriminated from a close error by type and never by message text (`js/packages/truapi/src/transport.ts:65`):

```ts
export class RequestTimeoutError extends Error {
  readonly timeoutMs: number;
  constructor(timeoutMs: number) {
    super(`TrUAPI request timed out after ${timeoutMs}ms`);
    this.name = "RequestTimeoutError";
    this.timeoutMs = timeoutMs;
  }
}
```

The timer is armed before `send`, so a synchronous `send` failure still rejects with the close error rather than the timeout (`js/packages/truapi/src/client.ts:617`):

```ts
const bound = resolveRequestTimeoutMs(ids.request, requestTimeoutMs, timeoutMs);
const promise = new Promise<ResultPayload<Ok, Err>>((resolve, reject) => {
  if (closedError) {
    reject(closedError);
    return;
  }

  const requestId = `p:${++idCounter}`;
  const timer = setTimeout(() => {
    takePending(requestId);
    reject(new RequestTimeoutError(bound));
  }, bound);
  pending.set(requestId, {
    ids,
    resolve: (response) => resolve(decodeResponse(response)),
    reject,
    timer,
  });
  try {
    send({ requestId, payload: { id: ids.request, value: payload } });
  } catch (error) {
    takePending(requestId);
    reject(toError(error));
  }
});
```

One removal choke point. Response dispatch, the close loop, and the timeout callback all settle through it, so deletion and timer-clearing can never drift apart (`client.ts:353`):

```ts
function takePending(requestId: string) {
  const entry = pending.get(requestId);
  if (!entry) return undefined;
  pending.delete(requestId);
  clearTimeout(entry.timer);
  return entry;
}
```

Bound resolution as one testable decision (`client.ts:180`):

```ts
export function resolveRequestTimeoutMs(
  requestFrameId: number,
  transportTimeoutMs: number,
  perRequestTimeoutMs: number | undefined,
): number {
  if (perRequestTimeoutMs !== undefined) {
    return checkRequestTimeoutMs(perRequestTimeoutMs);
  }
  return Math.max(
    transportTimeoutMs,
    REQUEST_TIMEOUT_FLOOR_MS.get(requestFrameId) ?? 0,
  );
}
```

`checkRequestTimeoutMs` (`client.ts:160`) rejects the values `setTimeout` silently collapses into an immediate fire — `0`, `Infinity`, `NaN`, and anything above `MAX_REQUEST_TIMEOUT_MS = 2_147_483_647` (`client.ts:61`) — and it throws at the call site rather than rejecting through the promise, matching the transport-level validation.

The default is `DEFAULT_REQUEST_TIMEOUT_MS = 30_000` (`client.ts:71`), chosen against budgets the repo already ships rather than freely: the package waits 20s for a host-injected message port (`HOST_PORT_TIMEOUT_MS`, `js/packages/truapi/src/sandbox.ts:80`), and the playground bounds prompt-backed protocol calls at 30s (`playground/src/lib/auto-test.ts:17`).

`REQUEST_TIMEOUT_FLOOR_MS` (`client.ts:109`) holds 23 entries keyed on generated `W.*.request` ids — so codegen renumbering cannot silently re-bind a floor to another method — in three classes:

| Class | Value | Entries | Derivation |
| --- | --- | --- | --- |
| `REMOTE_AUTHORITY_REQUEST_TIMEOUT_MS` (`client.ts:79`) | `190_000` | 15 | above the runtime's 180s remote-authority deadline (`runtime.rs:186`), which itself follows host-spec B.6.2 (`runtime.rs:183-185`) |
| `USER_APPROVAL_REQUEST_TIMEOUT_MS` (`client.ts:89`) | `420_000` | 5 | no host deadline exists; a person answers, so this is the client's own ceiling |
| `LIVE_ALLOCATION_REQUEST_TIMEOUT_MS` (`client.ts:95`) | `420_000` | 3 | above the 300s allocation and 360s preimage caps (`runtime.rs:191`, `:196`) |

## Why This Works

The invariant is the single removal choke point. `takePending` is the only place an entry leaves `pending`, and it always clears the timer, so no settled request leaves a live timer that could reject an already-settled promise, and a reply arriving after the bound fired finds no entry to resolve — it is inert rather than throwing (`client.test.ts:744`). Arming the timer before `send` is what keeps the discriminant the caller needs: the synchronous send-failure path settles through the same `takePending` with the close error rather than a timeout (`client.ts:647-650`), so "the channel is gone" stays distinguishable from "the host went silent" — the distinction `client.test.ts:831` pins by asserting a disposed transport rejects with a plain `Error`, never `RequestTimeoutError`.

The floors work because they are derived from the host's own permission to answer, not from a UI preference. The runtime allows 180s for a remote-authority answer — over six times the default — and the person-backed methods carry no deadline at all, so bounding either at 30s would convert a legitimate slow answer into a spurious timeout, and worse, a caller who then retries a non-idempotent submit can double-execute it (requests carry no cancel frame, unlike subscriptions, which have a `stop`). `Math.max(configured, floor)` lets a product tighten or loosen its own bound while never aborting an answer the host is permitted to deliver.

## Prevention

**Gate the classification, not the values.** A generated request method added without a floor fails this test rather than silently inheriting the default (`client.test.ts:913`, with the prompt-free set at `client.test.ts:26`):

```ts
it("classifies every generated request method as floored or prompt-free", () => {
  const unclassified = Object.entries(W)
    .filter(([name, ids]) => {
      if (!(ids && typeof ids === "object" && "request" in ids)) return false;
      const requestId = ids.request;
      return (
        typeof requestId === "number" &&
        !REQUEST_TIMEOUT_FLOOR_MS.has(requestId) &&
        !PROMPT_FREE_REQUESTS.has(name)
      );
    })
    .map(([name]) => name);

  expect(unclassified).toEqual([]);
});
```

**Show each test failing on the bug it targets.** Passing on correct code proves nothing about a test's power. Four mutants were run against this suite when the fix landed, and each failed the case that targets it — the per-mutant failure counts below are that session's measurement, not something the tree records: revert the timer arming (5 cases failed), swap `max(configured, floor)` for `floor ?? configured` (1 — `client.test.ts:882`, which asserts a 500s configured bound survives a 190s floor), delete the per-request override branch (2), drop one method from the classification sets (1). If a plausible regression leaves the suite green, the suite does not test that property.

**Know that the floors are an ungated cross-language restatement.** `190_000` and `420_000` restate Rust deadlines (`runtime.rs:186`, `:191`, `:196`) with nothing tying them together, and the repo already demonstrates that this drifts: `rust/crates/truapi-host-cli/js/diagnosis.ts:19` bounds prompt-backed methods at `190_000` while `playground/src/lib/auto-test.ts:18` bounds the same methods at `60_000`. Re-verify the floor table whenever a host-side deadline moves; the durable fix is emitting each method's deadline into the generated wire table from rustdoc, so a Rust change either updates the client or fails the build.

## Related Issues

- GitHub paritytech/truapi#406 — the hang this learning fixes.
- `docs/design/truapi-protocol.md:124` — the protocol requires exactly one response per `requestId`; `:150` names a timeout only for the handshake.
- `docs/local-e2e-testing.md` — the manual E2E guide names the same symptom ("if a method call hangs") without a budget for it.
- `js/packages/truapi/README.md` — the shipped "Request timeouts" contract, including the floor table an embedder sees.
