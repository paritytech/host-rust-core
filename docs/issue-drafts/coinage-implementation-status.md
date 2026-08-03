---
title: "Coinage base layer — implementation status"
status: "Working notes"
---

# Coinage base layer — implementation status

Working state of the RFC-17 coinage implementation on branch `rfc17-coinage-core`,
written as a handoff. Becomes the PR description; delete afterwards.

Companion document: `coinage-rfc-notes.md` holds the RFC and design-document
corrections this work turned up. That one becomes an RFC.

## 1. Where this stands

| Layer | Scope | State |
|---|---|---|
| 0 | Formally verified kernel | **Dropped** — no formal methods in the implementation |
| 1 | Base layer: coins, entries, purses, selection, chain | Machinery built; **§8 primitive API not built** |
| 2 | RFC-17 product API (`CoinPayment`) | **Not started** |

The seam between layers 1 and 2 is `export_coins` / `import_coins` (§3.5), and it
is **not built**. Selection anticipates it — `OutputRequirement::AnyDenominations`
is documented as the export/rebalance case — but the primitives are absent.

Measured against "implement RFC-17", we are not close: RFC-17 *is* layer 2.
What exists is the foundation it composes on.

## 2. What is built

Thirteen commits, ~7k lines, 619 tests. All gates green: `cargo test`,
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

### Tests and tooling

- `tests/coinage_lifecycle.rs` — 11 end-to-end scenarios over the public API with
  a `ScriptedChain` stand-in. Includes one guarding the rescue-sweep failure mode.
- `examples/coinage_chain_agreement.rs` — read-only checks against a live runtime.
  Linted by `--all-targets`, never run by CI.
- Extrinsic assembly is tested offline against
  `tests/fixtures/paseo-next-v2-metadata.scale`, which does contain the Coinage
  pallet and the `AsCoinage` extension.

## 3. What is not built

**Layer 1, in rough dependency order:**

1. **Submission.** Assembly exists; the pipeline around it does not — dry-run,
   submit-and-watch, classifying the dispatch outcome from inclusion-block
   events, and settling the operation via `finish_operation` with the right
   consumed lock set. `runtime/bulletin_rpc.rs` already does exactly this shape
   (including a rebuild-and-retry on definitive failure) and is the thing to
   match rather than reinvent.
2. **Signing.** Narrower than it looks: coin-origin and unload-token calls are
   unsigned by design. Only the faucet path needs a conventional signature.
3. **The §8 primitive API** — `create_purse`, `query_purse`, `rename_purse`,
   `delete_purse`, `rebalance_purse`, `top_up`, `transfer`, `export_coins`,
   `import_coins`, `external_offload`, `run_maintenance_sweep`,
   `classify_incoming_payment`, the three subscriptions, `recover`,
   `extend_scan`. The store has mechanics some of these need; nothing composes
   them into operations.
4. **The two sweeps** — coin→entry recycling and entry→coin rescue, driven by a
   host-supplied tick.
5. **Recovery** — gap-limit scanning from root entropy.

**Layer 2:** everything. `impl CoinPayment for ProductRuntimeHost {}` is still
the empty impl.

## 4. Known gaps and hazards

- **Only one extension variant has ever been accepted by a chain.**
  `InfallibleUnpaidSigned` is proven via the CLI host's existing usage; the five
  unload variants are encoded from the pallet source. The live agreement check
  confirms all six *exist* at indices 0–5 in the assumed order, which is
  reassuring but not the same as acceptance.
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

## 5. Ordering advice for the next session

Build the **`/coinage` CLI surface or a thin driver script first**, before more
layers. Reasoning: everything committed so far is verified offline, and the next
increment is the first that moves value. A live feedback loop makes submission
debuggable; without one you are adding unverified code on top of unverified
code. This inverts the original plan and is a deliberate correction.

Note that pgherveou's `/balance` and `/top-up` in truapi#323 derive at
`//pps//…`, so they cannot see what our derivation creates. Building beside them
means reimplementing the faucet flow, including the `AuthorizeValueTransfer`
Ed25519 seed (`HOST_CLI_VALUE_TRANSFER_AUTH_KEY`, or `W3S_AUTH_KEY` as the
iOS-compatible fallback) that gates the test-asset transfer. That duplication is
accepted.

The faucet is also the lowest-risk submission path: `Assets.transfer` plus
`load_recycler_with_external_asset_unpaid_batch`, both with conventional origins
using `InfallibleUnpaidSigned` — the one extension variant already known good. So
it exercises the whole submission stack without depending on anything unproven.

## 6. Commit history on the branch

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
