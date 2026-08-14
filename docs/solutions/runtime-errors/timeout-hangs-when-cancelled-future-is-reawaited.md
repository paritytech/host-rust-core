---
title: A deadline that re-awaits the future it just cancelled is not a deadline
date: 2026-08-14
category: runtime-errors
module: truapi-server
problem_type: runtime_error
component: service_object
symptoms:
  - "A wire request is neither answered nor refused — the caller sees no success and no timeout error, only silence"
  - "The stall needs no error condition: a host connect or subscribe that simply never resolves is enough"
  - "The handler future never resolves, so the dispatcher never sends a response frame"
  - "Tests asserting post-deadline cleanup start failing once the deadline is actually enforced"
root_cause: async_timing
resolution_type: code_fix
severity: high
related_components:
  - authentication
  - testing_framework
tags:
  - cancellation
  - cooperative-cancellation
  - timeout
  - async-rust
  - futures-select
  - drop
  - deadline
---

# A deadline that re-awaits the future it just cancelled is not a deadline

**The rule:** cooperative cancellation is a *request*, not a guarantee. A future that
is parked on an await which never polls the cancellation token will never observe it,
and nothing in the token machinery can force it to. The only hard stop a caller owns
is dropping the future. So a `select!` that cancels a loser and then awaits it has not
bounded anything — it has just moved the hang one line down.

## Problem

`remote_authority_call` (`rust/crates/truapi-server/src/runtime.rs:262`) races a host
authority call against a cooperative `CancellationToken` and an optional deadline. Every
non-success arm ended with `let _ = call.await;` — re-awaiting the future it had just
cancelled — before returning its error. When the inner future was parked on an await
that never observes the token, the timeout arm parked with it and the outer call returned
nothing at all.

## Symptoms

- A logged-in user's `account_get` never comes back. `Dispatcher::dispatch` sends a
  response frame only once the handler resolves, so the request sat neither answered nor
  refused — the failure is silence on the wire, not an error.
- No fault is required to trigger it. A statement-store `connect` that stays pending
  (`rust/crates/truapi-server/src/test_support.rs:1355-1357` models exactly this with
  `futures::future::pending::<()>().await`) or a subscribe whose ack never arrives
  (`rust/crates/truapi-server/src/runtime/pairing_host/sso_channel.rs`, where
  `submit_remote_message` parks on `wait_for_sso_remote_response`) is sufficient.
- The deadline appears to be configured and is in fact inert. Every one of the 18
  `remote_authority_call` sites sits under a non-`None` timeout, so the timeout branch is
  always the one that fires — and it was the branch that hung.
- **The clearest symptom only appears after the fix:** two assertions that a timed-out
  request unsubscribes two statement streams began failing. See *Prevention*.

## What Didn't Work

- **Make the three parking awaits cancel-aware and keep the re-await.** This treats the
  awaits that happen to park today. The next await added inside any authority call that
  does not poll the token reintroduces the identical hang, and the re-await is precisely
  what keeps the abandoned future alive. The hazard is open-ended; the patch is not.
- **Detach the inner future onto a spawner with a reaper.** This trades a hang for a leak:
  a never-resolving connect keeps its stack, its connection, and any lock it holds, now
  with no one waiting on it. It is also structurally awkward —
  `remote_authority_call` is a free `fn(cx: &CallContext, call: F)` with no spawner in
  scope, so threading one through would touch all 18 call sites to buy that leak.
- **Arguing that the drop is safe because no orphan can hold a lock.** An earlier draft of
  the plan asserted this. It is false, and code review falsified it: on the SigningHost,
  `allocate_statement_store_allowance` takes `registration_lock`
  (`rust/crates/truapi-server/src/runtime/signing_host/sso_responder.rs:949`) and holds it
  across an on-chain submission, reachable from `remote_authority_call` at
  `rust/crates/truapi-server/src/runtime/statement_store.rs:344`. The drop *is* still the
  right fix — guards release on drop — but the reason is that `Drop` runs, not that
  orphans hold nothing. What the drop does not do is restore the invariant the guard was
  protecting, and that is a genuine residual to design for separately, not a detail to
  wave away.

## Solution

Delete the re-await from every non-success arm so each returns its error directly,
dropping the `select!` loser. Keep `cancel_with_reason` ahead of the drop.

Before:

```rust
() = timeout => {
    let reason = CancellationReason::TimedOut { timeout: timeout_duration };
    cx.cancel().cancel_with_reason(reason.clone());
    let _ = call.await;                                    // parks here forever
    Err(authority_cancellation_error(cx, reason).into())
}
```

After (`rust/crates/truapi-server/src/runtime.rs:277-283`):

```rust
() = timeout => {
    let reason = CancellationReason::TimedOut { timeout: timeout_duration };
    cx.cancel().cancel_with_reason(reason.clone());
    Err(authority_cancellation_error(cx, reason).into())
}
```

The same deletion applies to the two cancellation arms. The shape already had a precedent
in the same crate: `submit_preimage` returns on cancel and on timeout without re-awaiting
its loser (`rust/crates/truapi-server/src/runtime/bulletin_rpc.rs:293`, `:313-315`).

The drop also skips the unwind that used to emit the host-side log for an abandoned call,
so that diagnostic moved onto `authority_cancellation_error` itself.

## Why This Works

`cancel_with_reason` records a reason and wakes registered wakers
(`rust/crates/truapi/src/lib.rs:289`); `CancellationFuture::poll` stays `Pending` until a
reason is set (`rust/crates/truapi/src/lib.rs:327-330`). Nothing in that machinery reaches
into a future that is parked elsewhere. If the inner future never polls the token, it never
learns anything happened — which is the whole meaning of *cooperative*.

The caller, by contrast, owns its own control flow unconditionally. Returning from the
`select!` drops the losing future, and the drop is not negotiable: it runs `Drop` all the
way down the tree, releasing subscriptions, connection handles, and lock guards.

Keeping `cancel_with_reason` **before** the drop is not redundant. The token is shared, so
raising it first still gives cancel-aware inner futures and every other holder of the same
token their cooperative path, and leaves the reason observable via `cx.cancel().reason()`
(`rust/crates/truapi/src/lib.rs:304`). The layering is the point: cooperation first, drop
as the guaranteed stop behind it.

## Prevention

- **Write the test against a future that *cannot* cooperate.** A future whose `poll`
  always returns `Poll::Pending` and whose `Drop` sets an `AtomicBool`
  (`rust/crates/truapi-server/src/runtime.rs:2887`) is the only shape that can tell a real
  bound from a cooperative one. Drive it on a spawned thread and assert four things
  together (`rust/crates/truapi-server/src/runtime.rs:2910`): the error came back, the
  shared token recorded the reason, the inner future was dropped before the caller
  resumed, and the wall-clock elapsed time is under a ceiling. A test that asserts only
  "an error came back" passes just as happily against a re-await bounded by a grace period.
- **Assert the cancel signal, not just the return.** Deleting
  `cancel_with_reason` leaves every timing assertion green — the drop alone still returns
  on time. Asserting `token.reason()` is what makes the cooperative half of the contract
  load-bearing.
- **Revert-check before shipping.** Restore the bug and watch the new tests fail for the
  *stated* reason. Both gates here were confirmed that way: re-adding the re-await hung
  the bounded-return tests, and removing `cancel_with_reason` failed the reason assertion
  with `left: None, right: Some(TimedOut { timeout: 1ms })`.
- **When a fix makes an old assertion fail, ask what the assertion was measuring.** Two
  assertions that a timed-out request unsubscribes *two* statement streams broke here. A
  throwaway probe showed why: under a real bound only **one** subscribe is ever sent,
  because the call is abandoned before it reaches the second. Those assertions had only
  ever passed because the re-await let a timed-out call keep working past its deadline —
  they were asserting the bug's side effect. They were deleted, not loosened. The
  unsubscribe-on-abandonment contract still has a home in
  `sign_raw_cancellation_unsubscribes_sso_subscriptions`, which stages both subscriptions
  *before* firing the token.
- **Do not measure a bound against a suite you have not measured first.** The
  `truapi-server` suite has pre-existing wall-clock flakiness under back-to-back load,
  reproduced on the clean tree: `submit_preimage_recovers_inconsistent_inclusion_via_recheck`
  failed once in four clean runs with `Timeout { phase: Connect }`. A replacement test
  proposed in review was written, measured to flake one run in three, and removed rather
  than shipped.

## Recurrence scan

A scan of `rust/**` for the same shape found the fixed site to be the only instance. Every
other `futures::select!` with a cancellation or timeout arm returns from that arm without
re-awaiting the loser — `bulletin_rpc.rs:293`/`:313-315`/`:559`/`:641`, `identity.rs`,
`sso_pairing.rs`, `sso_remote.rs`, `host_rpc_client.rs`. Remaining `let _ = <fut>.await;`
occurrences in the crate are shutdown pumps or deliberately joined handles, not cancelled
`select!` losers.

Deadlines are centralized: they enter through the `remote_authority_context_*` family
(`rust/crates/truapi-server/src/runtime.rs:237-246` sets the default; `:248-260` sets an
absolute one) and are enforced only by `remote_authority_call`, so this one function is
the whole enforcement surface for the authority path.

## Related Issues

- Issue #405 — the originating report.
- `docs/plans/2026-08-14-1832-fix-authority-call-timeout-bounded-return-plan.md` — the
  implementation plan, including the rejected alternatives and the corrected lock claim.
- `docs/residual-review-findings/ryan-405.md` — code-review findings, including the
  `registration_lock` truncation and two non-`Drop` compensation windows left open.
