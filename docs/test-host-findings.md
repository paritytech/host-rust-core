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

Verified three ways: zero payment references in the generated JS host callbacks; zero
payment supertrait in Rust (`pub trait Platform` at `truapi-platform/src/lib.rs:2968`
has exactly 12 supertraits, none of them payment); but 85 payment references in the
product-facing client. **Payments are wholly core-owned in TrUAPI with no host seam.**

Five of the 40 control-plane members therefore have nothing to attach to. That is a
gap, not a port, and it is not costable until someone decides between adding a host
seam, dropping those members, or implementing them inside the Rust mock.

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

## 7. Where this leaves the plan

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

## Working notes

- **A fresh checkout does not compile.** `rust/crates/truapi-server/src/generated/` is
  gitignored and generated on demand, so `cargo test` fails with
  `error[E0583]: file not found for module 'generated'`. Run `./scripts/codegen.sh`
  (~2 min). Not `make codegen` — that also runs a playground `yarn install`.
- Read `origin/main` in product-sdk and host-api-test-sdk. Both working trees are on
  feature branches behind shipped (158 commits and 5 commits respectively), and both
  have already produced wrong answers when read directly.
- Never share `CARGO_TARGET_DIR` between worktrees.
