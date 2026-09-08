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
import { openIndexedDbWarmStore } from "@parity/truapi-provider/warm-store";
import wasmUrl from "@parity/truapi-provider/truapi_provider_bg.wasm?url";

await init({ module_or_path: wasmUrl });

const builder = new ChainProviderBuilder();
const chains = builder.addNetwork("paseo-next-v2");
builder.setWarmStore(openIndexedDbWarmStore());

const provider = builder.build();

// Seed the relay from the blob the store already holds, before connecting.
await provider.warmUp(chains.relay);
const connection = await provider.connect(chains.relay);

connection.send('{"jsonrpc":"2.0","id":1,"method":"chainSpec_v1_genesisHash","params":[]}');
const response = await connection.nextResponse(); // undefined once closed
connection.close();

// Later, with the page or worker still alive, write finalized state back.
// Resolves false while the chain has finalized nothing worth storing.
await provider.persist(chains.relay);
```

## Warm start

A light client that starts from a stored blob resumes from finalized state
instead of warp syncing from the chain-spec checkpoint. The provider owns when
a blob is read and written; the host owns where it lives.

`setWarmStore()` takes any object with `load(genesisHashHex)` resolving to the
stored string or `null`, and `save(genesisHashHex, blob)`. Both are called with
a `0x`-prefixed lowercase genesis hash and may return a promise. A store that
cannot answer must reject. Resolving `null` means nothing is stored yet, so a
failed read reported that way lets the next `persist()` overwrite good state.

On the web, use the bundled IndexedDB store:

```js
import { openIndexedDbWarmStore } from "@parity/truapi-provider/warm-store";

const store = openIndexedDbWarmStore(); // { databaseName } to override
```

It keeps one record per chain, keyed by genesis hash, in the
`truapi-provider-warm-start` database. That name is a persisted browser key.
Renaming it strands every blob already written under the old name, and those
chains warp sync again. Do not put blobs in `localStorage`: a snapshot runs to
several megabytes against a quota near five, and the write blocks the main
thread.

`warmUp()` has to run before the first `connect()` for that chain. smoldot keys
a chain by its genesis hash and ignores the blob on every add after the first,
so a later seed cannot take effect; the provider logs a warning and answers
`false` rather than letting the chain stay silently cold.

`persist()` answers `false` for a chain this provider never connected, rather
than starting one just to snapshot it.

`snapshot()` and `setDatabase()` remain for a host that keeps blobs somewhere
the provider cannot reach.

#### Save on a cadence, not on the way out

`persist()` is a round trip through the light client, so it needs the context to
stay scheduled. There is no save-on-exit on the web: the provider usually runs
in a Web Worker, which sees neither `pagehide` nor `visibilitychange`, and
neither event keeps an async snapshot alive long enough to land.

Use the shipped loop rather than writing your own:

```js
import { startWarmStartPersistence } from "@parity/truapi-provider/warm-store";

const stop = startWarmStartPersistence(provider, [
  chains.relay,
  chains.people,
]);
// stop() when the worker or page is done with the provider.
```

It waits 30 seconds before the first round, then repeats every 60 seconds, and
skips a tick while the previous round is still running so a slow chain cannot
build a backlog of snapshots of the same state. Both intervals are options. A
chain that fails is reported through `onError` and does not stop the others;
the default reports to `console.warn`, because a store that quietly stops
writing looks exactly like one that is working until the next cold start.

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
