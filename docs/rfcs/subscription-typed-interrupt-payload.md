---
title: "Subscription Typed Interrupt Payload"
owner: "@johnthecat"
status: draft
---

# RFC — Subscription Typed Interrupt Payload

## Summary

Every subscription names its interrupt type, and its stream can end with a value of that type at any point. The
`_interrupt` frame carries the value; a normal end is an empty frame, which the client delivers as `complete`.
`Subscription<Item, Interrupt>` replaces both `Subscription<Item>` and `Result<Subscription<Item>, CallError<E>>`,
because a start-time failure is an interrupt with no items before it.

```ts
truapi.theme.subscribe({
  next: (theme) => apply(theme),
  error: (error) => console.warn("theme stream failed:", error.reason),
  complete: () => {},
});
```

## Motivation

A live subscription cannot fail. `Subscription<Item>` yields items only, so when the platform stream behind
`theme.subscribe` errors, the runtime drops the error and the product's theme freezes on its last value. A chain-head
follow whose connection drops ends with the same frame as one that finished cleanly.

The one place a typed reason exists, it is inconsistent. Methods declared `Result<Subscription<..>, CallError<E>>` send
a typed `_interrupt` when the start fails, and the generated TS client surfaces it as
`error(SubscriptionError { reason })`. Plain methods send an empty `_interrupt` for the same failure, and the client
reports `complete`, so a host that does not support the method looks like a stream that ended normally. When a
result-kind stream ends normally, the empty frame is fed to the typed decoder, which throws.

Host-initiated methods need the same in the other direction. A product that streams items to the host has no way to say
that it is done, or why it stopped, other than ending the stream or declining with a bare `[0]` byte that the host sees
as `GenericError { reason: "product interrupted the host-initiated subscription" }`. A stream that finishes with an
outcome has to encode that outcome as an error or lose it.

## Approach

`_interrupt` with a payload carries the method's interrupt value, encoded as declared and without further wrapping.
`_interrupt` with an empty payload is a normal end, which the TS client delivers as `complete`. `_stop` is unchanged.

`Subscription<Item, Interrupt>` is a stream whose items are `Result<Item, Interrupt>`; the first `Err` is terminal. The
dispatcher encodes it as the `_interrupt` payload and drops the rest of the stream. A stream that ends without an `Err`
produces the empty frame. A method chooses the shape of `Interrupt`: `CallError<E>` for a failure-only end, or
`Result<(), CallError<E>>` when a normal end carries meaning of its own. Methods with a domain error declare
`CallError<E>`, so their interrupt bytes are unchanged. Methods without one declare `CallError<GenericError>`, which is
what their platform streams yield, so the runtime forwards the platform error instead of dropping it.
`Subscription::interrupted(value)` is a stream that ends with the given interrupt and replaces `Subscription::empty()`.

Codegen emits `ObservableLike<Item, Reason>`, `SubscriptionError<Reason>` and an interrupt decoder for every
subscription; the decoder treats an empty payload as `complete`. A product that reads `error.reason` gets the declared
interrupt value.

A product handler for a host-initiated method returns `Subscription<Item, Interrupt>`. When its observable errors with
the method's interrupt value, the client encodes the value into the `_interrupt` frame, the server preserves the bytes,
and the host's stream ends with `Err(value)`. A product-side stream whose end carries an outcome declares it as the
interrupt type instead of encoding it as an error.

The frame format is unchanged, so there is no protocol version bump. A client without a decoder for the interrupt type
delivers any interrupt as `complete`, and a host that sends an empty frame on failure is read as `complete`.

## Trade-offs

- Every subscription implementer changes its return type, on all hosts, in one pass.
- A normal end is an empty `_interrupt` frame, not silence, so a product can distinguish a finished stream from a
  waiting one.
- `CallError<GenericError>` carries a string, not a discriminated enum. A method that needs a richer reason declares its
  own interrupt type.
