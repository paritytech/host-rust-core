# @parity/truapi-host

WASM-backed TrUAPI host runtime. It embeds the `truapi-server` Rust core (compiled to WASM)
behind a Web Worker provider, plus per-environment integration entry points. It is the
counterpart to the native Android/iOS host shells.

`executionKind: "Chat"` is accepted by the runtime config but not served: the
Chat modality reaches products through a host-supplied `ChatPlatform` adapter,
which only the native (UniFFI) entrypoints can install. A JS host that opens a
`Chat` execution gets a provider whose Chat requests answer unsupported; its
subscriptions end empty, which is indistinguishable from a healthy close.
Tracked in paritytech/host-rust-core#383.

## Entry points

The package exposes tree-shakeable subpath exports — import only what your environment needs:

| Import                               | Provides                                                                                                            |
| ------------------------------------ | ------------------------------------------------------------------------------------------------------------------- |
| `@parity/truapi-host`                | Shared runtime types plus generated typed host callback contracts.                                                  |
| `@parity/truapi-host/web`            | Browser pairing host: `createIframeHost` (iframe MessageChannel handshake) and `createWebWorkerPairingHostRuntime`. |
| `@parity/truapi-host/worker-runtime` | Web Worker entrypoint (import with your bundler's `?worker` suffix) so the WASM core runs off the page main thread. |
| `@parity/truapi-host/wasm/web`       | The raw browser `wasm-bindgen` glue, if you need to instantiate the core yourself.                                  |

## Bundler requirements

The worker imports the WASM glue by a literal specifier, so every bundler
resolves it statically and emits `truapi_server.js` as a chunk. Whether the
`truapi_server_bg.wasm` payload comes with it depends on the bundler: emitting
it requires treating `new URL("truapi_server_bg.wasm", import.meta.url)` inside
the glue as an asset reference, and not all of them do.

| Bundler             | Emits the `.wasm`? | Host action                                                    |
| ------------------- | ------------------ | -------------------------------------------------------------- |
| Vite                | Yes                | None — no copy step, and don't reach into `dist/wasm/web/`.    |
| webpack 5           | Yes                | None.                                                          |
| Rollup (standalone) | No                 | Add `@web/rollup-plugin-import-meta-assets`, or copy manually. |
| esbuild             | No                 | Copy manually (see below).                                     |
| Bun (`bun build`)   | No                 | Copy manually (see below).                                     |

esbuild and Bun pass `new URL(..., import.meta.url)` through verbatim: the build
succeeds and the glue chunk is emitted, but no `.wasm` is written and the worker
404s at runtime. No flag changes this — `--loader:.wasm=file` only fires on
`import` statements, never on `new URL`. Hosts on those bundlers must copy
`truapi_server_bg.wasm` out of `@parity/truapi-host/dist/wasm/web/` into the same
output directory as the emitted `truapi_server-*.js` chunk, since the glue
resolves the payload relative to its own URL.

Running Vite under Bun (`bunx --bun vite build`) uses Vite's bundler and is
unaffected; only `bun build` is.

The literal import makes the worker a code-split chunk, so a Vite host must ask
for ES workers; the default `iife` format cannot code-split and fails the build:

```ts
export default defineConfig({ worker: { format: "es" } });
```

Only the `.wasm` the glue references is emitted, and bundlers content-hash it —
Vite writes `assets/truapi_server_bg-<hash>.wasm`, webpack writes a bare
`<hash>.wasm`. The `.wasm.gz` / `.wasm.br` sidecars under `dist/wasm/web/`
therefore cannot be copied into a host's output: `gzip_static` /
`brotli_static` serve `<request-path>.gz` / `.br`, and the request path now
carries the bundler's hash. Hosts that serve precompressed assets should
generate them from their own build output, after hashing — either a post-build
pass over `dist` (gzip level 9 and brotli max quality reproduce the sidecars
byte for byte) or a bundler plugin:

```ts
import { compression } from "vite-plugin-compression2";

export default defineConfig({
  worker: { format: "es" },
  plugins: [
    compression({ include: [/\.(js|css|html|wasm)$/], algorithms: ["gzip"] }),
    compression({
      include: [/\.(js|css|html|wasm)$/],
      algorithms: ["brotliCompress"],
    }),
  ],
});
```

webpack hosts get the same result from `compression-webpack-plugin`. Skipping
this ships the full 1.4 MB `.wasm` where about 600 kB (gzip) or 470 kB (brotli)
would do — and a server configured with `gzip_static` but no dynamic `gzip on`
has no fallback.

## Generated WASM artefacts

The ignored bundle under `dist/wasm/web/` is built with host-owned chain access.
Hosts wire their JSON-RPC provider through `chainConnect`; if they omit it,
chain calls fail with the core's standard unavailable error. Release builds use
the workspace size-optimized Rust profile plus `wasm-opt -Oz`, validate that
debug/name/producers custom sections were stripped, and emit `.wasm.gz` and
`.wasm.br` sidecars for hosts that serve precompressed assets.

Build them after editing `rust/crates/truapi-server` and before packaging, publishing, or running
tests that load the raw WASM bundle (requires `wasm-pack` on PATH):

```bash
npm run build:wasm   # or `make wasm` from the repo root
```

## Example — browser (Web Worker)

```ts
import HostWorker from "@parity/truapi-host/worker-runtime?worker";
import { createWebWorkerPairingHostRuntime } from "@parity/truapi-host/web";

const runtime = await createWebWorkerPairingHostRuntime(
  new HostWorker(),
  callbacks,
  {
    hostConfig,
  },
);

const firstProvider = await runtime.createProvider({ productId: "first.dot" });
const secondProvider = await runtime.createProvider({
  productId: "second.dot",
});
```

`@parity/truapi-host/web` also exports `createIframeHost` for the
protocol-iframe MessageChannel handshake. Host code creates one worker runtime
and then opens one provider per product id.

## Session lifecycle

The core owns the session; the host owns persistence and drives the transitions
below. Every one of them reports the resulting `AuthState` through the `auth`
callback, including when nothing changed — so a host may await an answer at boot
rather than treating silence as "signed out".

| Runtime method                  | Use it to                                                                    |
| ------------------------------- | ---------------------------------------------------------------------------- |
| `activateStoredSession()`       | Restore the session in the core's `AuthSession` slot. Await before routing.  |
| `activateExternalSession(blob)` | Install a session the host holds itself, without writing it to core storage. |
| `notifySessionStoreChanged()`   | Tell the core the persisted blob may have changed; it re-reads it.           |
| `disconnectSession()`           | Log out: clears the session and notifies the peer.                           |
| `resetSessionState()`           | Drop the local session without notifying the peer.                           |

The boot order is create the runtime, restore, then open providers:

```ts
const runtime = await createWebWorkerPairingHostRuntime(
  new HostWorker(),
  callbacks,
  { hostConfig },
);

// Resolves once product frames may use the restored session; rejects when
// there was nothing to restore.
await runtime.activateStoredSession().catch(() => {});

const provider = await runtime.createProvider({ productId: "first.dot" });
```

## Debugging (dev-only)

The worker can stream every product↔core wire frame to the wire debugger. It is
off by default and enabled purely from the host page — the product needs no
changes. Two conditions must **both** hold or nothing dials, the core installs no
tap, and nothing is logged:

1. **The host page is a dev build.** The `localStorage` read sits behind a hard
   `import.meta.env.DEV` gate, which bundlers replace with a boolean literal: in
   a production bundle it returns `null` unconditionally, so no stored key can
   turn the tap on. A production build that shows no frames is this gate, not a
   broken debugger.
2. **The host origin's `localStorage` carries a `ws://` loopback URL**, read on
   the host page at runtime boot and forwarded to the worker in its `init`
   message:

   ```js
   localStorage.setItem("truapi:debugger", "ws://127.0.0.1:9231");
   ```

Run the debugger at the other end (`@parity/truapi-debugger`, `npm run serve`,
`127.0.0.1:9231`). On the next runtime boot the worker dials that URL and (via
the Rust core's `DebugSink` tap) sends each frame as `{ channelId, dir, frame }`.

The URL must be `ws://` on a loopback host. Anything else — `wss://`, `http://`,
a LAN or public address, a non-loopback hostname — yields an inert link and a
`wire debugger URL rejected` console warning; there is no certificate or `wss`
path. Prefer the literal `127.0.0.1` over `localhost`: `localhost` passes the
gate, but it resolves `::1` first on macOS while the debugger binds `127.0.0.1`
alone, so the same URL handed to a native host (`truapi-server`'s `WsDebugSink`
dials the first resolved address) silently never connects.

The debugger owns all decoding and decodes every frame it can, including signing
and payment payloads; its safety is the dev-build gate above, not redaction. See
`js/packages/truapi-debugger/README.md` for the tap, the envelope, and the
host-dials-debugger topology.

## Publishing

This package is published by the root `Release` workflow through
`paritytech/npm_publish_automation`. Do not run `npm publish` locally. Cut a
`release:` PR with a changeset for `@parity/truapi-host`; the workflow builds
the generated host bindings, the browser WASM bundle, packs the tarball, and
publishes it when the `@parity/truapi-host@<version>` tag does not already
exist.

## Architecture

```text
JS host code
  protocol handlers / typed callbacks
  (types from @parity/truapi-host)
       |
       v
createWebWorkerPairingHostRuntime
  shared worker runtime: pairing session, chain runtime, WASM instance
       |
       +-- createProvider({ productId }) -> product core / WireProvider
       |
       +-- createProvider({ productId }) -> product core / WireProvider
```
