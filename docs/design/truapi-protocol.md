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

The two bytes after the `requestId` are the **`(trait, method)` discriminant pair**. The first byte identifies the API trait (`System`, `Account`, `Chain`, ...); the second identifies the action within that trait. The payload bytes are the SCALE-encoded action value, inlined without a length prefix — the receiver reads to the end of the transport frame. Conceptually, `Payload` is a per-trait enum whose variants are the **actions** — the individual things a Host and Product can say to each other.

Actions are not written by hand. They are derived mechanically from the TrUAPI methods, so the high-level method signature and the wire format can never drift apart. One method expands into several actions depending on its shape: a plain call becomes a request/response pair, while a subscription becomes a small lifecycle of start, stop, interrupt, and receive messages.

Trait discriminants are assigned per trait in the `truapi` crate via the trait-level `#[wire_trait(id = N)]` annotation, with the `System` trait fixed at `192` — the lowest id the codec permits (see the appendix) — so a handshake request frame always starts `[requestId][0xC0][0x00]`. Each action carries an explicit method discriminant within its trait — its `request_id`, `response_id`, `start_id`, `stop_id`, `interrupt_id`, or `receive_id` — assigned per method via the `#[wire(...)]` annotation and numbered from `0` independently inside every trait. Ids are **append-only per trait and never reused**: once a `(trait, method)` pair ships it keeps its meaning forever, which is what lets a newer Host and an older Product still understand each other, and adding methods to one trait never disturbs the ids of any other trait. The crate is the source of truth for all values. Trait discriminant `255` is permanently reserved for protocol errors and cannot be assigned to an API trait, so no method can ever be addressed there; a protocol error travels on the pair `(255, 255)`.

Payloads are versioned independently of the discriminant pair, so a single message can evolve without renumbering anything around it. The current version `V1` encodes as discriminant `0`:

```rust
enum Versioned<T> {
  V1(T),
  // ...
}
```

Actions are derived from the TrUAPI methods using the following algorithm:

- For request functions, actions are derived as follows:
  - Request
    - Name: `method_name + '_request'`
    - Argument: `Versioned<(arg1, arg2, ...)>`
    - Discriminant: `request_id`
  - Response
    - Name: `method_name + '_response'`
    - Argument: `Versioned<Result<ReturnValue, ReturnError>>`
    - Discriminant: `response_id`
- For subscriptions, there are four messages:
  - Subscribe
    - Name: `method_name + '_start'`
    - Argument: tuple of all arguments except the callback `Versioned<(arg1, arg2, ...)>`
    - Discriminant: `start_id`
  - Unsubscribe
    - Name: `method_name + '_stop'`
    - Argument: none
    - Discriminant: `stop_id`
  - Interrupt
    - Name: `method_name + '_interrupt'`
    - Argument: none
    - Discriminant: `interrupt_id`
  - Receive
    - Name: `method_name + '_receive'`
    - Argument: the versioned callback argument `Versioned<CallbackArg>`
    - Discriminant: `receive_id`

Put together, a slice of one trait's `Payload` actions looks like this (the payload types are illustrative; see the `truapi` crate for the real ones):

```rust
enum Payload {
  host_handshake_request(Versioned::V1(HandshakeVersion)),
  host_handshake_response(Versioned::V1(Result<(), GenericErr>)),

  // ...
  // imaginary subscription method

  message_send_request(Versioned::V1((ChainId, str))),
  message_send_response(Versioned::V1(Result<(), GenericErr>)),

  message_subscribe_start(Versioned::V1(ChainId)),
  message_subscribe_stop,
  message_subscribe_interrupt,
  message_subscribe_receive(Versioned::V1(str)),

  // ...
}
```

### Rules

A single byte channel carries every call in both directions at once, so the two sides need a way to tell which message belongs to which exchange. That is what `requestId` is for.

#### Requests

Every request expects exactly one response. Each Host or Product MUST send a response message for every request it receives, and the request and its response MUST share the same `requestId` — so the caller can match a reply to the call it made even with many calls in flight.

If a receiver has no handler for an incoming `(trait, method)` pair, it MUST send a protocol-error frame addressed to `(255, 255)` with the same `requestId`. The codec-version-2 payload is `V1(UnsupportedMessage { trait_id, method_id })`, encoded as the four bytes `[0, 0, unsupported_trait, unsupported_method]` — one byte cannot name a pair, so the error that describes the envelope grew with it. The sender maps this method-independent response to its own pending request or subscription and reports a generic unsupported error. A receiver MUST NOT answer a protocol-error frame with another protocol error.

A protocol-error frame MUST NOT receive another protocol-error response. An unmatched error is ignored, while a malformed protocol-error payload is rejected as a wire violation. These rules prevent error loops without hiding malformed control messages.

Hosts and Products released before this control frame was introduced still silently drop unknown discriminants. They must be upgraded once before they can safely reject APIs introduced by later peers. Existing API frames and codec version 1 remain unchanged.

#### Subscription

A subscription is not a one-shot call but an ongoing stream: the consumer asks once and then receives updates until it stops listening. Its four messages — `start`, `stop`, `interrupt`, and `receive` — MUST all share the same `requestId`, so a subscription handler can route every update and teardown signal to the right place.

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

Trait id assignment. Ids start at 192 (`truapi::MIN_TRAIT_ID`): no codec-1
implementation allocated a flat discriminant above 171, so no codec-1 frame's
first byte can name a codec-2 trait, and such a frame is reported as unroutable instead of decoding
into whichever trait would otherwise share its old id. Codegen rejects any
`#[wire_trait(id = N)]` below the floor.

| Trait | Trait id |
| --- | --- |
| `System` | 192 |
| `Account` | 193 |
| `Chain` | 194 |
| `Chat` | 195 |
| `CoinPayment` | 196 |
| `Entropy` | 197 |
| `LocalStorage` | 198 |
| `Notifications` | 199 |
| `Payment` | 200 |
| `Permissions` | 201 |
| `Preimage` | 202 |
| `ResourceAllocation` | 203 |
| `Signing` | 204 |
| `StatementStore` | 205 |
| `Theme` | 206 |

Per-action mapping (codec-1 flat id → codec-2 `(trait, method)` pair):

| Action | Codec-1 id | Codec-2 (trait, method) |
| --- | --- | --- |
| `system_handshake_request` | 0 | (192, 0) |
| `system_handshake_response` | 1 | (192, 1) |
| `system_feature_supported_request` | 2 | (192, 2) |
| `system_feature_supported_response` | 3 | (192, 3) |
| `system_navigate_to_request` | 6 | (192, 4) |
| `system_navigate_to_response` | 7 | (192, 5) |
| `account_connection_status_subscribe_start` | 18 | (193, 0) |
| `account_connection_status_subscribe_stop` | 19 | (193, 1) |
| `account_connection_status_subscribe_interrupt` | 20 | (193, 2) |
| `account_connection_status_subscribe_receive` | 21 | (193, 3) |
| `account_get_account_request` | 22 | (193, 4) |
| `account_get_account_response` | 23 | (193, 5) |
| `account_get_account_alias_request` | 24 | (193, 6) |
| `account_get_account_alias_response` | 25 | (193, 7) |
| `account_create_account_proof_request` | 26 | (193, 8) |
| `account_create_account_proof_response` | 27 | (193, 9) |
| `account_get_legacy_accounts_request` | 28 | (193, 10) |
| `account_get_legacy_accounts_response` | 29 | (193, 11) |
| `account_get_user_id_request` | 110 | (193, 12) |
| `account_get_user_id_response` | 111 | (193, 13) |
| `account_request_login_request` | 112 | (193, 14) |
| `account_request_login_response` | 113 | (193, 15) |
| `account_sign_vrf_request` | 164 | (193, 16) |
| `account_sign_vrf_response` | 165 | (193, 17) |
| `chain_follow_head_subscribe_start` | 76 | (194, 0) |
| `chain_follow_head_subscribe_stop` | 77 | (194, 1) |
| `chain_follow_head_subscribe_interrupt` | 78 | (194, 2) |
| `chain_follow_head_subscribe_receive` | 79 | (194, 3) |
| `chain_get_head_header_request` | 80 | (194, 4) |
| `chain_get_head_header_response` | 81 | (194, 5) |
| `chain_get_head_body_request` | 82 | (194, 6) |
| `chain_get_head_body_response` | 83 | (194, 7) |
| `chain_get_head_storage_request` | 84 | (194, 8) |
| `chain_get_head_storage_response` | 85 | (194, 9) |
| `chain_call_head_request` | 86 | (194, 10) |
| `chain_call_head_response` | 87 | (194, 11) |
| `chain_unpin_head_request` | 88 | (194, 12) |
| `chain_unpin_head_response` | 89 | (194, 13) |
| `chain_continue_head_request` | 90 | (194, 14) |
| `chain_continue_head_response` | 91 | (194, 15) |
| `chain_stop_head_operation_request` | 92 | (194, 16) |
| `chain_stop_head_operation_response` | 93 | (194, 17) |
| `chain_get_spec_genesis_hash_request` | 94 | (194, 18) |
| `chain_get_spec_genesis_hash_response` | 95 | (194, 19) |
| `chain_get_spec_chain_name_request` | 96 | (194, 20) |
| `chain_get_spec_chain_name_response` | 97 | (194, 21) |
| `chain_get_spec_properties_request` | 98 | (194, 22) |
| `chain_get_spec_properties_response` | 99 | (194, 23) |
| `chain_broadcast_transaction_request` | 100 | (194, 24) |
| `chain_broadcast_transaction_response` | 101 | (194, 25) |
| `chain_stop_transaction_request` | 102 | (194, 26) |
| `chain_stop_transaction_response` | 103 | (194, 27) |
| `chat_create_room_request` | 38 | (195, 0) |
| `chat_create_room_response` | 39 | (195, 1) |
| `chat_register_bot_request` | 40 | (195, 2) |
| `chat_register_bot_response` | 41 | (195, 3) |
| `chat_list_subscribe_start` | 42 | (195, 4) |
| `chat_list_subscribe_stop` | 43 | (195, 5) |
| `chat_list_subscribe_interrupt` | 44 | (195, 6) |
| `chat_list_subscribe_receive` | 45 | (195, 7) |
| `chat_post_message_request` | 46 | (195, 8) |
| `chat_post_message_response` | 47 | (195, 9) |
| `chat_action_subscribe_start` | 48 | (195, 10) |
| `chat_action_subscribe_stop` | 49 | (195, 11) |
| `chat_action_subscribe_interrupt` | 50 | (195, 12) |
| `chat_action_subscribe_receive` | 51 | (195, 13) |
| `chat_custom_message_render_start` | 52 | (195, 14) |
| `chat_custom_message_render_stop` | 53 | (195, 15) |
| `chat_custom_message_render_interrupt` | 54 | (195, 16) |
| `chat_custom_message_render_receive` | 55 | (195, 17) |
| `coin_payment_create_purse_request` | 136 | (196, 0) |
| `coin_payment_create_purse_response` | 137 | (196, 1) |
| `coin_payment_query_purse_request` | 138 | (196, 2) |
| `coin_payment_query_purse_response` | 139 | (196, 3) |
| `coin_payment_rebalance_purse_start` | 140 | (196, 4) |
| `coin_payment_rebalance_purse_stop` | 141 | (196, 5) |
| `coin_payment_rebalance_purse_interrupt` | 142 | (196, 6) |
| `coin_payment_rebalance_purse_receive` | 143 | (196, 7) |
| `coin_payment_delete_purse_start` | 144 | (196, 8) |
| `coin_payment_delete_purse_stop` | 145 | (196, 9) |
| `coin_payment_delete_purse_interrupt` | 146 | (196, 10) |
| `coin_payment_delete_purse_receive` | 147 | (196, 11) |
| `coin_payment_create_receivable_request` | 148 | (196, 12) |
| `coin_payment_create_receivable_response` | 149 | (196, 13) |
| `coin_payment_create_cheque_request` | 150 | (196, 14) |
| `coin_payment_create_cheque_response` | 151 | (196, 15) |
| `coin_payment_deposit_start` | 152 | (196, 16) |
| `coin_payment_deposit_stop` | 153 | (196, 17) |
| `coin_payment_deposit_interrupt` | 154 | (196, 18) |
| `coin_payment_deposit_receive` | 155 | (196, 19) |
| `coin_payment_refund_start` | 156 | (196, 20) |
| `coin_payment_refund_stop` | 157 | (196, 21) |
| `coin_payment_refund_interrupt` | 158 | (196, 22) |
| `coin_payment_refund_receive` | 159 | (196, 23) |
| `coin_payment_listen_for_payment_start` | 160 | (196, 24) |
| `coin_payment_listen_for_payment_stop` | 161 | (196, 25) |
| `coin_payment_listen_for_payment_interrupt` | 162 | (196, 26) |
| `coin_payment_listen_for_payment_receive` | 163 | (196, 27) |
| `entropy_derive_request` | 108 | (197, 0) |
| `entropy_derive_response` | 109 | (197, 1) |
| `local_storage_read_request` | 12 | (198, 0) |
| `local_storage_read_response` | 13 | (198, 1) |
| `local_storage_write_request` | 14 | (198, 2) |
| `local_storage_write_response` | 15 | (198, 3) |
| `local_storage_clear_request` | 16 | (198, 4) |
| `local_storage_clear_response` | 17 | (198, 5) |
| `notifications_send_push_notification_request` | 4 | (199, 0) |
| `notifications_send_push_notification_response` | 5 | (199, 1) |
| `notifications_cancel_push_notification_request` | 134 | (199, 2) |
| `notifications_cancel_push_notification_response` | 135 | (199, 3) |
| `payment_balance_subscribe_start` | 118 | (200, 0) |
| `payment_balance_subscribe_stop` | 119 | (200, 1) |
| `payment_balance_subscribe_interrupt` | 120 | (200, 2) |
| `payment_balance_subscribe_receive` | 121 | (200, 3) |
| `payment_top_up_request` | 122 | (200, 4) |
| `payment_top_up_response` | 123 | (200, 5) |
| `payment_request_request` | 124 | (200, 6) |
| `payment_request_response` | 125 | (200, 7) |
| `payment_status_subscribe_start` | 126 | (200, 8) |
| `payment_status_subscribe_stop` | 127 | (200, 9) |
| `payment_status_subscribe_interrupt` | 128 | (200, 10) |
| `payment_status_subscribe_receive` | 129 | (200, 11) |
| `permissions_request_device_permission_request` | 8 | (201, 0) |
| `permissions_request_device_permission_response` | 9 | (201, 1) |
| `permissions_request_remote_permission_request` | 10 | (201, 2) |
| `permissions_request_remote_permission_response` | 11 | (201, 3) |
| `preimage_lookup_subscribe_start` | 64 | (202, 0) |
| `preimage_lookup_subscribe_stop` | 65 | (202, 1) |
| `preimage_lookup_subscribe_interrupt` | 66 | (202, 2) |
| `preimage_lookup_subscribe_receive` | 67 | (202, 3) |
| `preimage_submit_request` | 68 | (202, 4) |
| `preimage_submit_response` | 69 | (202, 5) |
| `resource_allocation_request_request` | 130 | (203, 0) |
| `resource_allocation_request_response` | 131 | (203, 1) |
| `signing_create_transaction_request` | 30 | (204, 0) |
| `signing_create_transaction_response` | 31 | (204, 1) |
| `signing_create_transaction_with_legacy_account_request` | 32 | (204, 2) |
| `signing_create_transaction_with_legacy_account_response` | 33 | (204, 3) |
| `signing_sign_raw_with_legacy_account_request` | 34 | (204, 4) |
| `signing_sign_raw_with_legacy_account_response` | 35 | (204, 5) |
| `signing_sign_payload_with_legacy_account_request` | 36 | (204, 6) |
| `signing_sign_payload_with_legacy_account_response` | 37 | (204, 7) |
| `signing_sign_raw_request` | 114 | (204, 8) |
| `signing_sign_raw_response` | 115 | (204, 9) |
| `signing_sign_payload_request` | 116 | (204, 10) |
| `signing_sign_payload_response` | 117 | (204, 11) |
| `statement_store_subscribe_start` | 56 | (205, 0) |
| `statement_store_subscribe_stop` | 57 | (205, 1) |
| `statement_store_subscribe_interrupt` | 58 | (205, 2) |
| `statement_store_subscribe_receive` | 59 | (205, 3) |
| `statement_store_create_proof_request` | 60 | (205, 4) |
| `statement_store_create_proof_response` | 61 | (205, 5) |
| `statement_store_submit_request` | 62 | (205, 6) |
| `statement_store_submit_response` | 63 | (205, 7) |
| `statement_store_create_proof_authorized_request` | 132 | (205, 8) |
| `statement_store_create_proof_authorized_response` | 133 | (205, 9) |
| `theme_subscribe_start` | 104 | (206, 0) |
| `theme_subscribe_stop` | 105 | (206, 1) |
| `theme_subscribe_interrupt` | 106 | (206, 2) |
| `theme_subscribe_receive` | 107 | (206, 3) |
