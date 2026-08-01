---
title: "Chat Modality Shared Core Implementation Plan"
type: design
status: proposed
created: 2026-07-31
---

# Chat Modality Shared Core Implementation Plan

This plan implements the
[Chat Modality on the Shared Rust Core](./chat-modality-shared-core.md) design.
The design document is the source of truth for protocol, runtime, and native
host behavior. Product-side work is defined separately in the
[Chat Modality Product SDK](./chat-modality-product-sdk.md) design.

## 1. Contract and generated bindings

- Keep `custom_message_render_subscribe` product-initiated and change it from a
  one-way subscription into paired request and response streams.
- Change its request into `Update` and `Failed` variants.
- Change its item into a render-request struct containing `message_id`,
  `message_type`, and `payload`.
- Generate a minimal TypeScript `SubjectLike<Request>` for product-to-Rust
  values and reuse `ObservableLike<Item>` for Rust-to-product values.
- Generalize Rust `Subscription<T>` into a direction-neutral typed stream so it
  can represent both halves of the operation.
- Use paired streams only for `custom_message_render_subscribe`; ordinary Chat
  subscriptions remain one-way.
- Add service-level `required_execution` metadata and annotate the Chat trait
  with `Chat`.
- Generate a service registration that wraps all Chat requests, subscriptions,
  and stream pairs in the server's `ExecutionFilter`.
- Generate the TypeScript request/response-stream client and the corresponding
  Rust dispatcher implementation.
- Generate native `CustomRendererNode` bindings.
- Add conformance tests for stream opening, values in both directions,
  renderer updates, cancellation, disconnect, and recursive renderer nodes.

The Chat service remains one logical product-to-host contract. Custom rendering
uses paired request and response streams supplied by the Rust Chat service.

## 2. Shared runtime and execution connections

- Refactor native construction into one process-owned `TrUAPIHostRuntime`.
- Add `open_product_execution(context)` returning a connection-specific
  endpoint and control handle.
- Bind each WebSocket token to one immutable `ProductContext`.
- Add `truapi-server/src/middleware/execution.rs` and construct one
  `ExecutionFilter` from the connection context.
- Reuse that filter for generated Chat dispatch and native-to-product
  `ProductRuntime` methods.
- Keep one frame dispatcher and live-channel registry per connection while
  sharing authentication, chain resources, storage services, and policy.
- Add the Chat service, action publisher, bounded connection-scoped action
  buffer, renderer-stream routing, message-id correlation, native update
  fan-out, connection-level cancellation, and resource limits.
- Atomically drain buffered actions in FIFO order when
  `chat_action_subscribe` opens, then route subsequent actions directly.

### Manifest example

The
[Host Playground deployment config](https://github.com/paritytech/host-playground/blob/ab7ddb1476881a1ea3c77a4685f94a5ba60b6c72/bulletin-deploy.config.ts#L20-L42)
declares one `app` executable and one `worker` executable whose entrypoint is
`index.js` and whose `includes` value is `{ chat: true, pocket: false }`:

```ts
executables: [
  { kind: "app", path: "./out" },
  {
    kind: "worker",
    path: "./out/worker",
    entrypoint: "index.js",
    includes: { chat: true, pocket: false },
  },
];
```

`bulletin-deploy` publishes this configuration as DotNS records. At runtime,
the host resolves those records and derives the immutable context for each
executable.

## 3. iOS reference integration

- Make `SPAInteractor` open an `App` execution for `index.html`.
- Make `ProductsScriptExecutor` open a `Chat` execution for `worker/index.js`
  when its resolved DotNS metadata declares `includes.chat: true`.
- Implement `ChatPlatform` with the existing
  `ChatExtensionDiscoverContext`/CoreData behavior.
- Replace `onUserMessage`, `dispatchEvent`, and `renderMessage` with calls on
  the Chat connection's `ProductRuntime` handle.
- Delete `onBotStarted` and every chat-specific `evaluate` call.
- Pass generated `CustomRendererNode` values to native SwiftUI rather than
  SCALE hex strings.

## 4. Other hosts

- Dotli maps a resolved DotNS worker with `includes.chat: true` to a `Chat`
  execution and opens its connection through the WASM host runtime.
- Android implements `ChatPlatform` when native chat storage and UI are
  available; until then Chat calls return `Unsupported`.
- The CLI may install an explicit in-memory `ChatPlatform` for end-to-end
  tests. Its default runtime has no Chat adapter.

## 5. Verification

The integration is complete when the following pass without JavaScript
evaluation or `container.js`:

- SPA and worker connect concurrently to one host runtime with distinct
  contexts.
- An `App` request, subscription start, or renderer-stream open targeting Chat
  is denied before its handler or `ChatPlatform` adapter runs.
- Native Chat actions and render requests cannot use an `App` connection.
- Native actions published before `chat_action_subscribe` opens are buffered
  and delivered in FIFO order before subsequent live actions.
- Filling the startup action buffer returns `ProductRuntimeError::BufferFull`.
- Closing a Chat execution discards its buffer; a replacement connection does
  not inherit those actions.
- Room creation reports `New` and `Exists` correctly.
- User text reaches the worker and the reply is persisted.
- Multiple rooms route replies through the action's room id.
- A stored custom message renders after app restart.
- One renderer stream pair multiplexes independent render instances for multiple
  live messages.
- The renderer request stream accepts multiple typed `Update` values for the same
  message.
- Native cell and widget cleanup emits no product control message.
- Closing the Chat view closes the associated product connection and renderer
  stream.
- One action subscription delivers widget actions with the correct message and
  action identifiers.
- An unknown message type sends `Failed` and affects only its render instance.
- Worker reconnect closes the old renderer streams and establishes a clean
  replacement pair.
- Two products cannot observe each other's rooms, actions, or renders.
- A host without `ChatPlatform` reports `Unsupported` consistently.
