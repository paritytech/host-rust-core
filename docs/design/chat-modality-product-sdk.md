---
title: "Chat Modality Product SDK"
type: design
status: proposed
created: 2026-07-31
---

# Chat Modality Product SDK

## Summary

This document defines the product-side convenience API layered over the
generated TrUAPI Chat client. The underlying execution context, stream types,
message schemas, runtime policy, and native host contract are defined by
[Chat Modality on the Shared Rust Core](./chat-modality-shared-core.md).

The Product SDK owns:

- ordered Chat activation;
- custom renderer selection and React integration;
- widget-action routing to product callbacks;
- compatibility with the existing Triangle product API.

It does not add another transport or lifecycle protocol. All communication uses
the generated TrUAPI connection.

## Activation

The high-level entrypoint is:

```ts
await chat.start({
  onAction,
  renderCustomMessage,
});
```

`renderCustomMessage` is optional. `chat.start` performs the following ordered
setup:

```text
worker calls chat.start(...)
  -> install local action and renderer callbacks
  -> when a renderer is supplied:
       open custom_message_render_channel
  -> optionally open chat_list_subscribe
  -> open chat_action_subscribe last
  -> resolve
```

Installing callbacks before opening streams ensures the SDK can handle values
as soon as Rust delivers them. Native actions that arrive before
`chat_action_subscribe` opens remain in Rust's bounded connection-scoped
buffer. A text-only Chat product skips the renderer streams.

Module import starts the worker. `onBotStarted()` is not part of the new SDK.

## Custom renderer adapter

The SDK adapts the renderer request and response streams to the existing
product renderer model:

```text
render item(message_id, message_type, payload)
  -> select renderer by message_type
  -> decode payload
  -> mount the product React tree
  -> send Update(message_id, CustomRendererNode)

later React commit
  -> send another Update for the same message_id
```

If no renderer accepts `message_type`, the SDK sends `Failed { message_id }`.
That failure affects only the corresponding native render stream.

The React reconciler continues to produce complete `CustomRendererNode` trees.
Each `Update` replaces the previous native tree; products never manipulate
UIKit, SwiftUI, or Compose objects directly.

Native owns the lifecycle of emitted widget trees and sends no per-message
cleanup event. The SDK retains its React roots and action callbacks for the
Chat connection and releases all of them when that connection closes.

## Widget actions

Interactive renderer nodes contain opaque action identifiers such as
`click_action` or `value_change_action`. The SDK uses one
`chat_action_subscribe` stream for the Chat execution:

```text
ActionTriggered(message_id, action_id, payload)
  -> find the renderer state for message_id
  -> find the callback for action_id
  -> invoke the callback
  -> send any resulting renderer Update
```

The action identifier maps to an in-memory product callback; it is not a remote
callback reference. Input payloads such as text-field values are decoded before
the callback runs.

## Compatibility and migration

- Preserve `onCustomMessageRenderingRequest` as a facade over incoming renderer
  stream items.
- Keep the existing React reconciler and `CustomRendererNode` serializer.
- Remove the Chat dependency on `container.js` and direct JavaScript
  `evaluate` calls.
- Route every reply through the room id received in its action. Coin Flip must
  use `action.roomId` rather than its single-room constant.

The
[Coin Flip renderer](https://github.com/paritytech/coin-flip/blob/1158f534651537ed524db2a33735cc6841859757/worker/index.tsx#L31-L86)
is the reference migration: it decodes the stored result payload and renders
the flip count and result as a React tree.

## Verification

The Product SDK integration is complete when:

- `chat.start` installs callbacks before opening any stream;
- the optional renderer streams are opened before the action subscription;
- text-only products open only the action subscription;
- incoming render items select the correct message renderer;
- multiple React commits send ordered updates for the same message;
- an unknown message type sends `Failed` without closing the renderer streams;
- widget actions reach the correct message renderer and local callback;
- native widget cleanup sends no product control message;
- closing the Chat connection unmounts all React roots and removes all action
  callbacks;
- reconnecting establishes new streams and fresh renderer state;
- Coin Flip replies to the action's room id;
- no Chat path depends on `container.js` or JavaScript evaluation.

## References

- [Shared-core Chat protocol](./chat-modality-shared-core.md)
