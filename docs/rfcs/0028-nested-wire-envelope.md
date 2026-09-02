---
title: "Nested wire envelope: trait, method, version, and direction"
owner: "@decrypto21"
---

# RFC 0028: Nested Wire Envelope: Trait, Method, Version, and Direction

|                 |                                                                                                                  |
| --------------- | ---------------------------------------------------------------------------------------------------------------- |
| **RFC Number**  | 28                                                                                                                 |
| **Start Date**  | 2026-08-31                                                                                                         |
| **Description** | Replace the flat `(trait, method)` wire discriminant with a single nested address (trait, method, version, direction), so ids run as a dense per-trait sequence instead of a request/response or subscription-quartet spread. |
| **Authors**     | Nidish                                                                                                             |

## Summary

The `(trait, method)` pair that addresses every TrUAPI frame is the same shape as a Substrate extrinsic's `(pallet_index, call_index)`: one byte names the module, the other names the operation within it. Codec 2's envelope (`[requestId][trait: u8][method: u8][payload]`) still spends that per-trait operation budget on *direction*, not just the operation: a request/response method reserves two consecutive ids, a subscription reserves four. This RFC moves direction into the payload itself, one decode step past the `(trait, method)` routing pair, as a further SCALE Enum: the payload's own leading byte selects a method's `{Method}Version` variant, and that variant wraps a `Request<Req, Res>` enum (or, for subscriptions, a `Subscription<Start, Item, Err>` enum) whose own variant carries direction. The `(trait, method)` address stays exactly as flat as it is today (one `MethodIds` constant per method, unchanged as the dispatcher's routing key); only what a method's *payload* decodes into changes. Each method costs exactly one id, method ids run as a dense 0, 1, 2, ... sequence per trait, and a method's version history is the single place its shape (request/response today, subscription tomorrow) can change without touching its wire address.

## Motivation

Codec 2 already fixed the *global* fragmentation problem: every trait now owns a contiguous 256-value method-id block instead of competing for one flat byte. But within a trait, the id budget is still spent two-at-a-time or four-at-a-time on something that is not really part of the method's identity: which direction a given frame flows. `system_get_product_context` is method ids 8 and 9; a four-frame subscription like `account_connection_status_subscribe` is ids 0 through 3. That pattern means:

- **The 256-value ceiling arrives twice as fast for request/response methods, four times as fast for subscriptions.** A trait with 60 subscription methods exhausts its id space at 15 methods, not 60.
- **Version is addressable nowhere.** Today a method's version history lives entirely inside its payload type (`versioned::account::HostAccountGetRequest::V1(...)`); the wire address that routed the frame there already forgot which version answered it. Debug tooling and wire dumps see only the outer `(trait, method)` pair; the version that actually decided the payload shape is one `Decode` call deeper, invisible until it fully round-trips.
- **A method's shape is locked in by its ids, not its version.** If `foo_request` needs to become a subscription later, that is not a version bump; it's a new set of wire ids (a start/stop/interrupt/receive quartet) replacing the old request/response pair, i.e. a breaking removal plus a breaking addition. There is no way to express "this method grew a streaming variant" as an additive version change.
- **Public release is the last point this can move for free.** Once products in the field are decoding on any fixed shape of this envelope, every registered id becomes permanent; this restructuring is free today and a second breaking wire cutover after release.

This RFC folds those concerns into the same nested address, at the same moment codec 2's own cutover (`WIRE_CODEC_VERSION` 1 → 2) is already in flight and unreleased.

## Detailed Design

### Current shape (codec 2)

```text
[requestId: SCALE str][trait: u8][method: u8][payload bytes]
```

`method` is not one id per method: `n` for a request, `n+1` for its response, or `n..n+3` for a subscription's start/stop/interrupt/receive. Routing happens on those bytes alone; the payload's own version (and, for responses, an `Ok`/`Err`) tag is never visible at the routing layer.

### Proposed shape

```text
[requestId: SCALE str][trait: u8][method: u8][version: u8][direction: u8][inner payload bytes]
```

One method id now serves every version and direction a method has. Two hand-written generics, reused by every generated version enum, carry direction:

```rust
pub enum Request<Req, Res> {
    Request(Req),
    Response(Res),
}

pub enum Subscription<Start, Item, Err> {
    Start(Start),
    Stop,
    Interrupt(Option<Err>),
    Receive(Item),
}
```

`Err` is a type parameter, not a fixed type: most subscriptions share a `GenericError` fallback, a family that fails alike shares one domain error, and a method that needs its own gets one. `Interrupt(None)` is natural completion; `Interrupt(Some(err))` is a failure, replacing today's silent empty-frame convention with an explicit, decodable case.

The `(trait, method)` address itself never changes: a subscription's start, stop, interrupt, and receive frames all address the same `MethodIds` constant, distinguished only by the version and direction bytes inside the payload.

### Routing is unchanged

The dispatcher still keys on `(trait_id, method_id)`, one lookup. Only inbound-shaped frames (`Request::Request`, `Subscription::Start`/`Stop`) ever reach it; an outbound-shaped frame arriving inbound is a protocol violation, answered with `CallError::MalformedFrame`, exactly as an undecodable payload is today.

### Compatibility

This folds into codec 2: `WIRE_CODEC_VERSION` stays `2`, and `MIN_TRAIT_ID`/`MAX_CODEC_1_METHOD_ID` are untouched, since the codec-1/codec-2 boundary is entirely about the first (trait) byte. Codec 2 has not shipped yet, so this is a zero-cost renumbering: there is no codec-2 peer anywhere to break a second time. Folding it into the same unreleased cutover avoids a third wire-breaking version bump before public release.

## Drawbacks

- One more decode step and one more byte (the direction tag; the version tag already existed inside the payload, just one level deeper) on every frame.
- `Request<Req, Res>` and `Subscription<Start, Item, Err>` are new hand-maintained generics every generated version enum now wraps its payload in, rather than naming the payload type directly: a small, permanent indirection at every call site of the generated client.
- Deriving `Encode`/`Decode` on a generic enum requires both type parameters to implement the trait; every existing versioned payload type already does, so no new bound is introduced on source traits, but the generic itself must live in `truapi::versioned` rather than being codegen-local, since every generated module needs to name it.

## Testing, Security, and Privacy

Regenerating the golden and fixture tests listed above is the primary verification surface: byte-level goldens (`golden-account-get.bin`, the wire-table/dispatcher parity tests) must be recomputed, not relaxed, exactly as codec 2's own cutover recomputed them rather than loosening their assertions. No new security surface is introduced; `CallError::MalformedFrame` is the correct response to a `Response`/`Receive`/`Interrupt` tag arriving where a `Request`/`Start` tag is expected, rather than accepting it silently.

## Performance, Ergonomics, and Compatibility

### Performance

Routing remains a single `HashMap<(u8, u8), _>` lookup, unchanged in complexity. The added cost is exactly one extra single-byte `Decode` call per frame for the direction (and, where not already implicit, version) tag, negligible next to decoding the payload itself.

### Ergonomics

Method ids become a dense, gap-free per-trait sequence (0, 1, 2, ...) instead of today's 0, 2, 4, 6, 8 pattern, which is easier to read off a wire dump and easier to eyeball for accidental collisions in review. A method that starts as plain request/response and later needs a streaming variant expresses that as a new `{Method}Version` variant wrapping `Subscription<...>` instead of `Request<...>`, rather than as a set of wire ids replacing another set.

### Compatibility

Covered above: folds into codec 2, no additional version bump.

## Future Directions and Related Material

Once every trait's method ids are dense and gap-free under this scheme, a later RFC could reconsider whether trait ids need the same permanent `MIN_TRAIT_ID` reservation once no codec-1 peer remains in the field.
