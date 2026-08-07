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

Trait discriminants are assigned per trait in the `truapi` crate via the trait-level `#[wire_trait(id = N)]` annotation, with the `System` trait fixed at `0` (so a handshake request frame always starts `[requestId][0x00][0x00]`). Each action carries an explicit method discriminant within its trait — its `request_id`, `response_id`, `start_id`, `stop_id`, `interrupt_id`, or `receive_id` — assigned per method via the `#[wire(...)]` annotation and numbered from `0` independently inside every trait. Ids are **append-only per trait and never reused**: once a `(trait, method)` pair ships it keeps its meaning forever, which is what lets a newer Host and an older Product still understand each other, and adding methods to one trait never disturbs the ids of any other trait. The crate is the source of truth for all values.

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

#### Subscription

A subscription is not a one-shot call but an ongoing stream: the consumer asks once and then receives updates until it stops listening. Its four messages — `start`, `stop`, `interrupt`, and `receive` — MUST all share the same `requestId`, so a subscription handler can route every update and teardown signal to the right place.

Each message has a defined role:

- `start` — the consumer subscribes; it MUST send a `start` message to the provider.
- `stop` — the consumer unsubscribes; it MUST send a `stop` message.
- `interrupt` — if the provider can no longer supply data, it CAN send an `interrupt` message; the consumer MAY react by notifying the application layer.
- `receive` — the provider MUST deliver each update with a `receive` message.

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

Trait id assignment:

| Trait | Trait id |
| --- | --- |
| `System` | 0 |
| `Account` | 1 |
| `Chain` | 2 |
| `Chat` | 3 |
| `CoinPayment` | 4 |
| `Entropy` | 5 |
| `LocalStorage` | 6 |
| `Notifications` | 7 |
| `Payment` | 8 |
| `Permissions` | 9 |
| `Preimage` | 10 |
| `ResourceAllocation` | 11 |
| `Signing` | 12 |
| `StatementStore` | 13 |
| `Theme` | 14 |

Per-action mapping (codec-1 flat id → codec-2 `(trait, method)` pair):

| Action | Codec-1 id | Codec-2 (trait, method) |
| --- | --- | --- |
| `system_handshake_request` | 0 | (0, 0) |
| `system_handshake_response` | 1 | (0, 1) |
| `system_feature_supported_request` | 2 | (0, 2) |
| `system_feature_supported_response` | 3 | (0, 3) |
| `system_navigate_to_request` | 6 | (0, 4) |
| `system_navigate_to_response` | 7 | (0, 5) |
| `account_connection_status_subscribe_start` | 18 | (1, 0) |
| `account_connection_status_subscribe_stop` | 19 | (1, 1) |
| `account_connection_status_subscribe_interrupt` | 20 | (1, 2) |
| `account_connection_status_subscribe_receive` | 21 | (1, 3) |
| `account_get_account_request` | 22 | (1, 4) |
| `account_get_account_response` | 23 | (1, 5) |
| `account_get_account_alias_request` | 24 | (1, 6) |
| `account_get_account_alias_response` | 25 | (1, 7) |
| `account_create_account_proof_request` | 26 | (1, 8) |
| `account_create_account_proof_response` | 27 | (1, 9) |
| `account_get_legacy_accounts_request` | 28 | (1, 10) |
| `account_get_legacy_accounts_response` | 29 | (1, 11) |
| `account_get_user_id_request` | 110 | (1, 12) |
| `account_get_user_id_response` | 111 | (1, 13) |
| `account_request_login_request` | 112 | (1, 14) |
| `account_request_login_response` | 113 | (1, 15) |
| `account_sign_vrf_request` | 164 | (1, 16) |
| `account_sign_vrf_response` | 165 | (1, 17) |
| `chain_follow_head_subscribe_start` | 76 | (2, 0) |
| `chain_follow_head_subscribe_stop` | 77 | (2, 1) |
| `chain_follow_head_subscribe_interrupt` | 78 | (2, 2) |
| `chain_follow_head_subscribe_receive` | 79 | (2, 3) |
| `chain_get_head_header_request` | 80 | (2, 4) |
| `chain_get_head_header_response` | 81 | (2, 5) |
| `chain_get_head_body_request` | 82 | (2, 6) |
| `chain_get_head_body_response` | 83 | (2, 7) |
| `chain_get_head_storage_request` | 84 | (2, 8) |
| `chain_get_head_storage_response` | 85 | (2, 9) |
| `chain_call_head_request` | 86 | (2, 10) |
| `chain_call_head_response` | 87 | (2, 11) |
| `chain_unpin_head_request` | 88 | (2, 12) |
| `chain_unpin_head_response` | 89 | (2, 13) |
| `chain_continue_head_request` | 90 | (2, 14) |
| `chain_continue_head_response` | 91 | (2, 15) |
| `chain_stop_head_operation_request` | 92 | (2, 16) |
| `chain_stop_head_operation_response` | 93 | (2, 17) |
| `chain_get_spec_genesis_hash_request` | 94 | (2, 18) |
| `chain_get_spec_genesis_hash_response` | 95 | (2, 19) |
| `chain_get_spec_chain_name_request` | 96 | (2, 20) |
| `chain_get_spec_chain_name_response` | 97 | (2, 21) |
| `chain_get_spec_properties_request` | 98 | (2, 22) |
| `chain_get_spec_properties_response` | 99 | (2, 23) |
| `chain_broadcast_transaction_request` | 100 | (2, 24) |
| `chain_broadcast_transaction_response` | 101 | (2, 25) |
| `chain_stop_transaction_request` | 102 | (2, 26) |
| `chain_stop_transaction_response` | 103 | (2, 27) |
| `chat_create_room_request` | 38 | (3, 0) |
| `chat_create_room_response` | 39 | (3, 1) |
| `chat_register_bot_request` | 40 | (3, 2) |
| `chat_register_bot_response` | 41 | (3, 3) |
| `chat_list_subscribe_start` | 42 | (3, 4) |
| `chat_list_subscribe_stop` | 43 | (3, 5) |
| `chat_list_subscribe_interrupt` | 44 | (3, 6) |
| `chat_list_subscribe_receive` | 45 | (3, 7) |
| `chat_post_message_request` | 46 | (3, 8) |
| `chat_post_message_response` | 47 | (3, 9) |
| `chat_action_subscribe_start` | 48 | (3, 10) |
| `chat_action_subscribe_stop` | 49 | (3, 11) |
| `chat_action_subscribe_interrupt` | 50 | (3, 12) |
| `chat_action_subscribe_receive` | 51 | (3, 13) |
| `chat_custom_message_render_subscribe_start` | 52 | (3, 14) |
| `chat_custom_message_render_subscribe_stop` | 53 | (3, 15) |
| `chat_custom_message_render_subscribe_interrupt` | 54 | (3, 16) |
| `chat_custom_message_render_subscribe_receive` | 55 | (3, 17) |
| `coin_payment_create_purse_request` | 136 | (4, 0) |
| `coin_payment_create_purse_response` | 137 | (4, 1) |
| `coin_payment_query_purse_request` | 138 | (4, 2) |
| `coin_payment_query_purse_response` | 139 | (4, 3) |
| `coin_payment_rebalance_purse_start` | 140 | (4, 4) |
| `coin_payment_rebalance_purse_stop` | 141 | (4, 5) |
| `coin_payment_rebalance_purse_interrupt` | 142 | (4, 6) |
| `coin_payment_rebalance_purse_receive` | 143 | (4, 7) |
| `coin_payment_delete_purse_start` | 144 | (4, 8) |
| `coin_payment_delete_purse_stop` | 145 | (4, 9) |
| `coin_payment_delete_purse_interrupt` | 146 | (4, 10) |
| `coin_payment_delete_purse_receive` | 147 | (4, 11) |
| `coin_payment_create_receivable_request` | 148 | (4, 12) |
| `coin_payment_create_receivable_response` | 149 | (4, 13) |
| `coin_payment_create_cheque_request` | 150 | (4, 14) |
| `coin_payment_create_cheque_response` | 151 | (4, 15) |
| `coin_payment_deposit_start` | 152 | (4, 16) |
| `coin_payment_deposit_stop` | 153 | (4, 17) |
| `coin_payment_deposit_interrupt` | 154 | (4, 18) |
| `coin_payment_deposit_receive` | 155 | (4, 19) |
| `coin_payment_refund_start` | 156 | (4, 20) |
| `coin_payment_refund_stop` | 157 | (4, 21) |
| `coin_payment_refund_interrupt` | 158 | (4, 22) |
| `coin_payment_refund_receive` | 159 | (4, 23) |
| `coin_payment_listen_for_payment_start` | 160 | (4, 24) |
| `coin_payment_listen_for_payment_stop` | 161 | (4, 25) |
| `coin_payment_listen_for_payment_interrupt` | 162 | (4, 26) |
| `coin_payment_listen_for_payment_receive` | 163 | (4, 27) |
| `entropy_derive_request` | 108 | (5, 0) |
| `entropy_derive_response` | 109 | (5, 1) |
| `local_storage_read_request` | 12 | (6, 0) |
| `local_storage_read_response` | 13 | (6, 1) |
| `local_storage_write_request` | 14 | (6, 2) |
| `local_storage_write_response` | 15 | (6, 3) |
| `local_storage_clear_request` | 16 | (6, 4) |
| `local_storage_clear_response` | 17 | (6, 5) |
| `notifications_send_push_notification_request` | 4 | (7, 0) |
| `notifications_send_push_notification_response` | 5 | (7, 1) |
| `notifications_cancel_push_notification_request` | 134 | (7, 2) |
| `notifications_cancel_push_notification_response` | 135 | (7, 3) |
| `payment_balance_subscribe_start` | 118 | (8, 0) |
| `payment_balance_subscribe_stop` | 119 | (8, 1) |
| `payment_balance_subscribe_interrupt` | 120 | (8, 2) |
| `payment_balance_subscribe_receive` | 121 | (8, 3) |
| `payment_top_up_request` | 122 | (8, 4) |
| `payment_top_up_response` | 123 | (8, 5) |
| `payment_request_request` | 124 | (8, 6) |
| `payment_request_response` | 125 | (8, 7) |
| `payment_status_subscribe_start` | 126 | (8, 8) |
| `payment_status_subscribe_stop` | 127 | (8, 9) |
| `payment_status_subscribe_interrupt` | 128 | (8, 10) |
| `payment_status_subscribe_receive` | 129 | (8, 11) |
| `permissions_request_device_permission_request` | 8 | (9, 0) |
| `permissions_request_device_permission_response` | 9 | (9, 1) |
| `permissions_request_remote_permission_request` | 10 | (9, 2) |
| `permissions_request_remote_permission_response` | 11 | (9, 3) |
| `preimage_lookup_subscribe_start` | 64 | (10, 0) |
| `preimage_lookup_subscribe_stop` | 65 | (10, 1) |
| `preimage_lookup_subscribe_interrupt` | 66 | (10, 2) |
| `preimage_lookup_subscribe_receive` | 67 | (10, 3) |
| `preimage_submit_request` | 68 | (10, 4) |
| `preimage_submit_response` | 69 | (10, 5) |
| `resource_allocation_request_request` | 130 | (11, 0) |
| `resource_allocation_request_response` | 131 | (11, 1) |
| `signing_create_transaction_request` | 30 | (12, 0) |
| `signing_create_transaction_response` | 31 | (12, 1) |
| `signing_create_transaction_with_legacy_account_request` | 32 | (12, 2) |
| `signing_create_transaction_with_legacy_account_response` | 33 | (12, 3) |
| `signing_sign_raw_with_legacy_account_request` | 34 | (12, 4) |
| `signing_sign_raw_with_legacy_account_response` | 35 | (12, 5) |
| `signing_sign_payload_with_legacy_account_request` | 36 | (12, 6) |
| `signing_sign_payload_with_legacy_account_response` | 37 | (12, 7) |
| `signing_sign_raw_request` | 114 | (12, 8) |
| `signing_sign_raw_response` | 115 | (12, 9) |
| `signing_sign_payload_request` | 116 | (12, 10) |
| `signing_sign_payload_response` | 117 | (12, 11) |
| `statement_store_subscribe_start` | 56 | (13, 0) |
| `statement_store_subscribe_stop` | 57 | (13, 1) |
| `statement_store_subscribe_interrupt` | 58 | (13, 2) |
| `statement_store_subscribe_receive` | 59 | (13, 3) |
| `statement_store_create_proof_request` | 60 | (13, 4) |
| `statement_store_create_proof_response` | 61 | (13, 5) |
| `statement_store_submit_request` | 62 | (13, 6) |
| `statement_store_submit_response` | 63 | (13, 7) |
| `statement_store_create_proof_authorized_request` | 132 | (13, 8) |
| `statement_store_create_proof_authorized_response` | 133 | (13, 9) |
| `theme_subscribe_start` | 104 | (14, 0) |
| `theme_subscribe_stop` | 105 | (14, 1) |
| `theme_subscribe_interrupt` | 106 | (14, 2) |
| `theme_subscribe_receive` | 107 | (14, 3) |
