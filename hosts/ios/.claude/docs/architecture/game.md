# DIM2 Game

## Overview

DIM2 game uses WebRTC for peer video and real-time data-channel messages. Game peer lifecycle policy belongs to the game layer; lower-level WebRTC creators expose connection primitives and state but do not own game reconnect policy.

## Key Components

### Modules
- `GameVideoService` — coordinates local capture, remote video tracks, gesture acceptance messages, connection state reporting, and explicit game disconnect
- `VideoGameConnectionManager` — reconciles active remote players with one `VideoGamePeerEngine` per peer, and bridges its synchronous public API to async peer lifecycle calls
- `VideoGamePeerEngine` — owns one peer context and forwards async peer APIs to it
- `VideoGamePeerEngineContextFactory` — builds per-peer context dependencies, including the combined peer component factory
- `VideoGamePeerComponentFactory` — creates both the game signaling session and one-shot connection flows for a peer lifecycle
- `VideoGamePeerSessionDelegate` — adapts MessageExchange callbacks into an incoming-envelope stream consumed by the context
- `VideoGamePeerEngineContext` — actor that owns peer lifecycle state, session, current connection flow, ordered incoming envelopes, offer tracking, and state publication
- `VideoGamePeerConnectionFlow` — owns one WebRTC connection generation: data channel setup, media setup, resource cleanup, and connection-state events
- `VideoGameSignalingSession` — actor that converts game signaling envelopes to `PeerConnectionSignal` and sends outgoing envelopes through MessageExchangeKit
- `ConnectionAttemptTracker` — stores offer IDs for game reconnection

## Peer Lifecycle

```
VideoGameConnectionManager
        ↓ one engine per remote player
VideoGamePeerEngine
        ↓ context lifecycle calls
VideoGamePeerEngineContext
        ↑ incoming envelopes from VideoGamePeerSessionDelegate
        ↓ sequential connection generations and state machine
VideoGamePeerConnectionFlow
        ↓ WebRTC generation
DataConnectionCreator → CallCreator → MultiplexedDataChannel
```

## Hard Rules

1. **One peer engine per remote player** — `VideoGameConnectionManager` owns add/remove reconciliation. Removing a peer disposes the engine; adding it again creates a fresh engine.
2. **Context owns mutable peer lifecycle state** — `VideoGamePeerEngineContext` is the synchronization point for session, current connection flow, incoming envelope ordering, offer tracking, state stream, and disposal.
3. **Engine context API is async** — engine async APIs await the context actor directly. The engine should not hide unstructured `Task {}` bridges internally.
4. **Reconnect is game policy** — the context validates reconnection messages and restarts the connection flow in order.
5. **Dispose is terminal** — after `VideoGamePeerEngineContext.dispose()`, the context is not restarted. New peer membership must create a new engine/context.
6. **MessageExchange callbacks stay lightweight** — `VideoGamePeerSessionDelegate` yields incoming envelopes into its stream and responds quickly; ordered processing happens inside the context lifecycle task.
7. **Transport creators do not own game reconnection** — `DataConnectionCreator`, `CallCreator`, and WebRTC wrappers should be cancelable/closable primitives. They should not persist game offer IDs or decide when to reconnect.
8. **Manager-owned one-shot tasks are only async bridges** — because `VideoGameConnectionManaging` is synchronous, `VideoGameConnectionManager` may launch short one-shot tasks to call async engine APIs. These tasks must not contain peer state-machine logic.
9. **Interactor deinit is the teardown fallback** — normal navigation throttles explicitly; deinit invokes the same teardown path as a safeguard.

## Connection Flow

1. Manager creates a `VideoGamePeerEngine` for each active remote player.
2. Manager starts the engine through an async bridge; the context starts once.
3. Context creates the `VideoGameSignalingSession` through `VideoGamePeerComponentMaking.makeSignalingSession()`.
4. Context starts the current `VideoGamePeerConnectionFlow` using `VideoGamePeerComponentMaking.makeConnectionFlow(session:)`.
5. The flow establishes data and media connections and reports state. The context tracks active offer IDs.
6. Incoming MessageExchange envelopes are yielded into the delegate stream in callback order.
7. Context checks each batch for accepted reconnection requests before delivering normal signaling into the session.
8. Reconnection cancels the current flow/resources, resets session signaling state, starts a fresh flow, and handles envelopes that followed the reconnection marker.
9. Manager disposes removed engines through async bridges. Terminal teardown clears offer IDs after disposal; resumable teardown preserves them.
10. Dispose stops incoming events, cancels lifecycle work, and closes flow resources.
11. Game disconnect removes remote tracks and stops local capture.
12. Engines may outlive their owners briefly while asynchronous disposal completes.

## Seams

| Seam                         | Where                         | When to touch                         |
|------------------------------|-------------------------------|---------------------------------------|
| Peer membership              | `VideoGameConnectionManager`  | Player set changes, add/remove policy |
| Peer lifecycle state         | `VideoGamePeerEngineContext`  | Setup/reconnect/dispose ordering      |
| Game signaling envelope rules | `VideoGameSignalingSession`   | Offer ID, reconnected, filtering      |
| WebRTC connection generation | `VideoGamePeerConnectionFlow` | Data/media setup behavior             |
| Gesture data-channel messages | `GameVideoService`            | Game message use cases                |
