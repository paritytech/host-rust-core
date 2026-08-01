---
title: "Chat Modality on the Shared Rust Core"
type: design
status: proposed
created: 2026-07-30
---

# Chat Modality on the Shared Rust Core

## Summary

Chat products use the same TrUAPI execution path as SPA products.

The visible app and Chat worker remain separate executions with separate
connections. Both connections terminate in the same process-owned Rust runtime
and use the host's native platform services.

## Current architecture

### Legacy iOS chat communication

The working chat implementation in `polkadot-app-ios-v2` loads both
`container.js` and `worker/index.js` in a headless webview. The bridge has two
directions:

- **Product to native:** the worker calls the Triangle Chat API. `container.js`
  receives the SCALE request and forwards supported operations through
  `callNative(method, params)` to `ContainerBridge`, which invokes the Swift
  `ProductsNativeApi` implementation.
- **Native to product:** Swift evaluates globals installed by `container.js`,
  such as `dispatchUserMessage(...)` and `dispatchChatAction(...)`.
  `container.js` converts those calls into Chat actions delivered to the
  worker's Triangle subscription.

```text
Native iOS app                       container.js                     Product worker
(Chat UI / CoreData)            (headless WKWebView)                (worker/index.js)
       |                                  |                                  |
       | user submits "!echo hello"       |                                  |
       | ProductBot.onTextMessage         |                                  |
       | ProductsScriptExecutor evaluates |                                  |
       | dispatchUserMessage(             |                                  |
       |   roomId, text)                  |                                  |
       |--------------------------------->|                                  |
       |                                  | creates MessagePosted:           |
       |                                  | Text("!echo hello")              |
       |                                  |--------------------------------->|
       |                                  |                                  | subscribeAction receives
       |                                  |                                  | the action and builds
       |                                  |                                  | "Echo: hello"
       |                                  |                                  |
       |                                  | chatManager.sendMessage(         |
       |                                  |   roomId, Text("Echo: hello"))   |
       |                                  |<---------------------------------|
       |                                  | callNative(                      |
       |                                  |   "chatSendTextMessage", ...)    |
       |<---------------------------------|                                  |
       |                                  |                                  |
       | ProductsNativeApi persists       |                                  |
       | the message in CoreData          |                                  |
       | Native Chat UI displays          |                                  |
       | "Echo: hello"                    |                                  |
       |                                  |                                  |
```

## Target architecture

### Topology

The target design has four structural rules:

- the host process owns one long-lived Rust host runtime
- each executable gets its own connection and per-connection runtime
- `app/index.html` connects as `App`, while a Chat-enabled
  `worker/index.js` connects as `Chat`
- both connections share authentication, storage, chain resources, and the
  native Chat adapter

On iOS, the existing `ProductTrUAPIHostRuntime` worker integration becomes the
Chat connection into the process-owned host runtime. It keeps the existing
worker launch path: inject the same WebSocket bootstrap as the SPA, then load
`worker/index.js`. The generated TrUAPI Chat API is available on that
`ProductContext(Chat)` connection. It replaces the legacy JavaScript globals
and `container.js` Chat bridge, which are removed.

Chat is an API-backed modality with host-owned native UI. Its modality
declaration selects the Chat worker executable. The current DotNS
`includes.chat` declaration is the existing representation of that association
and may later map to the general `modalities.chat` manifest shape.

The host derives each immutable context from resolved DotNS product and
executable records. The
[Host Playground deployment config](https://github.com/paritytech/host-playground/blob/ab7ddb1476881a1ea3c77a4685f94a5ba60b6c72/bulletin-deploy.config.ts#L20-L42)
is a concrete example.

```text
+---------------+---------------+           +---------------+---------------+
| App execution                 |           | Chat execution                |
| app/index.html                |           | worker/index.js               |
| ProductContext(App)           |           | ProductContext(Chat)          |
+---------------+---------------+           +---------------+---------------+
                | connection A                              | connection B
                +---------------------+---------------------+
                                      |
                                      | SCALE / TrUAPI
                                      v
         +---------------------------------------------------------+
         | Shared Rust HostRuntime                                 |
         |                                                         |
         | ProductRuntime(App)       ProductRuntime(Chat)          |
         | per-connection dispatch and live subscriptions          |
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

Both executions use exactly the same SCALE protocol and generated client. They
differ only in:

- which product executable was loaded
- the trusted context attached to their connection
- the long-lived protocol streams opened by the product executable
- whether they have a visible DOM

### Trusted execution context

The host creates the product connection with context derived from the resolved
DotNS product and executable metadata described above. The existing
`ProductContext` changes only by adding the trusted execution kind:

```rust
 pub struct ProductContext {
     pub product_id: String,
+    /// Trusted kind derived from the resolved DotNS executable metadata.
+    pub execution_kind: ProductExecutionKind,
 }
```

```rust
/// Classifies the product executable running on a connection.
pub enum ProductExecutionKind {
    /// Visible application entrypoint, such as `app/index.html`.
    App,
    /// Host-embedded product widget entrypoint.
    Widget,
    /// Headless worker executable that provides the Chat modality.
    Chat,
}
```

The context is bound to the transport endpoint before product code runs. On
iOS, the localhost WebSocket token resolves to this context when Rust accepts
the connection. The JavaScript product cannot submit or override its execution
kind.

For this design, a DotNS executable declared as `kind: "worker"` with
`includes.chat: true` maps to `ProductExecutionKind::Chat`. Other worker modes
are outside the current scope and can add execution kinds when needed.

The requirement is declared once on the API trait:

```rust
#[truapi::service(required_execution = Chat)]
pub trait Chat: Send + Sync {
    // requests, subscriptions, and paired request/response streams
}
```

`truapi-codegen` carries that service metadata into the generated server
registration. The generated registration is equivalent to:

```rust
dispatcher.register_service(
    chat,
    ExecutionFilter::require(ProductExecutionKind::Chat),
);
```

`ExecutionFilter` lives in `truapi-server/src/middleware/execution.rs`. It is
created from the immutable `ProductContext` when the connection's
`ProductRuntime` is built and runs before any Chat handler or stream is opened.
A mismatch returns `Denied`; accepted calls continue to the Chat service's
authentication and `ChatPlatform` checks.

The native `ProductRuntime` Chat entrypoints call the same filter before
publishing actions or render requests. Consequently, an `App` connection cannot
be used as the Chat connection, even when both executables belong to the same
product.

### Execution lifecycle

The host creates the Chat execution, loads its worker, and accepts the worker's
product-initiated subscriptions:

```text
Native host                    Shared Rust HostRuntime               Product worker
     |                                  |                                  |
     | create Chat execution            |                                  |
     |--------------------------------->|                                  |
     | load worker/index.js             |                                  |
     |-------------------------------------------------------------------->|
     |                                  | open TrUAPI connection           |
     |                                  |<---------------------------------|
     |                                  | chat_action_subscribe            |
     |                                  |<---------------------------------|
     |                                  |                                  |
```

As a startup edge case, actions published before `chat_action_subscribe` opens
are held in a bounded connection-scoped FIFO and drained in order. Filling it
returns `ProductRuntimeError::BufferFull`; closing the connection discards it
rather than carrying actions into a replacement connection.

The optional renderer and room-list streams are independent; their setup order
is defined by the Product SDK. There is at most one active Chat execution per
product in a host process.

Closing or replacing an execution terminates all of its protocol streams.
Reconnection creates a new execution, reloads the worker module, and
establishes fresh streams.

Durable redelivery, acknowledgement, and bot inbox semantics remain outside
this design.

## Chat flows

### Custom rendering

The existing `custom_message_render_subscribe` operation remains initiated by
the product. It now has a product-to-Rust request stream and a Rust-to-product
response stream:

| Event                | Direction       | Value                                  |
| -------------------- | --------------- | -------------------------------------- |
| Open stream          | Product -> Rust | call `custom_message_render_subscribe` |
| Ask for native UI    | Rust -> product | render item                            |
| Return or replace UI | Product -> Rust | request `Update`                       |
| Reject render        | Product -> Rust | request `Failed`                       |

The product opens the operation by subscribing to its response stream. Opening
it carries no application request value. Other Chat subscriptions remain
ordinary one-way subscriptions.

The resulting Rust API shape is:

```rust
/// Serves custom-message rendering over paired request and response streams.
async fn custom_message_render_subscribe(
    &self,
    _cx: &CallContext,
    requests: Subscription<ProductChatCustomMessageRenderSubscribeRequest>,
) -> Subscription<ProductChatCustomMessageRenderSubscribeItem>;

/// Values sent from the product to Rust on the renderer request stream.
pub enum ProductChatCustomMessageRenderSubscribeRequest {
    /// Replaces the native tree for one active render instance.
    Update {
        /// Identifier supplied by the host in the corresponding render item.
        message_id: String,

        /// Complete replacement tree produced by the product renderer.
        node: CustomRendererNode,
    },

    /// Reports that the product cannot render one requested message.
    Failed {
        /// Identifier supplied by the host in the corresponding render item.
        message_id: String,
    },
}

/// Render request sent from Rust to the product on the renderer response stream.
pub struct ProductChatCustomMessageRenderSubscribeItem {
    /// Stable identifier used to correlate updates and widget actions.
    pub message_id: String,

    /// Product-defined discriminator used to select a renderer.
    pub message_type: String,

    /// Stored product-defined message payload.
    pub payload: Vec<u8>,
}
```

In the target API, `Subscription<T>` is a direction-neutral typed stream. The
`requests` parameter is the product-to-Rust stream, while the returned
`Subscription` is the Rust-to-product stream. Both are scoped to the same
connection and operation.

The generated TypeScript API reuses `ObservableLike` for responses and adds a
minimal `SubjectLike` for requests:

```ts
export interface SubjectLike<T> {
  next: (value: T) => void;
}

export class ChatClient {
  customMessageRenderSubscribe(): {
    requests: SubjectLike<ProductChatCustomMessageRenderSubscribeRequest>;
    responses: ObservableLike<ProductChatCustomMessageRenderSubscribeItem>;
  };
}
```

Usage remains close to an existing TrUAPI subscription:

```ts
const { requests, responses } = truapi.chat.customMessageRenderSubscribe();

responses.subscribe({
  next(item) {
    const node = render(item.messageType, item.payload);

    requests.next({
      tag: "Update",
      value: { messageId: item.messageId, node },
    });
  },
});
```

Subscribing to `responses` registers the renderer. A text-only Chat product
does not create these streams. Closing the Chat connection closes both; no
application-level start or stop value is required.

```text
Native platform                    Shared Rust HostRuntime                   Product worker
(Chat UI)                             (ProductRuntime)                      (worker/index.js)
       |                                      |                                     |
       |                                      | open renderer streams                |
       |                                      |<------------------------------------|
       |                                      | renderer streams are active          |
       |                                      |                                     |
       | display Custom(message_id,           |                                     |
       |   message_type, payload)             |                                     |
       | render_custom_message(...)           |                                     |
       |------------------------------------->|                                     |
       |                                      | render item { message_id,           |
       |                                      |   message_type, payload }           |
       |                                      |------------------------------------>|
       |                                      |                                     | decode payload
       |                                      |                                     | produce renderer tree
       |                                      | Update { message_id, node }         |
       |                                      |<------------------------------------|
       | typed CustomRendererNode             |                                     |
       |<-------------------------------------|                                     |
       | repaint native widget                |                                     |
       |                                      |                                     |
       |                                      |                                     | renderer state changes
       |                                      | Update { message_id, new_node }     |
       |                                      |<------------------------------------|
       | typed replacement node               |                                     |
       |<-------------------------------------|                                     |
       |                                      |                                     |
       | dismiss Chat UIView                  |                                     |
       | destroy native widget trees          | close Chat connection               |
       |------------------------------------->|------------------------------------>|
       |                                      |                                     | discard all renderer state
       |                                      |                                     |
```

The stored `message_id` correlates each render item, all of its `Update` values,
and widget actions. Native owns the lifecycle of cells, observers, and the
latest widget tree. Removing a native observer sends no product control
message. Product-side renderer state is scoped to the Chat connection and is
discarded when it closes. `Failed` ends only the matching native render stream;
it does not close the shared renderer streams.

`CustomRendererNode` crosses the native boundary as a generated Swift or Kotlin
type. SCALE hex strings and separately maintained native decoders are not part
of the interface.

## Native host contract

When the native host opens a Chat worker connection, `truapi-server` returns a
concrete `ProductRuntime` bound to that connection. Swift, Kotlin, or another
host binding retains this handle and uses it to send native events through
Rust to the product worker. It is not part of the product-facing TrUAPI API.

```rust
impl ProductRuntime {
    fn publish_chat_action(
        &self,
        action: HostChatActionSubscribeItem,
    ) -> Result<(), ProductRuntimeError>;

    fn render_custom_message(
        &self,
        message_id: String,
        message_type: String,
        payload: Vec<u8>,
    ) -> Result<PlatformStream<CustomRendererNode>, ProductRuntimeError>;
}
```

`publish_chat_action` covers both `MessagePosted` and `ActionTriggered` by
accepting the existing action enum. For example:

```text
Native Chat UI                 ProductRuntime                  Product worker
      |                              |                               |
      | user types "hello"           |                               |
      | publish_chat_action(...)     |                               |
      |----------------------------->|                               |
      |                              | MessagePosted(Text("hello"))  |
      |                              |------------------------------>|
      |                              | via chat_action_subscribe     |
      |                              |                               |
```

`render_custom_message` is called when a native cell needs to display a stored
custom message. It publishes a render item on the active product-initiated
response stream and returns a native stream fed by matching `Update` values
from the request stream. Native owns that stream's observers and rendered
views; dropping them sends nothing to the product.

In the opposite direction, product-originated room, message, and room-list
calls flow from Rust through the optional `ChatPlatform` adapter. Hosts install
it only when they provide native chat storage and UI:

```rust
pub trait ChatPlatform: Send + Sync {
    async fn create_room(
        &self,
        product: &ProductContext,
        request: CreateRoomRequest,
    ) -> Result<CreateRoomResponse, ChatPlatformError>;

    async fn post_message(
        &self,
        product: &ProductContext,
        request: PostMessageRequest,
    ) -> Result<PostMessageResponse, ChatPlatformError>;

    fn room_list(
        &self,
        product: &ProductContext,
    ) -> PlatformStream<ChatRoomList>;
}
```

`ChatPlatform` remains the adapter Rust invokes for product requests that
mutate or observe native Chat storage.

`ChatPlatform` identifies rooms by the trusted `ProductContext.product_id`
together with the product-local `room_id`. It must never treat a
product-supplied `room_id` as a globally authoritative native database key.
Message lookup and mutation are constrained to the same product namespace.

Exact UniFFI async-stream mechanics may use a generated callback handle, but
the values crossing the boundary remain generated typed values.

## Failure behavior

Policy and renderer-stream validation are enforced in Rust:

| Condition                                         | Result                                               |
| ------------------------------------------------- | ---------------------------------------------------- |
| Ordinary Chat call is not from a Chat execution   | `CallError::Denied`                                  |
| Ordinary Chat call has no `ChatPlatform` adapter  | `CallError::Unsupported`                             |
| Ordinary Chat call is unauthenticated             | Existing authentication failure                      |
| Native action targets a closed execution          | `ProductRuntimeError::Closed`                        |
| Native action fills the startup buffer            | `ProductRuntimeError::BufferFull`                    |
| Renderer is requested on a non-Chat connection    | `ProductRuntimeError::Denied`                        |
| Chat execution did not open renderer streams      | Rendering reports `ProductRuntimeError::Unsupported` |
| Product sends `Failed` for the message type       | Only that native render stream ends                  |
| Renderer node is malformed or exceeds host limits | Only that native render stream fails                 |
| A renderer-stream value cannot be decoded         | The renderer streams and render instances fail       |
| Product disconnects during rendering              | Its renderer streams and native streams terminate    |

Every call is scoped from `ProductContext`; product-supplied ids are
never used to select another product connection.

## References

- [Implementation plan](./chat-modality-shared-core-implementation-plan.md)
- [Product SDK design](./chat-modality-product-sdk.md)
- [TrUAPI Protocol Design](./truapi-protocol.md)
- [`Chat` Rust trait](../../rust/crates/truapi/src/api/chat.rs)
- [`CustomRendererNode` types](../../rust/crates/truapi/src/v01/chat/custom_renderer.rs)
- [Current iOS worker executor](../../hosts/ios/Packages/Products/Sources/Products/Services/ProductsScriptExecutor.swift)
- [Current iOS TrUAPI bridge](../../hosts/ios/Packages/Products/Sources/Products/Services/ProductTrUAPIHostBridge.swift)
