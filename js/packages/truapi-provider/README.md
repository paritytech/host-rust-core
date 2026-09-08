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

#### Web (JavaScript)

The published package is `wasm-bindgen` glue plus a `.wasm` binary. Instantiate
the module once per page or worker.

```js
import init, { ChainProviderBuilder } from "@parity/truapi-provider";
import { openIndexedDbWarmStore } from "@parity/truapi-provider/warm-store";
import wasmUrl from "@parity/truapi-provider/truapi_provider_bg.wasm?url";

await init({ module_or_path: wasmUrl });

const builder = new ChainProviderBuilder();
const chains = builder.addNetwork("paseo-next-v2");
builder.setWarmStore(openIndexedDbWarmStore());

const provider = builder.build();
const connection = await provider.connect(chains.relay);

connection.send(
  '{"jsonrpc":"2.0","id":1,"method":"chainSpec_v1_genesisHash","params":[]}',
);
const response = await connection.nextResponse(); // undefined once closed
connection.close();
```

## Warm start

A light client that starts from a stored blob resumes from finalized state
instead of warp syncing from the chain-spec checkpoint.

Give the provider somewhere to keep blobs and it handles the rest: it reads a
chain's blob before connecting to it, and from then on snapshots that chain's
finalized state into the store, 30 seconds after the connect and every minute
after that. There is nothing to call and no cadence to choose.

```js
import { openIndexedDbWarmStore } from "@parity/truapi-provider/warm-store";

builder.setWarmStore(openIndexedDbWarmStore());
```

The store keeps one record per chain, keyed by genesis hash, in the
`truapi-provider-warm-start` database. That name is a persisted browser key:
renaming it strands every blob already written under the old name, and those
chains warp sync again. `openIndexedDbWarmStore({ databaseName })` overrides it.

Warm start is an optimisation, never a dependency. A store that cannot answer
leaves the chain to sync from the checkpoint; it does not fail the connect. Do
not keep blobs in `localStorage`: a snapshot runs to several megabytes against
a quota near five, and the write blocks the main thread.

`setWarmStore()` accepts any object with `load(genesisHashHex)` resolving to the
stored string or `null`, and `save(genesisHashHex, blob)`. A store that cannot
answer must reject rather than resolve `null`, which means "nothing stored yet"
and would let the next snapshot overwrite good state.

`warmUp()` and `persist()` remain for a host that would rather drive both
itself, and `snapshot()`/`setDatabase()` for one that keeps blobs somewhere the
provider cannot reach.

## Native hosts

Android and iOS do not consume this package. The same `truapi-provider` crate is
published for them as its own artifacts over UniFFI — a `TrUAPIProvider` Swift
package and a `truapi-provider-android` AAR — exposing the same `ChainProvider`
contract with the same bundled catalog, so the wiring differs only in language.

## Building

The `dist/` bundle is generated and gitignored. It has two halves: the
wasm-bindgen glue and binary at the top level, and the compiled `./warm-store`
entry under `dist/js/`.

```bash
npm run build           # both halves
npm run build:wasm      # wasm-pack --target web, features "js networks"
npm run build:ts        # tsc, emits dist/js/
npm test                # bun test, against fake-indexeddb
```

`wasm-pack` is required (`cargo install wasm-pack`). Set `TRUAPI_WASM_PROFILE=dev`
for a fast unoptimized build. The repo's `make wasm` target rebuilds the wasm
half alongside the host runtime; run `npm run build:ts` as well before
publishing, or before importing `@parity/truapi-provider/warm-store` from a
local checkout.

## License

MIT AND Apache-2.0. See [LICENSE](LICENSE), [LICENSE-APACHE](LICENSE-APACHE), and
[NOTICE](NOTICE).
