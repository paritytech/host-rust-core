# @parity/truapi-host

WASM-backed TrUAPI host runtime. It embeds the `truapi-server` Rust core (compiled to WASM)
behind a Web Worker provider, plus per-environment integration entry points. It is the
counterpart to the native Android/iOS host shells.

## Entry points

The package exposes tree-shakeable subpath exports — import only what your environment needs:

| Import                               | Provides                                                                                                                      |
| ------------------------------------ | ----------------------------------------------------------------------------------------------------------------------------- |
| `@parity/truapi-host`                | Shared runtime types plus generated typed host callback contracts.                                                            |
| `@parity/truapi-host/web`            | Browser pairing host: `createIframeHost` (iframe MessageChannel handshake) and `createWebWorkerPairingHostRuntime`.           |
| `@parity/truapi-host/worker-runtime` | Web Worker entrypoint (import with your bundler's `?worker` suffix) so the WASM core runs off the page main thread.           |
| `@parity/truapi-host/wasm/web`       | Bundler-free `wasm-bindgen` module with manual initialization and both `WasmPairingHostRuntime` and `WasmSigningHostRuntime`. |

## Generated WASM artefacts

The ignored bundle under `dist/wasm/web/` is built with host-owned chain access.
Hosts wire their JSON-RPC provider through `chainConnect`; if they omit it,
chain calls fail with the core's standard unavailable error. The Cargo invocation
deliberately disables default features and explicitly enables
`wasm-signing-host`; the pairing wrapper is unconditional. After `wasm-pack`,
the build fails unless both `WasmPairingHostRuntime` and
`WasmSigningHostRuntime` have constructors in the generated JavaScript and
type declarations.

Release builds use the workspace size-optimized Rust profile plus
`wasm-opt -Oz`, validate that debug/name/producers custom sections were
stripped, and emit `.wasm.gz` and `.wasm.br` sidecars for hosts that serve
precompressed assets.

Build them after editing `rust/crates/truapi-server` and before packaging, publishing, or running
tests that load the raw WASM bundle (requires `wasm-pack` on PATH):

```bash
npm run build:wasm   # or `make wasm` from the repo root
```

Each successful build also writes deterministic
`dist/wasm/web/artifact-manifest.json`, exported as
`@parity/truapi-host/wasm/web/artifact-manifest.json`. Its `schemaVersion`,
`packageName`, `packageVersion`, and `buildProfile` fields describe the build;
each entry under `files` records the SHA-256 digest and byte `size` of
`truapi_server.js` and `truapi_server_bg.wasm`. Consumers can compare both
downloaded files with an independently trusted copy of the manifest before
loading them. This package-provenance manifest does not replace product
identity or permission checks.

## Example — bundler-free static WASM

Copy `truapi_server.js`, `truapi_server_bg.wasm`, and
`artifact-manifest.json` from `dist/wasm/web/` to the same static directory,
then use the browser-native module and pass the WASM URL to its default
initializer:

```html
<script type="module">
  import init, {
    WasmPairingHostRuntime,
    WasmSigningHostRuntime,
  } from "/vendor/truapi-host/truapi_server.js";

  await init("/vendor/truapi-host/truapi_server_bg.wasm");

  // Choose the role implemented by this host:
  const runtime = new WasmPairingHostRuntime(
    pairingCallbacks,
    pairingHostConfig,
  );
  // Or, for a wallet-local signing host:
  // const runtime = new WasmSigningHostRuntime(
  //   signingCallbacks,
  //   signingHostConfig,
  // );
</script>
```

`WasmPairingHostRuntime` manages a shared pairing session and creates
product-scoped runtimes. `WasmSigningHostRuntime` manages a wallet-local
signing session and creates the same product-scoped runtime interface. The
explicit `init()` call makes this entry usable without a bundler or WASM loader
plugin.

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

// The trusted host loader computes this digest from the exact verified bundle.
const artifactSha256 = new Uint8Array([
  0x00, 0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07,
  0x08, 0x09, 0x0a, 0x0b, 0x0c, 0x0d, 0x0e, 0x0f,
  0x10, 0x11, 0x12, 0x13, 0x14, 0x15, 0x16, 0x17,
  0x18, 0x19, 0x1a, 0x1b, 0x1c, 0x1d, 0x1e, 0x1f,
]);

const firstProvider = await runtime.createProvider({
  productId: "first.dot",
  artifactSha256,
});
const secondProvider = await runtime.createProvider({
  productId: "second.dot",
  artifactSha256,
});
```

`@parity/truapi-host/web` requires the trusted host loader's SHA-256 digest
for every product provider. Never accept this value from product-controlled
code. The package also exports `createIframeHost` for the protocol-iframe
MessageChannel handshake. Host code creates one worker runtime and then opens
one provider per verified product artifact.

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
       +-- createProvider({ productId, artifactSha256 }) -> product core / WireProvider
       |
       +-- createProvider({ productId, artifactSha256 }) -> product core / WireProvider
```
