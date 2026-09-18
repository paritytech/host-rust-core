---
title: "Request cancellation"
owner: "@decrypto21"
status: draft
---

# RFC: Request cancellation

## Summary

A caller can withdraw a request it has already sent. A `Cancel` leg on the method's own wire address fires the call's
cancellation token on the far side, and the call still settles with exactly one response.

## Motivation

One-shot calls are not short. `signing.createTransaction` and `resourceAllocation.request` wait for a person to act on
a paired phone; the `chain` methods wait on a remote node. Nothing carries the caller's decision to stop waiting.

`CallContext` already holds a `CancellationToken`, and the runtime already honours it: `remote_authority_call` races the
handler against the token and gives it a bounded unwind before dropping it. But every generated request handler builds
its own context with `CallContext::with_request_id`, a fresh token no frame can reach. Only a timeout or a host-internal
decision fires it.

So the product abandons calls the host keeps running. The TypeScript client arms a deadline on every request that drops
the pending entry and rejects the promise without sending anything, and a product that navigates away or unmounts a
component leaks the same way with no deadline at all. In both cases the signing prompt stays on the phone, the chain
query keeps its connection, and the paired authority keeps a message in flight, because nothing told the host
otherwise.

A timeout is the wrong instrument for this. A signing call has to allow minutes, which is far too slow to serve as an
abort, and it reports elapsed time for what was a person's decision to stop.

Subscriptions have none of this problem. `Stop` is exactly this message, and it already works.

## Approach

`Cancel` is a message type on the request/response family, beside `Request` and `Response`, carried on the method's own
`(trait, method)` address and correlated by `requestId`. It has no payload and travels in the same direction as that
method's `Request`. [RFC 0028][0028] put the leg in the envelope for this case: a new leg costs a message-type value and
a dispatch arm, and no method id moves. Every request method is cancellable, with no per-method opt-in.

What a cancel does and does not promise:

- Exactly one `Response` still settles a `requestId`.
- A withdrawn call answers `CallError::Cancelled`, whatever its handler made of the token.
- A `Cancel` naming no call in flight is never answered, and is remembered rather than dropped, because it may have
  overtaken the request it names.
- Cancelling is cooperative in what it stops, not in what it answers. A handler that never observes its token runs to
  completion and loses a result nobody is waiting for.

### Host side

The dispatcher gains a registry of in-flight requests keyed by `requestId`, holding each call's token, in the same
shape as the subscription registry that already serves `Stop`. It reserves the entry before awaiting the handler, so a
cancel arriving during setup is not lost, and handlers take their token from the registry rather than minting one. The
runtime's existing `in_flight` map is keyed by a monotonic dispatch id and holds `AbortHandle`s, which is the right
shape for dropping every call at teardown and the wrong one for naming a single call from the wire. It stays as it is.

Frame order does not survive the trip. Transports spawn a task per inbound frame, so the `Request` and `Cancel` a
client wrote to the socket in order can reach dispatch the other way round, and the cheaper `Cancel` often wins. A
withdrawal that found nothing would be lost, and the product would wait out its full deadline while the host kept
working, with the phone still prompting. So a `Cancel` that finds no call records the id instead, in a short capped
queue, and the `Request` that follows answers `Cancelled` without running its handler at all. Not running it is the
point: a `createTransaction` withdrawn before it started must never reach a person.

For a withdrawn call the dispatcher substitutes the response, and it can build one without naming either of a method's
payload types: `Err(CallError::Cancelled)` is the `Result`'s `Err` tag followed by the variant's index, and `Cancelled`
carries nothing, so the same two bytes are a valid response leg for every request method. The client already uses that
trick to decline a host-initiated subscription with a fixed `HostFailure` frame.

### Why this rides no codec bump

`CallError` gains `Cancelled` as its last variant, so every existing discriminant keeps its index. Two things then keep
the change additive.

The wire schema hash moves, because `CallError`'s shape is in the fingerprint precisely so an error discriminant cannot
change unannounced. But that fingerprint is read only by the debugger, deciding whether its decode table matches the
host it is tapping. It gates nothing between a product and a host.

The variant is reachable only by a peer that asked for it, and the dispatcher holds that line: it substitutes the
`Cancelled` response only for a call a `Cancel` frame withdrew, never for one whose token a runtime fired itself. A
host-internal timeout still becomes an `AuthorityError::Cancelled` mapped into the method's own domain error, so a
product that never sends a `Cancel` never has to decode the new variant.

That is worth the care, because `WIRE_CODEC_VERSION` is what a bump would cost. The handshake compares it for exact
equality in both directions, so moving it is a flag day rather than a rollout: a product on the new number cannot talk
to a host on the old one at all, for any method, and native hosts ship on app-release cycles. Keeping the generated
client's number in step with `truapi::WIRE_CODEC_VERSION` is #848's work, not this change's.

### Peers that predate the leg

A `Cancel` arriving at one is dropped with a log and no reply. The `(255, 255)` protocol error answers an unknown
`(trait, method)` pair, and a `Cancel` addresses a pair the old peer implements, so it reaches the request arm's
message-type guard and dies there. Nothing else about that pairing breaks: the call proceeds and settles normally, and
only the withdrawal is lost. But the caller cannot tell a cancel the host honoured from one it never understood, and it
has nothing to fall back on but its own deadline. That is the gap [#478][478] closes, and this RFC assumes a product
checks method-level support before offering an abort.

### Client side

A product cancels through an `AbortSignal`, taken as the last argument of every generated request method. Aborting
sends `Cancel` and lets the promise settle on the response, so the product reads `Cancelled` instead of a local
rejection the host never heard about. A signal already aborted when the call is made sends nothing at all. The client's
own deadline sends `Cancel` before it rejects, which is the leak it closes: today that deadline drops the pending entry
and rejects without telling anyone.

Tearing down an execution is unchanged. It aborts the dispatch futures wholesale, which drops the handlers outright and
is strictly stronger than firing their tokens. The registry entries those futures held are not released on that path,
since the release runs after the handler returns and an aborted future never reaches it. They cost a slot each until the
registry itself is dropped with the connection, and a monotonic id is never presented again, so nothing is left
reachable.

Cancelling a call that waits on a paired host ends the local wait by the path a timeout already takes. The paired host
is not told, because the SSO protocol has no cancel message.

## Trade-offs

- Cooperative, not preemptive. A handler that never observes the token runs to completion: the caller is told the call
  was cancelled, but the work behind it was not stopped, and the caller waits as long as it would have.
- Aborting is not instant. The product learns the outcome when the response arrives.
- One dispatch arm and one registry per side, and codegen emits the arm for every request method.
- A single protocol-level cancel address carrying the target `requestId` in its payload, as `(255, 255)` carries
  protocol errors, needs no per-method codegen. It was dropped because a frame that names no method is opaque to a
  debug tap and to any per-method policy, and it splits teardown across two mechanisms when `Stop` already works
  per-method.

## Open questions

1. Does the SSO protocol need a cancel message in the same change? Unblocking the product while the phone keeps
   prompting is half of what cancelling a signature is asked to do.

[0028]: 0028-wire-message-type-byte.md
[478]: https://github.com/paritytech/truapi/issues/478
