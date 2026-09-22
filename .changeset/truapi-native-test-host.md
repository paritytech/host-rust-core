---
"@parity/truapi-host": minor
---

`@parity/truapi-host/testing` exposes a mock host products can be tested against. `createMockHost` answers the host
callbacks from memory and records what the core asked for, so a test asserts on the confirmation reviews, permission
answers, navigations and storage writes the core produced rather than on a host's internals. `./testing/playwright`
provides a fixture that runs the real core in a Web Worker with the product in an iframe, `./testing/server` the node
server behind it, `./testing/client` a no-iframe variant for unit tests, and `./testing/dev-accounts` named accounts
that sign with real sr25519 from fixed entropy.

A second WASM bundle at `./wasm/testing` carries the `wasm-signing-host` and `test-host` Cargo features, which is what
lets the test host own keys and answer resource allocation as granted without allocating anything. Neither feature is on
in the `./wasm/web` production bundle, so no shipping browser host has an entry point to either.

Statement Store and Bulletin allowance allocation compiles for `wasm32` as well as native, so a browser signing host
reaches the same on-chain allocation path a native one does. That adds about 1.7 KB to the `./wasm/web` bundle.

Statement-store controls are served through the chain connection the host owns: `injectStatement` publishes a
SCALE-encoded statement into the product's subscriptions, `getSubmittedStatements` reads submissions back off the
transport, and `injectChatAction` publishes a host-authored Chat action into the product's action stream.

Payments throw with the reason rather than returning a plausible value: the protocol declares them but no host
implements them, so a test reaching that path learns why instead of passing against a fake. `setLoginBehavior` throws
too, pointing at the `loginBehavior` fixture option, which is where the test host takes it.
