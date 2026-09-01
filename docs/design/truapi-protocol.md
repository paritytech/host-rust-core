---
title: "TrUAPI Protocol Design"
type: design
status: accepted
created: 2026-03-13
---

# TrUAPI Protocol Design

## Overview

The TrUAPI protocol connects a **Product** — a web application — with its **Host**, the native Polkadot application that embeds it. The two run in separate execution contexts (an iframe or webview inside a native shell) and share no memory; everything they exchange has to cross a process boundary as raw bytes.

This document specifies the **transport layer**: the rules for turning a method call on one side into bytes on the wire and back into a typed result on the other. It deliberately stops there. The concrete call surface — the methods themselves, their request/response types, error enums, and the wire-protocol discriminant ids — is defined in the `truapi` crate (`rust/crates/truapi`) and the clients generated from it. Keeping the two apart lets the API surface grow without disturbing the transport rules underneath it.

TrUAPI is language-agnostic. The protocol assumes nothing Rust-specific; any language that can serialize the same byte layout can speak it.

## Technical Requirements

A Host and a Product may be built on different platforms — web, iOS, Android — and in different languages. The transport therefore makes no assumptions about either side beyond a shared byte channel:

- The protocol MUST provide a transport layer between Host and Product over an arbitrary byte channel.
- The message format MUST be well-defined and serializable, so that an encoder on one platform and a decoder on another agree byte-for-byte.

## Transport

Communication between Host and Product can be carried over any IPC mechanism — a `MessagePort`, `postMessage` across an iframe boundary, or anything else that moves bytes. The transport treats that channel as opaque: the body of each IPC message is a single serialized `Message` (a byte array), and how those bytes actually travel is left to the environment.

Because the channel carries nothing but bytes, both sides must agree precisely on how a `Message` is laid out. That agreement is the serialization format.

### Serialization

Messages are plain structs and enums that are serialized into bytes on one side and decoded back into the same shape on the other.

Message serialization is built on [SCALE codec](https://github.com/paritytech/parity-scale-codec). The codec is positional — it writes no field names or tags, only values in declaration order — so **the field order of structs and the variant order of enums are part of the wire contract**; reordering them silently breaks compatibility. The examples in this document omit the codec derive calls, but they are always implied. `Result` is treated as an ordinary serializable enum.

#### Note on `Compact`

SCALE encodes integers in fixed width by default. The `Compact` type provides a variable-length encoding that keeps small numbers small on the wire — a single byte for the common small values.

### Interface

Every message on the wire shares one envelope:

```rust
struct Message {
  requestId: str,
  payload: Payload
}
```

`requestId` ties related messages together (see [Rules](#rules)); `payload` carries the action itself. On the wire the envelope is laid out as:

```text
[requestId: SCALE str][trait: u8][method: u8][payload bytes...]
```

The two bytes after the `requestId` are the **`(trait, method)` discriminant pair**. The first byte identifies the API trait (`System`, `Account`, `Chain`, ...); the second identifies a method within it: exactly one id per method, regardless of that method's shape. The payload bytes are the SCALE-encoded value for that method's own nested envelope (below), inlined without a length prefix; the receiver reads to the end of the transport frame.

Trait discriminants are assigned per trait in the `truapi` crate via the trait-level `#[wire_trait(id = N)]` annotation, with the `System` trait fixed at `193` (the lowest id the codec permits, see the appendix), so a handshake request frame always starts `[requestId][0xC1][0x00]`. Each method carries an explicit discriminant within its trait, assigned via the `#[wire(id = N)]` annotation and numbered from `0` independently inside every trait. Ids are **append-only per trait and never reused**: once a `(trait, method)` pair ships it keeps its meaning forever, which is what lets a newer Host and an older Product still understand each other, and adding methods to one trait never disturbs the ids of any other trait. The crate is the source of truth for all values. Trait discriminant `255` is permanently reserved for protocol errors and cannot be assigned to an API trait, so no method can ever be addressed there; a protocol error travels on the pair `(255, 255)`.

#### The nested envelope

A `(trait, method)` pair names a method, not a direction: request and response share it, and so do a subscription's four phases. Direction, and the payload version, both live inside the payload bytes as a small nested envelope instead:

```rust
enum Versioned<Shape> {
  V1(Shape),
  // ...
}

enum Request<Req, Res> {
  Request(Req),
  Response(Res),
}

enum Subscription<Start, Item, Err> {
  Start(Start),
  Stop,
  Interrupt(Option<Err>), // None = clean completion, Some(err) = failure
  Receive(Item),
}
```

`Shape` is `Request<Req, Result<Ok, Err>>` for a plain call, or `Subscription<Start, Item, Err>` for a subscription, whichever the method's own return type calls for. The version tag therefore selects a method's *shape*: today every method has exactly one version and one shape, but a later version of the same method could switch a call to a subscription (or vice versa) without needing a new `(trait, method)` pair. On the wire, `Versioned<Shape>`'s tag and `Request`/`Subscription`'s own direction tag are two consecutive SCALE enum discriminant bytes: `[version][direction][...direction's own payload]`.

For example, a `system_feature_supported` request/response pair (trait `193`, method `1`) is carried entirely by the payload bytes at that one address:

```text
outbound: [0xC1][0x01][0x00 V1][0x00 Request][...request fields]
inbound:  [0xC1][0x01][0x00 V1][0x01 Response][0x00 Ok][...response fields]
```

and a subscription's four phases (start, stop, interrupt, receive) all address the same `(trait, method)` pair, distinguished only by which `Subscription` variant tag follows the version byte:

```text
start:     [trait][method][0x00 V1][0x00 Start][...start fields]
stop:      [trait][method][0x00 V1][0x01 Stop]
interrupt: [trait][method][0x00 V1][0x02 Interrupt][...Option<Err>]
receive:   [trait][method][0x00 V1][0x03 Receive][...item fields]
```

Request/response and subscription methods are both derived mechanically from the TrUAPI trait methods, so the high-level method signature and the wire format can never drift apart; nothing is written by hand.

### Rules

A single byte channel carries every call in both directions at once, so the two sides need a way to tell which message belongs to which exchange. That is what `requestId` is for.

#### Requests

Every request expects exactly one response. Each Host or Product MUST send a response message for every request it receives, and the request and its response MUST share the same `requestId` — so the caller can match a reply to the call it made even with many calls in flight.

If a receiver has no handler for an incoming `(trait, method)` pair, it MUST send a protocol-error frame addressed to `(255, 255)` with the same `requestId`. The codec-version-2 payload is `V1(UnsupportedMessage { trait_id, method_id })`, encoded as the four bytes `[0, 0, unsupported_trait, unsupported_method]` — one byte cannot name a pair, so the error that describes the envelope grew with it. The sender maps this method-independent response to its own pending request or subscription and reports a generic unsupported error. A receiver MUST NOT answer a protocol-error frame with another protocol error.

A protocol-error frame MUST NOT receive another protocol-error response. An unmatched error is ignored, while a malformed protocol-error payload is rejected as a wire violation. These rules prevent error loops without hiding malformed control messages.

Hosts and Products released before this control frame was introduced still silently drop unknown discriminants. They must be upgraded once before they can safely reject APIs introduced by later peers. Existing API frames and codec version 1 remain unchanged.

#### Subscription

A subscription is not a one-shot call but an ongoing stream: the consumer asks once and then receives updates until it stops listening. Its four messages (`start`, `stop`, `interrupt`, and `receive`) all address the same `(trait, method)` pair (distinguished by the `Subscription` direction tag inside the payload) and MUST all share the same `requestId`, so a subscription handler can route every update and teardown signal to the right place.

Each message has a defined role:

- `start` — the consumer subscribes; it MUST send a `start` message to the provider.
- `stop` — the consumer unsubscribes; it MUST send a `stop` message.
- `interrupt` — if the provider can no longer supply data, it CAN send an `interrupt` message; the consumer MAY react by notifying the application layer.
- `receive` — the provider MUST deliver each update with a `receive` message.

When a protocol error rejects a subscription's `start` frame, the consumer
MUST terminate that subscription with a generic unsupported error and MUST NOT
send a `stop` frame in response.

The returned `Subscriber` interface depends on the implementation, but a generic one may look like this:

```rust
struct Subscriber {
  unsubscribe: fn(),
  onInterrupt: fn(fn())
}
```

### Handshake

Before either side trusts a single byte of payload, they have to agree on how those bytes are encoded. That negotiation is the handshake, and it runs first.

Handshake calls are bidirectional: both Host and Product can send a handshake request, and both MUST respond to one. An implementation CAN apply a timeout of 10 seconds, after which the connection is marked failed and the call returns a timeout error. The handshake result can be cached.

The handshake request carries the protocol (codec) version as a `u8`. On receiving it, the peer switches its encoding/decoding mode to match; for the SCALE codec with the two-byte `(trait, method)` envelope, the version is `2`. (Codec version `1` designates the retired single-byte-discriminant envelope; a peer speaking it fails the handshake.) A successful handshake MUST be the first request TrUAPI processes — any other request sent before a successful handshake response MUST fail.

The concrete handshake request, response, and error types are defined in the `truapi` crate.


## Appendix: codec-1 → codec-2 discriminant mapping

Codec version 1 used a single flat `u8` discriminant shared across all traits. Codec version 2 replaces it with the `(trait, method)` pair. This table is the one-time mapping between the two numberings; it exists only to interpret captured codec-1 traffic and old fixtures, and is never extended — new methods only ever get codec-2 pairs.

Codec 1 spent a separate discriminant per action (request and response, or each of a subscription's four phases), where codec 2 spends one `(trait, method)` pair per *method* and folds direction into the payload (see [above](#the-nested-envelope)). The table below therefore still lists one row per historical codec-1 action, but every action belonging to the same method now maps to the same codec-2 pair.

Trait id assignment. Ids start at 193 (`truapi::MIN_TRAIT_ID`), one past
`truapi::MAX_CODEC_1_METHOD_ID`: `triangle-js-sdks` `host-api` allocated
166..=171 to the RFC-0024 ring VRF methods, and this crate's own flat numbering
later reached 192 via `System::host_info`, added on `main` while codec 2 was
still unmerged. 192 is therefore the highest known codec-1 discriminant across
both, so no codec-1 frame's first byte can name a codec-2 trait, and such a
frame is reported as unroutable instead of decoding into whichever trait would
otherwise share its old id. Codegen rejects any `#[wire_trait(id = N)]` below
the floor.

| Trait | Trait id |
| --- | --- |
| `System` | 193 |
| `Account` | 194 |
| `Chain` | 195 |
| `Chat` | 196 |
| `CoinPayment` | 197 |
| `Entropy` | 198 |
| `LocalStorage` | 199 |
| `Notifications` | 200 |
| `Payment` | 201 |
| `Permissions` | 202 |
| `Preimage` | 203 |
| `ResourceAllocation` | 204 |
| `Signing` | 205 |
| `StatementStore` | 206 |
| `Theme` | 207 |

Per-action mapping (codec-1 flat id → codec-2 `(trait, method)` pair):

| Action | Codec-1 id | Codec-2 (trait, method) |
| --- | --- | --- |
| `system_handshake_request` | 0 | (193, 0) |
| `system_handshake_response` | 1 | (193, 0) |
| `system_feature_supported_request` | 2 | (193, 1) |
| `system_feature_supported_response` | 3 | (193, 1) |
| `system_navigate_to_request` | 6 | (193, 2) |
| `system_navigate_to_response` | 7 | (193, 2) |
| `account_connection_status_subscribe_start` | 18 | (194, 0) |
| `account_connection_status_subscribe_stop` | 19 | (194, 0) |
| `account_connection_status_subscribe_interrupt` | 20 | (194, 0) |
| `account_connection_status_subscribe_receive` | 21 | (194, 0) |
| `account_get_account_request` | 22 | (194, 1) |
| `account_get_account_response` | 23 | (194, 1) |
| `account_get_account_alias_request` | 24 | (194, 2) |
| `account_get_account_alias_response` | 25 | (194, 2) |
| `account_create_account_proof_request` | 26 | (194, 3) |
| `account_create_account_proof_response` | 27 | (194, 3) |
| `account_get_legacy_accounts_request` | 28 | (194, 4) |
| `account_get_legacy_accounts_response` | 29 | (194, 4) |
| `account_get_user_id_request` | 110 | (194, 5) |
| `account_get_user_id_response` | 111 | (194, 5) |
| `account_request_login_request` | 112 | (194, 6) |
| `account_request_login_response` | 113 | (194, 6) |
| `account_sign_vrf_request` | 164 | (194, 7) |
| `account_sign_vrf_response` | 165 | (194, 7) |
| `chain_follow_head_subscribe_start` | 76 | (195, 0) |
| `chain_follow_head_subscribe_stop` | 77 | (195, 0) |
| `chain_follow_head_subscribe_interrupt` | 78 | (195, 0) |
| `chain_follow_head_subscribe_receive` | 79 | (195, 0) |
| `chain_get_head_header_request` | 80 | (195, 1) |
| `chain_get_head_header_response` | 81 | (195, 1) |
| `chain_get_head_body_request` | 82 | (195, 2) |
| `chain_get_head_body_response` | 83 | (195, 2) |
| `chain_get_head_storage_request` | 84 | (195, 3) |
| `chain_get_head_storage_response` | 85 | (195, 3) |
| `chain_call_head_request` | 86 | (195, 4) |
| `chain_call_head_response` | 87 | (195, 4) |
| `chain_unpin_head_request` | 88 | (195, 5) |
| `chain_unpin_head_response` | 89 | (195, 5) |
| `chain_continue_head_request` | 90 | (195, 6) |
| `chain_continue_head_response` | 91 | (195, 6) |
| `chain_stop_head_operation_request` | 92 | (195, 7) |
| `chain_stop_head_operation_response` | 93 | (195, 7) |
| `chain_get_spec_genesis_hash_request` | 94 | (195, 8) |
| `chain_get_spec_genesis_hash_response` | 95 | (195, 8) |
| `chain_get_spec_chain_name_request` | 96 | (195, 9) |
| `chain_get_spec_chain_name_response` | 97 | (195, 9) |
| `chain_get_spec_properties_request` | 98 | (195, 10) |
| `chain_get_spec_properties_response` | 99 | (195, 10) |
| `chain_broadcast_transaction_request` | 100 | (195, 11) |
| `chain_broadcast_transaction_response` | 101 | (195, 11) |
| `chain_stop_transaction_request` | 102 | (195, 12) |
| `chain_stop_transaction_response` | 103 | (195, 12) |
| `chat_create_room_request` | 38 | (196, 0) |
| `chat_create_room_response` | 39 | (196, 0) |
| `chat_register_bot_request` | 40 | (196, 1) |
| `chat_register_bot_response` | 41 | (196, 1) |
| `chat_list_subscribe_start` | 42 | (196, 2) |
| `chat_list_subscribe_stop` | 43 | (196, 2) |
| `chat_list_subscribe_interrupt` | 44 | (196, 2) |
| `chat_list_subscribe_receive` | 45 | (196, 2) |
| `chat_post_message_request` | 46 | (196, 3) |
| `chat_post_message_response` | 47 | (196, 3) |
| `chat_action_subscribe_start` | 48 | (196, 4) |
| `chat_action_subscribe_stop` | 49 | (196, 4) |
| `chat_action_subscribe_interrupt` | 50 | (196, 4) |
| `chat_action_subscribe_receive` | 51 | (196, 4) |
| `chat_custom_message_render_start` | 52 | (196, 5) |
| `chat_custom_message_render_stop` | 53 | (196, 5) |
| `chat_custom_message_render_interrupt` | 54 | (196, 5) |
| `chat_custom_message_render_receive` | 55 | (196, 5) |
| `coin_payment_create_purse_request` | 136 | (197, 0) |
| `coin_payment_create_purse_response` | 137 | (197, 0) |
| `coin_payment_query_purse_request` | 138 | (197, 1) |
| `coin_payment_query_purse_response` | 139 | (197, 1) |
| `coin_payment_rebalance_purse_start` | 140 | (197, 2) |
| `coin_payment_rebalance_purse_stop` | 141 | (197, 2) |
| `coin_payment_rebalance_purse_interrupt` | 142 | (197, 2) |
| `coin_payment_rebalance_purse_receive` | 143 | (197, 2) |
| `coin_payment_delete_purse_start` | 144 | (197, 3) |
| `coin_payment_delete_purse_stop` | 145 | (197, 3) |
| `coin_payment_delete_purse_interrupt` | 146 | (197, 3) |
| `coin_payment_delete_purse_receive` | 147 | (197, 3) |
| `coin_payment_create_receivable_request` | 148 | (197, 4) |
| `coin_payment_create_receivable_response` | 149 | (197, 4) |
| `coin_payment_create_cheque_request` | 150 | (197, 5) |
| `coin_payment_create_cheque_response` | 151 | (197, 5) |
| `coin_payment_deposit_start` | 152 | (197, 6) |
| `coin_payment_deposit_stop` | 153 | (197, 6) |
| `coin_payment_deposit_interrupt` | 154 | (197, 6) |
| `coin_payment_deposit_receive` | 155 | (197, 6) |
| `coin_payment_refund_start` | 156 | (197, 7) |
| `coin_payment_refund_stop` | 157 | (197, 7) |
| `coin_payment_refund_interrupt` | 158 | (197, 7) |
| `coin_payment_refund_receive` | 159 | (197, 7) |
| `coin_payment_listen_for_payment_start` | 160 | (197, 8) |
| `coin_payment_listen_for_payment_stop` | 161 | (197, 8) |
| `coin_payment_listen_for_payment_interrupt` | 162 | (197, 8) |
| `coin_payment_listen_for_payment_receive` | 163 | (197, 8) |
| `entropy_derive_request` | 108 | (198, 0) |
| `entropy_derive_response` | 109 | (198, 0) |
| `local_storage_read_request` | 12 | (199, 0) |
| `local_storage_read_response` | 13 | (199, 0) |
| `local_storage_write_request` | 14 | (199, 1) |
| `local_storage_write_response` | 15 | (199, 1) |
| `local_storage_clear_request` | 16 | (199, 2) |
| `local_storage_clear_response` | 17 | (199, 2) |
| `notifications_send_push_notification_request` | 4 | (200, 0) |
| `notifications_send_push_notification_response` | 5 | (200, 0) |
| `notifications_cancel_push_notification_request` | 134 | (200, 1) |
| `notifications_cancel_push_notification_response` | 135 | (200, 1) |
| `payment_balance_subscribe_start` | 118 | (201, 0) |
| `payment_balance_subscribe_stop` | 119 | (201, 0) |
| `payment_balance_subscribe_interrupt` | 120 | (201, 0) |
| `payment_balance_subscribe_receive` | 121 | (201, 0) |
| `payment_top_up_request` | 122 | (201, 1) |
| `payment_top_up_response` | 123 | (201, 1) |
| `payment_request_request` | 124 | (201, 2) |
| `payment_request_response` | 125 | (201, 2) |
| `payment_status_subscribe_start` | 126 | (201, 3) |
| `payment_status_subscribe_stop` | 127 | (201, 3) |
| `payment_status_subscribe_interrupt` | 128 | (201, 3) |
| `payment_status_subscribe_receive` | 129 | (201, 3) |
| `permissions_request_device_permission_request` | 8 | (202, 0) |
| `permissions_request_device_permission_response` | 9 | (202, 0) |
| `permissions_request_remote_permission_request` | 10 | (202, 1) |
| `permissions_request_remote_permission_response` | 11 | (202, 1) |
| `preimage_lookup_subscribe_start` | 64 | (203, 0) |
| `preimage_lookup_subscribe_stop` | 65 | (203, 0) |
| `preimage_lookup_subscribe_interrupt` | 66 | (203, 0) |
| `preimage_lookup_subscribe_receive` | 67 | (203, 0) |
| `preimage_submit_request` | 68 | (203, 1) |
| `preimage_submit_response` | 69 | (203, 1) |
| `resource_allocation_request_request` | 130 | (204, 0) |
| `resource_allocation_request_response` | 131 | (204, 0) |
| `signing_create_transaction_request` | 30 | (205, 0) |
| `signing_create_transaction_response` | 31 | (205, 0) |
| `signing_create_transaction_with_legacy_account_request` | 32 | (205, 1) |
| `signing_create_transaction_with_legacy_account_response` | 33 | (205, 1) |
| `signing_sign_raw_with_legacy_account_request` | 34 | (205, 2) |
| `signing_sign_raw_with_legacy_account_response` | 35 | (205, 2) |
| `signing_sign_payload_with_legacy_account_request` | 36 | (205, 3) |
| `signing_sign_payload_with_legacy_account_response` | 37 | (205, 3) |
| `signing_sign_raw_request` | 114 | (205, 4) |
| `signing_sign_raw_response` | 115 | (205, 4) |
| `signing_sign_payload_request` | 116 | (205, 5) |
| `signing_sign_payload_response` | 117 | (205, 5) |
| `statement_store_subscribe_start` | 56 | (206, 0) |
| `statement_store_subscribe_stop` | 57 | (206, 0) |
| `statement_store_subscribe_interrupt` | 58 | (206, 0) |
| `statement_store_subscribe_receive` | 59 | (206, 0) |
| `statement_store_create_proof_request` | 60 | (206, 1) |
| `statement_store_create_proof_response` | 61 | (206, 1) |
| `statement_store_submit_request` | 62 | (206, 2) |
| `statement_store_submit_response` | 63 | (206, 2) |
| `statement_store_create_proof_authorized_request` | 132 | (206, 3) |
| `statement_store_create_proof_authorized_response` | 133 | (206, 3) |
| `theme_subscribe_start` | 104 | (207, 0) |
| `theme_subscribe_stop` | 105 | (207, 0) |
| `theme_subscribe_interrupt` | 106 | (207, 0) |
| `theme_subscribe_receive` | 107 | (207, 0) |
