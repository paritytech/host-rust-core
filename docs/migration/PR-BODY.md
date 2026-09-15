# A TrUAPI-native test host

Builds the test host natively in this repo: an in-memory mock platform, a
browser host page that runs the real core, a Playwright fixture over it, and the
server that serves them. Nine of product-sdk's example suites have been run
against it end to end.

Supersedes #294 (the `MockPlatform` re-port) and #261 (the browser harness).
Both are carried here rather than rebased — see *What happened to #294 and #261*
below.

## What this gives you

**A mock host on both sides of the boundary.** `MockPlatform` in Rust and
`createMockHost` in TypeScript expose the same control surface: recordings of
what the core asked the host to do, per-capability permission answers, chat,
theme, chain-connection simulation, fault injection, and `reset()` for isolation
between cases. The JS surface uses `@parity/host-api-test-sdk`'s method names, so
a migrating suite changes its import rather than its assertions.

**A guard against the two halves drifting.** `mock-host-surface.test.ts` parses
the `impl MockPlatform` block out of `mock.rs` and fails when a control method
exists on one side and not the other. Adding a method to the Rust mock and not
the JS one reddens it by name. It carries a second test pinning a member floor,
so a regex that silently matched nothing cannot make it vacuously green.

**A Playwright fixture on the production topology.** The host page runs the core
in a Web Worker, the way a real web host does, and embeds the product in an
iframe over a `MessagePort`. `@parity/truapi-host/testing/playwright` exports the
fixture, `/testing/server` the server, `/testing/client` a no-iframe variant for
a product's own unit tests.

**Live chain, opt-in.** `chainProxies` forwards to a real node when a suite needs
real state. Default stays hermetic — nothing reaches the network unless asked.

## What is proven

Nine suites, real browser, real codec-2 core, real wire:

| Suite | Result |
| --- | --- |
| storage-demo | **8/8** |
| keys-demo | **8/8** |
| host-demo | **6/6** |
| signer-demo | **8/9**, 1 skipped with its reason |
| chain-client-demo | **2/2** against the real Asset Hub |
| tx-demo | boots, signs, blocked on unfunded accounts |
| contracts-demo | boots to `pallet-revive` account mapping, a write |
| statement-store-demo | connects over the real people chain; cannot submit |
| cloud-storage-demo | already skipped upstream |

**22 of 22 across the chain-free suites.** Migrating them took 5 assertion
rewrites out of 31 tests — 16% — and every one had the same cause: the test read
`@parity/host-api-test-sdk`'s internal storage keys out of the host page. None
was a behavioural difference. The migration is mechanical.

Those rewrites are staged as a patch in `docs/migration/`, with a cover note; it
applies cleanly to product-sdk `origin/main` but has a hard ordering dependency
on the codec bump, which the note spells out.

## What this does not do, and why

**Chain-bound suites.** `tx-demo` and `contracts-demo` reach the chain, sign, and
fail on transaction fees; their accounts are unfunded. TrUAPI derives a product
account per (session entropy, product id), so the addresses differ from
polkadot-js `//Bob` and are not funded by default. Funding them is an
operational decision with a standing cost, not a code change.

**The statement store.** Proxying the real people chain gets it to "connected"
and subscription traffic is visible, but publishing is rejected inside the core
before any RPC is emitted, because it needs a statement allowance. So it cannot
be recorded on the transport either. The three statement controls exist on the
fixture and throw with that reason rather than being absent.

**Payments.** Declared by the protocol, implemented by nobody — every method in
`capabilities/payment.rs` returns an error and ignores its arguments. The mock
throws with that reason rather than faking a success for a path no host can
execute.

In each case the mock refuses and explains, rather than returning something
plausible. A test that passes against a fake is worse than one that fails.

## Two findings worth a reviewer's attention

**`@parity/host-api-test-sdk` does not run the TrUAPI core.** It has no runtime
dependency on `@parity/truapi` — the only reference is an unused devDependency
pinned at `^0.6.0` — and no core WASM. The protocol comes entirely from
`@novasamatech/*`. Every product suite green against it has been exercising a
TypeScript reimplementation rather than the code that ships.

The empirical proof is in this branch: `signer-demo`'s permission test passes
there and cannot pass here. A real core persists a decided permission per
(product, permission) and answers from its own storage, so a mid-run revoke never
reaches the host. With no core, nothing caches, and the test passes. That is the
case for migrating, and it is not about hermeticity or maintenance burden: the
thing under test has not been the thing that ships.

**Compiled artefacts silently lag their source.** Four separate incidents while
building this, each looking like a different bug: a test reading a stale `dist/`,
a rebuilt WASM exposing a required raw bridge callback `tsc` cannot see, a served
bundle missing a method added after the last build, and a mutation check that
hung instead of reddening. `dist/` and `dist/wasm/` are gitignored with no
freshness check. `docs/test-host-findings.md` §11 records it.

## What happened to #294 and #261

#294's Rust half is here, re-ported onto current main. #261's ideas are here,
rebuilt rather than rebased: it forked when `js/packages/` held only `truapi`,
and its wasm-runtime commit landed on main via squash, so there is no shared
ancestry to rebase through. Its `namespaceMockCallbacks` helper lifted a flat
object into every namespace slot, which is a type lie now that both sides are
nested, and its `featureSupported({Chain, genesisHash: 0x00×32})` assertion only
passed because the hash was zero.

What #261 had that this needed: the Web Worker topology, the single-page
`createMockClient`, and a CI job that builds the WASM. All three are here.

## Also in this branch

A `host-wasm` CI job. Nothing in CI built the WASM, so `wasm-bridge.test.ts` — the
only test proving the JS mock works against the real core — skipped silently on
every PR. The job builds both bundles and sets `REQUIRE_WASM=1`; verified in
three modes: passes with the artefact, exits 1 without it, skips green on a
fresh checkout when the flag is unset.

Two WASM bundles: the production `web` one is unchanged, and a `testing` one adds
`wasm-signing-host` so the test host can own dev accounts and sign locally. A
test asserts the testing bundle has a signing host *and the web one does not*.

## Verification

`cargo test` 1001 passed, `bun test` 151 passed, `clippy -D warnings` clean,
`cargo +nightly fmt --check` clean, `sync-release-versions --check` clean. The
drift guard was re-proved by mutation after the final rebase.
