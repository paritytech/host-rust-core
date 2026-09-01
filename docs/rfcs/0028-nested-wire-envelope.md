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

The codec 2 envelope (`[requestId][trait: u8][method: u8][payload]`) still spends its per-trait method-id budget on *direction*: a request/response method reserves two consecutive ids, a subscription reserves four. This RFC moves direction into the payload itself, one decode step past the `(trait, method)` routing pair: version selects a method's own `{Method}Version` enum, and that version wraps a `Request<Req, Res>` (or, for subscriptions, a `Subscription<Start, Item, Err>`) value whose own variant tag carries direction. The `(trait, method)` address stays exactly as flat as it is today (one `MethodIds` constant per method, unchanged as the dispatcher's routing key); only what a method's *payload* decodes into changes. Each method costs exactly one id, method ids run as a dense 0, 1, 2, ... sequence per trait, and a method's version history is the single place its shape (request/response today, subscription tomorrow) can change without touching its wire address.

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

`method` is not one id per method: it is `n` for a request, `n+1` for its response; or `n..n+3` for a subscription's start/stop/interrupt/receive. `RequestFrameIds { trait_id, request_id, response_id }` and `SubscriptionFrameIds { trait_id, start_id, stop_id, interrupt_id, receive_id }` are the generated types that carry this today; the Rust dispatcher keys a `HashMap<(u8, u8), _>` on `(trait_id, request_id)` / `(trait_id, start_id)`, with `stop_id` tracked in a parallel `HashSet`. `payload bytes` already begins with a version tag and, for responses, an `Ok`/`Err` tag (`encode_versioned_ok_payload` / `encode_versioned_err_payload`), but that structure is invisible at the routing layer, because routing has already happened by the time those bytes are read.

### Proposed shape

```text
[requestId: SCALE str][trait: u8][method: u8][version: u8][direction: u8][inner payload bytes]
```

Two bytes replace what request/response or subscription ids used to encode, and one method id now serves every version and every direction a method ever has:

```rust
// truapi::versioned: hand-written once, reused by every generated version enum.

/// Direction tag for a request/response method: which half of the
/// exchange this frame carries.
pub enum Request<Req, Res> {
    Request(Req),
    Response(Res),
}

/// Direction tag for a subscription method: which half of the four-frame
/// exchange this frame carries. `Stop` carries no payload (cancellation
/// needs no data beyond "this subscription, now"), and `Interrupt` reuses
/// the method's own error type rather than a bespoke shape. `Interrupt(None)`
/// is natural stream completion; `Interrupt(Some(err))` is a failure. Today's
/// implementation sends an empty frame for the former (no representable value
/// otherwise), which this makes an explicit, decodable case instead.
pub enum Subscription<Start, Item, Err> {
    Start(Start),
    Stop,
    Interrupt(Option<Err>),
    Receive(Item),
}
```

`Err` is a type parameter, not a fixed type, so `Subscription<Start, Item, Err>` is one shape shared by every subscription regardless of how specific that method's own error is: a shared `GenericError` fallback for most subscriptions, a domain-shared error for a family of methods that all fail the same way (every `CoinPayment` subscription reuses `CoinPaymentError`), or a method-specific error for one that needs its own (each `Payment` subscription gets its own). None of the three needs a bespoke wrapper shape.

The address space stays flat (one `MethodIds { trait_id, method_id }` `pub const` per method, exactly as it is today) because the version/direction structure lives entirely inside the payload type; no per-trait method enum sits between the address and it:

```rust
// Generated (rust/wire_table.rs): one MethodIds const per method, built
// from the same #[wire_trait(id = N)] / #[wire(id = N)] annotations already
// on the source traits, just no longer split into request_id/response_id/etc.
pub const LOCALE_SUBSCRIBE: MethodIds = MethodIds { trait_id: 208, method_id: 0 };

// Hand-written (truapi/src/versioned/locale.rs): the {Method}Version type
// codegen names but does not itself emit; wraps the bare v01 item type
// directly, and the error slot is the CallError<D> wrapper, not a bare D.
pub enum HostLocaleSubscribeVersion {
    V1(Subscription<(), v01::HostLocaleSubscribeItem, CallError<crate::latest::GenericError>>),
}
```

A frame for `locale_subscribe`'s start half now reads: the `(trait_id, method_id)` pair addresses `LOCALE_SUBSCRIBE`, the version byte selects `V1`, the direction byte selects `Start`, and the remaining bytes are `()` (no start payload). The exact same leading bytes up through `method_id` route the matching `Stop`/`Interrupt`/`Receive` frames: the address never changes across a subscription's lifetime, only the version and direction tags inside the payload do.

### Routing is unchanged

The dispatcher's routing key is unchanged: `(trait_id, method_id)`, one `HashMap` lookup, because only inbound-shaped frames (`Request::Request(..)` or `Subscription::Start(..)` / `Subscription::Stop`) ever arrive at a host's dispatcher. A `Request::Response(..)` or `Subscription::Receive(..)`/`Interrupt(..)` arriving inbound is not a routing miss to fall back on; it is a protocol violation, answered with `CallError::MalformedFrame` exactly as an undecodable payload is today. What disappears is the *separate ids*: `response_id`, `start_id`/`stop_id`/`interrupt_id`/`receive_id` stop being fields on the generated `RequestFrameIds`/`SubscriptionFrameIds` structs, replaced by a single `MethodIds { trait_id, method_id }`, and `stop_ids: HashSet<(u8, u8)>` in `Dispatcher` disappears. A `Stop` frame arrives at the same `(trait_id, method_id)` as `Start`, but `dispatch()` peeks the direction tag itself before invoking anything and routes `Stop` straight to `SubscriptionManager::handle_stop`; only `Start` ever reaches the registered handler.

### Local surfaces this touches

- **`truapi-macros`**: `#[wire(request_id = N, response_id = N, ...)]` collapses to `#[wire(id = N)]`: one id argument, no `response_id`/`start_id`/`stop_id`/`interrupt_id`/`receive_id` variants left to parse. `#[wire_trait(id = N)]` is unchanged: trait ids keep their own explicit numbering and the `MIN_TRAIT_ID` / `MAX_CODEC_1_METHOD_ID` codec-1 floor guarantee is untouched, since that guarantee is about the *first* byte only.
- **`truapi-codegen/src/rustdoc.rs`**: extracts one `@wire_id=N` doc tag per method instead of up to four (`@wire_request_id`, `@wire_response_id`, `@wire_start_id`, ...).
- **`truapi-codegen/src/rust/wire_table.rs`**: emits a flat `MethodIds { trait_id, method_id }` `pub const` per method, replacing `RequestFrameIds`/`SubscriptionFrameIds`; no per-trait method enum sits between the address and the `{Method}Version` type declarations, which live alongside it.
- **`truapi-codegen/src/rust/dispatcher.rs`**: generated `register_*` functions keep registering `on_request`/`on_subscription` against the single `MethodIds` constant; the generated handler body gains one `match` arm to read the `Request`/`Subscription` tag before reaching the caller's trait method.
- **`truapi-codegen/src/ts.rs`**: mirrors all of the above into the generated TS wire table and client stub.
- **`truapi-server/src/frame.rs`**: `ProtocolMessage`'s hand-rolled `Decode` is unchanged in what it reads for routing (`trait_id`, `method_id`, both flat `u8`s); `encode_versioned_ok_payload`/`encode_versioned_err_payload` and friends go unused by every real method, which instead call `.encode()` directly on the derived `{Method}Version` enum to write `[version][direction][payload]` instead of `[version][Ok/Err][payload]`. The old functions stay in the tree only for `truapi-codegen`'s own synthetic-fixture legacy fallback and its unit tests.
- **`truapi-server/src/dispatcher.rs`**: loses `stop_ids: HashSet<(u8, u8)>`; `dispatch()` peeks the direction tag itself and routes `Stop` straight to `SubscriptionManager::handle_stop`, one decode step above the registered handler; only `Start` ever reaches it.
- **`truapi-server/src/subscription.rs`**: `Interrupt`/`Receive` frames sent to a product carry the `Subscription` direction tag instead of a distinct wire id.
- **`js/packages/truapi/src/client.ts`**: the hand-symmetric client-side router (`createTransport`'s `provider.subscribe` callback, matching on `traitId`/`methodId`) mirrors the Rust dispatcher's change exactly: same `(traitId, methodId)` map, one more decode step for the direction tag.
- **Golden and fixture tests** all need regeneration under the new shape: `truapi-codegen`'s own golden `wire_table.rs`/`dispatcher.rs`, `truapi-server`'s `golden-account-get.bin`, `wire_table_ts_parity.rs`, `wire_result_shape.rs`, `golden_frame.rs`.

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
