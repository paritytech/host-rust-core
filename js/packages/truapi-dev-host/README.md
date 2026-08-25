# @parity/truapi-dev-host

Local development signing host for TrUAPI products. Installs the native
`truapi-host` CLI as an ordinary npm dev dependency and wraps it in the
plumbing every product otherwise rebuilds: a process supervisor, network
presets, product-id resolution, and the browser bridge that connects an app
in a plain browser tab to the host on your desk.

> Looking for the embeddable WASM host runtime? That is
> [`@parity/truapi-host`](../truapi-host) — a different package. This one is
> the development tool.

**Testnets only.** The supervised host runs with `--auto-accept`, so any
connected page can sign as the host's identity without confirmation. Never
point it at keys that hold real value.

## Quick start (once published)

```bash
pnpm add -D @parity/truapi-dev-host
pnpm exec truapi-dev-host -- pnpm dev
```

## Using it today, before it is published

The package is not on npm yet — the per-platform binary packages and their
release wiring are a follow-up PR. Until then, consume it from a checkout of
this branch:

```bash
git clone git@github.com:paritytech/truapi.git
cd truapi && git switch feat/truapi-dev-host
npm install
npm run build --prefix js/packages/truapi-dev-host
cargo build -p truapi-host-cli --bin truapi-host   # or use an installed CLI
```

Then point your app's dev dependency at the checkout — a `file:` dependency
works with every package manager (`portal:` under yarn berry, so the checkout
build of the binary is found automatically):

```json
"@parity/truapi-dev-host": "file:../truapi/js/packages/truapi-dev-host"
```

Everything below works the same from here on. Without the platform packages
the binary comes from `TRUAPI_HOST_BIN`, a `cargo build` in the checkout, or
a `truapi-host` on PATH — see the resolution order below. The
[host-playground `feat/use-truapi-dev-host` branch](https://github.com/paritytech/host-playground/tree/feat/use-truapi-dev-host)
is a working consumer to crib from.

`truapi-dev-host` starts a `truapi-host signing-host` beside your dev server,
waits for a real signer identity (a first run provisions a lite username
on-chain, which can take minutes), pre-flights the product account, then runs
the wrapped command with the connection details in its environment:

| variable                   | value                                               |
| -------------------------- | --------------------------------------------------- |
| `TRUAPI_HOST_WS`           | frame endpoint, `ws://127.0.0.1:<port>`             |
| `TRUAPI_HOST_GENESIS_HASH` | the selected network's genesis hash                 |
| `TRUAPI_HOST_PRODUCT_ID`   | the resolved product id (only on explicit override) |

Each is also injected as a `NEXT_PUBLIC_`- and `VITE_`-prefixed copy so
Next.js and Vite expose it to the browser bundle.

In the app, arm the bridge once (the URL is only defined in dev, so
production builds are untouched):

```ts
import { connectCliHost } from "@parity/truapi-dev-host/browser";

connectCliHost({ url: import.meta.env.VITE_TRUAPI_HOST_WS });
```

`@parity/product-sdk` then detects a host container and every hosted code
path — product account, signing, statement store, permissions — runs against
the local CLI.

## Configuration

All knobs are environment variables, so they live in an `.env.local` and
never in argv:

| knob                     | default                | meaning                                          |
| ------------------------ | ---------------------- | ------------------------------------------------ |
| `TRUAPI_HOST_PORT`       | `9955`                 | frame WebSocket port                             |
| `TRUAPI_HOST_NETWORK`    | `nextv2`               | `nextv2`, `preview`, or a CLI-native preset name |
| `TRUAPI_HOST_PRODUCT_ID` | `localhost:<app port>` | product label or qualified id to act as          |
| `TRUAPI_HOST_SESSION`    | the CLI's              | named signer session                             |
| `TRUAPI_HOST_MNEMONIC`   | unset                  | sign as an existing identity (testnet keys only) |
| `TRUAPI_HOST_BIN`        | unset                  | path to a locally built CLI binary               |

A bare product label resolves into the selected network's namespace
(`play` → `play.paseo` on Paseo Next v2): a host only signs for the product
id it serves, so the network and product knobs steer both the host and the
app from one place. `--app-port <n>` tells the launcher which port the
wrapped dev server binds when it is not 3000, since the default product id
names it.

A host already listening on the port is attached instead of spawned — useful
for watching approvals in the CLI's own window — and pre-flighted with a
throwaway signature, since an attached host may serve a different product id.

## Where the binary comes from

Resolution order:

1. `TRUAPI_HOST_BIN` (or the `binary` option),
2. the installed platform package (`@parity/truapi-dev-host-<platform>-<arch>`,
   version-pinned by your lockfile — not yet published),
3. a `cargo build -p truapi-host-cli` output in an enclosing repo checkout,
4. `truapi-host` on `PATH`.

The CLI binary and the `@parity/truapi` wire client must come from matching
releases: a skew presents as a misleading `MalformedFrame` error naming a
struct field. Installing both from this package's lockfile pin is the point
of the package.

## Programmatic use

Everything the `truapi-dev-host` launcher does is exported from the package
root — `ensureHost`, `startHost`, `waitForSigner`,
`preflightProductAccount`, `connectHost` (a Node-side TrUAPI client over the
frame socket), `resolveNetwork`, `resolveProductId` — for repos that need
their own launcher choreography.
