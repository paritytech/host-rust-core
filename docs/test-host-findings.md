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

## Working notes

- **A fresh checkout does not compile.** `rust/crates/truapi-server/src/generated/` is
  gitignored and generated on demand, so `cargo test` fails with
  `error[E0583]: file not found for module 'generated'`. Run `./scripts/codegen.sh`
  (~2 min). Not `make codegen` — that also runs a playground `yarn install`.
- Read `origin/main` in product-sdk and host-api-test-sdk. Both working trees are on
  feature branches behind shipped (158 commits and 5 commits respectively), and both
  have already produced wrong answers when read directly.
- Never share `CARGO_TARGET_DIR` between worktrees.
