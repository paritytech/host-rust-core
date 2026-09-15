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
over a `MessagePort`. It ships from the existing `@parity/truapi-host` package
rather than a new one, on subpaths this branch adds:
`./testing/playwright` for the fixture, `./testing/server` for the node server,
`./testing/client` for a no-iframe variant a product's own unit tests can use,
and `./testing/dev-accounts` for the named accounts. No published version
carries them yet.

`productUrl` is the only required option: the fixture starts its own host
server when none is supplied, shares it across a file, and unrefs it so it
cannot hold a worker open. It also accepts `@parity/host-api-test-sdk`'s
`networks` shape and expands it into the proxy, chain set and runtime genesis
that have to agree. The two options TrUAPI cannot honour --
`productAccounts` and an account given by derivation `uri` -- are accepted and
rejected at construction with what to do instead, rather than being absent and
failing as a type error.

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
| tx-demo | signs and submits; rejected for fees on unfunded accounts |
| contracts-demo | boots to `pallet-revive` account mapping, a write |
| statement-store-demo | connects over the real people chain; cannot submit |
| cloud-storage-demo | already skipped upstream |

**22 of 22 across the chain-free suites.** Adopting the fixture is an import
change: the whole diff for eight of the nine suites is the import line in
`e2e/fixtures.ts` plus a type import in `e2e/helpers.ts`.

Seven tests out of 31 needed more. Five read the old host's *internal* storage
keys rather than product behaviour, and now read through the control surface.
One asserted that switching the host account leaves the product account
unchanged -- it does not, because TrUAPI derives the product account from the
session root, so that is a real behavioural difference rather than churn. One is
proposed as skipped: the core answers a decided permission from its own storage,
so a revoked permission never re-reaches the host and no test host can make it
pass.

Those rewrites are staged as a patch in `docs/migration/`, with a cover note.
The patch applies cleanly to a fresh clone of product-sdk main, and product-sdk
builds against the published `@parity/truapi` 0.16.0 once `createFakeHost` gains
the two members the newer client requires.

Adoption needs two releases, and the order matters. `@parity/truapi` 0.16.0 is
the first release on **wire codec 2**, and the handshake refuses a mismatched
codec, so a codec-1 product cannot talk to this host at all. Nothing published
is on codec 2 yet: the latest `product-sdk-host` (0.19.1) pins
`@parity/truapi` `^0.13.1`, and a caret on a `0.x` version pins the minor, so it
cannot resolve 0.16.0. product-sdk's own suites pass here because this checkout
links `@parity/truapi` at the 0.16.0 worktree — a local override, not a
published state.

So the sequence is: this branch merges; a `@parity/truapi-host` release carries
the `./testing` subpath, which no published version has yet; product-sdk moves
its catalog to `@parity/truapi` 0.16.0 and re-releases; and only then can a
consumer adopt the fixture. Findings doc section 19 has the resolution table.

## What it deliberately does not do

**Chain writes.** `tx-demo` boots against the real Asset Hub, signs through the
host and submits, and the chain rejects the transaction with `Invalid.Payment`:
a product account derives per (session entropy, product id), so the addresses
hold no balance for fees. Funding them is an operational decision with a
standing cost, not a code change.

One run instead stalled before reaching the signer and ended on
`submitAndWatch`'s own 300s timeout. That has not reproduced, and every run
since reaches signing. Findings doc section 18 records what was measured, since
an intermittent failure against a public testnet is worth knowing about before
someone reads a red CI job as a regression here.

**The statement store.** The store connects over a proxied people chain and its
subscription traffic is observable, but publishing is rejected inside the core
before any RPC is emitted, because the submitting account needs a statement-store
allowance — so it cannot be recorded on the transport either.
`getSubmittedStatements`, `injectStatement` and `clearStatements` exist on the
fixture and throw with that reason.

Granting the allowance is `truapi-host alloc-check --target <hex-32> --submit`,
which requires an onboarded person: the extrinsic proves LitePeople ring
membership. The identity available here does not have it — `alloc-check` reports
`onboarding pending` across all 26 rings and `identity-check` returns
`IDENTITY_NONE`, so the grant cannot be made from this environment. Slots
themselves are free (`People` and `LitePeople` both report `free seq=0` for the
current period), so this is a personhood gap rather than a quota one.

**Payments.** The protocol declares them and no host implements them: every
method in `capabilities/payment.rs` returns an error and ignores its arguments.
The mock throws with that reason.

In each case the mock refuses and explains rather than returning something
plausible, so a test reaching for an unserved path learns why instead of passing
against a fake.

Funding the derived accounts is what `tx-demo` and `contracts-demo` are waiting
on. `statement-store-demo` needs something different: a statement-store
allowance for an onboarded person, which no amount of host-side work
substitutes for.

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

`cargo test` 1001 passed, `bun test` 153 passed, `clippy -D warnings` clean,
`cargo +nightly fmt --check` clean, `sync-release-versions --check` clean. Every
guard in this branch was mutation-tested — including the drift guard, re-proved
after the final rebase.
