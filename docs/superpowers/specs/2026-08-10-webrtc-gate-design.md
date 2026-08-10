# WebRTC permission gate in `js/container`

**Date:** 2026-08-10
**Status:** Design approved, pending implementation plan
**Scope:** `js/container` (TypeScript lockdown container) only

## Summary

Today the TrUAPI lockdown container hard-blocks WebRTC by deleting the
constructor (`freezeAndDelete(window, 'RTCPeerConnection')`, `js/container/src/index.ts:125`).
This design replaces that hard block with a **permission-gated
`RTCPeerConnection`** that asks the native iOS host for app-level WebRTC access
over a **new `WKScriptMessageHandler` bridge**, and installs the gated class
only when that bridge is present (otherwise it keeps deleting the constructor,
fail-closed).

Camera and microphone access via `navigator.mediaDevices.getUserMedia` is
**not** touched in JavaScript. It stays gated natively by the host's
`WKUIDelegate.webView(_:decideMediaCapturePermissionsFor:type:)`, which performs
the app-level and OS-level (`AVCaptureDevice.requestAccess`) prompts.

This mirrors the split used by the reference product container in
`polkadot-app-ios-v2` (`Packages/Products/product-container`): WebRTC gated in
JS via a message-handler bridge; camera/mic handled entirely by the native UI
delegate.

## Scope

**In scope** (`js/container` only):
- New `webrtc-manager.ts`, `native-transport.ts`, `ios-bridge.ts` modules.
- Rewire the `RTCPeerConnection` handling in `index.ts`.
- Unit tests and `js/container` test-runner setup.
- Documenting the bridge contract for the Swift implementer.

**Out of scope** (explicitly not in this plan):
- Swift / `ios/truapi-host` changes (the `WKScriptMessageHandler` receiver and
  the `WKUIDelegate` camera/mic handler). The bridge is defined here as a
  contract; the Swift side is implemented separately.
- Rust / TrUAPI wire-protocol changes. WebRTC permission rides the new
  message-handler channel, not the existing WebSocket wire protocol.
- Any JS override of `getUserMedia` / `navigator.mediaDevices`.
- Product isolation re-architecture (see "Trust model" below).

## Architecture

Three new platform-layered modules under `js/container/src/`, wired into the
existing `index.ts` lockdown.

### `webrtc-manager.ts` — platform-agnostic gated connection

Near-verbatim port of the reference `WebRtcManager`:

- `WebRtcManager` subclasses the native `RTCPeerConnection` and returns a
  `GatedRTCPeerConnection` from `connectionClass`.
- The five network-initiating async methods are gated:
  `createOffer`, `createAnswer`, `setLocalDescription`, `setRemoteDescription`,
  `addIceCandidate`. Each calls `ensureAllowed(this, method)` then delegates to
  `super`.
- Permission is requested **once per connection** and cached in a
  `WeakMap<object, Promise<boolean>>`.
- On denial: `connection.close()` then `throw new TypeError('WebRTC access is not allowed')`.
- The constructor is intentionally *not* gated — a peer connection is inert
  until an SDP/ICE method touches the network.
- Drop the reference's `console.log`/`console.warn` tracing.

```ts
export type WebRtcAccessRequester = () => Promise<boolean>;

export class WebRtcManager {
  readonly connectionClass: typeof RTCPeerConnection;
  constructor(nativeConnectionClass: typeof RTCPeerConnection, requestAccess: WebRtcAccessRequester);
}
```

### `native-transport.ts` — platform-agnostic, request/response only

A minimal RPC channel — one request, one reply, no streaming. The reference's
`subscribe`/`update`/`complete` machinery is deliberately omitted; the gate only
needs a single boolean call.

- `createNativeTransport(sendToNative): { callNative(method, params): Promise<any> }`.
- Outbound envelope: `{ type: 'request', id, method, params }`.
- Inbound envelopes: `{ value }` resolves, `{ error: { code, message } }`
  rejects (string error tolerated for robustness).
- `pending` is a `Map<string, { resolve, reject }>` keyed by id.
- Installs the reply dispatcher at `window.__truapi_container_callback__`
  (see hardening below).

**Contract boundary:** this channel is request/response only. The Swift receiver
must never send `subscribe`/`update`/`complete` frames on this handler. If
streaming is ever needed, the transport is extended then.

### `ios-bridge.ts` — the only module touching `window.webkit`

Owns everything iOS-`WKScriptMessageHandler`-specific and the security
hardening.

- `HANDLER_NAME = '__truapi_container__'` — single source of truth for the
  contract.
- `hasBridge(): boolean` — feature-detects
  `window.webkit?.messageHandlers?.[HANDLER_NAME]`.
- `createWebRtcAccessRequester(): WebRtcAccessRequester` — captures the native
  `postMessage` reference, builds the transport, installs the frozen callback,
  and returns
  `() => callNative('allowWebRtcAccess', {}).then(r => r?.allowed === true)`.

### `index.ts` — rewire (replaces line 125)

```ts
import { hasBridge, createWebRtcAccessRequester } from './ios-bridge';
import { WebRtcManager } from './webrtc-manager';

const _NativeRTC = window.RTCPeerConnection;
if (_NativeRTC && hasBridge()) {
  freezeValue(window, 'RTCPeerConnection',
    new WebRtcManager(_NativeRTC, createWebRtcAccessRequester()).connectionClass);
} else {
  freezeAndDelete(window, 'RTCPeerConnection'); // fail-closed: no bridge => WebRTC blocked as today
}
```

`index.ts` no longer references `window.webkit` directly; all bridge specifics
live in `ios-bridge.ts`. The gated class is installed via the existing
`freezeValue` (non-configurable getter), so product code cannot reassign
`RTCPeerConnection`.

## Bridge contract (for the separate Swift implementer)

- **Handler name:** `window.webkit.messageHandlers.__truapi_container__`
- **JS → native:** `postMessage(JSON.stringify({ type: 'request', id, method, params }))`
- **Native → JS reply:** `window.__truapi_container_callback__(id, payloadJson)`
  invoked via `evaluateJavaScript`.
- **Method:** `allowWebRtcAccess`, params `{}`, success reply
  `{ value: { allowed: boolean } }`, error reply
  `{ error: { code, message } }`.
- **Channel discipline:** request/response only — no `subscribe`/`update`/`complete`.

The Swift side maps `allowWebRtcAccess` to its app-level WebRTC permission flow
(and any OS considerations), returning `allowed: true|false`. That flow is out
of scope here.

## Data flow

1. Product calls a gated method, e.g. `pc.createOffer()`.
2. `GatedRTCPeerConnection` calls `ensureAllowed(pc, 'createOffer')`.
3. First touch per connection: `requestAccess()` →
   `callNative('allowWebRtcAccess', {})` → native `postMessage`.
4. Native decides (app-level WebRTC permission) and replies via
   `window.__truapi_container_callback__(id, '{"value":{"allowed":true}}')`.
5. Allowed → the promise resolves `true`, cached on the connection, and the
   method delegates to `super.createOffer(...)`. Denied → `pc.close()` + throw.
6. Subsequent gated calls on the same connection reuse the cached decision.

## Security hardening (same-realm spoof resistance)

The container's lockdown runs in the **same JS realm** as product code (a
main-world `WKUserScript`, `forMainFrameOnly: true`, no `WKContentWorld` — this
is required because the lockdown mutates the product's own `window`). Therefore
`window.__truapi_container_callback__` is reachable by product code, and the app-
level WebRTC gate must resist a hostile product forging an `{ allowed: true }`
reply. There is no other sanctioned path to self-grant this gate: the WebSocket
wire bridge speaks the TrUAPI protocol to the Rust core (no `allowWebRtcAccess`),
and the native `RTCPeerConnection` class is captured in a closure the product
cannot reach.

A forged reply requires the product to produce a **valid `(id, payload)` pair**.
Three independent id-leak channels must all be closed; each maps to one measure,
and none is redundant:

| Channel — how the product could learn a valid id | Closed by |
|---|---|
| **Guess** a sequential id (`r0`, `r1`, …) | **Unguessable ids** — 128-bit `crypto.getRandomValues` hex |
| Read it off the **outbound** request via a `postMessage` spy | **Captured native `postMessage`** bound into the module closure at init |
| Read it off the **inbound** reply by wrapping the dispatcher | **Frozen callback** — non-configurable/non-writable `window.__truapi_container_callback__` |

- **Unguessable ids:** ids are generated with `crypto.getRandomValues` (128-bit
  hex), not a sequential counter, so the product cannot guess a pending id.
- **Captured native `postMessage`:** `ios-bridge.ts` reads and binds
  `window.webkit.messageHandlers.__truapi_container__.postMessage` at init
  (before any product script runs, since the container injects at
  `documentStart`). All outbound calls use the captured reference, so a product
  that later Proxies `window.webkit.messageHandlers` cannot observe the id.
- **Frozen callback:** the dispatcher is installed with the existing
  `freezeValue` helper (non-configurable getter, ignored setter). The product
  cannot replace or wrap it, so it cannot interpose to read the id that native
  passes in. (The product can still *call* the frozen dispatcher, but without a
  valid id the call is inert.)

The bundle is already built as an IIFE (`esbuild --format=iife`), so `pending`,
the id source, and the captured `postMessage` live in a closure the product
cannot reflect into.

### Residual limitation (documented, not solved here)

This raises the bar very high **within one realm**; it is not a formal trust
boundary. Exotic intrinsic tampering (e.g. replacing `Map.prototype.get` before
the dispatcher calls it) remains the same class of concern as the whole
same-realm lockdown. The proper fix is converging the iOS host onto the web
host's model — the product in a **cross-origin iframe** under a host-controlled
top document, where the bridge, token, and native handlers live in a realm the
product cannot reach and communication is an unforgeable `postMessage` boundary.
`@parity/truapi-host`'s `/web` entry already uses this iframe + Web Worker model;
the iOS container is the outlier because it loads the product as the main frame.
That convergence is a significant, separate effort tracked outside this plan.

## Build

No build change. `esbuild --bundle` already follows the new `import`s from
`index.ts` into `truapi-container.js`. The output path and IIFE format are
unchanged.

## Testing

`js/container` currently has only `build` and `typecheck` scripts and no test
runner. This plan adds `bun test` (matching `js/packages/truapi`), a `test`
script, and unit tests:

- **`webrtc-manager`** with a mocked `WebRtcAccessRequester`:
  - granted → each gated method resolves and delegates to the native super
    method (spy on the native class);
  - denied → the connection is closed and the method rejects with
    `TypeError('WebRTC access is not allowed')`;
  - permission requested exactly once per connection (WeakMap cache), and a
    second connection triggers a second request.
- **`native-transport`** with a mock `sendToNative`:
  - `{ value }` resolves, `{ error: { code, message } }` rejects with `code`
    preserved;
  - concurrent in-flight calls resolve to their matching ids;
  - unknown/stale ids are ignored by the dispatcher.
- **`ios-bridge`** hardening:
  - ids are non-sequential and unique across calls;
  - outbound messages go through the *captured* `postMessage` even after
    `window.webkit.messageHandlers` is replaced post-init;
  - `window.__truapi_container_callback__` cannot be reassigned or deleted.

## Docs

- `js/container/README.md` (create if absent): document the `__truapi_container__`
  bridge contract, the `allowWebRtcAccess` method, the fail-closed behavior, and
  the same-realm security model with the residual limitation.
- Update the top-level `README.md` if the container's public behavior is
  described there.

## Open questions

None blocking. The Swift-side receiver and the future iframe-isolation
convergence are tracked as separate efforts.
