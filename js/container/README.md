# TrUAPI lockdown container

## Context

A TrUAPI host runs third-party **products**
inside a native web view — a `WKWebView` on iOS, an Android `WebView`. Each
product shares that web view with the host's own bridge to native code.

This package is the **lockdown container**: a small TypeScript program the host
injects into the product's web view as a `documentStart`, main-world script —
before any product code runs. It mutates the product's own `window` to remove or
gate the platform capabilities a product must not use freely. It ships as one
IIFE bundle per platform (built by `npm run build`).

## Problem

A product is untrusted code executing in the **same JavaScript realm** as the
host bridge. Two consequences follow:

1. **Ambient platform power must be removed.** A raw web view hands the product
   `fetch`, `XMLHttpRequest`, WebSocket, IndexedDB, service workers, iframes, and
   WebRTC — direct routes to the network, disk, and background execution that
   bypass the host's mediation.
2. **Some capabilities should be _gated_, not deleted.** WebRTC is legitimate
   _with the user's permission_. Deleting `RTCPeerConnection` outright (the blunt
   fix) makes it permanently unusable; the container should instead ask native
   for app-level permission on first use.

The threat model is adversarial and same-realm: a hostile product script must
not be able to **reach, replace, or wrap** a gated API to slip past it, nor
**forge a permission grant**. There is no cross-origin boundary to lean on —
everything lives in one realm the product also controls.

The two platforms also gate the network differently: iOS mediates it in JS;
Android mediates `fetch` in a native request interceptor. So the policy must be
**composable per platform**, not one-size-fits-all.

## Solution

### 1. Composable, per-platform lockdown

`lockdown.ts` exposes each isolation step as a standalone function; the
per-platform entry points (`index-ios.ts`, `index-android.ts`) compose the
subset their host needs. The only difference today is `fetch`:

| Step | iOS | Android |
|---|:--:|:--:|
| `gateWebSocketToBridge` — only the bridge URL is constructible | ✅ | ✅ |
| `deleteLegacyNetwork` — remove `XMLHttpRequest`, `EventSource` | ✅ | ✅ |
| `disableSendBeacon` | ✅ | ✅ |
| `gateFetchSameOrigin` | ✅ | ❌ native request interceptor |
| `gateStorage` — remove `indexedDB`, `caches` | ✅ | ✅ |
| `disableCookies` | ✅ | ✅ |
| `gateWorkers` — `SharedWorker`, service worker | ✅ | ✅ |
| `blockIframeCreation` | ✅ | ✅ |
| `installWebRtcGate` | ✅ | ✅ |

Every step (`index-ios.ts`, `index-android.ts`) redefines the global through `freeze.ts` (`freezeValue` /
`freezeAndDelete`) as a **non-configurable getter with a swallowed setter**, so
product code cannot reassign or delete it.

### 2. WebRTC permission gate

`RTCPeerConnection` is **not** deleted when a bridge is present — it is gated so
the product can use WebRTC once the user grants access. A connection is inert
until it touches the network, so the constructor stays ungated and the five
network-initiating async methods are gated: `createOffer`, `createAnswer`,
`setLocalDescription`, `setRemoteDescription`, `addIceCandidate`. On the first
such call per connection, the container asks the host for app-level access
(cached per connection); denial closes the connection and throws
`TypeError('WebRTC access is not allowed')`. With no bridge it falls back to
deleting the constructor (fail-closed).

The gate is patched **onto the native prototype in place** (non-configurable /
non-writable), and the native class itself is installed as
`window.RTCPeerConnection` — **not a subclass**. In the same realm as product
code this is the crucial detail: a subclass leaves the native method reachable
three ways (a deletable shadow, the ungated parent prototype, or the native
constructor recovered via the subclass `[[Prototype]]`), each a bypass. In place
there is no ungated method anywhere on the chain, nothing to delete or
overwrite, and no native twin to construct — and the original method is captured
into a closure the product cannot reach.

Camera and microphone (`navigator.mediaDevices.getUserMedia`) are **not** touched
here — they stay gated natively by the host (on iOS, the
`WKUIDelegate.webView(_:decideMediaCapturePermissionsFor:type:)` delegate; on
Android, `WebChromeClient.onPermissionRequest`).

### 3. Native bridge contract

The gate talks to native over a request/response channel. The envelope and reply
are identical on both platforms; only the outbound call differs.

- **JS → native (iOS):** `window.webkit.messageHandlers.__container__.postMessage(json)`
- **JS → native (Android):** `window.Android.call('__container__', json)` (an `@JavascriptInterface`)
  where `json = JSON.stringify({ type: 'request', id, method, params })`.
- **Native → JS reply (both):** `window.__container_callback__(id, payloadJson)`
  (iOS via `evaluateJavaScript`, Android via `evaluateJavascript`).
- **Method:** `allowWebRtcAccess`, params `{}`.
  - success: `{ "value": { "allowed": true | false } }`
  - error: `{ "error": { "code": string, "message": string } }` (a bare string is tolerated)
- **Channel discipline:** request/response only — never send `subscribe`/`update`/`complete`.

Each native side maps `allowWebRtcAccess` to its app-level WebRTC permission flow
and returns `allowed`.

### 4. Security model — same-realm spoof resistance

The lockdown runs in the **same realm** as product code, so
`window.__container_callback__` is reachable by the product. Forging an
`{ allowed: true }` reply requires a valid `(id, payload)` pair; three id-leak
channels are each closed:

| How a product could learn a valid id | Closed by |
|---|---|
| Guess / make the id predictable | 128-bit ids from a `crypto.getRandomValues` (and `Uint8Array`) **captured at init**, encoded with a hex lookup — no `Number.prototype.toString` / `padStart` / iterator on the path, so no global override can make ids deterministic |
| Read the outbound request | the id is serialized with a `JSON.stringify` **captured at init** and sent via the **captured** native sender (`webkit…postMessage` / `Android.call`) — neither the serializer nor the sender on the id's path is a global the product can override |
| Read the inbound reply by wrapping the dispatcher | frozen (non-configurable) `window.__container_callback__` |

The bundle is an IIFE, so `pending`, the captured RNG/serializer, and the
captured native sender live in a closure the product cannot reflect into. The
capture happens at `documentStart`, before any product script runs — so the fix
is init-capture, never deletion of the (legitimate) globals themselves.

**Residual limitation.** This resists overriding the globals on the id's path,
but not wholesale replacement of shared intrinsics the runtime uses internally
(e.g. `Map.prototype.get`, used by the pending-request table). That is the
inherent ceiling of a same-realm lockdown; the proper boundary is a
cross-realm/worker isolation the product cannot reach.

### Bootstrap guide (host integration)

The host is responsible for injecting the container and implementing the native
receiver. On iOS:

1. **Register the receiver** before loading the page:
   `userContentController.add(bridge, name: "__container__")`, where `bridge`
   handles `allowWebRtcAccess` and replies via
   `webView.evaluateJavaScript("window.__container_callback__(<id>, <payloadJson>)")`
   on the main thread.
2. **Inject scripts at `documentStart`, in order** — the localhost bootstrap
   (publishes `window.__truapi_localhost` for the WebSocket gate), then the
   container:

   ```swift
   let cc = WKUserContentController()
   cc.addUserScript(bootstrapUserScript)                          // publishes __truapi_localhost
   cc.add(bridge, name: "__container__")                          // native receiver
   cc.addUserScript(WKUserScript(source: try ContainerScriptBundle.load(),
                                 injectionTime: .atDocumentStart, forMainFrameOnly: true))
   let config = WKWebViewConfiguration(); config.userContentController = cc
   let webView = WKWebView(frame: .zero, configuration: config)
   bridge.webView = webView                                       // reply target
   webView.uiDelegate = mediaDelegate                            // camera/mic
   ```

   `ContainerScriptBundle.load()` (in `ios/truapi-host`) returns the built
   `truapi-container.js`. Android is the mirror: `addJavascriptInterface(bridge, "Android")`
   plus `WebViewCompat.addDocumentStartJavaScript(...)` for the container.
3. **Camera/mic** are handled by the media delegate, not the container.

If no `__container__` receiver is registered, `installWebRtcGate` fail-closes
(deletes `RTCPeerConnection`) — WebRTC is blocked but nothing else breaks.

### Build outputs

`npm run build` emits one bundle per platform:

- `build:ios` → `../../ios/truapi-host/Sources/TrUAPIHost/Resources/truapi-container.js`
  (loaded via `ContainerScriptBundle.load()`; the iOS `rebuild.sh` runs this).
- `build:android` → `../../android/truapi-host/src/main/assets/truapi-container.js`.

### Modules

- `freeze.ts` — `freezeValue` / `freezeAndDelete` primitives.
- `lockdown.ts` — the composable isolation steps.
- `index-ios.ts` / `index-android.ts` — per-platform entry points.
- `webrtc-manager.ts` — the in-place `RTCPeerConnection` gate + `createWebRtcAccessRequester(transport)`.
- `native-transport.ts` — request/response RPC (unguessable ids, `dispatch`).
- `bridge-contract.ts` — `installNativeBridge(send)`: transport + frozen reply callback; `HANDLER_NAME` / `CALLBACK_NAME`.
- `ios-bridge.ts` — `createIOSBridge()` (the only module touching `window.webkit`).
- `android-bridge.ts` — `createAndroidBridge()` (the only module touching `window.Android`).

### Develop

```bash
npm install
npm run typecheck
npm test        # bun test (src/**/*.test.ts)
npm run build   # both bundles (build:ios + build:android)
```
