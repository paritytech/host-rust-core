# TrUAPI iOS chain transport

*Swift shell over the `truapi-provider` crate (UniFFI). An embedded smoldot light client and the bundled chain-spec catalog stay in Rust; the host addresses a chain by genesis hash and exchanges JSON-RPC strings.*

> **Status:** no `@parity/ios-provider` release exists yet, so `providerBinaryURL` and `providerBinaryChecksum` in the root `Package.swift` are placeholders and remote resolution of `TrUAPIProvider` fails on the checksum. Until the first `scripts/publish.sh` run, build against the local xcframework (`make provider-ios`, then `TRUAPI_PROVIDER_USE_LOCAL_BINARY=1`) or depend on the package by path. Everything below describes the target design.

The package lives in the truapi repo next to the Rust crate it wraps. `Package.swift` sits at the **repo root** (SPM requires that for git-URL dependencies) and declares two products: [`TrUAPIHost`](../truapi-host) and `TrUAPIProvider`. They are independent — a host depends on whichever it needs — and release on separate tags, so each has its own local-binary toggle.

## What this package is for

The `TrUAPIProvider` SPM product an iOS host imports when it wants to serve chain traffic itself rather than proxying it. It carries:

- `Sources/TrUAPIProvider/truapi_provider.swift` and `Sources/truapi_providerFFI/include/` — the generated UniFFI bindings. There is no hand-written Swift shell: the crate's [`ffi.rs`](../../rust/crates/truapi-provider/src/ffi.rs) is the whole surface.
- the crate as a binary target — a GitHub release asset by default (`providerBinaryURL` in the root `Package.swift`), or the locally built `Binaries/truapi_provider.xcframework` when `TRUAPI_PROVIDER_USE_LOCAL_BINARY=1`.

The bindings are committed build outputs; the xcframework is **gitignored** and distributed as a GitHub release asset. Two scripts split the lifecycle:

```bash
./scripts/rebuild.sh            # build the crate for device + simulator, regenerate
                                # the bindings, and bundle Binaries/truapi_provider.xcframework
./scripts/publish.sh <version>  # zip the built xcframework, upload it to the
                                # "@parity/ios-provider <version>" GitHub release,
                                # and point the root Package.swift at it
                                # (URL + checksum)
```

Run `rebuild.sh` after changing anything in the crate's `uniffi` surface — the `ChainProvider` methods, `ChainMessageListener`, `ChainProviderError`, `ChainCloseReason` — or after a chain-spec refresh, and commit the regenerated bindings together with the source change. Pass `--sim-only` (or `make provider-ios SIM_ONLY=1`) to skip the device slice while iterating; `publish.sh` refuses a simulator-only xcframework.

## Integrating in an iOS app

Add the package as an SPM dependency and link the `TrUAPIProvider` product into the app target:

```swift
.package(url: "https://github.com/paritytech/host-rust-core.git", branch: "main")
```

```swift
.product(name: "TrUAPIProvider", package: "truapi")
```

Release tags follow the repo-wide `@parity/ios-provider@<version>` naming, which SPM's semver resolution does not consume — depend by `branch:` or `revision:` instead, as with `TrUAPIHost`.

No Rust toolchain is needed: the xcframework carries the compiled crate, and the chain specs are compiled into it, so the app ships no spec files of its own and never refreshes them. Picking up a spec refresh means taking a newer release.

## Public surface

Everything is generated from [`ffi.rs`](../../rust/crates/truapi-provider/src/ffi.rs):

- `ChainProvider` — construct **one per process** and share it. Every connection runs on the single embedded light client, so they share sync, peers, and warm state while keeping their own request queue and response stream. `connect(genesisHash:listener:)` resolves the network from the bundled catalog (relay wiring and statement-store placement included), so the 32-byte genesis hash is the only argument.
- `ChainMessageListener` — the host implements it; `onMessage(message:)` receives each JSON-RPC response and notification, `onClosed(reason:)` fires once the pump stops and names why. Both may throw: a listener that throws stops the pump for that connection rather than being called again for every response, and an error it does not declare is reported as `.listener(reason:)` instead of aborting the process.
- `ChainConnection` — `send(request:)` queues a request, `disconnect()` tears the connection down.
- `ChainCloseReason` — `.streamEnded` when the response stream ended, which includes your own `disconnect()` coming back to you, and `.listenerFailed(reason:)` when your listener rejected a message and the connection was closed for it. It says why the pump stopped, not whether you should reconnect; carry an `@unknown default`, since variants may be added. `reason` on `.listenerFailed` is bounded to 256 Unicode scalar values, so it can measure more than 256 in Swift's `Character` count and up to 1024 bytes. Reconnect from a *serial* queue off the pump thread: `connect(genesisHash:listener:)` refuses to run inside a listener callback and throws `.connect(reason:)` if you try. Do not re-queue work with `send(request:)` from `onClosed(reason:)`: the connection is already closed by then, and `send` on a closed connection is dropped silently, with no error and no response frame.
- `ChainProviderError` — `.connect(reason:)` when the genesis is outside the catalog or the transport fails, `.badGenesis` when the hash is not 32 bytes, `.listener(reason:)` when the host's listener failed in a way it did not declare.

## Architecture

```text
host app
  ChainProvider().connect(genesisHash:listener:)
           |
           v
libtruapi_provider (embedded smoldot + bundled chain-spec catalog)
  → one light client per process, one added chain per connection
  → responses pumped on a Rust-owned thread into ChainMessageListener
```

A connection is a raw JSON-RPC string pipe. The provider does no decoding: what smoldot answers is what the listener receives.

## Example

> **Threading:** the crate pumps each connection's responses on a background thread it owns, so `onMessage` and `onClosed` are never called on the main thread — hop to it before touching UIKit. `connect(genesisHash:listener:)` is synchronous and blocks the calling thread while the chain is added, so call it off the main thread.

```swift
import Foundation
import TrUAPIProvider

final class Responses: ChainMessageListener, @unchecked Sendable {
    func onMessage(message: String) throws {
        // A JSON-RPC response or subscription notification, verbatim from smoldot.
        DispatchQueue.main.async { /* decode and render */ }
    }

    func onClosed(reason: ChainCloseReason) throws {
        // Reached whichever way the connection ended, including your own
        // disconnect(). Reconnect on your own intent, not on this alone.
        switch reason {
        case .streamEnded:
            DispatchQueue.main.async { /* drop the connection */ }
        case .listenerFailed(let reason):
            // This listener rejected a message and the connection closed for it.
            DispatchQueue.main.async { print("chain listener failed: \(reason)") }
        @unknown default:
            DispatchQueue.main.async { /* drop the connection */ }
        }
    }
}

// One provider per process; hold it for the app's lifetime.
let provider = ChainProvider()

// 32 raw bytes, not a hex string. Must be a chain in the bundled catalog.
let genesis = Data(repeating: 0, count: 32)
let connection = try provider.connect(genesisHash: genesis, listener: Responses())

connection.send(request: #"{"jsonrpc":"2.0","id":1,"method":"chainSpec_v1_genesisHash","params":[]}"#)

// On teardown:
connection.disconnect()
```

## Build outputs in detail

`./scripts/rebuild.sh` orchestrates everything; the underlying pieces, should you need one in isolation:

- **static libraries** — `cargo build -p truapi-provider --no-default-features --features uniffi` for `aarch64-apple-ios` and `aarch64-apple-ios-sim`. The `ws` backend is off, so the build carries the light client only.
- **bindings** — the workspace `uniffi-bindgen-cli` reads the built `libtruapi_provider.a` and emits `truapi_provider.swift` plus `truapi_providerFFI.h`/`.modulemap`. The script copies them into `Sources/`, renaming the emitted `truapi_providerFFI.modulemap` to `module.modulemap` so the SwiftPM `systemLibrary` target picks it up.
- **xcframework** — `xcodebuild -create-xcframework` bundles the slices with those same headers, and the result is copied into `Binaries/`.

## Maintainers: cutting a release

```bash
make provider-ios                             # must include the device slice
./ios/truapi-provider/scripts/publish.sh 0.1.0
```

`publish.sh` creates the `@parity/ios-provider@<version>` release if the tag does not exist yet (targeting `IOS_RELEASE_TARGET` when set, otherwise the current branch), uploads the zipped xcframework, and rewrites `providerBinaryURL` and `providerBinaryChecksum` in the root `Package.swift`. Commit that manifest change **after** the upload succeeds: a manifest pointing at an asset that is not live yet breaks every consumer resolving in that window.

The provider and the host use separate tag namespaces, so releasing one never moves the other.
