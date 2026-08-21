# @parity/truapi

_Typed TypeScript client for products that talk to a TrUAPI host._

[![License](https://img.shields.io/badge/license-MIT-blue.svg?style=flat-square)](../../../LICENSE)
[![Types](https://img.shields.io/badge/types-included-3178C6?style=flat-square&logo=typescript)](./package.json)

This package gives a product running inside a Polkadot host (Desktop Browser, Triangle webview) a fully typed client for every TrUAPI method. The transport, SCALE codecs, generated types, and generated domain clients are all bundled together.

## Install

```bash
npm install @parity/truapi
```

## Quick start

```ts
import {
  createClient,
  createMessagePortProvider,
  createTransport,
  type Client,
  type HostAccountGetResponse,
} from "@parity/truapi";

const provider = createMessagePortProvider(port);
const transport = createTransport(provider);
const truapi: Client = createClient(transport);

const result = await truapi.account.getAccount({
  productAccountId: {
    dotNsIdentifier: "my-product.dot",
    derivationIndex: { tag: "Index", value: 0 },
  },
});

if (result.isErr()) throw result.error;
const account: HostAccountGetResponse = result.value;
```

Request methods take the inner request value directly. The transport adds the wire-level version wrapper and unwraps versioned responses before the generated method returns.

## Subscriptions

Streaming methods return a small Observable-compatible object:

```ts
import type { Subscription, RemoteChainHeadFollowItem } from "@parity/truapi";

const sub: Subscription = truapi.chainInteraction
  .chainHeadFollow({ request: { genesisHash, withRuntime: false } })
  .subscribe({
    next(event: RemoteChainHeadFollowItem) {
      console.log(event);
    },
    error(error: Error) {
      console.error(error);
    },
    complete() {
      console.log("stream ended");
    },
  });

sub.unsubscribe();
```

## Request timeouts

Every request carries a time bound so a silent host never hangs the product. `createTransport`
accepts a transport-wide bound in `requestTimeoutMs` — an integer between `1` and `2147483647`,
defaulting to `30_000` — and a per-call `timeoutMs` on `transport.request` overrides it. A request
that outlives its bound rejects with `RequestTimeoutError`, which carries the bound it outlived on
`timeoutMs`.

```ts
import {
  createClient,
  createMessagePortProvider,
  createTransport,
  RequestTimeoutError,
  type Client,
} from "@parity/truapi";

const provider = createMessagePortProvider(port);
const transport = createTransport(provider, { requestTimeoutMs: 10_000 });
const truapi: Client = createClient(transport);

try {
  const result = await truapi.account.getAccount({
    productAccountId: {
      dotNsIdentifier: "my-product.dot",
      derivationIndex: { tag: "Index", value: 0 },
    },
  });
  // …
} catch (error) {
  if (error instanceof RequestTimeoutError) {
    // The peer accepted the frame and never replied. Requests carry no cancel
    // frame, so the host may still be executing: re-query state for a method
    // with side effects (submit, allocate, sign) rather than resubmitting.
  } else {
    // The transport or provider closed; re-establish the channel.
  }
}
```

A timeout surfaces as a **promise rejection**, not an `Err` in the `ResultAsync`: `request` builds
its result with `ResultAsync.fromSafePromise`, so a `.match(onOk, onErr)` runs neither callback and
the error is thrown instead — await the call inside `try`/`catch`, and discriminate with
`instanceof`, never on message text.

The effective bound is the larger of the configured `requestTimeoutMs` and the method's floor;
`timeoutMs` overrides both. Floors cover the methods whose answer either outlives the default under
a host deadline or waits on a person with no host deadline at all, so a bound never aborts an answer
the host is still allowed to send:

| Floor        | Methods                                                                                                                                                       | Why                                                 |
| ------------ | ------------------------------------------------------------------------------------------------------------------------------------------------------------- | --------------------------------------------------- |
| `190_000` ms | account get, alias, and proof; VRF sign and ring-VRF register, list, and sign; every signing method; statement-store create-proof and create-proof-authorized | clears the runtime's 180s remote-authority deadline |
| `420_000` ms | request login; device and remote permission prompts; payment request and top-up                                                                               | a person answers, and the host applies no deadline  |
| `420_000` ms | resource allocation; preimage submit; statement-store submit                                                                                                  | clears the 300s allocation and 360s preimage caps   |

Generated methods take the request value only, so the per-call `timeoutMs` is reachable through
`transport.request` rather than through a generated client method: a floored method cannot be
shortened from `Client`. `@parity/truapi/sandbox`'s `getClientSync()` takes no options, so it uses
the default `30_000` ms bound and the floors.

## What's in the package

- **Transport providers** for `MessagePort` pipes (used by both webview hosts and iframe hosts)
  and for WebSocket endpoints (used by hosts that serve frames on a loopback socket).
- **TrUAPI transport** that handles request, response, subscription, and handshake framing.
- **Generated domain clients and types** produced from the Rust API contract.
- **SCALE codec helpers** used by the generated code, also re-exported for direct use.
- **Sandbox bootstrap** (`@parity/truapi/sandbox`) that detects the host environment, builds the
  matching provider, and exposes a cached client — see below.

## Sandbox bootstrap

`@parity/truapi/sandbox` wires up a client for browser-embedded hosts: it detects whether the app
runs inside a TrUAPI host (iframe or webview), builds the matching provider, and caches the
resulting client. Use it instead of assembling `createTransport` / `createClient` by hand.

```ts
import {
  getClientSync,
  isCorrectEnvironment,
  subscribeConnectionStatus,
} from "@parity/truapi/sandbox";

const client = getClientSync(); // null outside a host container
if (client) {
  // …make host calls
}

// Or drive UI off connection status:
const unsubscribe = subscribeConnectionStatus((status) => {
  // "disconnected" | "connected"
});
```

| Export                                      | Purpose                                         |
| ------------------------------------------- | ----------------------------------------------- |
| `isCorrectEnvironment(): boolean`           | Synchronous host-environment detection.         |
| `getClientSync(): TrUApiClient \| null`     | Cached client; `null` outside a host container. |
| `subscribeConnectionStatus(cb): () => void` | Connected / disconnected status listener.       |
| `connectWebSocketHost(url): TrUApiClient`   | Use a host that serves frames over a WebSocket. |

### Hosts on a WebSocket

Some hosts serve protocol frames on a loopback WebSocket rather than injecting a `MessagePort`:
the Rust core's `ws-bridge`, and `truapi-host signing-host --frame-listen`. Point the sandbox at
that endpoint once, before anything else touches the client, and every export above behaves as it
does inside a webview:

```ts
import { connectWebSocketHost } from "@parity/truapi/sandbox";

connectWebSocketHost("ws://127.0.0.1:9955");
```

This is what makes a real host usable from an ordinary browser tab during development. For a
transport without the sandbox's caching and detection, `createWebSocketProvider(url)` from the
package root returns the bare `WireProvider`.

## Wire format

Frames are SCALE encoded:

```text
[requestId: SCALE str][discriminant: u8][payload bytes...]
```

The discriminant table is generated from Rust `#[wire(request_id = N)]` and `#[wire(start_id = N)]` annotations and is written to `src/generated/wire-table.ts`.

## Generated files

`src/generated/`, `src/playground/codegen/`, and `test/generated/examples/` are produced by [`truapi-codegen`](../../../rust/crates/truapi-codegen/) from the Rust crate and are ignored by git. Do not edit generated files directly. Run from the repo root:

```bash
./scripts/codegen.sh
```

## Develop

```bash
npm install
npm run build
npm test
```

On a clean checkout, the first build or test run will generate the ignored TypeScript outputs from the Rust sources, so Rust stable + nightly must be installed locally. `npm test` runs the package's [`bun test`](https://bun.sh/docs/cli/test) suite (`src/**/*.test.ts`) directly against the source `.ts` files (no build step), so [bun](https://bun.sh/) must also be installed.

## License

[MIT](../../../LICENSE)
