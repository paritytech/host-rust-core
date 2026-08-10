# @parity/truapi-provider

Network transport for the TrUAPI `ChainProvider` contract: an embedded
[smoldot](https://github.com/smol-dot/smoldot) light client, or a remote
WebSocket JSON-RPC node, behind one API. This package is the WebAssembly build,
for browser and desktop (webview) hosts.

You connect to a network by its genesis hash, and everything else is handled for
you: the bundled catalog provides the spec and relay wiring, so clients never
ship or refresh specs of their own. One light client is shared across all
connections. Its synced state can be captured and restored, so a launch resumes
from finalized state instead of syncing from scratch.

## Usage

Build a provider, connect to a network by its genesis hash, and exchange JSON-RPC
request and response strings over the connection. Every connection shares the one
embedded light client.

#### Web (JavaScript)

The published package is `wasm-bindgen` glue plus a `.wasm` binary. Instantiate
the module once per page or worker.

```js
import init, { ChainProviderBuilder } from "@parity/truapi-provider";
import wasmUrl from "@parity/truapi-provider/truapi_provider_bg.wasm?url";

await init({ module_or_path: wasmUrl });

const genesis = "0x3740…";
const builder = new ChainProviderBuilder();

// Resume from the state saved by the previous run, when there is one.
const saved = localStorage.getItem(`chain-db:${genesis}`);
if (saved) builder.setDatabase(genesis, saved);

const provider = builder.build();
const connection = await provider.connect(genesis);

connection.send('{"jsonrpc":"2.0","id":1,"method":"chainSpec_v1_genesisHash","params":[]}');
const response = await connection.nextResponse(); // undefined once closed
connection.close();

// Later, once the light client has synced, save state for the next launch.
localStorage.setItem(`chain-db:${genesis}`, await provider.snapshot(genesis));
```

Warm start is driven by the host: call `snapshot()` once the light client has
synced, persist the string, and hand it back through `setDatabase()` before
`build()` on the next launch.

## Native hosts

Android and iOS do not consume this package. The same `truapi-provider` crate is
published for them as its own artifacts over UniFFI — a `TrUAPIProvider` Swift
package and a `truapi-provider-android` AAR — exposing the same `ChainProvider`
contract with the same bundled catalog, so the wiring differs only in language.

## Building

The `dist/` bundle is generated and gitignored. Rebuild it from the Rust crate:

```bash
npm run build:wasm      # wasm-pack --target web, features "js networks"
```

`wasm-pack` is required (`cargo install wasm-pack`). Set `TRUAPI_WASM_PROFILE=dev`
for a fast unoptimized build. The repo's `make wasm` target rebuilds this bundle
alongside the host runtime.

## License

MIT AND Apache-2.0. See [LICENSE](LICENSE), [LICENSE-APACHE](LICENSE-APACHE), and
[NOTICE](NOTICE).
