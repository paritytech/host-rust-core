---
title: "Handover: host-initiated custom-message render subscription"
type: handover
status: open
created: 2026-08-06
---

# Handover: host-initiated custom-message render subscription

Implementation handover for the custom-rendering design in
[chat-modality-shared-core.md](./chat-modality-shared-core.md). Custom message
rendering becomes a host-initiated subscription, one per rendered message,
byte-compatible with the legacy triangle
`product_chat_custom_message_render_subscribe` protocol. This replaces the
product-initiated `custom_message_render_channel` currently implemented on the
`feat/chat-modality-shared-core` branch.

## Decisions already made

Do not relitigate these; they came out of the design discussion:

- No general reversed-request facility. Host-initiated *subscriptions* are the
  only reverse primitive; every roadmap use case (Chat render, future Widget
  render) is stream-shaped.
- Wire ids 52-55 keep their slots and become byte-compatible with the legacy
  protocol (payloads below). Correlation is the wire request id; `message_id`
  no longer appears in the repaint path.
- Host-minted request ids get a dedicated prefix (`h:`) so they cannot collide
  with product-minted ids. `IdFactory`
  (`rust/crates/truapi-server/src/frame.rs:147`) already supports prefixes.
- Product-side TS API is handler registration
  (`chat.onCustomMessageRender(handler)`), not a channel argument.
- Start frames arriving before handler registration buffer product-side,
  capacity 64 (match `ACTION_BUFFER_CAPACITY` in
  `rust/crates/truapi-server/src/runtime/chat.rs:17`); overflow interrupts the
  oldest buffered instance.
- Handler stream semantics: each emission repaints; throw or stream error
  sends `interrupt` (decline); stream completion keeps the last delivered tree
  on screen and the instance stays live until the host sends `stop`.
  Re-registering replaces the handler for future starts; in-flight instances
  keep their streams.
- `ProductRuntimeControl::render_custom_message` keeps its exact signature.
  Cancelling or dropping the returned subscription sends `stop`.
- The paired-stream transport machinery added for the channel is removed
  (nothing else uses it). See "Removals".

## Wire contract

One subscription per render instance, host-minted request id prefixed `h:`.
All payloads are versioned envelopes (`V1` = discriminant `0x00`).

| Frame       | Id | Direction       | Payload after the `V1` byte                      |
| ----------- | -- | --------------- | ------------------------------------------------ |
| `start`     | 52 | host to product | `SCALE(message_id: str, message_type: str, payload: Vec<u8>)` |
| `stop`      | 53 | host to product | empty                                            |
| `interrupt` | 54 | product to host | empty (unit)                                     |
| `receive`   | 55 | product to host | `SCALE(CustomRendererNode)`                      |

Legacy reference codecs (must match byte for byte):

- [`protocol/v1/chat.ts:165-169`](https://github.com/paritytech/triangle-js-sdks/blob/main/packages/host-api/src/protocol/v1/chat.ts)
  (`ChatCustomMessageRenderingV1_start/_receive/_interrupt`)
- [`protocol/v1/customRenderer.ts`](https://github.com/paritytech/triangle-js-sdks/blob/main/packages/host-api/src/protocol/v1/customRenderer.ts)
  (already byte-identical to `v01::CustomRendererNode`)
- [`transport.ts` `handleSubscription`](https://github.com/paritytech/triangle-js-sdks/blob/main/packages/host-api/src/transport.ts)
  (product-serving side; frame slot order start/stop/interrupt/receive = index+0..+3)
- [`host-api-wrapper/src/chat.ts` `onCustomMessageRenderingRequest`](https://github.com/paritytech/triangle-js-sdks/blob/main/packages/host-api-wrapper/src/chat.ts)
  (the product API shape being matched)

## Current state to replace (branch inventory)

The channel implementation to remove or rework:

- Trait method `custom_message_render_channel`:
  `rust/crates/truapi/src/api/chat.rs:129-136`
- Types `ProductChatCustomMessageRenderChannelRequest` (Update/Failed) and
  `ProductChatCustomMessageRenderChannelItem`:
  `rust/crates/truapi/src/v01/chat/custom_renderer.rs:312-338`, versioned
  wrappers in `rust/crates/truapi/src/versioned/chat.rs:17-18`
- `ChatConnection` renderer half (`RendererState`, generation counter,
  `register_renderer`, `message_id -> sender` demux):
  `rust/crates/truapi-server/src/runtime/chat.rs`. Keep the action-buffer
  half untouched.
- Host `Chat` impl of the channel:
  `rust/crates/truapi-server/src/runtime.rs:1872`
- Paired-stream plumbing: `on_stream_pair` in
  `rust/crates/truapi-server/src/dispatcher.rs`; `reserve_pair`,
  `RequestSender`, `SubscriptionRequestStream`, `subscription_request_stream`
  in `rust/crates/truapi-server/src/subscription.rs`
- TS paired-stream support: `sendSubscriptionItem` and
  `SendSubscriptionItemParams` in `js/packages/truapi/src/transport.ts` and
  `js/packages/truapi/src/client.ts:418`. Keep `ObservableSource`
  (`transport.ts:113`); it becomes the handler return type.
- Playground worker channel usage: `playground/worker/index.ts:46-51` and the
  `Update`/`Failed` sends at `playground/worker/index.ts:197-201`
- Native entrypoints (keep signatures, rewire internals):
  `render_custom_message` at `rust/crates/truapi-server/src/native.rs:1088`
  and `:1317`; observer machinery in
  `rust/crates/truapi-server/src/native_renderer.rs` is unchanged.

## Work plan

### 1. Protocol types (`truapi`)

- Rename `ProductChatCustomMessageRenderChannelItem` to
  `ProductChatCustomMessageRenderRequest` (same fields; it becomes the start
  payload). Delete the `...ChannelRequest` Update/Failed enum.
- Add a versioned item wrapper for renderer trees, e.g.
  `ProductChatCustomMessageRenderItem { V1 => v01::CustomRendererNode }` in
  `versioned/chat.rs`, so the `receive` wire payload is `[0x00] ++ node`.
- Replace the trait method with the host-initiated declaration:

  ```rust
  #[wire(host_initiated, start_id = 52)]
  fn custom_message_render(
      request: ProductChatCustomMessageRenderRequest,
  ) -> Subscription<ProductChatCustomMessageRenderItem>;
  ```

  Exact IDL surface (whether the trait carries a default body or the macro
  elides it from the required methods) is the implementer's call; the trait
  must not force hosts to implement it as a server method.

### 2. Macro (`truapi-macros`)

- Accept a `host_initiated` flag in `#[wire(...)]`
  (`rust/crates/truapi-macros/src/lib.rs:34` argument parsing) and smuggle it
  through the rustdoc JSON the same way ids are smuggled today.

### 3. Codegen (`truapi-codegen`)

- `rustdoc.rs`: parse the flag into the method model.
- Wire table emission: unchanged ids; method name becomes
  `chat_custom_message_render`.
- Rust dispatcher emission: skip server registration for host-initiated
  methods; instead emit a typed host-side caller that fronts the generic
  facility from step 4.
- TS emission (`ts.rs`): emit the registration method

  ```ts
  onCustomMessageRender(
    handler: (request: ProductChatCustomMessageRenderRequest)
      => ObservableSource<CustomRendererNode>,
  ): { unsubscribe(): void };
  ```

  with the pre-registration buffer and the repaint/interrupt/complete
  semantics from "Decisions".
- Update goldens: `tests/golden/dispatcher.rs`, `tests/golden/wire_table.rs`,
  and the TS golden if the client surface is covered there.

### 4. Server runtime (`truapi-server`)

- Add a host-initiated subscription facility beside `SubscriptionManager`:
  mint `h:`-prefixed ids, send `start`, route inbound `receive`/`interrupt`
  frames by request id to the per-instance stream, send `stop` when the
  returned `Subscription` is dropped or cancelled, tear everything down on
  disconnect.
- Inbound routing: product frames carrying discriminants 54/55 with an
  `h:`-prefixed request id go to this facility, not the request dispatcher.
- Rewire `render_custom_message` (runtime control, `native.rs`,
  `host_core.rs`) onto the facility. Delete the `ChatConnection` renderer
  half; port its tests to the new facility (routing by instance, cancel on
  close, isolation between connections).
- A malformed `receive` value fails only that instance's stream.

### 5. JS client (`js/packages/truapi`)

- Transport: route inbound frames whose discriminant is a host-initiated
  `start_id` to a registered server handler; keep a bounded buffer (64) when
  no handler is installed; send `interrupt` for overflow evictions.
- Emit `receive` frames with the peer-supplied request id; `stop` tears down
  the handler's observable subscription.
- Remove `sendSubscriptionItem` and its params type.
- Client tests: registration before/after start, buffering, overflow
  interrupt, repaint stream, decline via throw, stop disposes.

### 6. Playground worker and diagnosis

- Replace the channel usage with `onCustomMessageRender`.
- Diagnosis checks to keep or add: render round trip, replacement tree,
  decline path, and a `stop`-dispose check (host cancels, worker observes its
  observable being unsubscribed).
- `playground/tests/unit/chat-diagnosis.test.ts` and
  `scripts/lib/chat-diagnosis-report.mjs` follow the renamed method.

### 7. Host CLI and reports

- `rust/crates/truapi-host-cli/SPEC.md:1218,1544` reference "six generated
  Chat methods" and channel wording; update to the host-initiated method.
- Refresh `explorer/diagnosis-reports/chat/ios.md` by re-running
  `scripts/launch-ios-chat-playground.mjs` after the uniffi surface
  regenerates (native observer API is unchanged, so host code should only
  need a rebuild).

### 8. Docs

- `docs/design/chat-modality-product-sdk.md` still describes the channel
  (`open custom_message_render_channel`, `Update`/`Failed`); rewrite its
  adapter section around `onCustomMessageRender`.
- README mentions of the channel method name, if any (`rg
  custom_message_render_channel` after the rename must come up empty).

## Byte-compatibility tests

Add fixture tests that pin the wire bytes, not just round trips:

- Rust: encode `V1(ProductChatCustomMessageRenderRequest)` and
  `V1(CustomRendererNode)` samples and assert against hard-coded hex captured
  from the legacy codecs (`ChatCustomMessageRenderingV1_start.enc`,
  `ChatCustomMessageRenderingV1_receive.enc` in triangle-js-sdks; generate the
  hex once with a throwaway script there).
- Interrupt payload must be exactly `0x00` (`v1` + unit), stop exactly empty.

## Removals

Delete with the channel (verify no other consumer first):

- `dispatcher.rs` `on_stream_pair`
- `subscription.rs` `reserve_pair` / `RequestSender` /
  `SubscriptionRequestStream` / `subscription_request_stream`
- TS `sendSubscriptionItem` / `SendSubscriptionItemParams`
- `ChatConnection` renderer state and its tests (superseded by the facility's
  tests)

## Verification

Definition of done for this change, in order: `rust-checks`, `regen-codegen`,
`ts-client-checks`, `refresh-playground-snapshot`, `playground-checks`, then
the iOS chat diagnosis run. Golden tests
(`rust/crates/truapi-codegen/tests/golden_rust_emit.rs`) must be regenerated,
not hand-edited.
