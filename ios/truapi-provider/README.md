# TrUAPIProvider

Chain transport for native hosts: an embedded [smoldot](https://github.com/smol-dot/smoldot)
light client with a bundled chain-spec catalog, addressed by genesis hash.

This package is a binary distribution of the
[`truapi-provider`](../../rust/crates/truapi-provider) crate over UniFFI. A
consumer needs no Rust toolchain and takes no dependency on the crate.

It is independent of [`TrUAPIHost`](../truapi-host): the two are separate products
of the same SPM package, and a project can depend on either or both.

## Consuming it

Add the repository as a package dependency and pick the `TrUAPIProvider` product:

```swift
.package(url: "https://github.com/paritytech/truapi.git", from: "0.1.0")
```

```swift
.target(name: "YourApp", dependencies: [
    .product(name: "TrUAPIProvider", package: "truapi")
])
```

Then connect to a chain by genesis hash and exchange JSON-RPC strings. Responses
arrive on a listener rather than a pull loop, and the genesis hash is 32 raw
bytes:

```swift
import TrUAPIProvider

final class Responses: ChainMessageListener {
    func onMessage(message: String) { /* JSON-RPC response or notification */ }
    func onClosed() {}
}

let provider = ChainProvider()
let connection = try provider.connect(genesisHash: genesis, listener: Responses())

connection.send(request: #"{"jsonrpc":"2.0","id":1,"method":"chainSpec_v1_genesisHash","params":[]}"#)
connection.close()
```

Construct **one provider per process** and share it: every connection runs on the
single embedded light client, so they share sync, peers and warm state while
keeping their own request queue and response stream.

The catalog resolves the relay wiring and statement-store placement for a bundled
network, so the genesis hash is the only argument. A hash outside the catalog
fails with `ProviderError.connect`.

## Layout

```
Sources/TrUAPIProvider/          uniffi-generated Swift (committed)
Sources/truapi_providerFFI/      C header + module map (committed)
Binaries/                        the xcframework (gitignored, see below)
scripts/rebuild.sh               regenerate bindings + xcframework from the crate
scripts/publish.sh               upload the xcframework and update Package.swift
```

The bindings are committed so a plain git checkout resolves. The xcframework is
not: it is a release asset, and the root `Package.swift` carries its URL and
checksum.

## Working on it locally

```bash
make provider-ios              # bindings + xcframework, device and simulator
make provider-ios SIM_ONLY=1   # simulator slice only, for a faster loop

TRUAPI_PROVIDER_USE_LOCAL_BINARY=1 swift build --target TrUAPIProvider
```

`TRUAPI_PROVIDER_USE_LOCAL_BINARY` is deliberately separate from
`TRUAPI_USE_LOCAL_BINARY`: the two products release on their own schedules, so
building one against a local binary must not require the other to have one.

## Releasing

```bash
make provider-ios                             # must include the device slice
./ios/truapi-provider/scripts/publish.sh 0.1.0
```

That uploads the asset under the tag `@parity/ios-provider@<version>` and rewrites
`providerBinaryURL` / `providerBinaryChecksum` in the root `Package.swift`. Commit
that change only after the upload succeeds: a manifest pointing at an asset that
is not live yet breaks every consumer resolving in that window.
