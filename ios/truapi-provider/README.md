# TrUAPI iOS chain transport

*Swift shell over the `truapi-provider` crate (UniFFI). An embedded smoldot light client and the bundled chain-spec catalog stay in Rust; the host addresses a chain by genesis hash and exchanges JSON-RPC strings.*

The package lives in the truapi repo next to the Rust crate it wraps, with its own `Package.swift` in this directory. It is independent of [`TrUAPIHost`](../truapi-host), whose manifest sits at the repo root: a host depends on whichever it needs.

## What this package is for

The `TrUAPIProvider` SPM product an iOS host imports when it wants to serve chain traffic itself rather than proxying it. It carries:

- `Sources/TrUAPIProvider/truapi_provider.swift` and `Sources/truapi_providerFFI/include/` — the generated UniFFI bindings. There is no hand-written Swift shell: the crate's [`ffi.rs`](../../rust/crates/truapi-provider/src/ffi.rs) is the whole surface.
- the crate as a binary target: the locally built `Binaries/truapi_provider.xcframework`.

The bindings and the xcframework are both **gitignored** build outputs, so the package's Swift target does not exist until `rebuild.sh` has run. Two scripts split the lifecycle:

```bash
./scripts/rebuild.sh            # build the crate for device + simulator, regenerate
                                # the bindings, and stage Binaries/truapi_provider.xcframework
./scripts/stage-xcframework.sh  # copy the built xcframework into Binaries/ and strip the
                                # per-slice module.modulemap (rebuild.sh calls it for you)
```

The strip matters because module resolution comes from the `systemLibrary` target; a slice copy collides with other xcframeworks in Xcode's flat include dir, which is what stops a host embedding both this and its own UniFFI framework.

Run `rebuild.sh` after changing anything in the crate's `uniffi` surface — the `ChainProvider` methods, `ChainMessageListener`, `ChainProviderError`, `ChainCloseReason` — or after a chain-spec refresh, to refresh your local build outputs; the bindings are gitignored and CI regenerates them. Pass `--sim-only` (or `make provider-ios SIM_ONLY=1`) to skip the device slice while iterating.

## Integrating in an iOS app

Depend on the package by path and link the `TrUAPIProvider` product into the app target. Run `rebuild.sh` first, since the package has no Swift sources or binary until then:

```swift
.package(name: "TrUAPIProvider", path: "<path to the repository root>/ios/truapi-provider")
```

```swift
.product(name: "TrUAPIProvider", package: "TrUAPIProvider")
```

The chain specs are compiled into the xcframework, so the app ships no spec files of its own. Picking up a spec refresh means rebuilding from a newer checkout.

## Public surface

Everything is generated from [`ffi.rs`](../../rust/crates/truapi-provider/src/ffi.rs):

- `ChainProvider` — construct **one per process** and share it. Every connection runs on the single embedded light client, so they share sync, peers, and warm state while keeping their own request queue and response stream. `connect(genesisHash:listener:)` resolves the network from the bundled catalog (relay wiring and statement-store placement included), so the 32-byte genesis hash is the only argument. At most 32 connections are held at once: past that, `connect(genesisHash:listener:)` throws `.connect(reason:)` rather than adding another chain, and `disconnect()` hands the slot back. That ceiling is a backstop against connections you never close, not a budget to spend; the catalog resolves eight chains, so one reused connection per chain stays well under it.
- `ChainMessageListener` — the host implements it; `onMessage(message:)` receives each JSON-RPC response and notification, `onClosed(reason:)` fires once the pump stops and names why. Both may throw: a listener that throws stops the pump for that connection rather than being called again for every response, and an error it does not declare is reported as `.listener(reason:)` instead of aborting the process.
- `ChainConnection` — `send(request:)` queues a request, `disconnect()` tears the connection down.
- `ChainCloseReason` — `.streamEnded` when the response stream ended, which includes your own `disconnect()` coming back to you, and `.listenerFailed(reason:)` when your listener rejected a message and the connection was closed for it. It says why the pump stopped, not whether you should reconnect; carry an `@unknown default`, since variants may be added. That is source compatibility only: adding a variant does not change the `on_closed` checksum, so bindings older than the binary pass the integrity check and then fail to decode the reason, which surfaces as `onClosed` never firing. Regenerate bindings and binary together. `reason` on `.listenerFailed` is bounded to 256 Unicode scalar values, so it can measure more than 256 in Swift's `Character` count and up to 1024 bytes. Reconnect from a *serial* queue off the pump thread: `connect(genesisHash:listener:)` refuses to run inside a listener callback and throws `.connect(reason:)` if you try. Do not re-queue work with `send(request:)` from `onClosed(reason:)`: the connection is already closed by then, and `send` on a closed connection is dropped silently, with no error and no response frame.
- `ChainProvider.withStorage(store:)` — build a provider that resumes each chain from stored finalized state instead of warp syncing from the checkpoint in the chain spec. The plain `ChainProvider()` stores nothing, so `loadDatabase` and `saveDatabase` throw on it rather than doing nothing. The crate ships no storage of its own: you own where the bytes live, and with it whether the directory is backed up, encrypted, or excluded from iCloud.
- `StorageClient` — implement it over your own storage, typically `FileManager` under `applicationSupportDirectory`. `load(genesisHash:)` answers the stored string or `nil`, `save(genesisHash:blob:)` replaces it, and both take a 32-byte hash as `Data`. A client that cannot answer must throw: returning no blob means "nothing stored yet" and lets the next write replace good state. Both are awaited on the thread the caller drives, so the implementation must not require the main actor.
- `loadDatabase(genesisHash:)` — read the stored state for a chain in before connecting to it. Call it first: smoldot consumes a blob only on the first add of a chain, so a later call cannot take effect and answers `false`.
- `saveDatabase(genesisHash:)` — snapshot the finalized state of a running chain into your storage. Answers `false`, without writing, for a chain that has finalized nothing yet or that the embedded client is not running. It is a full round trip through the light client, so drive it while the app is alive and treat a call from a backgrounding callback as best effort.
- `ChainProviderError` — `.connect(reason:)` when the genesis is outside the catalog or the transport fails, `.badGenesis` when the hash is not 32 bytes, `.listener(reason:)` when the listener the host installed failed in a way it did not declare, `.storage(reason:)` when your storage failed or the provider has none. Your client reports its own failures as `StorageClientError`. Adding a case here does not change the checksum of the methods that return it, so bindings older than the binary pass the integrity check and then fail to decode the new case. Regenerate bindings and binary together, exactly as `ChainCloseReason` above requires.

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
