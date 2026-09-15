---
"@parity/truapi-host": minor
---

`@parity/truapi-host/testing` exposes a mock host products can be tested against. `createMockHost` answers the host
callbacks from memory and records what the core asked for, so a test asserts on the confirmation reviews, permission
answers, navigations and storage writes the core produced rather than on a host's internals. `./testing/playwright`
provides a fixture that runs the real core in a Web Worker with the product in an iframe, `./testing/server` the node
server behind it, `./testing/client` a no-iframe variant for unit tests, and `./testing/dev-accounts` named accounts
that sign with real sr25519 from fixed entropy.

A second WASM bundle at `./wasm/testing` carries `wasm-signing-host`, which is what lets the test host own keys; the
`./wasm/web` production bundle is unchanged.

Capabilities the protocol declares but no host implements — payments, and the statement-store controls — throw with the
reason rather than returning a plausible value, so a test reaching an unserved path learns why instead of passing
against a fake.
