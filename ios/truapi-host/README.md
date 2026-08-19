# TrUAPI iOS host adapter

*Thin Swift shell over the Rust TrUAPI core (UniFFI). Wire decoding, request routing, and subscription lifecycle stay in the Rust core; products connect through the localhost WebSocket bridge.*

The package lives in the truapi repo next to the Rust core it wraps. `Package.swift` sits at the **repo root** (SPM requires that for git-URL dependencies), with all target paths pointing into `ios/truapi-host/`; the build scripts regenerate the committed outputs from this repo's workspace.

## What this package is for

The `TrUAPIHost` SPM package an iOS host app imports directly. It carries:

- [`Sources/TrUAPIHost/TrUAPIHost.swift`](Sources/TrUAPIHost/TrUAPIHost.swift) — the hand-written shell: `TrUAPIHostCore` (owning wrapper around the UniFFI-generated `NativeTrUApiCore`, with the localhost WS bridge, session controls, and native change notifications), `TrUAPIHostCoreProtocol`, `RuntimeConfig`, and `LocalhostBridgeBootstrap`.
- [`Sources/TrUAPIHost/ProductScripts.swift`](Sources/TrUAPIHost/ProductScripts.swift) — `TrUAPIHost.installProductScripts(into:core:endpoint:)`, which registers the bootstrap and the lockdown container with the frame scopes the lockdown depends on and peeks the WebRTC decision. The supported way to wire a product web view.
- the Rust core as a binary target — a GitHub release asset by default (`publishedBinaryURL` in the root `Package.swift`), or the locally built `Binaries/truapi_server.xcframework` when `useLocalBinary` is flipped to true.
- `Sources/TrUAPIHost/truapi_server.swift` and `Sources/truapi_serverFFI/include/` — the generated UniFFI bindings.
- [`js/container/`](../../js/container) — the TS lockdown container; built into `Sources/TrUAPIHost/Resources/truapi-container.js` and exposed via `ContainerScriptBundle.load()`.
- `Tests/` — WS-bridge round-trip tests that boot the real Rust core.

The generated bindings and the container bundle are committed build outputs; the xcframework is **gitignored** and distributed as a GitHub release asset. Two scripts split the lifecycle:

```bash
./scripts/rebuild.sh            # regenerate xcframework + bindings + container
                                # from this repo (make xcframework at the root)
./scripts/publish.sh <version>  # zip the built xcframework, upload it to the
                                # "@parity/ios-host <version>" GitHub release,
                                # and point the root Package.swift at it
                                # (URL + checksum)
```

When only the bindings need refreshing — a Rust surface change with no container
or xcframework impact — skip the full rebuild, which needs Xcode and the iOS
targets:

```bash
# from the repo root
make uniffi && ./ios/truapi-host/scripts/sync-bindings.sh
```

CI's `iOS bindings (uniffi)` job runs the same two commands with
`sync-bindings.sh --check`, which diffs the committed bindings against freshly
generated ones and writes nothing. It runs on Linux, so it verifies the
generated files only.

The hand-written conformers in `TrUAPIHost.swift` and `Tests/` are covered by
the `iOS package (swift compile)` job instead, which builds a simulator-only
debug XCFramework from the pull request source and runs `xcodebuild
build-for-testing`. It is path-filtered to pull requests touching `ios/`,
`Package.swift`, the `Makefile` or `rust/crates/truapi-server/src/native*`.
Nothing compiles `TrUAPIHost.kt` or the embedding apps.

Run `rebuild.sh` after changing anything host-visible — the `NativeTrUApiCore` methods, `HostCallbacks`, the native mirror types in `rust/crates/truapi-server/src/native*`, or `js/container/src` — and commit the regenerated bindings/container together with the source change. To publish from a release PR, add `@parity/ios-host <version>` to its `release:` title. After the release commit passes CI, the release workflow rebuilds and simulator-tests the XCFramework on macOS, uploads it, and makes the `Package.swift` follow-up commit only after the asset is live. `publish.sh` remains available for an ad hoc manual release.

For local iteration without publishing, flip `useLocalBinary = true` in the root `Package.swift` to build against `Binaries/` directly; flip it back before committing.

The embedding app implements `HostBridge` (defined in `TrUAPIHost.swift`): navigation, push, permissions, auth state, scoped + core storage, chain JSON-RPC, confirmations, preimage, theme, feature support, and the served chain set. UI-decision callbacks are `async` and awaited by the Rust core. `HostCallbackAdapter` translates it to the UniFFI-generated `HostCallbacks` protocol, and both `TrUAPIHostRuntime` and `TrUAPIHostCore` take a `HostBridge`. Conform to `HostBridge` rather than to the generated protocol: its extension defaults the optional callbacks, so a newly added one does not break the build. Storage arrives as the `storage` and `coreStorage` sub-objects, which the adapter flattens.

## Integrating in an iOS app

Add the package as an SPM dependency and link the `TrUAPIHost` product into the app target:

```swift
.package(url: "https://github.com/paritytech/host-rust-core.git", branch: "main")
```

```swift
.product(name: "TrUAPIHost", package: "truapi")
```

Release tags follow the repo-wide `@parity/ios-host@<version>` naming, which SPM's semver resolution does not consume — depend by `branch:` or `revision:` instead. SPM pins the resolved revision in the app's `Package.resolved`; update it (File > Packages > Update in Xcode, or `xcodebuild -resolvePackageDependencies`) after new commits land on the branch.

Run the package tests against an iOS simulator (the xcframework has no macOS slice):

```bash
# from the repo root
xcodebuild test -scheme TrUAPIHost -destination 'platform=iOS Simulator,name=iPhone 16'
```

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

- `devicePermission(request:)` - OS-scoped grants (camera, mic, location, push). `request` is a typed `HostDevicePermissionRequest`.
- `remotePermission(request:)` - per-product capabilities. `request` is a typed `RemotePermission`.

Both return a `Bool` granted flag; the host renders the typed request in its own prompt UI. The same typed values drive the `TrUAPIHostCore` permission admin API (`permissionAuthorizationStatus`, `setPermissionAuthorizationStatus`), which reads and updates the persisted decisions without prompting.

## SSO session handling

`TrUAPIHostRuntime` exposes two methods for wallet-owned SSO sessions. Meaningful request answering requires `activateLocalSession` to have been called first; `prepareDisconnectRequest` needs no session.

```swift
func handleSsoRequest(message: Data) async throws -> SsoRequestOutcome
func prepareDisconnectRequest() -> Data
```

`handleSsoRequest(message:)` takes one SCALE-encoded `RemoteMessage` exactly as decrypted from the statement-store session and routes it through the Rust core. The returned `SsoRequestOutcome` is the generated UniFFI enum (no Swift mirror):

- `.response(message:)` — SCALE-encoded reply; post it back over the same session.
- `.disconnected` — the peer ended the session; tear down the transport and records on the wallet side.
- `.ignored` — the message was not a request; nothing to post.

Confirmation-gated requests suspend on `confirmUserAction`, so `handleSsoRequest` can take arbitrarily long. Always call it from a `Task`, never the main thread.

`prepareDisconnectRequest()` returns the SCALE-encoded `Disconnected` message to post when the wallet is ending the session. Posting and record cleanup (host entry, device record, device-removed broadcast) stay with the wallet.

## Statement-store allowance renewal

Statement-store allowances are granted per period, so a host has to re-register the accounts it wants to keep writing. They are not revoked the moment the period ends: `Resources.StmtStoreGraceWindow` keeps an ended period's allowances active until cleanup catches up, 48 hours on `paseo-next-v2`. The runtime owns the ledger and the registration; the app owns only the schedule.

Record the accounts to keep allowed. This needs an active session, so call it after `activateLocalSession` or after pairing, not at construction:

```swift
try runtime.trackStatementRenewalTargets([
    .walletSso,
    .account(accountId: deviceStatementKey, label: "device"),
])
```

The ledger persists across launches, and it is append-only: there is no untrack, and an entry is dropped only when the identity that promised it changes. `.walletSso` and `.productStatementAllowance` are derivation recipes, so they survive that; `.account` carries a fixed account id and does not. A dropped target is listed in `report.pruned`, which is how a host learns to re-track one and keep renewal covering it. There is still no reader and no untrack on this surface, so a host cannot list what is tracked or remove a wrong entry. Re-tracking is idempotent, so the safe habit is to re-track the full set after every identity change rather than trying to reason about what survived.

Then run a pass from a background task, off the main thread. It needs an active session too, which is the whole difficulty here: a `BGTaskScheduler` wake on a cold start has none until you restore one, and the pass then fails with the bare reason `Disconnected`. Restore the session first, and read that reason as "not ready" rather than as a renewal failure. `startStatementAllowanceRenewal()` does not need this care, since its loop skips a tick with no session and retries.

```swift
let report = try runtime.renewStatementAllowances()
for outcome in report.outcomes {
    log("\(outcome.label): \(outcome.status)")
}
for label in report.pruned {
    // Promised by a previous identity and discarded; re-track to keep it renewed.
    log("dropped: \(label)")
}
if report.slotsExhausted {
    // Every slot for this period is taken and none was replaceable.
}
```

One scheduled pass per period is enough, with room to spare: an allowance stays usable for `Resources.StmtStoreGraceWindow` past its boundary, which is 48 hours on `paseo-next-v2`, so a missed wake-up is recoverable rather than fatal. `nextStatementRenewalDelay()` reports the in-process loop's retry cadence, capped at an hour; a `BGTaskScheduler` host should read a value under an hour as the boundary approaching rather than requesting a wake-up every hour for a pass that will almost always report `alreadyAllocated`.

`startStatementAllowanceRenewal()` runs the same pass on an in-process loop instead. It suits a host that stays resident; on iOS a suspended app stops ticking, so prefer `BGTaskScheduler` driving the one-shot call. A pass has no cancellation, so several targets can outlast a short background budget; targets registered before the process is killed are not lost, and read back as already allocated next time.

An account id must be exactly 32 bytes. Anything else is rejected as `NativeRenewalTargetError.InvalidAccountId` before any chain work happens.

`TrUAPIHostCore` exposes the same four calls for hosts that use it instead of `TrUAPIHostRuntime`.

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

    func pushNotification(request: HostPushNotificationRequest) async throws -> UInt32 {
        let id: UInt32 = 1
        await MainActor.run { /* schedule request.text / request.deeplink / request.scheduledAt */ }
        return id
    }

    func cancelNotification(id: UInt32) throws {
        DispatchQueue.main.async { /* cancel notification */ }
    }

    func devicePermission(request: HostDevicePermissionRequest) async throws -> Bool {
        // Awaited by the core: present the prompt and suspend until the user
        // decides. Other TrUAPI traffic keeps flowing while suspended.
        await MainActor.run { /* show prompt for request (.camera, .microphone, ...); */ false }
    }

    func remotePermission(request: RemotePermission) async throws -> Bool {
        await MainActor.run { /* show prompt for request (.chainSubmit, .remote(domains:), ...); */ false }
    }

    // Core-owned auth state stream: render `.connected`/`.disconnected` as the
    // account badge and `.loginFailed` as a retryable error, unless its `kind`
    // is `.noFreeAllowanceSlots`, which is unlikely to succeed before the
    // period rolls over, so retry should not be the primary action. This core
    // is a signing host — it owns the signer and never
    // pairs — so `.pairing` and `.authenticating` are not emitted and
    // `core.cancelLogin()` is inert.
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

    func confirmUserAction(review: UserConfirmationReview) async throws -> Bool {
        // Switch on the review variant (.signPayload, .createTransaction, ...)
        // to render the confirmation prompt with its typed fields.
        await MainActor.run { /* render review; */ false }
    }

    func lookupPreimage(key: Data) async throws -> Data? { nil }

    func currentTheme() throws -> ThemeVariant { .dark }

    func featureSupported(request: HostFeatureSupportedRequest) async throws -> Bool { false }

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

// Register the bootstrap + lockdown container before the web view loads the
// product page. `installProductScripts` owns the two properties that are easy to
// get wrong and silently fatal: the container goes into EVERY frame (a frame
// without it has pristine fetch/WebSocket/RTCPeerConnection, and a product
// reaches one through an `<iframe>` in its own HTML), while the bootstrap stays
// main-frame-only so a subframe has no bridge and no policy and fails closed. It
// also resolves the WebRTC decision by peeking the core rather than prompting.
// Do not register these scripts by hand.
let contentController = WKUserContentController()
try TrUAPIHost.installProductScripts(
    into: contentController,
    core: core,
    endpoint: endpoint
)

let configuration = WKWebViewConfiguration()
configuration.userContentController = contentController
let webView = WKWebView(frame: .zero, configuration: configuration)
webView.load(URLRequest(url: URL(string: "https://your-product.example/")!))

// On logout:
core.disconnect()
```

The product page reads `window.__truapi_localhost.url` (set by the bootstrap script) and passes it to `@parity/truapi`'s `createWebSocketProvider(url)`.

## Build outputs in detail

`./scripts/rebuild.sh` orchestrates everything; the underlying pieces, should you need one in isolation:

- **xcframework** — `make xcframework` (repo root) builds `truapi-server` for `aarch64-apple-ios` and `aarch64-apple-ios-sim` and bundles `target/truapi_server.xcframework`; the script copies it into `Binaries/` and strips the per-slice `module.modulemap` (module resolution comes from the `systemLibrary` target; the slice copy collides with other xcframeworks in Xcode's flat include dir).
- **bindings** — `make uniffi` (run automatically by `make xcframework`) emits the Swift bindings into `target/uniffi-swift-out/` via the workspace `uniffi-bindgen-cli`; `scripts/sync-bindings.sh` copies them into `Sources/TrUAPIHost/truapi_server.swift` and `Sources/truapi_serverFFI/include/`, renaming the emitted `truapi_serverFFI.modulemap` to `module.modulemap` so the SwiftPM `systemLibrary` target picks it up. `rebuild.sh` calls it, and CI's `--check` mode compares against it.
- **container** — `npm run build` in `js/container/` (repo root) bundles `src/index.ts` into `Sources/TrUAPIHost/Resources/truapi-container.js`.
