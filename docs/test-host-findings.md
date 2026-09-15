# Hermetic test host: what the code says

Findings from investigating the proposal to build a hermetic TrUAPI test host in this
repo to replace `@parity/host-api-test-sdk`. Everything below is measured against
source, with the ref named. Nothing here is an estimate carried over from an earlier
document.

Three checkouts are involved and all three are on disk:

| Repo | Path | Ref read |
| --- | --- | --- |
| host-rust-core (this repo) | `~/Work/Parity/truapi`, worktree `~/Work/Parity/mock-report` | `mock-rebase-probe` |
| product-sdk | `~/Work/Parity/product-sdk/product-sdk` | `origin/main` (working tree is 158 behind) |
| host-api-test-sdk | `~/Work/Parity/host-api-test-sdk` | `origin/main` = `17a28f9`, v0.12.1 |

## 1. `sign_raw` is hermetic; `create_transaction` is not

On a signing host, `sign_raw` needs no chain access. It passes a remote-permission
check named `ChainSubmit` — a local policy question answered by the platform, not an
RPC (`runtime.rs:611` resolves it through `require_remote_permission`) — and then signs
locally with sr25519. `create_transaction` and `sign_payload` do need chain metadata,
because they call `build_local_transaction`.

Proven by `rust/crates/truapi-server/tests/signing_host_mock_platform.rs` (3 tests):
a real `signing_sign_raw` product frame through the dispatcher into a
`SigningHostRuntime` whose entire platform is `MockPlatform`, with the returned
signature verified against a keypair derived independently from the activation
entropy. Both load-bearing assertions were mutation-checked: deriving from different
entropy fails with `EquationFalse`, and verifying the unwatermarked message fails.

The name `require_chain_submit` implies an RPC and is the reason this was mis-scoped.
The doc comments in `truapi-platform/src/mock.rs` and
`js/packages/truapi-host/src/web/create-mock-host.ts` asserted that signing parks under
a silent chain; both were corrected.

**Scope on what a call needs from the chain, not on whether it signs.**

## 2. The product-sdk suite is 63 tests, and 80% of the active ones need no chain

Counted directly across 34 spec files on `origin/main`: **63 test cases, 12 skipped
(10 inside four `describe.skip` blocks plus 2 individual `test.skip`), 51 active.**

| Bucket | Total | Active |
| --- | --- | --- |
| NONE — no chain at all | 41 | 41 |
| READ — reads only | 11 | 4 |
| EXTRINSIC — real inclusion | 10 | 5 |
| FINALITY | 1 | 1 |

The NONE bucket is exactly five whole examples — statement-store 10, signer 9, keys 8,
storage 8, host 6. Four declare zero chain-facing dependencies; `signer-demo` declares
`polkadot-api` and never imports it in either source file.

The discriminator is the host signing log: two tests assert type `"raw"`
(`signer-demo/e2e/sign-raw.spec.ts:28`, `lifecycle.spec.ts:51`) and five assert
`"createTransaction"`. That is the same hermetic/chain-bound line as finding 1,
arrived at independently from the JS side.

**Consequence:** a hermetic chain responder was scoped at 5–8 days, but the expensive
half — block production, event emission, dispatch-error semantics, finality — serves
only ~6 active tests. Serving the READ bucket alone is a static metadata blob plus two
fixed responses. The cheap win is partitioning the suite, not building a responder.

## 3. Nobody is blocked by `host-api-test-sdk`

All six skip markers were read. None is caused by the package being inadequate:

- 3 × `cloud-storage-demo` — the product migrated to `AsyncBulletinClient`; the new
  path needs "a real bulletin chain (or an extrinsic-aware mock)".
- 1 × `contracts-demo/query` — a contract was reaped in a Paseo genesis reset. The
  comment says outright: "This is stale chain state, not an SDK regression" (#322).
- 2 × `signing-rejected` — product-sdk caches the `TransactionSubmit` grant instead of
  re-checking per sign.

The proposed project fixes at most one of the six. The three cloud-storage skips need
the extrinsic-aware mock chain the proposal explicitly rejects, and those target a
**bulletin** chain rather than Asset Hub — re-enabling them means modelling two chains.

The package is actively maintained (98 commits in six months) and already tracks
TrUAPI: `ac633f8` (2026-07-17, Valentin Fernandez) answers TrUAPI 0.4's MessagePort
handshake.

## 4. The 40-member control plane already exists

`TestHostAPI` at `src/types.ts` on `origin/main` (v0.12.1, the version product-sdk's
catalog pins) has **40 members**. The local working tree shows 42 because it sits on
`test/fault-injection-e2e` with unreleased `setFaults`/`getFaults` — read `origin/main`,
not the working tree.

Every category previously sized as "genuinely net-new, nobody has costed these" is
already present:

- **Chat (5)**: `getChatRooms`, `getChatBots`, `getChatMessageLog`, `clearChatState`,
  `injectChatAction`
- **Payments (5)**: `setPaymentBalance`, `getPaymentLog`, `clearPaymentLog`,
  `setPaymentTopUpBehavior`, `simulatePaymentStatus`
- **Permission granularity (4)**: `grantPermission`, `revokePermission`,
  `getGrantedPermissions`, `setEnforcePermissions`, plus `getPermissionLog` and
  `clearPermissionLog`
- **Signing-log payloads**: `SigningLogEntry { type; payload: unknown; timestamp }` —
  records the payload, not merely the kind
- **8 `clear*` methods**

These exist in the package proposed for replacement, not in this repo's mock, which
still has ~20 members. The expansion would re-implement a working, shipped control
plane — a replacement-cost argument, not a work-already-done one.

## 5. The coupling is 40/60, but the seams are not congruent

`host-api-test-sdk/src` is 2,757 lines across 11 files.

**Protocol-coupled, ~1,092 lines (40%)** — would be rewritten:

- `src/browser/host-runtime.ts:331-1234` — the whole `setupContainer`, 904 lines,
  holding all 41 `container.handleXxx` registrations
- `src/fault-provider.ts` — 188 lines wrapping the `@novasamatech/host-api` `Provider`
- `src/types.ts:1,3` — two `HexString` type imports

**Protocol-agnostic, ~1,665 lines (60%)** — survives untouched: module state, dev
keyring, `buildSignedV4Extrinsic`, the iframe allow-attribute, `init()`, the entire
40-member control plane, and every other file (`playwright/fixture.ts`, `types.ts`,
`host-page.ts`, `server.ts`, `scenarios.ts`, `networks.ts`, `index.ts`, `accounts.ts`)
— all verified to hold zero protocol references.

The control plane block references the container in exactly two places, both lifecycle
(`dispose` and recreate on `setAccounts`). It is genuinely decoupled.

**But 41 Spektr handlers map onto only 22 TrUAPI host-callback methods**, because a
TrUAPI host *confirms* where a Spektr host *performs*. Every signing reference in the
generated host callbacks is a `UserConfirmationReview` variant; there is no `signRaw()`
host callback. So ~19 handlers — signing, accounts, statement store — are deleted
rather than ported, their work moving into the Rust core. Which is exactly what finding
1 proves runs against `MockPlatform`.

### The payments hole

There is no host seam for payments: zero payment references in the generated JS host
callbacks, and `pub trait Platform` (`truapi-platform/src/lib.rs:2968`) has exactly 12
supertraits, none of them payment. But the reason is not that the core owns payments.
**Payments are unimplemented.**

`rust/crates/truapi-server/src/runtime/capabilities/payment.rs` is the only `Payment` /
`CoinPayment` implementation in the workspace, and every method returns an error while
ignoring both `_cx` and `_request`: `balance_subscribe` yields `PermissionDenied`,
`request`, `status_subscribe` and `top_up` yield `PAYMENTS_NOT_IMPLEMENTED`, and all
nine `CoinPayment` methods return `Unsupported`. The constant reads
`"Payments are not supported in dot.li"` (`runtime.rs:931`). The wire surface is fully
specified and the TS client encodes all of it, so a product can call these — it just
always gets an error.

Meanwhile RFC 0006 (accepted, `docs/rfcs/0006-payments.md`) assigns payments to **host
implementors**, "including user consent flows, coin management, and settlement", and
requires that every `host_payment_request` raise a confirmation prompt the host must
not auto-approve (:27, :149).

So the seam is designed and accepted but unbuilt. Adding a payment trait — most
naturally to `OptionalPlatform`, which already carries `ChatPlatform` this way so
existing hosts keep compiling — is implementing an accepted RFC rather than inventing
protocol. The alternative is to accept that a TrUAPI test host's truthful payment
behaviour today is "returns `PAYMENTS_NOT_IMPLEMENTED`", in which case any product test
that exercises a *successful* payment cannot port, because TrUAPI cannot execute that
path at all.

That is the live decision, and it is a product decision rather than a test-host one.
Note that mocking cannot close this gap: there is no behaviour to fake.

A related second-order cost: several surviving members lose their *data source* even
though their code survives. `getSigningLog()` records payloads today because the host
signs; under TrUAPI the host only sees `confirmUserAction`. Recoverable —
`SignRawReview` carries the request — but it is re-plumbing, not a no-op.

## 6. The seam work was already prototyped here, and is now superseded

Branch `feat/truapi-host-engine` (`3454c5d`, Nidish, 2026-06-24) adds
`src/truapi-engine/host-iframe-provider.ts` (117 lines) plus a 159-line test — a
host-side (parent) iframe provider for `@parity/truapi`, written because
`createIframeProvider` serves the child side only. Local only, never pushed, 21 commits
behind `origin/main`.

**On its merits it is sound.** No TODOs or hedging. It reads `contentWindow` lazily so
iframe reloads work, pins both `event.source` and `event.origin`, guards the payload
type, and documents its one escape hatch as off-by-default. The 10 tests genuinely
discriminate — foreign source dropped, foreign origin dropped, non-`Uint8Array`
ignored, unsubscribe and dispose asserted by handler count, `allowAnyOrigin` asserted
to relax the origin *and* keep the source pin, and a reload case asserted in both
directions. Its structural `Provider` is member-for-member identical to today's
`WireProvider` (`js/packages/truapi/src/transport.ts:363`), optional `subscribeClose`
included; only the name changed.

**But the architecture moved past it.** TrUAPI hosts no longer bridge parent and iframe
with raw window `postMessage`: `createIframeHost`
(`js/packages/truapi-host/src/web/create-iframe-host.ts`) transfers a `MessagePort`
into the product iframe and the host pipes its end through `createMessagePortProvider`
(`js/packages/truapi/src/transport.ts:636`). Both ship today. And
`host-api-test-sdk`'s own main already answers that handshake (`ac633f8`, three weeks
after this branch was written).

So the branch reads as parked because the ground shifted and the need was met upstream,
not because it hit a wall — though only its author can confirm that. The practical
consequence is favourable: a seam retarget needs no bespoke provider at all.

## 7. The 40-member surface spans three layers, not one

"Grow the mock to 40 members" is the wrong target. `TestHostAPI` is shaped around a
host that *performs* signing, accounts and statements; a TrUAPI host only *confirms*.
Several members therefore have no `MockPlatform` home at all:

| Member | Where it belongs in TrUAPI |
| --- | --- |
| `injectChatAction` | The runtime. `publish_chat_action` (`host_core.rs:1155`) already exists, gated on a chat platform being installed — implementing `ChatPlatform` is what unlocks it. |
| `switchAccount`, `setAccounts`, `setLoginBehavior` | The runtime. Accounts derive from entropy, so these are `activate_local_session` with different material, not a host callback. |
| `getSubmittedStatements`, `injectStatement`, `clearStatements` | The chain responder. `truapi-platform` declares no statement trait or seam; `lib.rs:11` states that statement-store protocol flows live in the core. Statements are observable through `sent_rpc()` and injectable through scripted responses. |
| `getConnectionStatus` | The transport. `MockPlatform` models the chain connection, not the product-host link. |
| `getIsAuthenticated` | Already covered by `auth_states()`. `AuthPresenter` is observation-only. |
| The 5 payment members | Nowhere, until the decision above is made. |

What genuinely belongs on `MockPlatform` — and is now implemented — is the confirmation
and permission surface, chat, theme, preimages, chain connection simulation, and fault
injection.

## 8. Where this leaves the plan

| Step | Original | What the code says |
| --- | --- | --- |
| 1 Signing-host wiring | ~1d | Done and proven. |
| 2 JS half of #294 | 2.5–3d | Small repair of existing in-tree code; worth doing regardless. |
| 3 Chain responder | 5–8d | Expensive half serves ~6 active tests. Partitioning gets 80% for near-zero. |
| 4 Control surface to ~45 | ~7d | Re-implements a shipped, maintained 40-member API. |
| 5 Port #261 harness | 4–6d | Depends on 4. |
| 6 Package via product-sdk | 5–8d | Depends on 4–5. |

If a TrUAPI-native test host is still wanted, the cheapest path is to lift the 60% that
has no protocol imports, rewrite the 40% seam onto `createIframeHost` +
`createMessagePortProvider`, and archive the original — which satisfies both the
engineering and the stated goal of archiving `host-api-test-sdk`. Roughly 6–11 days
plus the payments decision, against 25–33 as originally scoped.

## 9. Migrating product-sdk needs a truapi bump first

`@parity/truapi` 0.13.1 and 0.15.0 are not wire-compatible, and the handshake
says so rather than hanging: #357 moved `WIRE_CODEC_VERSION` from 1 to 2
(`truapi/src/lib.rs:219`), and `system.rs` refuses a mismatched codec with
`UnsupportedProtocolVersion`. product-sdk's catalog pins ^0.13.1, so its suites
cannot run against a 0.15-derived host until that is bumped.

That bump is not free. Building product-sdk against 0.15 surfaces two compile
errors in **its own** code, both in `packages/host/src/testing.ts`
(`createFakeHost`):

- the signing stub is missing `signRawUnwatermarkedDeprecated` and
  `signRawUnwatermarkedDeprecatedWithLegacyAccount`, which 0.15 added to
  `SigningClient`;
- `PublicTruApiClient` is missing the whole `renderer` domain, which 0.15 added.

Both are two-line fixes -- the second follows the file's existing `notModeled`
pattern -- but they are a sequencing dependency nobody had costed: the test-host
migration cannot start until product-sdk compiles against the newer protocol.

## 10. Test suites couple to the host's internals, and that is the real churn

Running `storage-demo` against the TrUAPI mock host, 6 of 8 tests passed
unmodified. The 2 that failed did so for the same reason, and it is the reason
that matters: they assert on `@parity/host-api-test-sdk`'s internal storage
keys, reading `localStorage.getItem("test-host:demo:mykey")` out of the host
page. That is a test coupled to one host's implementation rather than to product
behaviour, and no amount of API compatibility ports it.

The fix is to read through the control surface -- `getProductStorage()`, or
`findProductStorage(key)` on the fixture -- not to teach the new mock to fake
the old one's key scheme, which would bake another host's internals into ours.

**Budget ~25% assertion churn per suite**, and expect it to be concentrated in
tests that verify routing rather than behaviour.

## 11. Compiled artefacts silently lag their source

Three separate incidents in one session, each costing time and each looking like
a different bug:

- `worker-wasm-import.test.ts` failed against a stale `dist/`, and its own
  failure message said so;
- rebuilding the WASM broke both bridge tests with
  `callbacks.workerDemandChanged must be a function` -- a raw bridge callback
  outside the generated `RequiredHostCallbacks`, so `tsc` cannot see it, and the
  old bundle predated the requirement. The tests had been passing against an
  older core;
- the served test-host bundle lacked `getHostCallCount` because `dist/`
  predated it.

`dist/` and `dist/wasm/` are gitignored build outputs with no freshness check.
Rebuild before trusting any test that reads them, and treat "it passed before my
change" as evidence about the artefact rather than about the source.

### The wider pattern: the check was not checking

Four instances, and the shape is worth naming because three of them produced a
**false pass**, which is far more dangerous than a false failure. A broken clone
reporting missing files announces itself; a green check that verified the wrong
thing does not.

- The `REQUIRE_WASM` guard lived in one of three suites, so rewriting that one
  test would have silently disabled the gate for the other two.
- A mutation check on a stream **hung** instead of reddening, so it taught
  nothing while also being able to hang CI.
- A `git apply --check` chained with `&&` reported success because the shell was
  checking the exit status of the following command, not of `git apply`.
- The stale artefacts above: suites passing against a bundle older than the
  source they were meant to exercise.

When a check passes, confirm it *can* fail. Every guard in this work was
mutation-tested for that reason.

## 12. The core caches a decided permission, by design

After a permission is decided for a `(product, permission)` pair, the core
persists the answer and short-circuits on it: `host_logic/permissions.rs:379`
keys the decision on `CoreStorageKey::device_permission_authorization` and reads
it back before prompting, with a test at :702 named
`check_or_prompt_device_caches_grant`.

The consequence for testing is sharp and easy to lose an afternoon to: **a grant
made after a denial does not take effect, and the second call never reaches the
host at all.** The mock's `permissionLog` stays at one entry, because the core
answered from its own storage.

This explains product-sdk's two skipped `signing-rejected` tests. Their comment
blames caching in product-sdk; the caching is in the *core*, and it is
deliberate. No test host can make those tests pass — not this one, not
`host-api-test-sdk` — without either a core change to per-call permissions or
the tests changing shape. They are a known constraint rather than a gap.

The same mechanism appears elsewhere with a coarser key: `IdentityDisclosure`'s
durable grant is keyed by `product_id` alone with no capability discriminator,
so one cached decision answers a finer-grained question.

## 13. The test host now runs the production topology

**Resolved.** The test host runs the core in a Web Worker by default, the same
way a production web host does. What follows is what it took, kept because the
constraint explains the shape of the fix.

The worker runtime supported pairing hosts only: `worker-runtime.ts` hardcoded
`new wasm.WasmPairingHostRuntime(...)` in its `init` handler and had no signing
references, while a test host needs a signing host to own dev accounts. The
change is additive, so a host written before it behaves exactly as it did:

- `init` gained an optional `role?: "pairing" | "signing"`; omitted means
  pairing;
- one new `MainToWorker` kind, `activateLocalSession { requestId, secret }`,
  shaped like the existing `activateExternalSession`, reusing the
  `handleSessionActivation` helper and its response;
- `createWebWorkerPairingHostRuntime` gained a `role` option and an
  `activateLocalSession` method;
- the init handler branches on role, and says so plainly when a bundle has no
  signing host rather than failing on an undefined constructor.

One thing deliberately **not** changed: the worker imports its WASM glue as a
literal specifier so bundlers resolve it statically, which is why the production
`web` bundle works at all. Making that dynamic would change how every web host
loads its core. The test host's server instead redirects the specifier at bundle
time, so only the test host loads the `testing` bundle.

The two topologies expose the core differently -- a worker hands back a wire
provider, the main thread a product core -- so the host page normalises both to
one "pipe this port" step. `topology: "main-thread"` remains available for
debugging.

**Both topologies produce identical suite results**: 22 of 22 across the
chain-free suites, and signer-demo's same 3 failures, which confirms those are
not topology-related.

## 13a. Superseded: how the gap looked before it was closed

Production web hosts run the core in a Web Worker
(`createWebWorkerPairingHostRuntime`). The test host runs it on the page's main
thread. That is not a preference: **the worker runtime supports pairing hosts
only** -- `worker-runtime.ts` hardcodes `new wasm.WasmPairingHostRuntime(...)`
in its `init` handler and contains no signing references -- while a test host
needs a signing host to own dev accounts and sign locally.

So today the choice is production topology *or* local signing, not both. The
main-thread fixture is the deliberate trade.

Closing it is small but not free, and it is protocol work on a surface every web
host uses:

- an optional `role?: "pairing" | "signing"` on the existing `init` message
  (additive; a host that omits it behaves exactly as now);
- one new `MainToWorker` kind, `activateLocalSession { requestId, secret }`,
  an exact clone of the existing `activateExternalSession { requestId, blob }`;
- no new response kind -- `handleSessionActivation` already covers it;
- one branch in the `init` handler to pick the runtime class.

The Rust side is already done: `WasmSigningHostRuntime` exists at
`wasm.rs:1139` and the `testing` WASM bundle already carries it. There is no way
to avoid the change and keep signing, because the worker's only session entry
point is `activateExternalSession`, which needs a real pairing handshake.

## 14. Every product suite, run against the TrUAPI mock host

Nine suites, real browser, real codec-2 core, real wire. Results, and the cause
of every failure rather than a count:

| Suite | Result | Why the failures fail |
| --- | --- | --- |
| storage-demo | **8/8** | 2 assertions read the old host's internal keys |
| keys-demo | **8/8** | 1 assertion, same cause |
| host-demo | **6/6** | 1 assertion, same cause |
| signer-demo | 6/9 | 3 distinct causes, below |
| statement-store-demo | 1/10 | 9 die on missing API, before reaching the store |
| tx-demo | 0/7 (1 skipped) | chain: submit, finalization, dispatch error |
| chain-client-demo | 0/2 | chain: boot gates on a live client |
| contracts-demo | 0/2 (4 skipped) | chain |
| cloud-storage-demo | 0/0 (7 skipped) | already skipped upstream |

**22 of 22 pass across the three chain-free suites.** The churn to get there was
4 assertion rewrites out of 22 tests -- **18%** -- and every one had the same
cause: reading `localStorage.getItem("test-host:…")` out of the host page. Not
one was a behavioural difference. The migration is mechanical, not semantic.

`tx-demo`, `chain-client-demo` and `contracts-demo` produced **no** "is not a
function" errors, so those tests genuinely reach the chain path and fail there.
`statement-store-demo` is the opposite and the distinction matters: its 9
failures are `testHost.clearStatements is not a function`, one layer *before*
the store. Reporting those as "fails on chain" would be wrong.

### signer-demo's three, none of which are churn

- **permission rejection** -- blocked by the core's permission caching
  (section 12). The test revokes `ChainSubmit` and reconnects expecting a fresh
  prompt; the core answers from its own storage and never asks the host. Not
  fixable by any test host.
- **persistence across a page reload** -- the mock's storage is in-memory per
  host-page load, where `host-api-test-sdk` used browser `localStorage`, which
  survives a reload. A real behavioural difference, and a deliberate one: the
  mock keeps no state outside the process that created it.
- **stable product account across a host account switch** -- in TrUAPI a product
  account derives from the session root, so switching the active account
  *changes* it. `host-api-test-sdk` pinned it with a `productAccounts` mapping,
  which made it stable. The test encodes that mapping's behaviour rather than
  the protocol's.

### Two fixture gaps this surfaced

- `productId` must match the identifier the product signs with. The core rejects
  a signing request whose account is scoped to a different product, and it
  surfaces as `PermissionDenied` rather than as a config error. The fixture now
  takes `productId`; without it, signer-demo failed 2 tests for a reason that
  looked like a permission problem.
- The permission log is now shaped as `{ tag, value, approved, kind }`, matching
  `host-api-test-sdk`'s `PermissionLogEntry`, because suites assert on those
  field names.

## 15. What the mock will not pretend to do

Three domains throw a descriptive error on any access rather than returning a
plausible value, so a test reaching for them learns why instead of silently
passing against a fake:

- `payment` and `coinPayment` -- the protocol declares them and no host
  implements them (section 9).
- `statements` -- the core owns the statement store and submits it over the
  people chain, so there is no host seam to record or inject through. This is
  why `statement-store-demo` cannot pass without chain support, and stating it
  as an explicit limit is the difference between "the method does not exist" and
  "this needs a chain".

## 16. Live chain: what host-api-test-sdk actually does, and what we now do

`host-api-test-sdk` does two different things under the word "chain":

- **statement store: it fakes it entirely in JS.** `handleStatementStoreSubmit`
  pushes to an in-memory array and matches topics against subscribers. No chain
  is involved, which is why those ten tests looked chain-free there.
- **everything else: it proxies a live public testnet**, opening
  `wss://paseo-asset-hub-next-rpc.polkadot.io` lazily on first connection. It
  does not simulate a chain at all.

The mock now supports the second, opt-in, through `chainProxies`. Default stays
hermetic: nothing reaches the network unless a suite asks. Use `liveChain()`,
which builds the proxy, the reported chain set and the runtime config's genesis
from one value -- they have to agree, and the product checks the last two.

**Proven:** `chain-client-demo` 2/2 against the real Asset Hub, and `tx-demo`'s
boot test passes with `Chain client ready (assetHub, bulletin, individuality)`.

### Two things this surfaced

**Pinned genesis hashes rot, and every published one is already stale.** The
chain reports `0x4349b00e…` today. `host-api-test-sdk` pins `0xbf0488db…` at
0.11.0 and `0x23e730eb…` at 0.12.1 -- *neither* matches, so its own suites would
fail the descriptor check against this endpoint now. Our proxy therefore routes
without a hash: an unhashed proxy takes every request, so a reset cannot break
routing. A hash is still needed in the *declared* config, because
`@parity/product-sdk-descriptors` refuses a host whose genesis disagrees with
the bundle it was built against; that one has to be re-pinned after a reset, and
`chain_getBlockHash(0)` reads the current value.

**Writes need funded accounts, and ours are not funded.** `tx-demo` now reaches
the chain and signs, then fails with `Invalid.Payment` -- no balance for the
fee. TrUAPI derives a product account per (session entropy, product id), so the
addresses differ from polkadot-js `//Bob` and are unfunded. `tx-demo.dot/0`
under the `alice` dev entropy is
`13B6hYAQJjAG37JuCYeszFhvD8rpVg49NQpHvmG2y4NcB6qP`. Funding is deterministic and
one-off per (account, product), but it is an operational step, not a code one.

So the boundary is: **live-chain reads work today; live-chain writes need those
addresses funded.**

## 17. Statement store: transport works, submission does not

Proxying the real people chain (`wss://paseo-people-next-system-rpc.polkadot.io`,
genesis `0x4a2b5b73…ad48`) connects the statement store. The demo boots to
"Statement store connected (host transport)" and
`statement_subscribeStatement` appears in `getSentRpc`, so subscription traffic
is real and observable.

Submission is not. Publishing fails with `Statement submission rejected: {}`
**inside the core, before any RPC is emitted** -- it needs a statement
allowance, which is a per-period budget. So there is nothing on the transport to
observe either, and `getSubmittedStatements` cannot be built as a recording over
`getSentRpc`.

The three controls therefore exist on the fixture and throw with that reason,
rather than being absent. A product author reaching for one gets an explanation
of which half is missing; before this they got
`testHost.clearStatements is not a function`, which reads like an unfinished
fixture rather than a boundary.

So the honest status is **"connects; submission needs an allowance"**, not
"needs chain support" -- a smaller and differently-shaped gap than it looked.

## 18. The tx-demo submit stall: three wrong leads, and what survives

Three confident diagnoses died here. Recording them because each was built on
evidence that looked stronger than it was, and the same reading error recurs.

**Wrong lead 1: the chain proxy.** The mock pooled one WebSocket per `rpcUrl`
while giving each lease its own reader, so three proxied chains numbered their
JSON-RPC ids from 1 onto one socket. That is a real defect -- every lease read
every other lease's frames, and `close()` leaked its listener -- and it is
fixed. It was **not** this symptom. After the fix the submit still does not
happen, and `getSentRpc` shows 0 transaction-related requests out of 24.

**Wrong lead 2: transaction construction.** `create_transaction` on the V5 path
needs chain metadata through `build_local_transaction`, so a park there looked
plausible. It is impossible. `capabilities/signing.rs` runs in this order:

1. normalize signer
2. `is_product_account_valid_for_caller` -> `PermissionDenied`, returns
3. `require_chain_submit` (:121)
4. `let Some(session) = ... current_session() else { return Rejected }` (:126)
5. `confirm_user_action(CreateTransaction)` (:131)
6. `authority.create_transaction` -> `build_local_transaction`

Step 5 precedes step 6, so construction cannot be entered without a
confirmation being recorded first. Zero reviews were recorded, so construction
was never reached.

Nothing between 3 and 5 can park, either. `require_chain_submit`
(`runtime.rs:622`) matches on the status and returns. `ChainSubmit` is not
`RemotePermission::Remote { domains }` (`host_logic/permissions.rs:82`), so
`check_or_prompt_remote` takes the no-domain branch: peek, prompt,
`persist_decision`, return -- the only await after the host answers is a storage
write the mock answers. And step 4 is **synchronous**: `current_session` at
`signing_host.rs:622` is `fn`, not `async fn`. It returns `Rejected`; it cannot
hang. The signing host's own `create_transaction` (`signing_host.rs:778`) raises
no confirmation at all, so a review can only come from step 5.

**Wrong lead 3: transaction broadcast.** `broadcast_transaction`
(`capabilities/chain.rs:217`) is the only `require_chain_submit` caller with no
confirmation after it and an unbounded chain await immediately following, which
made it the only shape fitting "permission approved, no review, real hang". It
did not run either -- see the host-call count below. It was the best available
explanation of an event that never happened.

**The permission log cannot attribute a call.** `require_chain_submit` has seven
call sites -- `capabilities/signing.rs` at :48, :121, :188, :278, :347, :407 and
`capabilities/chain.rs:227` (transaction broadcast). A single
`{"tag":"ChainSubmit","approved":true}` entry therefore says a chain-submitting
method ran, not *which*. Both wrong leads rested on reading it as if it named
`create_transaction`.

**Zero reviews is trustworthy, though.** `confirmUserAction`
(`create-mock-host.ts:718`) pushes the review on entry and returns the
configured answer immediately, so a recorded review cannot be lost to a park.
An empty log means the call never arrived.

**It is a genuine hang.** `tx-demo`'s handler wraps the flow in
`try`/`catch`/`finally` and writes `remark failed: ...` on both a returned error
and a throw, then re-enables the controls (`examples/tx-demo/src/main.ts:129`).
A `Rejected` return would therefore have left a failure line. The log stops dead
at `Submitting`, so an await never resolved -- a swallowed error is ruled out.

**The signing log is not a second witness.** `getSigningLog()` is
`reviews.flatMap(...)` (`create-mock-host.ts:816`) -- a filtered view of the
same reviews. "0 confirmations and 0 signing requests" is one measurement, not
two agreeing ones. Zero reviews implies zero signing entries trivially.

**Nothing reaches the host after the click.** `getHostCallCount()` is 18 before
and 18 after, `getSentRpc` shows 0 transaction requests out of 18, and there are
no page errors. So no host callback runs at all once the button is pressed.

That is conclusive rather than suggestive, because a permission check cannot be
free: `peek_stored` (`host_logic/permissions.rs:489`) calls
`storage.read_core_storage(...)` with no in-memory cache in front of it -- the
"cached" decision lives in core storage and is read through the host every time
(the `HashMap` at :530 is a test double). `coreStorage` is one of the namespaces
`countCallsIn` wraps (`create-mock-host.ts:587`), so any of the seven
`require_chain_submit` sites would have moved the counter. None did.

**So the `ChainSubmit` entry came from boot, not from the click.** There was
never a post-click permission event to explain. Every hypothesis above --
construction, and then broadcast -- was built to explain an artefact. Note
particularly that `getHostCallCount` counts namespace members only, so a chain
connection's `send()` is not counted; `getSentRpc` is what covers that, and it
is also empty of transaction traffic.

What survives: after the click the product awaits something that never resolves
and never reaches the core. Combined with the product logging any error it
receives, that puts the fault product-side or in the product-core transport,
before any host callback. It is outside the test host.

**Pre-funding and post-funding are different experiments.** Section 16 records
`tx-demo` constructing, confirming and broadcasting a transaction that the chain
then rejected for fees. That run predates the accounts being funded; every run
since is post-funding, and the branch has moved too. Neither observation is
wrong and they should not be reconciled as if one must be. The honest finding is
the transition itself: funding moved the failure *earlier*, from a chain-side
fee rejection to a flow that never reaches the host. That is strange, and it is
strange in a way nobody has explained.

**Method note.** Every one of these leads died to an instrument, not to an
argument. `getSentRpc` killed the first by showing no transaction traffic after
the proxy fix; `getHostCallCount` killed the third by showing the click produced
no host activity at all. Both were built because we hit something we could not
see, and both paid for themselves within a day.

The recurring error is worth naming: three times we read a log as evidence of
something it could not report. `ChainSubmit` names a permission, not a caller.
`getSigningLog` is a view of `reviews`, not a second source. A boot-time entry
is not a click-time event. Before a log is used to localise a fault, check what
it is physically capable of distinguishing.

## Working notes

- **A fresh checkout does not compile.** `rust/crates/truapi-server/src/generated/` is
  gitignored and generated on demand, so `cargo test` fails with
  `error[E0583]: file not found for module 'generated'`. Run `./scripts/codegen.sh`
  (~2 min). Not `make codegen` — that also runs a playground `yarn install`.
- Read `origin/main` in product-sdk and host-api-test-sdk. Both working trees are on
  feature branches behind shipped (158 commits and 5 commits respectively), and both
  have already produced wrong answers when read directly.
- Never share `CARGO_TARGET_DIR` between worktrees.
