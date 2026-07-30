# TrUAPI iOS host adapter

*Thin Swift shell over the Rust TrUAPI core (UniFFI). Wire decoding, request routing, and subscription lifecycle stay in the Rust core; products connect through the localhost WebSocket bridge.*

## What this package is for

The public surface lives in [`Sources/TrUAPIHost/TrUAPIHost.swift`](Sources/TrUAPIHost/TrUAPIHost.swift):

- `TrUAPIHostCore` - owning wrapper around the UniFFI-generated `NativeTrUApiCore`. Holds the callbacks alive for the lifetime of the core and exposes the localhost WebSocket bridge, session controls, and native change notifications for theme, preimage, and chain updates.
- `LocalhostBridgeBootstrap` - helper that produces a JS snippet publishing the WS bridge endpoint to the product page so it can dial back in.

The embedding app implements the UniFFI-generated `HostCallbacks` protocol directly (defined in `Sources/TrUAPIHost/truapi_server.swift`): navigation, push, permissions, auth state, scoped + core storage, chain JSON-RPC, confirmations, preimage, theme, and feature support. UI-decision callbacks are `async` and awaited by the Rust core.

The generated UniFFI bindings live alongside the shell in `Sources/TrUAPIHost/truapi_server.swift` and the C header / module map in `Sources/truapi_serverFFI/include/`. They are ignored build outputs; regenerate them before building or publishing the Swift package.

## Architecture

```text
product app in WKWebView
  Uint8Array frames via @parity/truapi createWebSocketProvider
           |
           v   ws://127.0.0.1:<port>/?t=<token>
TrUAPIHostCore.startWsBridge()
  → libtruapi_server (tokio WS server)
  → Rust dispatcher
```

The product running in the `WKWebView` opens a `WebSocket` to the localhost port + token returned by `startWsBridge`. From there the Rust core handles the wire protocol directly. Outbound responses and host-side capability callbacks (`navigateTo`, `pushNotification`, `cancelNotification`, `devicePermission`, `remotePermission`, `authStateChanged`, core storage, chain JSON-RPC, confirmations, preimage, theme, `featureSupported`, `storage`) reach the embedder through `HostCallbacks`.

## Permissions split

The core's `Permissions` platform trait has two methods, and so does `HostCallbacks`:

- `devicePermission(request:)` - OS-scoped grants (camera, mic, location, push). `request` is a SCALE-encoded `v01::HostDevicePermissionRequest`.
- `remotePermission(request:)` - per-product capability bundles. `request` is a SCALE-encoded `v01::RemotePermissionRequest`.

Both return a `Bool` granted flag. SCALE decoding for the UI prompt is done by the `@parity/truapi` JS client (or any consumer that links the protocol crate's types directly).

## Example

> **Threading:** the Rust core invokes every `HostCallbacks` method on a
> background thread it owns, never the main thread. Hop to the main thread
> (`MainActor` / `DispatchQueue.main`) before touching UIKit, WebKit, or the
> `WKWebView`. The `async` callbacks (`navigateTo`, `pushNotification`,
> `devicePermission`, `remotePermission`, `featureSupported`,
> `confirmUserAction`, `lookupPreimage`) are awaited by the core, so an
> implementation may suspend for as long as the user takes to decide (e.g.
> `await MainActor.run { ... }` or an `withCheckedContinuation` around a
> prompt); other TrUAPI traffic keeps flowing while you wait. The remaining
> sync callbacks (auth state, storage, core storage, chain, theme,
> `cancelNotification`) run inline on the dispatcher thread and must return
> promptly without blocking.

```swift
import Foundation
import WebKit
import TrUAPIHost

final class MyCallbacks: HostCallbacks, @unchecked Sendable {
    private var storage: [String: Data] = [:]
    private var coreStorage: [Data: Data] = [:]

    func onCoreLog(marker: String, detail: String) { /* log */ }

    func navigateTo(url: String) async throws {
        await MainActor.run { /* UIApplication.shared.open(...) */ }
    }

    func pushNotification(payload: Data) async throws -> UInt32 {
        let id: UInt32 = 1
        await MainActor.run { /* schedule notification */ }
        return id
    }

    func cancelNotification(id: UInt32) throws {
        DispatchQueue.main.async { /* cancel notification */ }
    }

    func devicePermission(request: Data) async throws -> Bool {
        // Awaited by the core: present the prompt and suspend until the user
        // decides. Other TrUAPI traffic keeps flowing while suspended.
        await MainActor.run { /* show prompt; */ false }
    }

    func remotePermission(request: Data) async throws -> Bool {
        await MainActor.run { /* show prompt; */ false }
    }

    // Core-owned auth state stream: render `.connected`/`.disconnected` as the
    // account badge and `.loginFailed` as a retryable error. This core is a
    // signing host — it owns the signer and never pairs — so `.pairing` and
    // `.authenticating` are not emitted and `core.cancelLogin()` is inert.
    // Activate the session with `core.activateLocalSession(secret:...)`.
    func authStateChanged(state: AuthState) {
        DispatchQueue.main.async { /* render the state */ }
    }

    func coreStorageRead(key: Data) throws -> Data? { coreStorage[key] }
    func coreStorageWrite(key: Data, value: Data) throws { coreStorage[key] = value }
    func coreStorageClear(key: Data) throws { coreStorage.removeValue(forKey: key) }

    func chainConnect(genesisHash: Data) throws -> UInt32? {
        let id: UInt32 = 1
        DispatchQueue.main.async { /* open JSON-RPC connection, forward responses via core.notifyChainResponse */ }
        return id
    }

    func chainSend(connectionId: UInt32, request: String) throws {
        /* send JSON-RPC request on the host connection */
    }

    func chainClose(connectionId: UInt32) throws {
        /* close host connection */
    }

    func confirmUserAction(review: Data) async throws -> Bool {
        await MainActor.run { /* render decoded UserConfirmationReview; */ false }
    }

    func lookupPreimage(key: Data) async throws -> Data? { nil }

    func currentTheme() throws -> HostTheme { .dark }

    func featureSupported(request: Data) async throws -> Bool { false }

    func localStorageRead(key: String) throws -> Data? { storage[key] }
    func localStorageWrite(key: String, value: Data) throws { storage[key] = value }
    func localStorageClear(key: String) throws { storage.removeValue(forKey: key) }
}

let callbacks = MyCallbacks()
let runtimeConfig = RuntimeConfig(
    productId: "my-product.dot",
    hostName: "My Host",
    hostIcon: "https://host.example/icon.png",
    peopleChainGenesisHash: Data(repeating: 0, count: 32),
    bulletinChainGenesisHash: Data(repeating: 0, count: 32),
    pairingDeeplinkScheme: .polkadotApp
)
let core = try TrUAPIHostCore(callbacks: callbacks, runtimeConfig: runtimeConfig)
try core.activateLocalSession(secret: entropyBytes, liteUsername: nil)
let endpoint = try core.startWsBridge()

// Call these from host/platform observers so native subscriptions see updates
// after their immediate current item.
core.notifyThemeChanged(theme: .dark)
core.notifyPreimageChanged(key: preimageKey, value: preimageBytesOrNil)
core.notifyChainResponse(connectionId: chainConnectionId, json: jsonRpcResponse)
core.notifyChainClosed(connectionId: chainConnectionId)

let contentController = WKUserContentController()
let bootstrapScript = LocalhostBridgeBootstrap.script(port: endpoint.port, token: endpoint.token)
let userScript = WKUserScript(
    source: bootstrapScript,
    injectionTime: .atDocumentStart,
    forMainFrameOnly: true
)
contentController.addUserScript(userScript)

let configuration = WKWebViewConfiguration()
configuration.userContentController = contentController
let webView = WKWebView(frame: .zero, configuration: configuration)
webView.load(URLRequest(url: URL(string: "https://your-product.example/")!))

// On logout:
core.disconnect()
```

The product page reads `window.__truapi_localhost.url` (set by the bootstrap script) and passes it to `@parity/truapi`'s `createWebSocketProvider(url)`.

## Linking the cdylib

This package does not vendor `libtruapi_server` - integrators link a prebuilt static or dynamic library when building the app target. Typical workflow:

```bash
cargo build -p truapi-server --release --features ws-bridge \
  --target aarch64-apple-ios
cargo build -p truapi-server --release --features ws-bridge \
  --target aarch64-apple-ios-sim
```

Then either bundle the `.a` files as a `.xcframework` and add it under "Frameworks, Libraries, and Embedded Content" in the app target, or link directly via `OTHER_LDFLAGS`.

## Regenerating the bindings

The ignored bindings under `Sources/TrUAPIHost/truapi_server.swift` and `Sources/truapi_serverFFI/include/` are produced from the workspace `uniffi-bindgen-cli`. Regenerate them before building or publishing the Swift package. The CLI emits `truapi_server.swift`, `truapi_serverFFI.h`, and `truapi_serverFFI.modulemap` into a single output directory; the modulemap is renamed to `module.modulemap` and the header is colocated under `Sources/truapi_serverFFI/include/` so SwiftPM's `systemLibrary` target picks them up.

```bash
cargo build -p truapi-server --release --features ws-bridge
mkdir -p /tmp/uniffi-swift-out
cargo run -p uniffi-bindgen-cli -- generate \
  --library target/release/libtruapi_server.so \
  --language swift \
  --out-dir /tmp/uniffi-swift-out
cp /tmp/uniffi-swift-out/truapi_server.swift \
   ios/truapi-host/Sources/TrUAPIHost/truapi_server.swift
cp /tmp/uniffi-swift-out/truapi_serverFFI.h \
   ios/truapi-host/Sources/truapi_serverFFI/include/truapi_serverFFI.h
cp /tmp/uniffi-swift-out/truapi_serverFFI.modulemap \
   ios/truapi-host/Sources/truapi_serverFFI/include/module.modulemap
```

Or run `make uniffi` from the repo root.
