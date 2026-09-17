# Durable Transactions Architecture

## Overview

`Packages/DurableTransactions` is the crash-durable "did this transaction land?" engine, shared by every
feature that submits mortal extrinsics whose effects must never be lost or double-spent. It owns the
ledger row, the submission watch, recovery, reorg handling and the block-body search. What a transaction
*means* — which resources it locks and how its effect is observed on chain — belongs to the feature that
registers it, behind one seam: `TxCompletionOracle`.

Coinage (`Packages/Coinage/Sources/CoinageTx/`) is the first domain.

## Key Components

### Engine (`Packages/DurableTransactions`)

| Component | Role |
|-----------|------|
| `DurableTxService` / `DurableTxServicing` | Builds, registers (atomically, with the domain's hook inside the same transaction) and submits; status and group streams; `start()` / `stop()` the head-driven recovery |
| `DurableTxRepositoryProtocol` | The ledger row, domain-neutral: id, `domainId`, sequence, group, tx hash, checkpoint, mortality, status, success record. Compare-and-set is the only status writer |
| `DurableTxRegistrationScope` | Marker for the store's open write transaction. A domain store writes its rows inside a hook receiving it and must throw `foreignRegistrationScope` for a scope of another store technology |
| `DurableTxTracker` | Follows one built extrinsic from submission; proposes verdicts through the same compare-and-set; releases ownership exactly once |
| `DurableTxOwnershipSet` | Volatile: which transactions a live submission owns, so a pass skips them |
| `DurableRecoveryPass` | One pinned view per chain, two rounds per domain (so a domain reasoning over other transactions' statuses sees round-one writes), CAS writes |
| `CompletionLadder` | Rules 0–5 (below) |
| `PinnedChainViewProtocol` / `PinnedChainViewFactory` | The generic chain reads at two pinned heads: block hash at height, block ref by hash, dispatch outcome, body search over a window. Keyed by `chainId` |
| `TxCompletionOracle` / `TxCompletionPassScope` | The domain seam (below) |
| `MonotoneEffectOracle`, `UnobservableOracle` | Ready-made oracles for "an effect that appears and stays" and for "decide by history alone" |
| `DurableChainToolsProviding` | Per-chain extrinsic operation factory and submitter, injected by the app |
| `DurableTransactionsTestSupport` | `FakeChain`, `FakePinnedChainViewFactory`, `StubPinnedChainView`, `InMemoryDurableTxRepository`, `FakeExtrinsicSubmitter`, `StubPassScope` — for any domain's tests |

### App-side (`polkadot-app/Common/DurableTransactions/`)

- `DurableTxCoreDataRepository` over `CDDurableTx`
  opens the one write transaction and hands `CoreDataRegistrationScope` to the domain hook.
- `DurableTxRowObserving` lets a domain react to a status write in the same transaction (coinage
  touches its coin/voucher rows so snapshot subscribers re-emit).
- `DurableChainToolsProvider` resolves extrinsic tools per chain from the chain registry.
- `ServiceCoordinator.createDurableTransactionEngine` builds the engine once; every domain shares it, and the coordinator alone calls `start()` (after coinage setup) and `stop()` (on throttle). No domain starts or stops the engine.

### Coinage's half (`Packages/Coinage/Sources/CoinageTx/`)

- `CoinageTxService` — the unchanged `CoinageTxServicing` facade; registers asset rows inside the
  engine's hook, maps engine errors to `CoinageTxError`.
- `CoinageAssetLedgerProtocol` — asset rows keyed by the engine's ids, the four registration
  invariants, handoff marks. App implementation: `CoinageAssetLedgerCoreData`.
- `CoinageResourceOracle` — the `TxCompletionOracle`: `CoinageEntryDag` + `CoinageEvidenceCollector` +
  `CoinageRules` answer completion / non-completion per head.
- `CoinageStateReader` — coin, voucher and alias reads at a `BlockRef`.
- `CoinageTxEntry` = engine `DurableTxEntry` + `inputs` / `outputs`. `CoinageTxId`, `CoinageTxStatus`,
  `CoinageTxGroupId` are typealiases of the engine's types; `Coinage` re-exports `DurableTransactions`.

## The Seam: `TxCompletionOracle`

```swift
public protocol TxCompletionOracle: Sendable {
    var chainId: ChainId { get }
    func openPass(transactions: [DurableTxEntry], ledger: any LedgerView, view: any PinnedChainViewProtocol)
        async throws -> any TxCompletionPassScope
}

public protocol TxCompletionPassScope: Sendable {
    func provenCompleted(_ tx: DurableTxEntry, at head: HeadKind) -> Bool
    func provenNotCompleted(_ tx: DurableTxEntry, at head: HeadKind) -> Bool   // default false
}
```

Three things about the shape are deliberate:

1. **Both questions are positive, and neither firing means "unknown".** An unknown transaction falls
   through to the block-body search, which is ground truth. The engine never negates a read, so a
   transport error cannot become a verdict.
2. **`provenNotCompleted` defaults to false.** At the finalized head, past mortality, it becomes a
   terminal failure that releases whatever the domain locked. Leaving it false costs one block scan;
   getting it wrong costs a double spend. A domain opts in only when its observation is monotone and
   singly written.
3. **The scope does not suspend.** Every chain read happens in `openPass`, batched; a per-transaction
   read during rule evaluation is not expressible.

`LedgerView` hands the oracle every transaction of its domain with the status the pass snapshotted, so a
domain whose answers depend on other transactions (coinage: a finalized successor proves the minter ran)
reads them there. Dependencies are therefore *implicit* — the engine stores no edges.

## The Ladder

Evaluated in order per transaction; first match wins. `F` is the finalized head, `B` the best head.

| # | Condition | Verdict |
|---|-----------|---------|
| 0 | a success block is recorded → is it still canonical? (read once per height per pass; unreadable → undecided) | canonical ≤ F → `finalizedSuccess`; canonical > F → `pendingSuccess`; gone → re-ask oracle at F, then B, else demote to `pending` and clear |
| 1 | `provenCompleted(F)` | `finalizedSuccess` |
| 2 | `provenCompleted(B)` | `pendingSuccess` recorded at B |
| 3 | window closed ∧ `provenNotCompleted(F)` | `failure` |
| 4 | window open ∧ `provenNotCompleted(B)` | `pending` (no body search this head) |
| 5 | body search over `[checkpoint … min(mortalityEnd, F)]` | found + success → `finalizedSuccess`; found + failed → `failure`; unreadable → `pending`; absent, whole window read, window closed → `failure`; else `pending` |

The mortality window is the extrinsic's own `CheckMortality` era, read off the built model at
registration — the window the runtime enforces, so the search covers exactly the blocks the extrinsic
could have landed in.

## Registration Atomicity

Registration commits before submission, so no extrinsic is ever in flight without a record holding what it
locks. The engine store opens one transaction, inserts its rows, then runs the domain hook with the
scope; the domain validates and writes its rows in that same context. A throw from the hook rolls both
back. Ownership is taken inside the same transaction, so a pass can never reach a committed row before its
watcher. A domain store never opens a transaction of its own inside the hook (the shared serial CoreData
queue would deadlock).

## Adding a Domain

1. Pick a `TxDomainId` and the `chainId` its transactions live on.
2. Implement `TxCompletionOracle` (or use `MonotoneEffectOracle` / `UnobservableOracle`) and register it
   with `engine.oracles` before the first submission.
3. Keep whatever the transaction locks in the domain's own rows keyed by `DurableTxId`, written inside
   the registration hook through the scope the engine hands you.
4. Submit with `engine.submitTransactions(domain:requests:groupId:onRegister:)`; observe with
   `subscribeTransactionStatus` / group streams.
5. Test over `DurableTransactionsTestSupport` fakes; the engine's own suite
   (`Packages/DurableTransactions/Tests`) needs no domain types.

## Hard Rules

1. **Terminal verdicts rest on finalized facts.** Only the finalized-bounded search, Rule 3 at F, and a
   pre-submission validation refusal may write `failure`; only F-level evidence writes `finalizedSuccess`.
2. **Unknown is never a verdict.** A failed read leaves a transaction undecided; every predicate is
   positive-form.
3. **Rows are never deleted.** Terminal rows are history a domain's provenance reads still need.
4. **One writer at a time.** A submission-owned transaction is skipped by the pass; every write is a
   compare-and-set against the status the verdict was formed from.
5. **Package tests run only through the test plan.** `DurableTransactionsTests` is listed in
   `polkadot-app/polkadot-app.xctestplan`; run with `-scheme polkadot-app -only-testing:DurableTransactionsTests`.

## Seams

| Seam | Where | When to touch |
|------|-------|---------------|
| Engine API | `Packages/DurableTransactions/Sources/DurableTransactions/Engine/DurableTxService.swift` | New engine capability every domain needs |
| Ladder | `.../Engine/CompletionLadder.swift` | Only for a rule true of *any* transaction |
| Domain seam | `.../Oracle/TxCompletionOracle.swift` | Changing what a domain can tell the engine |
| Chain reads | `.../Chain/PinnedChainView*.swift` | New generic chain access |
| App store | `polkadot-app/Common/DurableTransactions/` | CoreData shape of the ledger row, chain tools |
| Coinage oracle | `Packages/Coinage/Sources/CoinageTx/Engine/CoinageResourceOracle.swift`, `CoinageRules.swift` | Coin / voucher evidence semantics |
| Coinage ledger | `Packages/Coinage/Sources/CoinageTx/Store/CoinageAssetLedgerProtocol.swift`, `polkadot-app/Modules/Coinage/Model/CoreData/CoinageAssetLedgerCoreData.swift` | Asset rows, invariants, handoffs |
