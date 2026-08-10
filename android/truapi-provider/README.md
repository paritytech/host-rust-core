# truapi-provider-android

Chain transport for Android hosts: an embedded [smoldot](https://github.com/smol-dot/smoldot)
light client with a bundled chain-spec catalog, addressed by genesis hash.

The AAR carries the UniFFI Kotlin bindings **and** `libtruapi_provider.so` for
every published ABI, so a consumer needs no Rust toolchain and takes no
dependency on the crate. (This is the one difference from
[`truapi-host`](../truapi-host), whose AAR leaves the cdylib to the consumer.)

## Using it

```kotlin
import uniffi.truapi_provider.ChainProvider
import uniffi.truapi_provider.ChainMessageListener

val provider = ChainProvider()

val connection = provider.connect(genesisHash, object : ChainMessageListener {
    override fun onMessage(message: String) { /* JSON-RPC response or notification */ }
    override fun onClosed() {}
})

connection.send("""{"jsonrpc":"2.0","id":1,"method":"chainSpec_v1_genesisHash","params":[]}""")
connection.close()
```

`genesisHash` is 32 raw bytes. Construct **one provider per process** and share
it: every connection runs on the single embedded light client, so they share sync,
peers and warm state while keeping their own request queue and response stream.

The catalog resolves relay wiring and statement-store placement for a bundled
network, so the genesis hash is the only argument. A hash outside the catalog
fails with `ProviderError.Connect`.

## Building it

```bash
make provider-kotlin                  # regenerate the Kotlin bindings
make provider-android-jni             # cross-compile the cdylib per ABI (cargo-ndk + NDK)
make provider-android-publish-local   # both of the above, then publish to ~/.m2
```

Published ABIs are `arm64-v8a`, `armeabi-v7a` and `x86_64` (`ANDROID_ABIS`
overrides them). Publishing refuses to run when `src/main/jniLibs` has no
`libtruapi_provider.so`, because that AAR would resolve and then fail at the first
`ChainProvider()` with an `UnsatisfiedLinkError`.

Both the generated bindings and the `.so` files are gitignored build outputs.

## Distribution

`publishToMavenLocal` gives coordinates `io.parity:truapi-provider-android:0.1.0`,
which a consumer picks up through `mavenLocal()`. That is enough for local
development against an unreleased build.

A remote coordinate still needs a hosted Maven repository — GitHub Packages, or a
release asset served as a Maven repo. JitPack cannot serve this module as it
stands, because it builds from a git tag and both the bindings and the cdylib are
generated rather than committed.
