# TrUAPI Android host adapter

*Kotlin wrapper around the TrUAPI Rust core (UniFFI). Wire decoding, request routing, and subscription lifecycle stay in the Rust core; products connect through the localhost WebSocket bridge.*

Distribution: a Maven AAR published to GitHub Packages by the `release-android` workflow. Each release bundles, built from the same source tree: `libtruapi_server.so` for arm64-v8a, armeabi-v7a, x86 and x86_64 (built with the `ws-bridge` feature), the UniFFI Kotlin bindings (`uniffi.truapi_server.*`), and the Kotlin host adapter (`io.parity.truapi.*`). Consumers need no Rust toolchain or NDK.

## Consume

Add the GitHub Packages repository and the artifact to your app's Gradle build (GitHub Packages requires authentication even for public repos — any GitHub account token with `read:packages` works):

```kotlin
// settings.gradle.kts
dependencyResolutionManagement {
    repositories {
        google()
        mavenCentral()
        maven {
            url = uri("https://maven.pkg.github.com/paritytech/truapi")
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
    implementation("io.parity:truapi-host:0.1.0")
}
```

The consuming app must declare `android.permission.INTERNET` — the localhost WebSocket bridge binds a `127.0.0.1` TCP socket, which requires it even for loopback.

### Compatibility

- **minSdk**: 29 (Android 10). Aligns with the polkadot-app-android-v2 floor.
- **AGP**: built with 8.5.2; AGP 8.5+ consumers are fine. AAR is forward-compatible with newer AGPs.
- **Kotlin**: built with 1.9.24. Newer Kotlin compilers (2.x) read 1.9 metadata fine.
- **Transitive dependency**: the AAR pulls `net.java.dev.jna:jna:5.14.0` (UniFFI's runtime). Consumers that don't already use JNA will see ~1.5MB added to their app.

## Public surface

The public surface lives in [`src/main/kotlin/io/parity/truapi/TrUAPIHost.kt`](src/main/kotlin/io/parity/truapi/TrUAPIHost.kt):

- `HostBridge` - callback bundle the embedding app implements. Splits device permissions, remote permissions, navigation, push, feature support, a single `confirmUserAction`, and both storage backends.
- `HostStorage` - product-scoped read/write/clear interface the host backs with its own persistence.
- `HostCoreStorage` - core-owned read/write/clear interface for auth session, pairing identity, and persisted permission decisions (`key` is a SCALE-encoded `CoreStorageKey`).
- `TrUAPIHostCore` - owning wrapper around the UniFFI-generated `NativeTrUApiCore`. Holds the bridge alive for the lifetime of the core and exposes the localhost WebSocket bridge, core-owned disconnect, local-session activation, permission-authorization status, and native change notifications for session storage, theme, and preimage updates.
- `LocalhostBridgeBootstrap` - JS snippet that publishes the WS bridge endpoint (`window.__truapi_localhost`) to the product page so it can dial back in.

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

- `devicePermission(request)` - OS-scoped grants (camera, mic, location, push). `request` is a SCALE-encoded `v01::HostDevicePermissionRequest`.
- `remotePermission(request)` - per-product capability bundles. `request` is a SCALE-encoded `v01::RemotePermissionRequest`.

Both return a `Boolean` granted flag. SCALE decoding for the UI prompt is done by the `@parity/truapi` JS client (or any consumer that links the protocol crate's types directly).

## Example

> **Threading:** the Rust core invokes every `HostBridge` callback on a
> background thread it owns, never the UI thread. Marshal any UI work
> (navigation, prompts, notifications, touching the `WebView`) onto the main
> thread with `Handler(Looper.getMainLooper())` or a `Dispatchers.Main`
> `CoroutineScope`. Six callbacks each run on their own blocking-pool thread, so
> it is safe to block the calling thread (e.g. with a `CountDownLatch`) until the
> main-thread prompt resolves; other TrUAPI traffic keeps flowing while you wait:
> `navigateTo`, `pushNotification`, `devicePermission`, `remotePermission`,
> `featureSupported`, and `confirmUserAction`. The remaining callbacks (auth
> state, storage, core storage, chain, theme, preimage lookups, and
> `cancelNotification`) run inline on the dispatcher thread and must return
> promptly without blocking.

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
import uniffi.truapi_server.AuthState
import uniffi.truapi_server.HostTheme
import java.util.concurrent.CountDownLatch

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

    override fun navigateTo(url: String) {
        main.post { /* startActivity(Intent(ACTION_VIEW, Uri.parse(url))) */ }
    }

    override fun pushNotification(payload: ByteArray): UInt {
        val id = 1u
        main.post { /* show notification */ }
        return id
    }

    override fun cancelNotification(id: UInt) {
        main.post { /* cancel notification */ }
    }

    override fun devicePermission(request: ByteArray): Boolean {
        // Called on a blocking-pool thread; prompt on the main thread and
        // wait. Blocking here does not stall other TrUAPI traffic.
        val latch = CountDownLatch(1)
        var granted = false
        main.post { /* show prompt, set granted, then */ latch.countDown() }
        latch.await()
        return granted
    }

    override fun remotePermission(request: ByteArray): Boolean = false
    override fun featureSupported(request: ByteArray): Boolean = false

    // Core-owned auth state stream: render AuthState.Pairing as the pairing
    // QR sheet, connected/disconnected as the account badge, and login-failed
    // as a retryable error. When the user closes the pairing sheet, report it
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

    // One confirmation callback for every reviewed core action. Decode
    // `review` (SCALE `UserConfirmationReview`) with the @parity/truapi JS
    // client to pick the prompt (sign payload / raw / create tx / alias /
    // resource allocation / preimage submit).
    override fun confirmUserAction(review: ByteArray): Boolean {
        val latch = CountDownLatch(1)
        var approved = false
        main.post { /* show prompt, set approved, then */ latch.countDown() }
        latch.await()
        return approved
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
core.notifySessionStoreChanged()
core.notifyThemeChanged(HostTheme.DARK)
core.notifyPreimageChanged(preimageKey, preimageBytesOrNull)
core.notifyChainResponse(chainConnectionId, jsonRpcResponse)
core.notifyChainClosed(chainConnectionId)

// Publish the bridge endpoint to the product page. Install the bootstrap as a
// DOCUMENT-START script so it runs in the destination document before the page
// scripts — `evaluateJavascript` runs in the CURRENT document, which the
// following `loadUrl` replaces, so the product would lose the endpoint. Scope
// it to the product origin. The page reads `window.__truapi_localhost.url` and
// passes it to `@parity/truapi`'s `createWebSocketProvider`.
val bootstrap = LocalhostBridgeBootstrap.script(endpoint.port, endpoint.token)
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

The released AAR bundles `libtruapi_server.so` for all four ABIs under its `jni/` directory; JNA loads it from there without any consumer setup.

When iterating on the core from a source checkout instead of the published artifact, cross-compile into this module's `jniLibs` with:

```bash
make android-jni    # needs cargo-ndk, the NDK, and the four Android rust targets
```

or point the `mozilla-rust-android-gradle` plugin at `rust/crates/truapi-server` from the host app's own build (polkadot-app-android-v2 does this while it still builds from a checkout).

## Maintainers: cutting a release

Releases are built and published by `.github/workflows/release-android.yml`:

1. Tag the commit to release: `git tag truapi-host-android@0.1.0 && git push origin truapi-host-android@0.1.0` (or run the `release-android` workflow manually with a version input).
2. The workflow cross-compiles the cdylib for all four ABIs, regenerates the Kotlin bindings via the `codegen` cargo profile, and publishes `io.parity:truapi-host:<version>` to GitHub Packages.

Host apps that decode `UserConfirmationReview` payloads should regenerate their golden decoder fixtures against the release:

```bash
cargo run -p truapi-platform --bin review-fixtures
```

prints one `NAME=0x<hex>` line per review variant. The same hex is pinned by `rust/crates/truapi-platform/tests/review_fixtures.rs`, so a variant reorder or field change fails in this repo's CI before it can break a host's decoder.

For local development, publish into `~/.m2`:

```bash
make android-jni            # optional: bundle the cdylibs into the local AAR
make android-publish-local
```

The artifact lands under `~/.m2/repository/io/parity/truapi-host/0.0.0-local/`; consumers pointing at `mavenLocal()` resolve it as `io.parity:truapi-host:0.0.0-local`.

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
