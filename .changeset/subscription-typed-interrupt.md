---
"@parity/truapi": minor
"@parity/truapi-host": minor
---

Every subscription names the type it can be interrupted with. A host trait method returns
`Subscription<Item, CallError<E>>`, a stream of `Result<Item, CallError<E>>` whose first `Err` ends it, so a platform
failure reaches the product instead of freezing its last value. The `Interrupt` leg carries `Result<(), CallError<E>>`:
`Ok(())` is a normal end delivered as `complete`, and `Err(reason)` reaches `error` with `reason` set to the declared
value. Frame bytes are unchanged.

`Result<Subscription<Item>, CallError<E>>` is no longer a subscription return: a start-time failure is an interrupt with
no items before it. Methods that could only fail at start now report the same failure at any point.

A product serves a host-initiated method with `(request, send, interrupt) => teardown` rather than by returning an
observable. `interrupt()` ends the host's stream, and `interrupt(reason)` ends it with the method's own interrupt value,
which the host reads as `Err(reason)` instead of a fixed generic error.
