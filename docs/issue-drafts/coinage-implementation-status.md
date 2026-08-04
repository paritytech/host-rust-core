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
| 1 | Base layer: coins, entries, purses, selection, chain | **Complete** — foundations, durability, observation, subscriptions and the §8 primitives |
| 2 | RFC-17 product API (`CoinPayment`) | **Not started** |

The seam between layers 1 and 2 is `export_coins` / `import_coins` (§3.5), and it
is built: a coin already in the right shape leaves under its own secret with no
extrinsic at all, and one that has to be reshaped is handed over only once the
chain has definitely accepted it.

Measured against "implement RFC-17", layer 1 is done and layer 2 — which is what
RFC-17 actually specifies — has not been started. What exists is everything it
composes on, and nothing of the product API itself.

**Nothing here has been run against a chain.** Every path is verified offline
against a metadata fixture and a scripted node; the assumptions only a live
runtime can settle are listed in §4 and are what `examples/coinage_live_validation`
exists to settle.

## 2. What is built

~13k lines, 874 tests in `truapi-server` and 1,037 across the workspace. All gates
green: `cargo test`,
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
| `subscription` | The three streams of §8.9: events, purse balance, operation status |
| `plan` | Selection plan → ordered transactions, with destinations and output records |
| `offload` (host_logic) | The four-way phase decision an external offload re-runs |
| `execute` | The submission engine: assemble, log, broadcast, grade, terminate; `begin_transfer` |
| `ring` | Recycler ring members and the proof domain their size fixes |
| `scan` | The gap-limit wallet rescan of Appendix C, reading in bulk |
| `tokens` | Free-slot probing, paid-ring membership, fee-account balance |
| `fee` | Pricing an extrinsic, and the from-output ceiling that covers its own bytes |
| `testing` | `FakeChain`: an offline chain that answers by method, for driving whole operations |

### `host_logic/coinage/` additions

| Module | Contents |
|---|---|
| `log` | The write-ahead log: per-transaction entries, checkpoints, dependency ordering, receipt projection |
| `recovery` | The pure resolution decision — outputs present / inputs consumed / expired |
| `memo` | `MemoEntry` and `PaymentClassification` — what a payer tells a payee |

### Tests and tooling

- `tests/coinage_lifecycle.rs` — 12 end-to-end scenarios over the public API with
  a `ScriptedChain` stand-in. Includes one guarding the rescue-sweep failure mode,
  and one checking that the three subscription streams agree.
- `runtime/coinage/testing.rs` — `FakeChain`, an offline node that answers by
  method rather than by call order. It remembers what was submitted and serves it
  back inside the block it reports, which is what makes it possible to drive a
  whole operation — signature, proofs and all — with no chain. Every primitive is
  tested through it end to end.
- `examples/coinage_chain_agreement.rs` — read-only checks against a live runtime.
  Linted by `--all-targets`, never run by CI.
- `examples/coinage_live_validation.rs` — dry-runs all six `AsCoinage` origins
  against a real node and classifies each rejection: parsed-and-refused settles the
  encoding, unintelligible does not. Also never run by CI.
- Extrinsic assembly is tested offline against
  `tests/fixtures/paseo-next-v2-metadata.scale`, which does contain the Coinage
  pallet and the `AsCoinage` extension.

## 3. What is built, by phase

Every phase of the plan is complete: A (foundations), B (durability), C
(observation and subscriptions), D (the §8 primitives) and E (the live driver).

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
10. **The subscription streams.** All three of §8.9, fanned out from one hub the
    layer owns. Balances are reprojected from the store rather than carried on an
    event, because the clock alone moves them; operation status is read from the
    events, because a completed operation's record is already gone by the time
    its terminal status is delivered.

11. **Every §8 primitive.** Purse lifecycle, transfer, the export/import seam,
    both sweeps, external offload, payment classification, top-up, and wallet
    recovery — each with the submission engine behind it: coin-origin signing,
    recycler-ring reads, free unload tokens, fee-mode selection, and the
    plan-to-transactions walk.
12. **The live validation driver**, as `examples/coinage_live_validation`.

**Still to build:** layer 2. `impl CoinPayment for ProductRuntimeHost {}` is still
the empty impl, and it is no longer blocked — D3 built the seam it composes on.

## 4. Known gaps and hazards

- **Only one extension variant has ever been accepted by a chain.**
  `InfallibleUnpaidSigned` is proven via the CLI host's existing usage and by the
  shipped top-up flow; the five unload variants are encoded from the pallet source.
  The agreement check confirms all six *exist* at indices 0–5 in the assumed order,
  and `examples/coinage_live_validation` will say whether a node parses each one —
  neither has been run here, because this work had no chain access.
- **Nothing has been submitted to a chain.** Every path is exercised against
  `FakeChain`, which answers what the tests tell it to. That proves the layer is
  self-consistent and that its bytes are what this crate believes they are; it
  cannot prove the runtime agrees. The two examples are how that gets settled.
- **The paid unload-token ring is not implemented.** §6.5's fallback needs the
  `Members` collection identifier the pallet derives per period, which is neither
  in metadata nor derivable from anything the layer can read. Membership is read
  honestly, joining is never claimed, and a wallet out of free slots is told
  `NoUnloadToken` rather than handed a token it cannot prove. Details in
  `coinage-rfc-notes.md` §6.4.
- **A coin-origin call is a signed transaction after all.** `AsCoinage::AsCoin`
  transmutes a signed origin rather than conjuring one, so `split`, `transfer` and
  `load_recycler_with_coin` carry a `VerifyMultiSignature` extra signed by the coin
  account's own key — and because that extension precedes `AsCoinage`, the
  signature must cover the coinage extra. Signing the metadata-default extra
  instead produces bytes a runtime rejects as a bad proof with nothing to say why.
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
  never read, so the sweep must not be read as evidence that observation ran. The
  implementation says so at the API — `begin_maintenance_sweep` returns `None` for
  "nothing to do" and its doc names this trap — and a test pins it, including that
  advancing the clock by years changes nothing when the deadline is *missing*
  rather than distant.
- **Two chain constants are not discoverable.** `MaximumAge` and
  `RecyclerExpirationTime` are absent from metadata, so they are carried as
  configuration — and they are exactly the two values guarding the two
  fund-loss paths. Details in `coinage-rfc-notes.md` §6.
- **Balance streams need the driver to tick.** `refresh_subscriptions` is what
  turns time into a balance item, and nothing calls it on a schedule yet. Until a
  driver does, a purse whose only pending change is a jitter delay elapsing will
  not report becoming spendable until the next mutation. Same root cause as the
  scheduling gap below.
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

Nineteen steps in dependency order. **All nineteen are done.** One reorder: D2
moved ahead of D1, because a rebalance is a transfer whose recipient accounts are
ours and a purse drain is a rebalance of everything, so the transfer engine had to
exist first. Each item was one increment: implement, then run the full gate
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
| C2 | Subscription streams — balance, operation status, events (§8.9, §7.2) | **done** |
| D1 | Purse lifecycle primitives — `delete_purse` drain, `rebalance_purse` (§8.1) | **done** — built after D2 |
| D2 | Transfer (§8.3) — establishes the pattern every later primitive copies | **done** |
| D3 | Export / import, the layer seam (§8.4, §8.5) | **done** — layer 2 is unblocked |
| D4 | The two sweeps + `run_maintenance_sweep` (§6.4, §8.7) | **done** |
| D5 | External offload (§8.6) — exercises B2's ordering hardest | **done** |
| D6 | Payment classification (§8.8) — small, synchronous | **done** |
| D7 | Top-up and the faucet path (§8.2) | **done** — truapi#323 read; see below |
| D8 | Wallet recovery from entropy (§8.10, Appendix C) | **done** |
| E1 | Live validation driver, as a `cargo run --example` | **done** — written, never run |

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

**E1 is an example, not a CLI.** It reads the paths only a real chain can
answer for, and its cheapest move is the one it does: dry-run each of the six
`AsCoinage` origins and classify the rejection. A rejection naming the pallet's
own state — `Custom`, `BadProof` — means the runtime parsed our extra and
disagreed about *state*; anything else means it did not understand the *bytes*,
and that is the only answer worth acting on. Mortality expiry and
`post_dispatch` failure-lock behaviour still need a funded wallet and a
transaction that lands, and remain the next thing to run against a testnet.

### Notes for specific items

**D4** must not treat "nothing to rescue" as evidence that observation ran; see
the residual hazard in §4. The API says so and a test pins it.

**D5**'s loop re-reads the chain between phases, and has to: an entry a recycle
phase just created knows nothing about the ring the pallet put it in, and an
entry with no ring cannot be offboarded. A loop re-planning from local state
alone would recycle forever. That read is §8.6 step 1's "read the current view",
taken literally.

**D7**, the faucet, as built: the layer owns the coinage half only. `top_up`
takes a `FundingOrigin` — the account holding the external asset, which signs the
load — allocates one entry per denomination in the target purse, and submits a
single `load_recycler_with_external_asset_unpaid_batch` bounded by
`MaxBatchUnpaidLoad` (10 on the reference runtime). Moving the asset *to* that
account is the caller's business, which is what keeps the faucet's key material
out of the layer.

Reading truapi#323 settled three things. The extrinsic is a signed **V4**, not a
General v5, because `InfallibleUnpaidSigned` transmutes a conventional signed
origin. The runtime gates test-asset transfers behind an `AuthorizeValueTransfer`
extension carrying an Ed25519 signature, so `FundingOrigin` has a defaulted
`authorize_value_transfer` hook — absent on a runtime that does not gate, supplied
from `HOST_CLI_VALUE_TRANSFER_AUTH_KEY` (or the iOS-compatible `W3S_AUTH_KEY`) on
one that does. And `proof_of_ownership` signs the origin account's raw 32 bytes,
which confirmed the same reading D4 had already used for
`load_recycler_with_coin`.

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
- **The layer owns one subscription hub**, and `publish_and_persist` is what
  feeds it: the publisher receives the drained events *and* the store, because a
  balance is a projection of every record in a purse and no event can carry it.
- **Balance streams are recomputed, deduplicated by last value**, so a clock tick
  that changes nothing emits nothing. The alternative — deriving balances from
  events — cannot work, because a jitter delay elapsing moves a balance with no
  record changing.
- **Operation status is taken from the events, not the operation record**, since
  §7.8 lets the store drop a terminated operation the moment its status is
  emitted; the terminal event is the only place its receipt still exists.
- **A transfer's transactions are independent.** Both `split` and
  `unload_recycler_into_coins` name a destination per produced coin, so a payment
  mints straight into the payee's accounts and never needs "mint to myself, then
  transfer". Dependent log entries remain, because external offload really does
  spend what an earlier phase produced.
- **The unload fee chooses the origin, not just an argument.** Prepaid presents a
  token and carries `max_fee = 0`; from-output presents no token at all and lets
  the extension take the fee out of the value. An unfunded fee account therefore
  spends no free allowance — and the fee has to be priced before the origin is
  known, so the prepaid shape's own bytes are priced and the extrinsic
  re-assembled if the answer was from-output.
- **An export of a coin already in shape submits nothing.** Control moves with the
  secret. Only value that has to be reshaped costs an extrinsic, and those coins
  are emitted only once the chain has definitely accepted them.
- **A drained purse closes only after the chain agrees**, and a purse still
  holding value that cannot move right now is refused rather than closed around
  it. Closing drops the records, and a record dropped while its account holds a
  coin is value nobody can find again without a seed rescan.
- **`lock_for_operation` is idempotent**, which is what lets a multi-phase offload
  name the entries it created in an earlier phase without tracking whether it
  already holds them.
- **A recovery scan reads in bulk**, one `state_queryStorageAt` per batch rather
  than one per index. The recommended window is 500 × 4, so per-index reads would
  be thousands of round trips per purse.

## 6. Commit history on the branch

Twelve commits carry the foundations, the durability layer and the observation
driver. **The subscription streams, every §8 primitive and the live validation
driver are uncommitted working-tree changes on top of them.** Nothing is pushed.

Two items travel inside another commit because their whole diff lives in files
that commit introduces, and both say so in their message: **B2** (dependency
ordering) is inside "add the durable operation log and its ordering rules", and
**B3** (definite vs optimistic) is inside "submit coinage extrinsics and grade
the outcome".

**The branch does not bisect.** The tip is verified — 900 tests, clippy
`-D warnings`, fmt, wasm32, zero coinage doc warnings — but the commits were
split out of one finished working tree rather than replayed, and several do not
build standalone: `runtime/coinage.rs` declares every module and only lands in
the observation-driver commit, so earlier commits reference modules the mod list
does not yet expose. Worth a replay rebase before the PR if `git bisect` should
work on this branch; the history reads correctly either way.


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

## 7. What remains, and why it was not done

Layer 1's *specified API* is complete. Layer 1 as a **running subsystem** is not:
it has no observer, no scheduler, no caller, and no live validation. Four separate
pieces, with four different reasons for being open.

### 7.1 Reactive observation (§6.1) — a gap in the plan, not in the spec

§6.1 is explicit: *"the layer maintains continuous subscriptions to every chain
storage entry backing its local records… The layer does not pull-poll."* What
exists is the six **reads** (`observe::refresh_purse`), called only by operations
that need a fresh view mid-flight — the offload phase loop and the recovery scan.
Nothing subscribes and nothing polls, so an idle wallet never notices an incoming
payment, a coin ageing, or a chain lock expiring, and `refresh_subscriptions` has
no caller at all.

The nineteen-item plan never had an item for this; C1 was scoped to the reads.

Two things have to be decided before it can be built, and neither is obvious:

1. **`RpcClient` has no public subscription surface.** Only
   `submit_and_watch_inclusion` uses the inner `subscribe_raw`, so
   `state_subscribeStorage` has to be added to it.
2. **`CoinageLayer` is `&mut self` throughout.** A long-lived observer needs an
   ownership model the crate has not chosen: an actor loop owning the layer, or
   `Arc<Mutex<CoinageLayer>>` driven by the existing `crate::subscription::Spawner`.
   An actor avoids a mutex around every operation and is the recommendation, but it
   is a real design decision and should be made deliberately.

Until this lands, a host can drive the layer by calling `refresh_subscriptions` and
`refresh_purse` on a timer — a pull-poll the spec does not want, but honest.

### 7.2 Nothing constructs the layer — deliberate

`CoinageLayer::initialize` has no caller outside the coinage module. That is the
integration point, and it belongs with layer 2 / host wiring, which this plan
defers. Building a caller now would be product surface nobody asked for.

### 7.3 Paid unload tokens (§6.5) — blocked on one pallet fact, not yet chased

Blocked on the `Members` collection identifier the pallet derives per period, which
is neither in metadata nor derivable from anything the layer reads. **The obvious
next move has not been tried:** read
`paritytech/individuality`'s `pallets/coinage/src/lib.rs` directly. Fetching source
from GitHub worked for truapi#323, and it either closes this or confirms the gap in
one step. See `coinage-rfc-notes.md` §6.4.

### 7.4 Live validation — environmental

`examples/coinage_live_validation` exists, compiles and lints, and has never been
run: this work had no chain access. Running it against a testnet is what settles
whether a node parses the five `AsCoinage` variants that no runtime has yet
accepted. Mortality expiry and `post_dispatch` failure-lock behaviour need a funded
wallet on top of that.

### Suggested order

1. §7.3 — cheapest, and it either finishes §6.5 or closes the question.
2. §7.4 — read-only, needs only a testnet endpoint.
3. §7.1 — decide the ownership model first, then build it.
4. §7.2 — with layer 2.

