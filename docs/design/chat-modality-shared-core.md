---
title: "Chat Modality on the Shared Rust Core"
type: design
status: accepted
created: 2026-07-30
---

# Chat Modality on the Shared Rust Core

## Summary

Chat products run on the same TrUAPI execution path as SPA products: the
visible app and a headless Chat worker are separate executions, each with its
own connection into a single host-owned Rust runtime, speaking the same
SCALE protocol and generated client. This replaces the mobile `container.js`
bridges and evaluated JavaScript globals.

Compared with the current mobile architecture, the shared-core integration
changes three things:

- Chat access becomes a connection policy. The host assigns an immutable
  `ProductExecutionKind`, and an `ExecutionFilter` rejects Chat traffic from
  other executions.
- Custom rendering replaces `renderMessage` and `chatRenderWidget` with one
  product-initiated bidirectional TrUAPI channel.
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
- `app/index.html` connects as `App`, while `worker/index.js` connects as
  `Chat`; both share host services

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

Chat is an API-backed modality with host-owned native UI. The DotNS
`includes.chat` declaration selects `worker/index.js`. The host loads it through
the existing WebSocket bootstrap and derives its context from the resolved
DotNS records. The
[Host Playground deployment config](https://github.com/paritytech/host-playground/blob/ab7ddb1476881a1ea3c77a4685f94a5ba60b6c72/bulletin-deploy.config.ts#L20-L42)
is a concrete example.

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
    /// Visible application entrypoint such as `app/index.html`.
    App,
    /// Host-embedded product widget entrypoint.
    Widget,
    /// Headless worker executable that provides the Chat modality.
    Chat,
}
```

The required execution kind is declared once on the API trait, and
`truapi-codegen` emits the matching server registration:

```rust
#[truapi::service(required_execution = Chat)]
pub trait Chat: Send + Sync {
    // requests, subscriptions, and channels
}
```

`truapi-server` builds `ExecutionFilter` from the immutable context when it
creates the connection's `ProductRuntime`. The filter runs before Chat
handlers, streams, and native entrypoints, so an `App` connection cannot carry
Chat traffic.

## Custom rendering

`custom_message_render_channel` is a bidirectional stream initiated by the
product. Native sends render work; the product responds with a complete
`CustomRendererNode` (`Update`) or rejects it (`Failed`). Later `Update`s for
the same `message_id` repaint the widget.

```rust
/// Serves custom-message rendering over a product-initiated channel.
async fn custom_message_render_channel(
    &self,
    _cx: &CallContext,
    requests: Subscription<ProductChatCustomMessageRenderChannelRequest>,
) -> Subscription<ProductChatCustomMessageRenderChannelItem>;

/// Values sent from the product to Rust on the renderer request stream.
pub enum ProductChatCustomMessageRenderChannelRequest {
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

/// Render item sent from Rust to the product on the renderer response stream.
pub struct ProductChatCustomMessageRenderChannelItem {
    /// Stable identifier used to correlate updates and triggered actions.
    pub message_id: String,

    /// Product-defined discriminator used to select a renderer.
    pub message_type: String,

    /// Stored product-defined message payload.
    pub payload: Vec<u8>,
}
```

The generated TypeScript API takes the request stream as an argument (any
observable source, such as an RxJS `Subject`) and returns the item stream:

```ts
export class ChatClient {
  customMessageRenderChannel(
    requests: ObservableSource<ProductChatCustomMessageRenderChannelRequest>,
  ): ObservableLike<ProductChatCustomMessageRenderChannelItem>;
}
```

```ts
import { Subject } from "rxjs";

const requests = new Subject<ProductChatCustomMessageRenderChannelRequest>();

truapi.chat.customMessageRenderChannel(requests).subscribe({
  next(item) {
    const node = render(item.messageType, item.payload);

    requests.next({
      tag: "Update",
      value: { messageId: item.messageId, node },
    });
  },
});
```

```text
Native platform                    Shared Rust HostRuntime                   Product worker
(Chat UI)                             (ProductRuntime)                      (worker/index.js)
       |                                      |                                     |
       |                                      | open renderer channel                |
       |                                      |<------------------------------------|
       |                                      | renderer channel is active           |
       |                                      |                                     |
       | native cell encounters stored        |                                     |
       | Custom(message_id, message_type,     |                                     |
       |   payload) and needs its UI           |                                     |
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
```

`message_id` correlates render work, updates, and widget actions. `Failed`
ends only that message's native render stream. Native receives generated
Swift or Kotlin renderer types, not SCALE hex or a separate decoder.

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
`render_custom_message` sends render work and returns the matching `Update`
stream. Native owns its observers and rendered views.

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

## Failure behavior

Rust enforces connection policy and renderer-stream validation.

| Condition                                         | Result                                               |
| ------------------------------------------------- | ---------------------------------------------------- |
| Ordinary Chat call is not from a Chat execution   | `CallError::Denied`                                  |
| Ordinary Chat call has no `ChatPlatform` adapter  | `CallError::Unsupported`                             |
| Ordinary Chat call is unauthenticated             | Standard authentication failure                      |
| Native action targets a closed execution          | `ProductRuntimeError::Closed`                        |
| Renderer is requested on a non-Chat connection    | `ProductRuntimeError::Denied`                        |
| Chat execution did not open the renderer channel  | Rendering reports `ProductRuntimeError::Unsupported` |
| Product sends `Failed` for a message              | Only that message's native render stream ends        |
| Renderer node is malformed or exceeds host limits | Only that native render stream fails                 |
| A renderer-channel value cannot be decoded        | The channel and active render instances fail         |
| Product disconnects during rendering              | Its channel and native render streams terminate      |

## References

- [TrUAPI Protocol Design](./truapi-protocol.md)
- [`Chat` Rust trait](../../rust/crates/truapi/src/api/chat.rs)
- [`CustomRendererNode` types](../../rust/crates/truapi/src/v01/chat/custom_renderer.rs)
- [iOS worker executor](../../hosts/ios/Packages/Products/Sources/Products/Services/ProductsScriptExecutor.swift)
- [iOS TrUAPI host bridge](../../hosts/ios/Packages/Products/Sources/Products/Services/ProductTrUAPIHostBridge.swift)
- [Android host adapter](../../android/truapi-host)
