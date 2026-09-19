---
"@parity/truapi": minor
"@parity/truapi-host": minor
---

Authorize browser fetch, asynchronous XHR, WebSocket connections, media capture and WebRTC through the internal `authorize_remote_permission` and `authorize_device_permission` APIs. Install the shared sandbox in native product views. Synchronous XHR, `Worker`, `WebTransport` and `getDisplayMedia` screen capture are unavailable.

Camera and microphone grants are consumed per capture attempt, camera first. A later microphone denial or native capture failure does not restore an already consumed grant. Product consent is enforced by the container; native media delegates enforce OS permission separately.

Update native integrations: Swift `installProductScripts(into:endpoint:)` now takes a `WKWebView` and is synchronous, without an execution argument. Swift and Kotlin `LocalhostBridgeBootstrap.script` no longer take `webRtcAllowed`.
