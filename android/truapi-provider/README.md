# TrUAPI Android chain transport

*Kotlin bindings for the `truapi-provider` crate (UniFFI). An embedded smoldot light client and the bundled chain-spec catalog stay in Rust; the host addresses a chain by genesis hash and exchanges JSON-RPC strings.*

> **Status:** there is no remote coordinate yet. JitPack cannot serve this module as it stands — it builds from a git tag, and both the bindings and the cdylib are generated rather than committed — and no hosted Maven publication is wired up. Until one is, integrate with `make provider-android-publish-local` + `mavenLocal()`. The module itself has not been built on CI or a machine with the Android toolchain, so treat the Gradle wiring below as unverified.

Unlike [`truapi-host`](../truapi-host), whose AAR leaves the cdylib to the integrator, this AAR bundles `libtruapi_provider.so` for every published ABI. That is the point of the package: a consumer adds one coordinate and calls `ChainProvider()`, with no Rust toolchain and no dependency on the crate.

## Consume

```kotlin
// settings.gradle.kts
dependencyResolutionManagement {
    repositories {
        google()
        mavenCentral()
        mavenLocal() // until a hosted publication exists, see Status above
    }
}
```

```kotlin
// app/build.gradle.kts
dependencies {
    implementation("io.parity:truapi-provider-android:0.1.0")
}
```

The consuming app must declare `android.permission.INTERNET` — the light client dials peers over TCP and WebSocket.

Chain specs are compiled into the cdylib, so the app ships no spec files of its own and never refreshes them. Picking up a spec refresh means taking a newer version of this artifact.

### Compatibility

- **minSdk**: 29 (Android 10). Matches the `truapi-host` floor so a host can depend on both.
- **ABIs**: `arm64-v8a`, `armeabi-v7a`, `x86_64` (`ANDROID_ABIS` overrides the set). Each carries a copy of the light client, so the AAR is large; split APKs or an App Bundle keep the shipped size to one ABI.
- **Transitive dependency**: the AAR pulls `net.java.dev.jna:jna:5.14.0` (UniFFI's runtime), shared with `truapi-host` when both are present.

## Public surface

Everything is generated from [`ffi.rs`](../../rust/crates/truapi-provider/src/ffi.rs) into `uniffi.truapi_provider.*`:

- `ChainProvider` - construct **one per process** and share it. Every connection runs on the single embedded light client, so they share sync, peers, and warm state while keeping their own request queue and response stream. `connect(genesisHash, listener)` resolves the network from the bundled catalog (relay wiring and statement-store placement included), so the 32-byte genesis hash is the only argument.
- `ChainMessageListener` - the host implements it; `onMessage(message)` receives each JSON-RPC response and notification, `onClosed()` fires once the stream ends.
- `ChainConnection` - `send(request)` queues a request, `close()` tears the connection down.
- `ChainProviderError` - `Connect` when the genesis is outside the catalog or the transport fails, `BadGenesis` when the hash is not 32 bytes.

## Architecture

```text
host app
  ChainProvider().connect(genesisHash, listener)
           |
           v
libtruapi_provider.so (embedded smoldot + bundled chain-spec catalog)
  → one light client per process, one added chain per connection
  → responses pumped on a Rust-owned thread into ChainMessageListener
```

A connection is a raw JSON-RPC string pipe. The provider does no decoding: what smoldot answers is what the listener receives.

## Example

> **Threading:** the crate pumps each connection's responses on a background thread it owns, so `onMessage` and `onClosed` are never called on the UI thread — marshal any UI work onto it with `Handler(Looper.getMainLooper())` or a `Dispatchers.Main` `CoroutineScope`. `connect(genesisHash, listener)` is blocking and adds the chain on the calling thread, so keep it off the UI thread.

```kt
import android.os.Handler
import android.os.Looper
import uniffi.truapi_provider.ChainConnection
import uniffi.truapi_provider.ChainMessageListener
import uniffi.truapi_provider.ChainProvider

class Responses : ChainMessageListener {
    private val main = Handler(Looper.getMainLooper())

    // A JSON-RPC response or subscription notification, verbatim from smoldot.
    override fun onMessage(message: String) {
        main.post { /* decode and render */ }
    }

    override fun onClosed() {
        main.post { /* the stream ended: drop the connection */ }
    }
}

// One provider per process; hold it for the app's lifetime.
val provider = ChainProvider()

// 32 raw bytes, not a hex string. Must be a chain in the bundled catalog.
val genesis = ByteArray(32)
val connection: ChainConnection = provider.connect(genesis, Responses())

connection.send("""{"jsonrpc":"2.0","id":1,"method":"chainSpec_v1_genesisHash","params":[]}""")

// On teardown:
connection.close()
```

## Maintainers: publishing locally

```bash
make provider-android-publish-local
```

That regenerates the Kotlin bindings, cross-compiles the cdylib for every ABI, and publishes to `~/.m2/repository/io/parity/truapi-provider-android/<version>/`. It needs Gradle, JDK 17, the Android NDK, and `cargo-ndk` (`cargo install cargo-ndk`).

Publishing refuses to run when `src/main/jniLibs` holds no `libtruapi_provider.so`: such an AAR resolves fine and then fails at the first `ChainProvider()` with `UnsatisfiedLinkError`, which is a much worse failure than a build error. The two steps behind it are available separately:

```bash
make provider-kotlin       # regenerate the bindings only
make provider-android-jni  # cross-compile the cdylib only
```

Both the generated bindings under `src/main/kotlin/generated/uniffi/` and the `.so` files under `src/main/jniLibs/` are gitignored build outputs.

## Regenerating the UniFFI bindings

```bash
make provider-kotlin
```

That builds the crate with the `codegen` profile and runs the workspace `uniffi-bindgen-cli`. The `codegen` profile is required because uniffi-bindgen scans the cdylib's exported metadata symbols, which the `release` profile strips — a plain `--release` build produces a stripped library and no bindings. (`make uniffi-kotlin` does the same for the host package.)
