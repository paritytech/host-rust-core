# Coinage Architecture

## Overview

Coinage is the payment primitive for the Polkadot app — managing digital coins with derivation indices, values, and lifecycle states. Used for in-app payments, game rewards, and peer transfers.

## Key Components

### Package
- **Coinage** (`Packages/Coinage/`) — core coinage logic, coin models, transfer planning

### Module
- **Coinage** (`Modules/Coinage/`) — UI for coinage operations

### Services (in ServiceCoordinator)
- `coinageService` — coinage state management
- `coinageBackupSyncService` — iCloud backup synchronization

## Coin Model

A coin (`Packages/Coinage/Sources/Models/Coin.swift`) has:
- `exponent` — coin value as a power of two (`2^n`)
- `derivationIndex` — unique derivation path
- `age` — on-chain age; `nil` = never seen on chain, `0` = fresh from unload/split
- `isOnchain` — on-chain presence, written only by chain sync (`age != nil ∧ ¬isOnchain` = seen then vanished)
- `handoffMark` — whether the coin has been handed off to a peer, and how far along
- `publicKey` — on-chain account id derived from `derivationIndex`, cached so the durability layer never re-derives it

## Key Rules

1. **Use the `KeyDerivation` package** — never hand-roll coin keypair derivation. The derivation domain must be coinage-specific (never reused across features).
2. **Zero balance handling** — properly handle zero-balance edge cases
3. **Deterministic fund amounts** — top-up affordances (the "+" fund button) must compute the resulting coin set from a deterministic plan: same input balance + same target → same coin denominations every time. Don't sample randomly, don't depend on iteration order over an unsorted set, and don't let the displayed preview drift from the amount actually submitted. The fix was switching from "pick coins as we go" to producing a stable plan up-front, then rendering and submitting from that plan.
4. **Exact-match edge in transfer planning** — when the requested amount exactly equals one of the candidate coin denominations, the planner must take the single-coin path and skip the split/unload branches. Hitting split logic with an exact match crashes because it tries to break a coin it doesn't need to. The same care applies to the "no split needed" boundary in `Coinage` transfer planning: always test the exact equality case alongside under/over.

## Balance (strategy-aware, two-pass)

`CoinageBalanceService` emits a single `CoinageBalance` with three plank buckets:

- `availablePrivate` — spendable now at no privacy cost (coins the strategy leaves usable + usable vouchers).
- `gainingPrivacy` — `{ amount, canSpendWithConfirmation }`; deliberately held back, some strategies release it behind a confirmation (`maxPrivacy` does not).
- `pending` — arriving, or past the chain's age ceiling; never spendable.

Derived: `available` = `availablePrivate (+ gainingPrivacy.amount when canSpendWithConfirmation)`; `total` = all three. Amounts are planks — render via `CoinageBalanceServiceProtocol.denominationContext` (`decimal(fromPlanks:)`).

**Consumer semantics**: spend-sufficiency and the primary "spendable" figure use `availablePrivate`; the reachable-with-confirmation figure uses `available`. Products sufficiency → `availablePrivate`; TransferAmount `secured`/`lowPrivacy` → `availablePrivate`/`gainingPrivacy.amount` (the latter zeroed when `!canSpendWithConfirmation`); AssetDetails total → `total`, locked → `total − available`.

**`BalanceEvaluationMode` (immediate | complete).** The balance renders nothing until the first verdicts land, so `CoinRecyclingEvaluator` runs a two-pass: when it has no verdicts yet it first publishes an `immediate` pass (no chain read — `RingCapacityProviding.peekCapacities` returns only memoised capacities, and `RecyclingStrategyProviding.coinStrategy(for:mode:)` skips the quota read, treating quota as exhausted so only the chain age-ceiling gates), then a `complete` pass consults every limit and corrects. The correction is downward-only — a coin the policy would hold shows spendable until `complete` moves it, never the reverse. Recycling is triggered only off the `complete` pass. The balance service itself uses `immediate` (peek) capacities so it never blocks.

## Transfer Planning

Transfer plans determine how coins are spent:
- Exact coins — use specific coins
- Split — divide coins for partial amounts
- Unload and split — complex multi-step transfers

## Payment Processing

- `CoinagePaymentProcessingExtension` watches on-chain events for payment confirmations
- Integrates with chat for payment request/confirmation messages
- See `architecture/chat-extension.md` for chat integration

## External Payments (offramp)

`Packages/Coinage/Sources/ExternalPayment/` moves coins to a destination account for a product
 or the in-app pay flow (`ExternalPayment.nativeProductId`). Rows are
`ExternalPayment` (`CDExternalPayment`) keyed `external-payment:<productId>:<paymentId>`.

- **Planner** (`ExternalPaymentPlanner`): private vouchers alone, else every on-chain voucher
  (private first, then largest) → `.unloadVouchers`; else coins for the shortfall with all vouchers
  offboarded as they are → `.loadCoins(coins, exactVouchers)`; else `.notEnoughBalance`.
   "Private" is what the balance calls usable (`ExternalPaymentAssetClassifier`).
  `canPayPrivately` is the first step alone, so the warning and the plan cannot disagree. Callers
  warn when it is false and the preset is not `minPrivacy`.
- **Worker** (persist-per-transition, one run per payment, no retries): `Plan` → `OffboardVouchers`,
  or `Plan` → `OnboardCoins` → `OffboardVouchers`. Onboarding recycles under `<id>:recycle`, awaits
  `CoinageRecyclingServicing.observeRecycling` (`pending | allRecycled(vouchers:finalized:) | incomplete`;
  best-block inclusion is enough), then `pickOffboarding` selects what to unload from exact + recycled
  vouchers (largest first; a shortfall fails). The picked vouchers and their surplus are planner output
  persisted with the offboarding stage (`plannedVoucherIndices`, `surplusInPlanks`) and handed to the
  unload as they are. Offboarding submits under `<id>`: success completes, `partialSuccess` is terminal
  (`partiallyCompleted` with `settledInPlanks`), everything else fails. Each stage persists its
  vouchers (`plannedVoucherIndices`) and re-joins its durability group on relaunch; an onboarding row
  whose recycling group cannot be found fails rather than re-plan (nothing may be spent twice).
- **Status**: unknown id → the stream throws `notFound`; duplicates collapse; ends after the first
  terminal status. 
- **Tests**: `Packages/Coinage/Tests/ExternalPayment/`, sweep
  `Packages/Coinage/Tools/external_payment_mutation_sweep.py`.

## Seams

| Seam                    | Where                          | When to touch                    |
|-------------------------|--------------------------------|----------------------------------|
| Coin models             | `Packages/Coinage/`           | Coin structure changes           |
| Transfer planning       | `Packages/Coinage/`           | New transfer strategies          |
| External payments       | `Packages/Coinage/Sources/ExternalPayment/` | Offramp identity, retry, status, planner scope |
| Coinage UI              | `Modules/Coinage/`            | Coinage screen changes           |
| Backup sync             | ServiceCoordinator             | Backup/restore flow changes      |
| Durability (oracle, asset ledger) | `Packages/Coinage/Sources/CoinageTx/` | Coin/voucher evidence or invariants; the engine itself is `Packages/DurableTransactions` (see architecture/durable-transactions.md) |
| Instance ID config      | `AppConfig.Coinage.instanceId` | Remote config schema or app instance strategy changes |
