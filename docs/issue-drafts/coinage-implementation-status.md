---
title: "Coinage base layer — implementation status"
status: "Working notes"
---

# Coinage base layer — implementation status

Working state of the RFC-17 coinage implementation on branch `rfc17-coinage-core`,
written as a handoff. Becomes the PR description; delete afterwards.

**The specification is `docs/design/coinage-layer.md`.** It is authoritative:
it now carries the durability model, the operation log, transaction ordering,
mortality, and every design correction this work turned up. This document
records only what is and is not implemented against it.

Companion document: `coinage-rfc-notes.md` retains the RFC‑0017 amendments that
still need a new RFC, plus non-document follow-ups. Its design-doc corrections
have been folded into the specification.

## 1. Where this stands

| Layer | Scope | State |
|---|---|---|
| 0 | Formally verified kernel | **Dropped** — no formal methods in the implementation |
| 1 | Base layer: coins, entries, purses, selection, chain | Foundations and durability complete; **§8 primitive API not built** |
| 2 | RFC-17 product API (`CoinPayment`) | **Not started** |

The seam between layers 1 and 2 is `export_coins` / `import_coins` (§3.5), and it
is **not built**. Selection anticipates it — `OutputRequirement::AnyDenominations`
is documented as the export/rebalance case — but the primitives are absent.

Measured against "implement RFC-17", we are not close: RFC-17 *is* layer 2.
What exists is the foundation it composes on.

## 2. What is built

~9k lines, 900 tests across the workspace. All gates green: `cargo test`,
`clippy --all-targets --all-features -D warnings`, `+nightly fmt --check`,
`check --target wasm32-unknown-unknown`, and `cargo doc` with zero coinage
warnings.

### `host_logic/coinage/` — pure domain, no chain, no clock, no persistence

| Module | Contents |
|---|---|
| `types` | `PurseId`, `Amount` (u64 cents, fallible narrowing to the u32 wire type), `DenominationExponent` (i8, negatives rejected), indices, `RingLocation`, `Timestamp`, handles, `OperationKind` |
| `chain_constants` | `CoinageChainConstants` + `validate()` + `next_people_paseo()` reference |
| `params` | Policy tunables only; chain-enforced caps deliberately live elsewhere |
| `error` | `CoinageError`, `InvalidTransition` |
| `coin` / `entry` | Records and their lifecycles; entries carry orthogonal on-chain readiness × local state |
| `purse` | Purse record, monotonic index allocation, the three-value balance |
| `operation` | Status machine, cancellability, lock sets, receipts, restart disposition |
| `selection` | The three tiers, deterministic ordering, three-way failure classification |
| `store` | `CoinageStore` — the aggregate; `begin_operation` selects and locks atomically |
| `derivation` | Appendix B paths, all hard junctions |
| `unload_token` | Free-slot resolution, paid fallback, fee mode |
| `event` | `LayerEvent` |

### `runtime/coinage/` — chain-facing, native-only

| Module | Contents |
|---|---|
| `call` | Pallet call arguments; enforces the split-output cap and value conservation locally |
| `extension` | All six `AsCoinageInfo` variants, signing contexts, both proof messages |
| `proof` | Ring-VRF alias proofs (alias + proof returned together), free-token personhood proof |
| `storage` | Storage keys (golden-pinned), value decoding, `apply_observations` |
| `extrinsic` | Call assembly, inherited implication, unsigned General v5 assembly |
| `submit` | Dry-run, submit-and-watch, three-valued tracker outcome, optimistic vs finalized verdicts |
| `bootstrap` | `CoinageLayer::initialize`: constants from metadata, runtime check, fee account, store load |
| `persistence` | `CoinageState` round-trip; `publish_and_persist` makes the event-before-write order the only reachable one |
| `observe` | The six storage reads, pinned to a block, assembled into observations |
| `recover` | The finalized-state resolution loop and its store application |

### `host_logic/coinage/` additions

| Module | Contents |
|---|---|
| `log` | The write-ahead log: per-transaction entries, checkpoints, dependency ordering, receipt projection |
| `recovery` | The pure resolution decision — outputs present / inputs consumed / expired |

### Tests and tooling

- `tests/coinage_lifecycle.rs` — 11 end-to-end scenarios over the public API with
  a `ScriptedChain` stand-in. Includes one guarding the rescue-sweep failure mode.
- `examples/coinage_chain_agreement.rs` — read-only checks against a live runtime.
  Linted by `--all-targets`, never run by CI.
- Extrinsic assembly is tested offline against
  `tests/fixtures/paseo-next-v2-metadata.scale`, which does contain the Coinage
  pallet and the `AsCoinage` extension.

## 3. What is not built

Phases A (foundations) and B (durability) are **complete**, and C1 (the
observation driver) with them. The tracked plan is in the session task list;
what remains is the API surface.

**Done since the last revision of this document:**

1. **Mortal extrinsics.** `EraAnchor` on `ChainState`, opt-in so allowance
   registration keeps its immortal extrinsics. Coinage assembly refuses an
   immortal state outright. Era encoding golden-tested against Substrate's
   `d5 03`.
2. **Store persistence.** `CoreStorageKey::CoinageState` wired; a corrupt slot
   fails rather than resetting index counters.
3. **Bootstrap.** Constants read from metadata and validated at connect, fee
   account at `//coinage//fee`, store loaded.
4. **The write-ahead log.** One entry per transaction, with checkpoint,
   mortality, inputs, outputs and `depends_on`.
5. **Dependency ordering.** Submission gated on a dependency reaching *definite*
   success; resolution in dependency order; failure cascades to `Abandoned`.
6. **Definite vs optimistic.** `TrackerOutcome` is three-valued by construction;
   verdicts carry finality; `Recovering` added to the status machine.
7. **Operation recovery.** The finalized-state loop, plus the store transitions
   for succeeded / rejected / abandoned.
8. **The alias chain-lock.** `RecyclerAliasStates` read and modelled, completing
   §5.6's entry side.
9. **The observation driver.** All six reads, including the `Members` pallet
   lookup that resolves an entry's ring index and the dynamically-decoded ring
   revision.

**Still to build, in order:**

- **C2** subscription streams (balance, operation status, events).
- **D1–D8** the §8 primitives: purse lifecycle, transfer, the export/import
  seam, the two sweeps, external offload, payment classification, top-up (needs
  truapi#323 read first), wallet recovery.
- **E1** the live validation driver, as a `cargo run --example`.

**Layer 2:** everything. `impl CoinPayment for ProductRuntimeHost {}` is still
the empty impl, and it is blocked on D3.

## 4. Known gaps and hazards

- **Only one extension variant has ever been accepted by a chain.**
  `InfallibleUnpaidSigned` is proven via the CLI host's existing usage; the five
  unload variants are encoded from the pallet source. The live agreement check
  confirms all six *exist* at indices 0–5 in the assumed order, which is
  reassuring but not the same as acceptance.
- **A failed dispatch leaves records locked, not spent, and not free.** Both
  sides are now modelled — `Coin::locked_until` from `Coinage::LockedCoins` and
  `RecyclerEntry::alias_locked_until` from `Coinage::RecyclerAliasStates` — so
  selection will not reoffer a record the runtime would refuse. The consumed
  unload token is still gone, which retry policy has to budget for. Details in
  `coinage-rfc-notes.md` §1.1.
- **`RingStatus` carries `immutable_since`**, which the previous decoder
  dropped entirely. It is now decoded, carried through `ObservedEntry`, and
  stored as `RecyclerEntry::ring_immutable_since`; `needs_rescue` reads it from
  there rather than taking it as a parameter no caller had a source for.
  **Residual hazard:** an entry whose ring immutability was never observed has
  no deadline, and `needs_rescue` then declines *silently*. That is correct for
  a ring still accepting members and indistinguishable from a ring the layer
  never read, so D4 must not treat "nothing to rescue" as evidence that
  observation ran.
- **Two chain constants are not discoverable.** `MaximumAge` and
  `RecyclerExpirationTime` are absent from metadata, so they are carried as
  configuration — and they are exactly the two values guarding the two
  fund-loss paths. Details in `coinage-rfc-notes.md` §6.
- **Scheduling.** The core has no clock outside a live session, so both sweeps
  need the host to drive them. This is the general gap tracked as truapi#308,
  and it is load-bearing for correctness here, not a nice-to-have.
- **Store persistence is one blob** through `CoreStorageKey::CoinageState`. Fine
  for a testnet; will need revisiting when a purse holds thousands of records,
  since every mutation re-encodes everything.
- **Event ordering.** Events must be drained and published *before* the store is
  persisted, because a terminal operation drops its record and the receipt then
  exists only in the event. Documented on the store; not enforceable by types.

## 5. The plan, item by item

Nineteen steps in dependency order. **A1–C1 are done**; C2 onward is the
remaining work. Each item is one increment: implement, then run the full gate
set (`cargo test --workspace`, `clippy --all-targets --all-features -D
warnings`, `+nightly fmt --check`, `check --target wasm32-unknown-unknown`,
`cargo doc` for coinage warnings) before starting the next.

| # | Item | State |
|---|---|---|
| A1 | Mortal extrinsics | **done** |
| A2 | Store persistence | **done** |
| A3 | Bootstrap and fee account | **done** |
| B1 | Durable operation log (WAL) | **done** |
| B2 | Transaction dependency ordering | **done** |
| B3 | Definite vs optimistic outcomes | **done** |
| B4 | Operation recovery | **done** |
| B5 | Recycler alias chain-lock | **done** |
| C1 | Observation driver | **done** |
| C2 | Subscription streams — balance, operation status, events (§8.9, §7.2) | todo |
| D1 | Purse lifecycle primitives — `delete_purse` drain, `rebalance_purse` (§8.1) | todo |
| D2 | Transfer (§8.3) — establishes the pattern every later primitive copies | todo |
| D3 | Export / import, the layer seam (§8.4, §8.5) — **layer 2 is blocked on this** | todo |
| D4 | The two sweeps + `run_maintenance_sweep` (§6.4, §8.7) | todo |
| D5 | External offload (§8.6) — exercises B2's ordering hardest | todo |
| D6 | Payment classification (§8.8) — small, synchronous | todo |
| D7 | Top-up and the faucet path (§8.2) — **read truapi#323 first** | todo |
| D8 | Wallet recovery from entropy (§8.10, Appendix C) | todo |
| E1 | Live validation driver, as a `cargo run --example` | todo |

### Why this order

**Durability before the primitives.** An earlier revision of this document
advised building a `/coinage` CLI or driver first so submission could be
debugged live. Withdrawn on two counts. A CLI is not the deliverable and would
be product surface nobody asked for. And the risk it was meant to retire — the
five `AsCoinage` variants no chain has accepted — is contained in
`runtime/coinage/extension.rs` and does not propagate into the *shape* of the §8
API, so being wrong about it costs a local fix rather than rework.

Durability is the opposite: cross-cutting. Every primitive that submits must be
resumable by construction, so building fourteen against a settlement model that
treated best-block inclusion as final would mean reworking all fourteen.

**E1 comes last, and is an example not a CLI.** It is wanted for the paths only
a real chain can exercise — mortality expiry and `post_dispatch` failure-lock
behaviour — at which point it debugs orchestration rather than bytes. Shape it
like `examples/coinage_chain_agreement.rs`. Its cheapest first move is
read-only: dry-run each of the six `AsCoinage` variants and read the rejection
code. `Invalid::Custom(NoCoin)` proves the runtime parsed our extra and reached
state, which settles the encoding without owning a coin or moving value.

### Notes for specific items

**D4** must not treat "nothing to rescue" as evidence that observation ran; see
the residual hazard in §4.

**D7**, the faucet: pgherveou's `/balance` and `/top-up` in truapi#323 derive at
`//pps//…`, so they cannot see what our derivation creates. Building beside them
means reimplementing the faucet flow, including the `AuthorizeValueTransfer`
Ed25519 seed (`HOST_CLI_VALUE_TRANSFER_AUTH_KEY`, or `W3S_AUTH_KEY` as the
iOS-compatible fallback) that gates the test-asset transfer. That duplication is
accepted. It is also the lowest-risk submission path — `Assets.transfer` plus
`load_recycler_with_external_asset_unpaid_batch`, both conventional origins
using `InfallibleUnpaidSigned`, the one extension variant already known good.

### Decisions made during this work, not to be re-litigated

- **Mortality is 256 blocks** (Appendix A.14), opt-in on `ChainState` so
  statement-allowance keeps its immortal extrinsics. Coinage assembly refuses an
  immortal state.
- **Fee account derives at `//coinage//fee`**, outside the purse junction: it
  holds no coinage value and belongs to no purse.
- **The WAL records purse-scoped indices, not accounts**, so the durable store
  does not spell out the input-to-output linkage the anonymity set exists to
  break.
- **`publish_and_persist` is the only way to write the store**, which makes the
  events-before-persist order of §7.9 the only reachable one.
- **`needs_rescue` reads its own record** rather than taking the deadline as a
  parameter — the parameter form is how the value got lost in the first place.

## 6. Commit history on the branch

**Everything from A1 onward is uncommitted** — roughly 1,900 lines across 23
modified files plus 7 new ones, all gates green. New files:
`docs/design/coinage-layer.md`, `host_logic/coinage/{log,recovery}.rs`,
`runtime/coinage/{bootstrap,observe,persistence,recover}.rs`.


```
730cd1ab  feat(server): assemble unsigned coinage extrinsics
dd7989e6  feat(server): observe coinage chain state into the record store
156687ec  feat(server): generate ring-VRF proofs for entries and unload tokens
126686a1  test(server): check the coinage layer's assumptions against a live runtime
bb2d6bfb  test(server): add end-to-end scenarios over the coinage base layer
3465fd43  docs: collect coinage RFC and design-doc corrections
8138f2eb  feat(server): resolve unload tokens and choose the unload fee mode
724957cf  feat(server): encode the AsCoinage transaction extension
fadf0247  feat(server): add coinage key derivation and pallet call construction
6365e180  fix(server): harmonize the coinage layer with pallet-coinage
e83bbcdc  feat(server): add the coinage record store
8b890342  feat(server): add the coinage domain layer and selection
```

Nothing pushed. Branched from `main` at `079ecd19`.
