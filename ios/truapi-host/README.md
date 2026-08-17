# TrUAPI iOS host adapter

*Thin Swift shell over the Rust TrUAPI core (UniFFI). Wire decoding, request routing, and subscription lifecycle stay in the Rust core; products connect through the localhost WebSocket bridge.*

The package lives in the truapi repo next to the Rust core it wraps. `Package.swift` sits at the **repo root** (SPM requires that for git-URL dependencies), with all target paths pointing into `ios/truapi-host/`; the build scripts regenerate the committed outputs from this repo's workspace.

## What this package is for

The `TrUAPIHost` SPM package an iOS host app imports directly. It carries:

- [`Sources/TrUAPIHost/TrUAPIHost.swift`](Sources/TrUAPIHost/TrUAPIHost.swift) — the hand-written shell: `TrUAPIHostRuntime`, `TrUAPIProductExecution`, their configuration and bridge protocols, and `LocalhostBridgeBootstrap`.
- [`Sources/TrUAPIHost/ProductScripts.swift`](Sources/TrUAPIHost/ProductScripts.swift) — `TrUAPIHost.installProductScripts(into:execution:endpoint:)`, which registers the bootstrap and the lockdown container with the frame scopes the lockdown depends on and peeks the WebRTC decision. The supported way to wire a product web view.
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

Run `rebuild.sh` after changing anything host-visible — the `NativeTrUApiHostRuntime` or `NativeProductExecution` methods, `HostCallbacks`, the native mirror types in `rust/crates/truapi-server/src/native*`, or `js/container/src` — and commit the regenerated bindings/container together with the source change. To publish from a release PR, add `@parity/ios-host <version>` to its `release:` title. After the release commit passes CI, the release workflow rebuilds and simulator-tests the XCFramework on macOS, uploads it, and makes the `Package.swift` follow-up commit only after the asset is live. `publish.sh` remains available for an ad hoc manual release.

For local iteration without publishing, flip `useLocalBinary = true` in the root `Package.swift` to build against `Binaries/` directly; flip it back before committing.

The embedding app implements `HostBridge` (defined in `TrUAPIHost.swift`): navigation, push, permissions, auth state, scoped + core storage, chain JSON-RPC, confirmations, preimage, theme, feature support, and the served chain set. UI-decision callbacks are `async` and awaited by the Rust core. `HostCallbackAdapter` translates it to the UniFFI-generated `HostCallbacks` protocol; `TrUAPIHostRuntime` and each product execution retain their own adapter. Conform to `HostBridge` rather than to the generated protocol: its extension defaults the optional callbacks, so a newly added one does not break the build. Storage arrives as the `storage` and `coreStorage` sub-objects, which the adapter flattens.

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

## Chat

A host serving the Chat modality implements `ChatHostBridge` and opens the
execution with `ProductExecutionKind.chat`. Hosts without it pass nothing and
Chat calls answer unsupported.

```swift
// Called from a shared dispatch pool, so the backing store must be
// thread-safe, and a slow call here stalls other product executions.
final class MyChatBridge: ChatHostBridge, @unchecked Sendable {
    private let store: ChatStore

    init(store: ChatStore) { self.store = store }

    func createRoom(roomId: String, name: String, icon: String) throws
        -> ChatRoomRegistrationStatus
    {
        store.putRoom(roomId, name: name, icon: icon) ? .new : .exists
    }

    func registerBot(botId: String, name: String, icon: String) throws
        -> ChatBotRegistrationStatus
    {
        store.putBot(botId, name: name, icon: icon) ? .new : .exists
    }

    func postMessage(roomId: String, content: ChatMessageContent) throws -> String {
        if case .file = content {
            // Declining a variant is how a host opts out of rendering one.
            // Throw `HostRejection.Rejected` (or a `LocalizedError`) so the
            // product receives your reason rather than a bare type name.
            throw HostRejection.Rejected(reason: "this host cannot render file cards")
        }
        return store.append(roomId, content: content)
    }

    func listRooms() throws -> [ChatRoom] { store.rooms() }
}

let runtime = try TrUAPIHostRuntime(
    bridge: bridge,
    runtimeConfig: HostRuntimeConfig(
        hostName: "My Chat Host",
        peopleChainGenesisHash: peopleChainGenesisHash,   // exactly 32 bytes
        bulletinChainGenesisHash: bulletinChainGenesisHash
    )
)
// Chat needs an active session; without one every Chat call answers denied.
try runtime.activateLocalSession(secret: secret)

let execution = try runtime.openProductExecution(
    bridge: bridge,
    configuration: ProductExecutionConfig(productId: "chat.dot", executionKind: .chat),
    chat: MyChatBridge(store: store)
)
let endpoint = try execution.startWsBridge()
```

The core bounds and screens the product-supplied fields it forwards — ids,
names, icons, message bodies, URLs, and the action and media counts. Ids and
names are also normalized; a message body is bounded and screened but passed
through byte-for-byte, and `ChatFile.sizeBytes` is product-asserted and
unverified. Contextual output escaping is the host's job.

The id `postMessage` returns is the correlation key `ActionTrigger.messageId`
carries back, so it must name that message for as long as the host stores it.
Ids arriving *in* a `Reaction` or `ReactionRemoved` are product-chosen and
untrusted: they may name a message in another room, or one that never existed.

On the execution: `publishChatAction` delivers a user's action back to the
product, buffering up to 64 before it subscribes; `notifyChatRoomsChanged`
republishes the room list; `renderCustomMessage` returns a stream of typed UI
for a stored custom message; and `sessionChatIdentityKey` reads the session's
X25519 chat identity private key, which must not be logged or persisted.

## Architecture

```text
product app in WKWebView
  Uint8Array frames via @parity/truapi createWebSocketProvider
           |
           v   ws://127.0.0.1:<port>/?t=<token>
TrUAPIProductExecution.startWsBridge()
  → libtruapi_server (tokio WS server)
  → Rust dispatcher
```

The product running in the `WKWebView` opens a `WebSocket` to the localhost port + token returned by `startWsBridge`. From there the Rust core handles the wire protocol directly. Outbound responses and host-side capability callbacks (`navigateTo`, `pushNotification`, `cancelNotification`, `devicePermission`, `remotePermission`, `authStateChanged`, core storage, chain JSON-RPC, confirmations, preimage, theme, `featureSupported`, `storage`) reach the embedder through `HostCallbacks`.

## Permissions split

The core's `Permissions` platform trait has two methods, and so does `HostCallbacks`:

- `devicePermission(request:)` - OS-scoped grants (camera, mic, location, push). `request` is a typed `HostDevicePermissionRequest`.
- `remotePermission(request:)` - per-product capabilities. `request` is a typed `RemotePermission`.

Both return a `Bool` granted flag; the host renders the typed request in its own prompt UI. The same typed values drive the `TrUAPIProductExecution` permission admin API (`permissionAuthorizationStatus`, `setPermissionAuthorizationStatus`), which reads and updates the persisted decisions without prompting.

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

### Answering the scheduler

A pass reports per target and only throws when it could not run at all, so decide from the report rather than from the absence of an error:

- every status `Registered` or `AlreadyAllocated`: completed successfully.
- any status `Failed`: complete unsuccessfully and submit a fresh request, since iOS does not reschedule one for you. The grace window means that request can wait for the next opportunistic wake rather than a tight loop.
- any status `SkippedExhausted`, or `report.slotsExhausted`: completed successfully. Retrying cannot free a slot, only time or a replacement can, so a retry here only burns background budget. It does mean an allowance went unrenewed, so tell the person rather than only logging it.
- a throw carrying `Disconnected` before a session is restored: not ready rather than failed. Restore a session and let the next wake run the pass.

Scheduling is one of three layers, and only the first needs the OS:

1. a `BGTaskScheduler` wake, which is the only one that covers an app nobody opens.
2. a pass on session activation, which covers an app somebody does.
3. on-demand allocation, which registers a product's own account for the current period when that product asks for a statement-store allowance and none is held. That covers the asking product, not the rest of the ledger, so it narrows the window rather than closing it.

`lastStatementRenewalReport()` returns the most recent pass the in-process loop ran, or `nil` if none has, which is "not yet" rather than healthy. The loop returns nothing to its caller, so this is where a host driving it reads what it achieved; checking on resume is enough to catch an exhausted period. A direct `renewStatementAllowances()` hands back its own report and does not write here.

`startStatementAllowanceRenewal()` runs the same pass on an in-process loop instead. It suits a host that stays resident; on iOS a suspended app stops ticking, so prefer `BGTaskScheduler` driving the one-shot call. A pass has no cancellation, so several targets can outlast a short background budget; targets registered before the process is killed are not lost, and read back as already allocated next time.

An account id must be exactly 32 bytes. Anything else is rejected as `NativeRenewalTargetError.InvalidAccountId` before any chain work happens.

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

final class MyStorage: HostStorageBackend, @unchecked Sendable {
    private var values: [String: Data] = [:]

    func read(key: String) throws -> Data? { values[key] }
    func write(key: String, value: Data) throws { values[key] = value }
    func clear(key: String) throws { values.removeValue(forKey: key) }
}

final class MyCoreStorage: HostCoreStorageBackend, @unchecked Sendable {
    private var values: [Data: Data] = [:]

    func read(key: Data) throws -> Data? { values[key] }
    func write(key: Data, value: Data) throws { values[key] = value }
    func clear(key: Data) throws { values.removeValue(forKey: key) }
}

final class MyBridge: HostBridge, @unchecked Sendable {
    let storage: HostStorageBackend = MyStorage()
    let coreStorage: HostCoreStorageBackend = MyCoreStorage()

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
    // period rolls over, so retry should not be the primary action. This native
    // runtime is a signing host, so `.pairing` and `.authenticating` are not
    // emitted. Activate the session with `runtime.activateLocalSession(...)`.
    func authStateChanged(state: AuthState) {
        DispatchQueue.main.async { /* render the state */ }
    }

    func chainConnect(genesisHash: Data) throws -> UInt32? {
        let id: UInt32 = 1
        DispatchQueue.main.async { /* open JSON-RPC connection, forward responses via runtime.notifyChainResponse */ }
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
        //
        // `.foreignRingVrfKey` is the one variant a host must not remember: it
        // authorizes one product's use of another product's ring-VRF key for a
        // single message, and the core asks again on every call. Show the calling
        // product, the owning product, and whether the output is a context-scoped
        // proof or an unscoped, linkable member-key signature.
        await MainActor.run { /* render review; */ false }
    }

    func lookupPreimage(key: Data) async throws -> Data? { nil }

    func currentTheme() throws -> HostThemeSubscribeItem {
        HostThemeSubscribeItem(name: .default, variant: .dark)
    }

    func featureSupported(request: HostFeatureSupportedRequest) async throws -> Bool { false }

}

let bridge = MyBridge()
let runtimeConfig = HostRuntimeConfig(
    hostName: "My Host",
    hostIcon: "https://host.example/icon.png",
    peopleChainGenesisHash: Data(repeating: 0, count: 32),
    bulletinChainGenesisHash: Data(repeating: 0, count: 32)
)
let runtime = try TrUAPIHostRuntime(bridge: bridge, runtimeConfig: runtimeConfig)
try runtime.activateLocalSession(secret: entropyBytes, liteUsername: nil)
let execution = try runtime.openProductExecution(
    bridge: bridge,
    configuration: ProductExecutionConfig(
        productId: "my-product.dot",
        executionKind: .app
    )
)
let endpoint = try execution.startWsBridge()

// Call these from host/platform observers so native subscriptions see updates
// after their immediate current item.
execution.notifyThemeChanged(
    theme: HostThemeSubscribeItem(name: .default, variant: .dark)
)
execution.notifyPreimageChanged(key: preimageKey, value: preimageBytesOrNil)
runtime.notifyChainResponse(connectionId: chainConnectionId, json: jsonRpcResponse)
runtime.notifyChainClosed(connectionId: chainConnectionId)

// Register the bootstrap + lockdown container before the web view loads the
// product page. `installProductScripts` owns the two properties that are easy to
// get wrong and silently fatal: the container goes into EVERY frame (a frame
// without it has pristine fetch/WebSocket/RTCPeerConnection, and a product
// reaches one through an `<iframe>` in its own HTML), while the bootstrap stays
// main-frame-only so a subframe has no bridge and no policy and fails closed. It
// also resolves the WebRTC decision by peeking the execution rather than prompting.
// Do not register these scripts by hand.
let contentController = WKUserContentController()
try await TrUAPIHost.installProductScripts(
    into: contentController,
    execution: execution,
    endpoint: endpoint
)

let configuration = WKWebViewConfiguration()
configuration.userContentController = contentController
let webView = WKWebView(frame: .zero, configuration: configuration)
webView.load(URLRequest(url: URL(string: "https://your-product.example/")!))

// On logout:
runtime.disconnect()
```

The product page reads `window.__truapi_localhost.url` (set by the bootstrap script) and passes it to `@parity/truapi`'s `createWebSocketProvider(url)`.

## Build outputs in detail

`./scripts/rebuild.sh` orchestrates everything; the underlying pieces, should you need one in isolation:

- **xcframework** — `make xcframework` (repo root) builds `truapi-server` for `aarch64-apple-ios` and `aarch64-apple-ios-sim` and bundles `target/truapi_server.xcframework`; the script copies it into `Binaries/` and strips the per-slice `module.modulemap` (module resolution comes from the `systemLibrary` target; the slice copy collides with other xcframeworks in Xcode's flat include dir).
- **bindings** — `make uniffi` (run automatically by `make xcframework`) emits the Swift bindings into `target/uniffi-swift-out/` via the workspace `uniffi-bindgen-cli`; `scripts/sync-bindings.sh` copies them into `Sources/TrUAPIHost/truapi_server.swift` and `Sources/truapi_serverFFI/include/`, renaming the emitted `truapi_serverFFI.modulemap` to `module.modulemap` so the SwiftPM `systemLibrary` target picks it up. `rebuild.sh` calls it, and CI's `--check` mode compares against it.
- **container** — `npm run build` in `js/container/` (repo root) bundles `src/index.ts` into `Sources/TrUAPIHost/Resources/truapi-container.js`.
