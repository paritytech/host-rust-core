---
title: "Chat Modality on the Shared Rust Core"
type: design
status: accepted
created: 2026-07-30
---

# Chat Modality on the Shared Rust Core

## Summary

Chat products run on the same TrUAPI execution path as SPA products: the
visible SPA and a headless Chat worker are separate executions, each with its
own connection into a single host-owned Rust runtime, speaking the same
SCALE protocol and generated client. This replaces the mobile `container.js`
bridges and evaluated JavaScript globals.

Compared with the current mobile architecture, the shared-core integration
changes three things:

- Chat access becomes a connection policy. The host assigns an immutable
  `ProductExecutionKind`, and an `ExecutionFilter` rejects Chat traffic from
  other executions.
- Custom rendering replaces `renderMessage` and `chatRenderWidget` with a
  host-initiated TrUAPI render subscription per message, wire-compatible with
  the legacy render protocol.
- Platform-specific `evaluate` and `callNative` code is replaced by
  `ProductRuntimeControl`, `ChatPlatform`, and generated native types.

Execution kinds beyond Chat are outside this design.

## Legacy mobile chat bridges

`polkadot-app-ios-v2` and `polkadot-app-android-v2` run chat products the
same way: a headless webview loads a shared `container.js` bundle plus the
product's `worker/index.js`. Each platform implements bridge code in both
directions:

- **Product to native:** `container.js` receives the worker's SCALE requests
  and forwards supported operations through `callNative(method, params)`,
  into the Swift `ProductsNativeApi` on iOS and through a synchronous
  `@JavascriptInterface` into Kotlin handler groups on Android.
- **Native to product:** both platforms evaluate JavaScript globals installed
  by `container.js`, such as `dispatchUserMessage(...)`,
  `dispatchChatAction(...)`, and `renderMessage(...)`, with Android building
  the snippets by string concatenation.

These platform-specific bridges sit outside TrUAPI.

## Architecture

The architecture has three structural rules:

- the host owns one long-lived Rust runtime, shared by all of its product
  executions
- each executable has its own connection and per-connection runtime
- `app/index.html` connects as `Spa`, while `worker/index.js` connects as
  `Chat`; both share host services
- product executions initiate all ordinary calls and subscriptions; the
  runtime initiates only per-message render subscriptions, into Chat
  executions

```text
+---------------+---------------+           +---------------+---------------+
| SPA execution                 |           | Chat execution                |
| app/index.html                |           | worker/index.js               |
| ProductContext(Spa)           |           | ProductContext(Chat)          |
+---------------+---------------+           +---------------+---------------+
                | connection A                              | connection B
                +---------------------+---------------------+
                                      ^
                                      | SCALE / TrUAPI
                                      v
         +---------------------------------------------------------+
         | Shared Rust HostRuntime                                 |
         |                                                         |
         | ProductRuntime(Spa)       ProductRuntime(Chat)          |
         | dispatches product calls and live subscriptions         |
         | opens per-message render subscriptions into Chat        |
         | shared authentication, storage, and chain resources     |
         +----------------------------+----------------------------+
                                      ^
                                      | typed native bindings
                                      v
         +---------------------------------------------------------+
         | Native platform services                                |
         | ChatPlatform -> native Chat UI and database             |
         | authentication, storage, and chain services             |
         +---------------------------------------------------------+
```

Chat is an API-backed modality with host-owned native UI. The DotNS
`includes.chat` declaration selects `worker/index.js`. The host loads it through
the existing WebSocket bootstrap and derives its context from the resolved
DotNS records. The
[Host Playground deployment config](https://github.com/paritytech/host-playground/blob/ab7ddb1476881a1ea3c77a4685f94a5ba60b6c72/bulletin-deploy.config.ts#L20-L42)
is a concrete example.

## Execution bootstrap and transport ownership

The native host establishes the transport before it evaluates product code.
Opening an execution and establishing its connection are separate steps:

1. Native opens a product execution on the shared `HostRuntime`, supplying the
   trusted product id and execution kind. For a Chat worker the kind is `Chat`.
2. The execution starts a token-authenticated localhost WebSocket bridge and
   returns its port and per-execution endpoint token.
3. Native injects a WebSocket-backed `MessagePort` adapter at document start,
   before loading `worker/index.js`. On iOS the adapter is exposed as
   `window.__HOST_API_PORT__`.
4. The worker calls `getClientSync()` from `@parity/truapi/sandbox`. This
   returns a synchronous client facade, wraps the injected port, and starts the
   socket. Calls made before `onopen` are queued and flushed when the connection
   is ready; returning a client does not itself prove that the socket is open.
5. After the token-authenticated WebSocket upgrade, Rust creates one
   `ProductRuntime` for that connection, installs its immutable
   `ProductContext`, and attaches the native `ProductRuntimeControl`.
6. Constructing the generated `ChatClient` registers its host-initiated routes,
   including wire id 52 for custom rendering. The worker then installs its
   handler with `chat.onCustomMessageRender(...)` and starts ordinary calls and
   subscriptions.
7. Closing the execution closes its socket, disposes its per-connection
   runtime, and terminates all ordinary and host-initiated subscriptions owned
   by that connection. It does not stop the process-wide Rust runtime or other
   product executions.

```text
Native host                 Shared Rust runtime                 Product worker
     |                               |                                |
     | open Chat execution           |                                |
     |------------------------------>|                                |
     | start WebSocket bridge        |                                |
     |<------------------ port/token |                                |
     | inject MessagePort bootstrap  |                                |
     |--------------------------------------------------------------->|
     |                               |             getClientSync()    |
     |                               |<-------------------------------|
     |                               | authenticated WebSocket upgrade|
     |                               |<-------------------------------|
     |                               | create ProductRuntime(Chat)    |
     |                               | attach ProductRuntimeControl   |
     |                               |                                | register handlers
```

The visible SPA and its Chat worker repeat this sequence independently. They
share the host-owned Rust runtime and platform services, but they do **not**
share a socket, `ProductRuntime`, request-id counter, subscriptions, or
transport failure domain. Product-originated requests use `p:<id>` identifiers
on their connection. Host-initiated render subscriptions use `h:<id>`
identifiers allocated by that connection's Rust runtime.

Rust starts custom rendering with request id `h:<id>` and wire id 52 (`_start`),
encoding `messageId`, `messageType`, and `payload`. Renderer updates use wire id
55 with the same request id; wire ids 53 and 54 stop and interrupt the render
subscription.

## Trusted execution context

The host binds the context before product code runs. The product cannot submit
or override its execution kind. A DotNS worker with `includes.chat: true` maps
to `ProductExecutionKind::Chat`.

```rust
pub struct ProductContext {
    pub product_id: String,
    /// Trusted kind of executable attached to this connection by the host.
    pub execution_kind: ProductExecutionKind,
}

/// Trusted kind of product executable attached to a TrUAPI connection.
pub enum ProductExecutionKind {
    /// Visible single-page application entrypoint such as `app/index.html`.
    Spa,
    /// Headless worker executable that provides the Chat modality.
    Chat,
}
```

The required execution kind is declared once on the API trait, and
`truapi-codegen` emits the matching server registration:

```rust
#[truapi::service(required_execution = Chat)]
pub trait Chat: Send + Sync {
    // requests, subscriptions, and host-initiated subscriptions
}
```

`truapi-server` builds `ExecutionFilter` from the immutable context when it
creates the connection's `ProductRuntime`. The filter runs before Chat
handlers, streams, and native entrypoints, so a `Spa` connection cannot carry
Chat traffic.

## Custom rendering

`custom_message_render` is a host-initiated subscription, opened once per
rendered message. The host starts a subscription into the product when a
native cell needs a custom message's UI; the product answers with a stream of
complete `CustomRendererNode` trees, where each emission repaints the widget;
the host stops the subscription when the cell goes away. The wire request id
correlates one render instance end to end.

| Frame       | Direction       | Payload                                             |
| ----------- | --------------- | --------------------------------------------------- |
| `start`     | host to product | `{ message_id, message_type, payload }`             |
| `stop`      | host to product | none; the product disposes that renderer instance   |
| `interrupt` | product to host | none; the product declines or aborts that instance  |
| `receive`   | product to host | `CustomRendererNode`, a complete replacement tree   |

These frames are byte-compatible with the legacy triangle
`product_chat_custom_message_render_subscribe` protocol, so a product's
renderer path works unchanged against legacy mobile hosts and the shared Rust
core. The shared Rust host mints request ids with a dedicated `h:` prefix so
they cannot collide with product-minted ids. Product-side routing keys off the
globally unique render frame ids rather than requiring that prefix, preserving
compatibility with legacy hosts whose host-minted ids are opaque.

The method is declared on the `Chat` trait as IDL, marked host-initiated.
`truapi-codegen` emits no server dispatch entry for it; it generates the
product-side registration API and the host-side typed caller instead.

```rust
/// Streams renderer trees for one stored custom message.
#[wire(host_initiated, start_id = 52)]
fn custom_message_render(
    request: ProductChatCustomMessageRenderRequest,
) -> Subscription<CustomRendererNode>;
```

The generated TypeScript API is handler registration. The handler returns an
observable of renderer trees: each emission repaints, a throw or stream error
declines the instance (`interrupt`), and completing the stream keeps the last
delivered tree on screen. Start frames that arrive before registration are
held in a bounded product-side buffer; overflow interrupts the oldest
buffered instance.

```ts
export class ChatClient {
  onCustomMessageRender(
    handler: (
      request: ProductChatCustomMessageRenderRequest,
    ) => ObservableSource<CustomRendererNode>,
  ): { unsubscribe(): void };
}
```

```ts
truapi.chat.onCustomMessageRender(({ messageType, payload }) => {
  // Observable<CustomRendererNode>: emits on every renderer state change.
  return renderTrees(messageType, payload);
});
```

```text
Native platform                    Shared Rust HostRuntime                   Product worker
(Chat UI)                             (ProductRuntime)                      (worker/index.js)
       |                                      |                                     |
       |                                      |         onCustomMessageRender(...)  |
       |                                      |    (starts buffered until a handler |
       |                                      |                       is installed) |
       | native cell encounters stored        |                                     |
       | Custom(message_id, message_type,     |                                     |
       |   payload) and needs its UI          |                                     |
       | render_custom_message(...)           |                                     |
       |------------------------------------->|                                     |
       |                                      | start { message_id,                 |
       |                                      |   message_type, payload }           |
       |                                      |------------------------------------>|
       |                                      |                                     | decode payload
       |                                      |                                     | produce renderer tree
       |                                      | receive CustomRendererNode          |
       |                                      |<------------------------------------|
       | typed CustomRendererNode             |                                     |
       |<-------------------------------------|                                     |
       | repaint native widget                |                                     |
       |                                      |                                     |
       |                                      |                                     | renderer state changes
       |                                      | receive replacement node            |
       |                                      |<------------------------------------|
       | typed replacement node               |                                     |
       |<-------------------------------------|                                     |
       |                                      |                                     |
       | cell leaves the screen               |                                     |
       | cancel render subscription           |                                     |
       |------------------------------------->|                                     |
       |                                      | stop                                |
       |                                      |------------------------------------>|
       |                                      |                                     | dispose renderer state
```

`message_id` correlates a rendered widget with the `ActionTriggered` events
it emits. Native receives generated Swift or Kotlin renderer types.

## Native host contract

The host uses a per-connection `ProductRuntimeControl` to push native events
to the worker and may implement one runtime-wide `ChatPlatform` for product
calls into native chat storage and UI.

The native binding retains the control handle for the connection's lifetime;
it is not product-facing TrUAPI.

```rust
impl ProductRuntimeControl {
    fn publish_chat_action(
        &self,
        action: HostChatActionSubscribeItem,
    ) -> Result<(), ProductRuntimeError>;

    fn render_custom_message(
        &self,
        message_id: String,
        message_type: String,
        payload: Vec<u8>,
    ) -> Result<Subscription<CustomRendererNode>, ProductRuntimeError>;
}
```

`publish_chat_action` carries `MessagePosted` and `ActionTriggered`.
`render_custom_message` opens the host-initiated render subscription and
returns its tree stream. Cancelling the returned subscription sends `stop`,
telling the product to dispose that instance's renderer state. Native owns
its observers and rendered views.

In the opposite direction, product-originated room, message, and room-list
calls flow through the optional `ChatPlatform` adapter:

```rust
pub trait ChatPlatform: Send + Sync {
    async fn create_room(
        &self,
        product: &ProductContext,
        request: HostChatCreateRoomRequest,
    ) -> Result<HostChatCreateRoomResponse, HostChatCreateRoomError>;

    async fn post_message(
        &self,
        product: &ProductContext,
        request: HostChatPostMessageRequest,
    ) -> Result<HostChatPostMessageResponse, HostChatPostMessageError>;

    fn subscribe_rooms(
        &self,
        product: &ProductContext,
    ) -> BoxStream<'static, HostChatListSubscribeItem>;
}
```

### Room creation ownership

Opening the native Chat screen is host UI behavior, not a TrUAPI operation, and
does not implicitly create a product room. A host may enable or launch the Chat
execution and observe `chat.listSubscribe()` while it waits for a room to
appear, but the product worker decides which rooms its modality provides.

The worker requests a room through the generated client:

```ts
const result = await truapi.chat.createRoom({
  roomId: "support",
  name: "Support",
  icon: "",
});
```

Rust validates the Chat execution, decodes the versioned request, and calls
`ChatPlatform::create_room`. The platform adapter looks up or persists the room
and returns `New` or `Exists`.

The worker creates rooms with `createRoom`; `listSubscribe` may also emit
persisted rooms. The native UI owns waiting behavior.

## Failure behavior

Rust enforces connection policy and renderer-stream validation.

| Condition                                          | Result                                                        |
| -------------------------------------------------- | ------------------------------------------------------------- |
| Ordinary Chat call is not from a Chat execution    | `CallError::Denied`                                            |
| Ordinary Chat call has no `ChatPlatform` adapter   | `CallError::Unsupported`                                       |
| Ordinary Chat call is unauthenticated              | Standard authentication failure                                |
| Worker connects but never calls `createRoom`       | No room is synthesized; room observers remain unchanged        |
| Native action targets a closed execution           | `ProductRuntimeError::Closed`                                  |
| Renderer is requested on a non-Chat connection     | `ProductRuntimeError::Denied`                                  |
| Render `start` arrives before handler registration | Buffered product-side; overflow interrupts the oldest instance |
| Product declines a render (throw or stream error)  | `interrupt`; only that instance's native stream ends           |
| Host stops displaying a message                    | `stop`; the product disposes that instance's renderer state    |
| Renderer node is malformed or exceeds host limits  | Only that native render stream fails                           |
| A `receive` value cannot be decoded                | Only that render instance fails                                |
| Product disconnects during rendering               | All its render subscriptions terminate                         |

## References

- [TrUAPI Protocol Design](./truapi-protocol.md)
- [`Chat` Rust trait](../../rust/crates/truapi/src/api/chat.rs)
- [`CustomRendererNode` types](../../rust/crates/truapi/src/v01/chat/custom_renderer.rs)
- [iOS worker executor](https://github.com/paritytech/polkadot-app-ios-v2/blob/truhost-integration/Packages/Products/Sources/Products/Services/ProductsScriptExecutor.swift)
- [iOS TrUAPI host bridge](https://github.com/paritytech/polkadot-app-ios-v2/blob/truhost-integration/Packages/Products/Sources/Products/Services/ProductTrUAPIHostBridge.swift)
- [Android host adapter](../../android/truapi-host)
