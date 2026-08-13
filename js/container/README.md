# TrUAPI lockdown container

TypeScript lockdown injected as a `documentStart` main-world `WKUserScript` into
the iOS host web view. It runs after the native `LocalhostBridgeBootstrap` and
locks down platform globals so product scripts cannot reach network, storage,
worker, or DOM-embedding APIs. `npm run build` bundles `src/index.ts` into an
IIFE at `../../ios/truapi-host/Sources/TrUAPIHost/Resources/truapi-container.js`.

## Modules

- `freeze.ts` — `freezeValue` / `freezeAndDelete`: make a property
  non-configurable (getter + swallowed setter) so product code cannot replace it.
- `index.ts` — the lockdown sequence.
- `webrtc-manager.ts` — permission-gated `RTCPeerConnection` plus
  `createWebRtcAccessRequester(transport)`, which adapts any `NativeTransport`
  into the manager's requester via the `allowWebRtcAccess` contract method.
  Fully platform-agnostic.
- `native-transport.ts` — request/response RPC over an opaque native channel.
- `bridge-contract.ts` — the shared `HANDLER_NAME` / `CALLBACK_NAME` and
  `installNativeBridge(send)`, which builds the `NativeTransport` and installs
  the frozen reply callback. The per-platform bridges differ only in how they
  capture their outbound channel; everything downstream is shared.
- `ios-bridge.ts` — the only module touching `window.webkit`.
  `createIOSNativeBridge()` captures `WKScriptMessageHandler.postMessage`.
- `android-bridge.ts` — the only module touching `window.Android` (the
  `@JavascriptInterface`). `createAndroidNativeBridge()` captures `Android.call`.
- `native-bridge.ts` — `createNativeBridge()`: the shared transport for the
  first available bridge (iOS, then Android). Reused by every gated native API.

## WebRTC gating

`RTCPeerConnection` is **not** deleted outright. When a native container bridge
is present (iOS or Android), the container installs a gated subclass in its
place; otherwise it deletes the constructor (fail-closed — WebRTC blocked).

A peer connection is inert until it touches the network, so the constructor is
ungated. The five network-initiating async methods — `createOffer`,
`createAnswer`, `setLocalDescription`, `setRemoteDescription`,
`addIceCandidate` — are gated. On first such call per connection the container
asks the host for app-level WebRTC access; the decision is cached per
connection. Denial closes the connection and throws
`TypeError('WebRTC access is not allowed')`.

Camera and microphone (`navigator.mediaDevices.getUserMedia`) are not touched
here — they stay gated natively by the host (on iOS, the
`WKUIDelegate.webView(_:decideMediaCapturePermissionsFor:type:)` delegate).

## Bridge contract (native side)

The JS → native envelope and the native → JS reply are identical on both
platforms; only the outbound channel differs.

- **JS → native (iOS):** `window.webkit.messageHandlers.__container__.postMessage(json)`
- **JS → native (Android):** `window.Android.call('__container__', json)`
  (an `@JavascriptInterface`), where `json = JSON.stringify({ type: 'request', id, method, params })`.
- **Native → JS reply (both):** invoke `window.__container_callback__(id, payloadJson)`
  (iOS via `evaluateJavaScript`, Android via `evaluateJavascript`).
- **Method:** `allowWebRtcAccess`, params `{}`.
  - success reply payload: `{ "value": { "allowed": true | false } }`
  - error reply payload: `{ "error": { "code": string, "message": string } }`
    (a bare string error is tolerated).
- **Channel discipline:** request/response only — never send
  `subscribe`/`update`/`complete` frames on this handler.

Each native side maps `allowWebRtcAccess` to its app-level WebRTC permission
flow and returns `allowed: true | false`.

## Security model (same-realm spoof resistance)

The lockdown runs in the **same JS realm** as product code (a main-world script
that mutates the product's own `window`), so
`window.__container_callback__` is reachable by product code. A hostile
product forging an `{ allowed: true }` reply would need a valid `(id, payload)`
pair. Three id-leak channels are each closed:

| How a product could learn a valid id | Closed by |
|---|---|
| Guess a sequential id | 128-bit `crypto.getRandomValues` hex ids |
| Read the outbound request via an outbound-channel spy | the native sender (`webkit…postMessage` / `Android.call`) captured into the module closure at init |
| Read the inbound reply by wrapping the dispatcher | frozen (non-configurable) `window.__container_callback__` |

The bundle is an IIFE, so `pending`, the id source, and the captured native
sender live in a closure the product cannot reflect into.

## Develop

```bash
npm install
npm run typecheck
npm test        # bun test (src/**/*.test.ts)
npm run build   # esbuild IIFE bundle into the iOS host resources
```
