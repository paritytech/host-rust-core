# @parity/truapi-provider

Network transport for the TrUAPI `ChainProvider` contract: an embedded
[smoldot](https://github.com/smol-dot/smoldot) light client, or a remote
WebSocket JSON-RPC node, behind one API. This package is the WebAssembly build,
for browser and desktop (webview) hosts.

You connect to a network by its genesis hash, and everything else is handled for
you: the bundled catalog provides the spec and relay wiring, so clients never
ship or refresh specs of their own. One light client is shared across all
connections, and its synced state is kept between launches, so a launch resumes
from finalized state instead of syncing from scratch.

## Usage

#### Web (JavaScript)

The published package is `wasm-bindgen` glue plus a `.wasm` binary. Instantiate
the module once per page or worker.

```js
import init, { ChainProviderBuilder } from "@parity/truapi-provider";
import wasmUrl from "@parity/truapi-provider/truapi_provider_bg.wasm?url";

await init({ module_or_path: wasmUrl });

const builder = new ChainProviderBuilder();
const chains = builder.addNetwork("paseo-next-v2");

const provider = builder.build();
const connection = await provider.connect(chains.relay);

connection.send(
  '{"jsonrpc":"2.0","id":1,"method":"chainSpec_v1_genesisHash","params":[]}',
);
const response = await connection.nextResponse(); // undefined once closed
connection.close();
```

Warm start is opt-in, because this package stores nothing itself. Hand
`setStorage` a client to storage you already own:

```js
builder.setStorage({
  async load(genesisHash) {
    return (await myStore.get(genesisHash)) ?? null;
  },
  async save(genesisHash, blob) {
    await myStore.put(genesisHash, blob);
  },
});
```

Both are called with a `0x`-prefixed lowercase genesis hash. A client that cannot
answer must reject rather than resolve `null`, which means "nothing stored yet"
and would let the next write replace good state. Without a client every chain
syncs from the checkpoint in the chain spec on every run.

`setDatabaseContent(genesisHash, blob)` seeds one chain for this run and beats
anything the client would load for it. `saveDatabase(genesisHash)` forces a write
at a moment the host chooses.

## Native hosts

Android and iOS do not consume this package. The same `truapi-provider` crate is
published for them as its own artifacts over UniFFI — a `TrUAPIProvider` Swift
package and a `truapi-provider-android` AAR — exposing the same `ChainProvider`
contract with the same bundled catalog, so the wiring differs only in language.

## Building

The `dist/` bundle is generated and gitignored. Rebuild it from the Rust crate:

```bash
npm run build           # wasm-pack --target web, features "js networks"
```

`wasm-pack` is required (`cargo install wasm-pack`). Set `TRUAPI_WASM_PROFILE=dev`
for a fast unoptimized build. The repo's `make wasm` target rebuilds this bundle
alongside the host runtime.

## License

MIT AND Apache-2.0. See [LICENSE](LICENSE), [LICENSE-APACHE](LICENSE-APACHE), and
[NOTICE](NOTICE).
