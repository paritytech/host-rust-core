# TrUAPI Android host adapter

*Kotlin wrapper around the TrUAPI Rust core (UniFFI). Wire decoding, request routing, and subscription lifecycle stay in the Rust core; products connect through the localhost WebSocket bridge.*

Distribution: a Maven AAR published to GitHub Packages by the `release-android` workflow. Each release bundles, built from the same source tree: `libtruapi_server.so` for arm64-v8a, armeabi-v7a and x86_64 (built with the `ws-bridge` feature), the UniFFI Kotlin bindings (`uniffi.truapi_server.*`), and the Kotlin host adapter (`io.parity.truapi.*`). Consumers need no Rust toolchain or NDK.

## Consume

Add the GitHub Packages repository and the artifact to your app's Gradle build (GitHub Packages requires authentication even for public repos — any GitHub account token with `read:packages` works):

```kotlin
// settings.gradle.kts
dependencyResolutionManagement {
    repositories {
        google()
        mavenCentral()
        maven {
            url = uri("https://maven.pkg.github.com/paritytech/host-rust-core")
            credentials {
                username = providers.gradleProperty("gpr.user").orNull ?: System.getenv("GITHUB_ACTOR")
                password = providers.gradleProperty("gpr.key").orNull ?: System.getenv("GITHUB_TOKEN")
            }
        }
    }
}
```

```kotlin
// app/build.gradle.kts
dependencies {
    implementation("io.parity:truapi-host-android:0.1.0")
}
```

The package is public, so any authenticated GitHub identity can read it. In GitHub Actions that means the built-in `GITHUB_TOKEN` with a `permissions: packages: read` block, no secret to create or rotate. Locally it means a personal access token with `read:packages`, set once as `gpr.user` / `gpr.key` in `~/.gradle/gradle.properties`. A token without that scope fails with 401 even though the package is public, which is how GitHub Packages treats Maven.

The consuming app must declare `android.permission.INTERNET` — the localhost WebSocket bridge binds a `127.0.0.1` TCP socket, which requires it even for loopback.

### Compatibility

- **minSdk**: 29 (Android 10). Aligns with the polkadot-app-android-v2 floor.
- **AGP**: built with 8.5.2; AGP 8.5+ consumers are fine. AAR is forward-compatible with newer AGPs.
- **Kotlin**: built with 1.9.24. Newer Kotlin compilers (2.x) read 1.9 metadata fine.
- **Transitive dependencies**: `net.java.dev.jna:jna:5.14.0` (UniFFI's runtime, ~1.5MB for consumers that don't already use it), `org.jetbrains.kotlinx:kotlinx-coroutines-core:1.9.0` and `org.jetbrains.kotlin:kotlin-stdlib:1.9.24`.
- **Size**: the AAR is ~20MB, one `libtruapi_server.so` per ABI. An app bundle ships only the ABI the device needs, so the installed cost is ~9MB on arm64.

## Public surface

The public surface lives in [`src/main/kotlin/io/parity/truapi/TrUAPIHost.kt`](src/main/kotlin/io/parity/truapi/TrUAPIHost.kt):

- `HostBridge` - callback bundle the embedding app implements. Splits device permissions, remote permissions, navigation, push, feature support, a single `confirmUserAction`, and both storage backends.
- `HostStorage` - product-scoped read/write/clear interface the host backs with its own persistence.
- `HostCoreStorage` - core-owned read/write/clear interface for auth session, pairing identity, and persisted permission decisions (`key` is a SCALE-encoded `CoreStorageKey`).
- `TrUAPIHostCore` - owning wrapper around the UniFFI-generated `NativeTrUApiCore`. Holds the bridge alive for the lifetime of the core and exposes the localhost WebSocket bridge, core-owned disconnect, local-session activation, permission-authorization status, and native change notifications for session storage, theme, and preimage updates.
- `LocalhostBridgeBootstrap` - JS snippet that publishes the WS bridge endpoint (`window.__truapi_localhost`) to the product page so it can dial back in.
- `TrUAPIHostRuntime` - process-owned runtime whose product executions share one authentication session. Open a connection per executable with `openProductExecution`, which returns a `TrUAPIProductExecution` carrying that connection's own WS bridge, permission authorization, theme/preimage/chain notifications, and the Chat controls below.
- `ChatHostBridge` - native Chat storage and UI, implemented by hosts that serve the Chat modality and passed to `openProductExecution`. Hosts without it pass nothing and Chat calls answer unsupported.

## Chat

A host serving the Chat modality implements `ChatHostBridge` (`createRoom`, `registerBot`, `postMessage`, `listRooms`) and opens the execution with `ProductExecutionKind.CHAT`:

```kotlin
import io.parity.truapi.*
import uniffi.truapi.ChatBotRegistrationStatus
import uniffi.truapi.ChatMessageContent
import uniffi.truapi.ChatRoom
import uniffi.truapi.ChatRoomParticipation
import uniffi.truapi.ChatRoomRegistrationStatus
import uniffi.truapi_server.HostRejection

// Called from a shared dispatch pool, so the backing store must be
// thread-safe, and a slow call here stalls other product executions.
class MyChatBridge(private val store: ChatStore) : ChatHostBridge {
    override fun createRoom(roomId: String, name: String, icon: String) =
        if (store.putRoom(roomId, name, icon)) ChatRoomRegistrationStatus.NEW
        else ChatRoomRegistrationStatus.EXISTS

    override fun registerBot(botId: String, name: String, icon: String) =
        if (store.putBot(botId, name, icon)) ChatBotRegistrationStatus.NEW
        else ChatBotRegistrationStatus.EXISTS

    override fun postMessage(roomId: String, content: ChatMessageContent): String {
        if (content is ChatMessageContent.File) {
            // Declining a variant is how a host opts out of rendering one.
            throw HostRejection.Rejected("this host cannot render file cards")
        }
        return store.append(roomId, content)
    }

    override fun listRooms(): List<ChatRoom> = store.rooms()
}

val runtime = TrUAPIHostRuntime(
    bridge = bridge,
    runtimeConfig = HostRuntimeConfig(
        hostName = "My Chat Host",
        peopleChainGenesisHash = peopleChainGenesisHash,   // exactly 32 bytes
        bulletinChainGenesisHash = bulletinChainGenesisHash,
    ),
)
// Chat needs an active session; without one every Chat call answers `Denied`.
runtime.activateLocalSession(secret)

val execution = runtime.openProductExecution(
    bridge = bridge,
    configuration = ProductExecutionConfig("chat.dot", ProductExecutionKind.CHAT),
    chat = MyChatBridge(store),
)
val endpoint = execution.startWsBridge()
webView.evaluateJavascript(
    LocalhostBridgeBootstrap.script(endpoint.port, endpoint.token),
    null,
)
```

Chat requires an active session: `openProductExecution` succeeds without one,
but every Chat call then answers `Denied` until `activateLocalSession` or SSO
pairing completes.

The core bounds and screens the product-supplied fields it forwards — ids,
names, icons, message bodies, URLs, and the action and media counts. Ids and
names are also normalized; a message body is bounded and screened but passed
through byte-for-byte, and `ChatFile.size_bytes` is product-asserted and
unverified. Contextual output escaping is the host's job.

`postMessage` receives any `ChatMessageContent` variant; throw from it for one this host cannot render. The id it returns is the correlation key `ActionTrigger.messageId` carries back, so it must name that message for as long as the host stores it.

On the execution: `publishChatAction` delivers a user's action back to the product (buffered until it subscribes), `notifyChatRoomsChanged` republishes the room list, `renderCustomMessage` returns a `Flow` of typed UI for a stored custom message, and `sessionChatIdentityKey` reads the session's X25519 chat identity key.

## Architecture

```text
product app in WebView
  Uint8Array frames via @parity/truapi createWebSocketProvider
           |
           v   ws://127.0.0.1:<port>/?t=<token>
TrUAPIHostCore.startWsBridge()
  → libtruapi_server.so (tokio WS server)
  → Rust dispatcher
```

The product running in the `WebView` opens a `WebSocket` to the localhost port + token returned by `startWsBridge`. From there the Rust core handles the wire protocol directly. Outbound responses and host-side capability callbacks (`navigateTo`, `pushNotification`, `cancelNotification`, `devicePermission`, `remotePermission`, `authStateChanged`, core storage, chain JSON-RPC, `confirmUserAction`, preimage lookup, theme, `featureSupported`, `storage`) reach the embedder through `HostBridge`. Bulletin preimage build/sign/submit now happens inside the core, so the host only serves `lookupPreimage`.

## Permissions split

The core's `Permissions` platform trait has two methods, and so does the bridge:

- `devicePermission(request)` - OS-scoped grants (camera, mic, location, push). `request` is a typed `HostDevicePermissionRequest`.
- `remotePermission(request)` - per-product capabilities. `request` is a typed `RemotePermission`.

Both return a `Boolean` granted flag; the host renders the typed request in its own prompt UI. The same typed values drive the `TrUAPIHostCore` permission admin API (`permissionAuthorizationStatus`, `setPermissionAuthorizationStatus`), which reads and updates the persisted decisions without prompting.

## Statement-store allowance renewal

Statement-store allowances are granted per period, so a host has to re-register the accounts it wants to keep writing. They are not revoked the moment the period ends: `Resources.StmtStoreGraceWindow` keeps an ended period's allowances active until cleanup catches up, 48 hours on `paseo-next-v2`. The core owns the ledger and the registration; the app owns only the schedule.

Record the accounts to keep allowed. This needs an active session, so call it after `activateLocalSession` or after pairing, not at construction:

```kotlin
core.trackStatementRenewalTargets(
    listOf(
        NativeStatementRenewalTarget.WalletSso,
        NativeStatementRenewalTarget.Account(deviceStatementKey, "device"),
    ),
)
```

The ledger persists across launches, and it is append-only: there is no untrack, and an entry is dropped only when the identity that promised it changes. `WalletSso` and `ProductStatementAllowance` are derivation recipes and survive that; `Account` carries a fixed account id and does not. A dropped target is listed in `report.pruned`, which is how a host learns to re-track one and keep renewal covering it. There is still no reader and no untrack on this surface, so a host cannot list what is tracked or remove a wrong entry. Re-tracking is idempotent, so the safe habit is to re-track the full set after every identity change rather than trying to reason about what survived.

Then run a pass from a `WorkManager` worker. It submits extrinsics and blocks until they are included, so keep it off the main thread. It needs an active session too, which is the whole difficulty here: a worker on a cold start has none until you restore one, and the pass then fails with the bare reason `Disconnected`. Restore the session first, and read that reason as "not ready" rather than as a renewal failure. `startStatementAllowanceRenewal()` does not need this care, since its loop skips a tick with no session and retries.

```kotlin
val report = core.renewStatementAllowances()
report.outcomes.forEach { Log.i(TAG, "${it.label}: ${it.status}") }
report.pruned.forEach {
    // Promised by a previous identity and discarded; re-track to keep it renewed.
    Log.w(TAG, "dropped: $it")
}
if (report.slotsExhausted) {
    // Every slot for this period is taken and none was replaceable.
}
```

One scheduled pass per period is enough, with room to spare: an allowance stays usable for `Resources.StmtStoreGraceWindow` past its boundary, which is 48 hours on `paseo-next-v2`, so a missed run is recoverable rather than fatal. `nextStatementRenewalDelay()` reports the in-process loop's retry cadence, capped at an hour; a worker scheduling one run per period should read a value under an hour as the boundary approaching rather than waking hourly.

### Answering the scheduler

A pass reports per target and only throws when it could not run at all, so decide from the report rather than from the absence of an exception:

- every status `Registered` or `AlreadyAllocated`: `Result.success()`.
- any status `Failed`: `Result.retry()`. The grace window means the retry can wait for the worker's own backoff rather than a tight loop.
- any status `SkippedExhausted`, or `report.slotsExhausted`: `Result.success()`. Retrying cannot free a slot, only time or a replacement can, so a retry here only burns the worker's budget. It does mean an allowance went unrenewed, so tell the person rather than only logging it.
- an exception carrying `Disconnected` before a session is restored: not ready rather than failed. Restore a session and let the next run take it.

Scheduling is one of three layers, and only the first needs the OS:

1. a `WorkManager` run, which is the only one that covers an app nobody opens.
2. a pass on session activation, which covers an app somebody does.
3. on-demand allocation, which registers a product's own account for the current period when that product asks for a statement-store allowance and none is held. That covers the asking product, not the rest of the ledger, so it narrows the window rather than closing it.

`lastStatementRenewalReport()` returns the most recent pass the in-process loop ran, or `null` if none has, which is "not yet" rather than healthy. The loop returns nothing to its caller, so this is where a host driving it reads what it achieved; checking on resume is enough to catch an exhausted period. A direct `renewStatementAllowances()` hands back its own report and does not write here.

`startStatementAllowanceRenewal()` runs the same pass on an in-process loop instead, for a host that stays resident. A pass has no cancellation, so several targets can outlast a constrained worker budget; targets registered before the process is killed are not lost and read back as already allocated.

An account id must be exactly 32 bytes. Anything else throws `NativeRenewalTargetException.InvalidAccountId` before any chain work happens.

## Example

> **Threading:** the Rust core invokes every `HostBridge` callback on a
> background thread it owns, never the UI thread. Marshal any UI work
> (navigation, prompts, notifications, touching the `WebView`) onto the main
> thread with `Handler(Looper.getMainLooper())` or a `Dispatchers.Main`
> `CoroutineScope`. The `suspend` callbacks (`navigateTo`, `pushNotification`,
> `devicePermission`, `remotePermission`, `featureSupported`,
> `confirmUserAction`, `lookupPreimage`) are awaited by the core, so an
> implementation may suspend for as long as the user takes to decide (e.g.
> `withContext(Dispatchers.Main)` around a prompt); other TrUAPI traffic keeps
> flowing while you wait. The remaining callbacks (auth state, storage, core
> storage, chain, theme, and `cancelNotification`) run inline on the dispatcher
> thread and must return promptly without blocking.

```kt
import android.os.Handler
import android.os.Looper
import android.webkit.WebView
import androidx.webkit.WebViewCompat
import androidx.webkit.WebViewFeature
import io.parity.truapi.HostBridge
import io.parity.truapi.HostCoreStorage
import io.parity.truapi.HostStorage
import io.parity.truapi.LocalhostBridgeBootstrap
import io.parity.truapi.PairingDeeplinkScheme
import io.parity.truapi.RuntimeConfig
import io.parity.truapi.TrUAPIHostCore
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import uniffi.truapi_platform.AuthState
import uniffi.truapi.HostFeatureSupportedRequest
import uniffi.truapi.HostThemeSubscribeItem
import uniffi.truapi.ThemeName
import uniffi.truapi.ThemeVariant
import uniffi.truapi.HostDevicePermissionRequest
import uniffi.truapi.RemotePermission
import uniffi.truapi_platform.UserConfirmationReview
import uniffi.truapi.HostPushNotificationRequest

class MyStorage : HostStorage {
    private val map = mutableMapOf<String, ByteArray>()
    override fun read(key: String) = map[key]
    override fun write(key: String, value: ByteArray) { map[key] = value }
    override fun clear(key: String) { map.remove(key) }
}

// Core-owned storage: keyed by SCALE-encoded CoreStorageKey bytes. Back it with
// real persistence (e.g. EncryptedSharedPreferences); an in-memory map is shown
// for brevity.
class MyCoreStorage : HostCoreStorage {
    private val map = HashMap<String, ByteArray>()
    private fun k(key: ByteArray) = key.joinToString("") { "%02x".format(it) }
    override fun read(key: ByteArray) = map[k(key)]
    override fun write(key: ByteArray, value: ByteArray) { map[k(key)] = value }
    override fun clear(key: ByteArray) { map.remove(k(key)) }
}

class MyBridge(private val webView: WebView) : HostBridge {
    private val main = Handler(Looper.getMainLooper())

    override val storage = MyStorage()
    override val coreStorage = MyCoreStorage()

    override suspend fun navigateTo(url: String) {
        withContext(Dispatchers.Main) { /* startActivity(Intent(ACTION_VIEW, Uri.parse(url))) */ }
    }

    override suspend fun pushNotification(request: HostPushNotificationRequest): UInt {
        val id = 1u
        withContext(Dispatchers.Main) { /* show request.text / request.deeplink */ }
        return id
    }

    override fun cancelNotification(id: UInt) {
        main.post { /* cancel notification */ }
    }

    override suspend fun devicePermission(request: HostDevicePermissionRequest): Boolean {
        // Awaited by the core: present the prompt for the requested capability
        // (CAMERA, MICROPHONE, ...) and suspend until the user decides. Other
        // TrUAPI traffic keeps flowing while suspended.
        return withContext(Dispatchers.Main) { /* show prompt; */ false }
    }

    override suspend fun remotePermission(request: RemotePermission): Boolean = false
    override suspend fun featureSupported(request: HostFeatureSupportedRequest): Boolean = false

    // Core-owned auth state stream: render AuthState.Pairing as the pairing
    // QR sheet, connected/disconnected as the account badge, and login-failed
    // as a retryable error, unless its kind is
    // LoginFailureKind.NoFreeAllowanceSlots, which is unlikely to succeed
    // before the period rolls over, so retry should not be the primary action.
    // When the user closes the pairing sheet, report it
    // with `core.cancelLogin()`.
    override fun authStateChanged(state: AuthState) {
        main.post { /* render the state */ }
    }

    override fun chainConnect(genesisHash: ByteArray): UInt? {
        val id = 1u
        main.post { /* open JSON-RPC connection, forward responses via core.notifyChainResponse */ }
        return id
    }

    override fun chainSend(connectionId: UInt, request: String) {
        /* send JSON-RPC request on the host connection */
    }

    override fun chainClose(connectionId: UInt) {
        /* close host connection */
    }

    // One confirmation callback for every reviewed core action. Switch on the
    // review variant (SignPayload / SignRaw / CreateTransaction / AccountAlias /
    // ResourceAllocation / PreimageSubmit / ...) to render the prompt with its
    // typed fields.
    override suspend fun confirmUserAction(review: UserConfirmationReview): Boolean {
        return withContext(Dispatchers.Main) { /* show prompt; */ false }
    }
}

val webView: WebView = existingWebView
val runtimeConfig = RuntimeConfig(
    productId = "my-product.dot",
    hostName = "My Host",
    hostIcon = "https://host.example/icon.png",
    peopleChainGenesisHash = ByteArray(32),
    bulletinChainGenesisHash = ByteArray(32),
    // Optional: activate a local signing session from host-held BIP-39 entropy
    // (no SSO pairing). Omit for the QR pairing flow.
    localSessionSecret = null,
    pairingDeeplinkScheme = PairingDeeplinkScheme.POLKADOT_APP,
)
val core = TrUAPIHostCore(MyBridge(webView), runtimeConfig)
val endpoint = core.startWsBridge()

// Call these from host/platform observers so native subscriptions see updates
// after their immediate current item.
core.notifyThemeChanged(HostThemeSubscribeItem(ThemeName.Default, ThemeVariant.DARK))
core.notifyPreimageChanged(preimageKey, preimageBytesOrNull)
core.notifyChainResponse(chainConnectionId, jsonRpcResponse)
core.notifyChainClosed(chainConnectionId)

// Publish the bridge endpoint to the product page. Install the bootstrap as a
// DOCUMENT-START script so it runs in the destination document before the page
// scripts — `evaluateJavascript` runs in the CURRENT document, which the
// following `loadUrl` replaces, so the product would lose the endpoint. Scope
// it to the product origin. The page reads `window.__truapi_localhost.url` and
// passes it to `@parity/truapi`'s `createWebSocketProvider`.
// A peek, never a prompt — see LocalhostBridgeBootstrap.script. Baked in as a
// literal because the container enforces it inside the product's own realm,
// where an async permission request would be forgeable. A fresh grant therefore
// only takes effect once the web view reloads.
//
// Read this as a policy value, not a gate: Android injects no lockdown
// container, so nothing consumes the decision and WebRTC is reachable on
// Android whatever the status says. Pass what the core returns anyway — a
// literal `true` compiles and would silently keep that open once the container
// does land (#334 scopes the gate to iOS).
val webRtcAllowed = core.permissionAuthorizationStatus(
    PermissionAuthorizationRequest.Remote(RemotePermissionRequest(RemotePermission.WebRtc))
) == PermissionAuthorizationStatus.AUTHORIZED
val bootstrap = LocalhostBridgeBootstrap.script(endpoint.port, endpoint.token, webRtcAllowed)
main.post {
    val productUrl = "https://your-product.example/"
    if (WebViewFeature.isFeatureSupported(WebViewFeature.DOCUMENT_START_SCRIPT)) {
        WebViewCompat.addDocumentStartJavaScript(
            webView,
            bootstrap,
            setOf("https://your-product.example"), // origin allowlist
        )
    }
    webView.loadUrl(productUrl)
}

// On logout:
core.disconnect()
```

## The cdylib

The released AAR bundles `libtruapi_server.so` for all three ABIs under its `jni/` directory; JNA loads it from there without any consumer setup.

When iterating on the core from a source checkout instead of the published artifact, cross-compile into this module's `jniLibs` with:

```bash
make android-jni    # needs cargo-ndk, the NDK, and the three Android rust targets
```

or point the `mozilla-rust-android-gradle` plugin at `rust/crates/truapi-server` from the host app's own build (polkadot-app-android-v2 does this while it still builds from a checkout).

## Maintainers: cutting a release

Include `@parity/android-host <version>` in the `release:` PR title, the same flow the npm packages and the iOS host use. On merge, `release.yml` calls `release-android.yml` for the release commit, which cross-compiles the cdylib for all three ABIs, regenerates the Kotlin bindings via the `codegen` cargo profile, and publishes `io.parity:truapi-host-android:<version>` to GitHub Packages.

A manual `release-android` run with a version input reaches the same workflow, as an escape hatch. There is deliberately no tag trigger: a tag push cannot use `release.yml`'s gate on green CI, so it would be an unverified path to the registry.

The version lives only in the release subject. Nothing in the tree records it, so there is no committed version to keep in sync.

For local development, publish into `~/.m2`:

```bash
make android-jni            # optional: bundle the cdylibs into the local AAR
make android-publish-local
```

The artifact lands under `~/.m2/repository/io/parity/truapi-host-android/0.0.0-local/`; consumers pointing at `mavenLocal()` resolve it as `io.parity:truapi-host-android:0.0.0-local`.

## Regenerating the UniFFI bindings

The ignored Kotlin bindings under `src/main/kotlin/generated/uniffi/` are produced from the workspace `uniffi-bindgen-cli`. Regenerate them before building or publishing the Android host package:

```bash
make uniffi-kotlin
```

`make uniffi-kotlin` builds the host cdylib with the `codegen` profile and runs
the generator. The `codegen` profile is required because uniffi-bindgen scans
the cdylib's exported metadata symbols, which the `release` profile strips — a
plain `--release` build produces a stripped library and no bindings. (`make
uniffi` regenerates the Swift bindings; use `make uniffi-kotlin` for Android.)

No CI job compiles this package. After changing `TrUAPIHost.kt` or the UniFFI
surface it wraps, run `make android-check` locally — it regenerates the Kotlin
bindings and compiles the module against them.
