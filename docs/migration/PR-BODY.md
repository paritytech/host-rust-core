# A TrUAPI-native test host

A mock host products can be tested against, built in this repo: an in-memory
mock platform in Rust, its TypeScript sibling, a browser host page that runs the
real core, a Playwright fixture over it, and the server that serves them. Built
against `@parity/truapi` 0.16.0 (wire codec 2).

## What it provides

**A mock host on both sides of the boundary.** `MockPlatform`
(`truapi-platform`, behind the `mock` feature) and `createMockHost`
(`@parity/truapi-host/testing`) expose the same control surface: recordings of
what the core asked the host to do, per-capability permission answers, chat,
theme, chain-connection simulation, fault injection, and `reset()` for isolation
between cases. Confirmation reviews are recorded with their payloads, so a test
can assert *what* was put to the user rather than only that something was.

The TypeScript surface uses `@parity/host-api-test-sdk`'s method names, so a
suite adopting it changes its import rather than its assertions.

**A guard against the two halves drifting.** `mock-host-surface.test.ts` parses
the `impl MockPlatform` block out of `mock.rs` and fails when a control method
exists on one side and not the other, naming the missing member. A second test
pins a member floor, so a regex that matched nothing cannot make the check
vacuously green. Intentional naming differences live in one explicit alias map.

**A Playwright fixture on the production topology.** The host page runs the core
in a Web Worker, the way a web host does, and embeds the product in an iframe
over a `MessagePort`. `@parity/truapi-host/testing/playwright` exports the
fixture, `/testing/server` the node server, `/testing/client` a no-iframe variant
for a product's own unit tests, `/testing/dev-accounts` the named dev accounts.

**Dev accounts that sign.** The host runs a signing host and establishes sessions
from fixed BIP-39 entropy, so a product exercises real sr25519 signatures.
Addresses are derived root-from-entropy then per-product, so they differ from
polkadot-js `//Alice`; the module says so where someone will read it.

**Live chain, opt-in.** `chainProxies` forwards to a real node when a suite needs
real state; `liveChain()` keeps the proxy, the reported chain set and the runtime
config's genesis in agreement, since the product checks the last two. The default
is hermetic — nothing reaches the network unless a suite asks.

**Two WASM bundles.** `web` is the production browser host. `testing` adds
`wasm-signing-host`, which is what lets the test host own keys. A test asserts
the testing bundle has a signing host and the web one does not.

**A `host-wasm` CI job** that builds both bundles and runs the bridge suite with
`REQUIRE_WASM=1`, so a missing artefact fails loudly instead of skipping green.

## What is verified

Nine of product-sdk's example suites, real browser, real core, real wire:

| Suite | Result |
| --- | --- |
| storage-demo | **8/8** |
| keys-demo | **8/8** |
| host-demo | **6/6** |
| signer-demo | **8/9**, 1 skipped with its reason |
| chain-client-demo | **2/2** against the real Asset Hub |
| tx-demo | boots and signs; blocked on unfunded accounts |
| contracts-demo | boots to `pallet-revive` account mapping, a write |
| statement-store-demo | connects over the real people chain; cannot submit |
| cloud-storage-demo | already skipped upstream |

**22 of 22 across the chain-free suites.** Adopting the fixture took 5 assertion
rewrites out of 31 tests, and every one had the same cause: the test read a host
implementation detail — internal storage keys — rather than product behaviour.
None was a behavioural difference.

Those rewrites are staged as a patch in `docs/migration/`, with a cover note. It
applies cleanly to product-sdk `origin/main` and carries a hard ordering
dependency: product-sdk's catalog pins `@parity/truapi` at `^0.13.1`, which is
codec 1 and cannot negotiate with a codec-2 host, so the codec bump must land
first.

## What it deliberately does not do

**Chain writes.** `tx-demo` and `contracts-demo` reach the chain and sign, then
fail on transaction fees: a product account derives per (session entropy, product
id), so the addresses are not funded. Funding them is an operational decision
with a standing cost, not a code change.

**The statement store.** The store connects over a proxied people chain and its
subscription traffic is observable, but publishing is rejected inside the core
before any RPC is emitted, because it needs a statement allowance — so it cannot
be recorded on the transport either. `getSubmittedStatements`, `injectStatement`
and `clearStatements` exist on the fixture and throw with that reason.

**Payments.** The protocol declares them and no host implements them: every
method in `capabilities/payment.rs` returns an error and ignores its arguments.
The mock throws with that reason.

In each case the mock refuses and explains rather than returning something
plausible, so a test reaching for an unserved path learns why instead of passing
against a fake.

## Notes for review

The mock is not a reimplementation of the protocol — it mocks only the platform
seam, and the real Rust core runs behind it. That is what makes a product test
here exercise the code that ships, including behaviour a host cannot override:
the core persists a decided permission per (product, permission) and answers
from its own storage, so a permission revoked mid-run never reaches the host.
`signer-demo`'s permission spec is skipped for that reason, with the reason in
the skip.

`dist/` and `dist/wasm/` are gitignored and have no freshness check, so a suite
reading them can pass against a bundle older than its source. `make wasm` and
`npm run build` before trusting a result that depends on either.

## Verification

`cargo test` 1001 passed, `bun test` 151 passed, `clippy -D warnings` clean,
`cargo +nightly fmt --check` clean, `sync-release-versions --check` clean. Every
guard in this branch was mutation-tested — including the drift guard, re-proved
after the final rebase.
