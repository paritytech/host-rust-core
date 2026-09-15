# Coinage Architecture

> **What this doc is:** rules and seams for coinage code. Vocabulary is a glossary, not a tutorial.
> **What this doc is NOT:** an explainer of how coinage works. Read the code (`feature/coinage/**`) for that.

Coinage is the payment primitive: money is held as a set of power-of-2-denominated coins, each its own SR25519 keypair derived from the user's mnemonic. Transfers select coins, build per-coin extrinsics, and reconcile local + on-chain state.

---

## Glossary

- **Coin** — `(derivationIndex, valueExponent, age, spentState, accountId)`. Power-of-2 denomination (`tokenAmount = 2^exponent`).
- **`SpentState`** — `NOT_SPENT` | `SPENT_LOCALLY` (optimistically marked) | `SPENT_ON_CHAIN`.
- **`ValueExponent`** — `@JvmInline value class` over `Int`.
- **`RecyclerVoucher`** — token in a Bandersnatch ring; redeemable for coins via unload.
- **`TransferPlan`** — output of `TransferPlanner`. Strategies: `ExactCoins` | `Split` | `UnloadAndSplit`.
- **`CoinageTransactionOrigins`** — factory for `AsCoin`, `AsFreeUnloadToken`, `InfallibleUnpaidSigned`.
- **`CoinagePaymentProcessingExtension`** — direct `ChatExtension` that watches on-chain coinage events.
- **`ExternalPaymentService`** — host-API-driven payment flow (RFC-0006).

---

## Rules

1. **`blocking`** — A coinage transfer must mark selected coins `SPENT_LOCALLY` **before** the extrinsic submission. On failure, revert. Why: prevents balance flicker and double-spend race during in-flight tx.
2. **`blocking`** — Keypair derivation goes through `CoinKeypairDerivation` only. Path is `//pps//coin//<n>`. Hand-rolling the derivation is forbidden.
3. **`blocking`** — Voucher batches submitted under `AsFreeUnloadToken` must have a proof count that matches the on-chain consolidation contract exactly. **Never truncate** the count to stay under a cap.
4. **`major`** — A new on-chain origin used by coinage is built by adding a sealed branch to `AsCoinageInfo` and consuming via `CoinageTransactionOrigins`. Don't bypass the factory.
5. **`major`** — A new transfer strategy is added as a `tryGet*Plan()` method on `TransferPlanner`. Don't fork the planner.
6. **`major`** — On-chain coinage state is consumed via `subscribeCoinsInfoFor` / `subscribeAllNotSpentCoins`. Polling is forbidden.
7. **`major`** — `ExternalPaymentService` is the only path host-API payment requests reach the chain. New host-API payment flows route through it; don't add a parallel implementation.
8. **`major`** — Background workers that submit coinage extrinsics use `ChainConnectionRefCounter.withConnectionEnabled(...)`. The default chain connection isn't active off-screen. (`architecture/transactions.md § Background chain work`.)

## Seams (composition points)

| Seam | What it does | When to extend it |
|---|---|---|
| `CoinageTransactionOrigins` | Factory producing `SetTransactionExtensionOrigin` wrappers | New on-chain origin for a coinage call |
| `AsCoinageInfo` sealed | Selects which `TransactionExtension` to apply | New origin family (e.g. new pallet call) |
| `TransferPlanner.tryGet*Plan()` | Strategy selection | New transfer shape |
| `CoinAllocator` / `VoucherAllocator` | Generate new coins/vouchers on demand during planning | Custom allocation policy |
| `CoinageBalanceConverterUseCase` | Exponent → display token amount, respecting chain asset precision | New display format |
| `CoinagePaymentProcessingExtension` template | The "chat watches on-chain event" extension shape | Any new chat extension that reacts to chain events |

## Anti-patterns

| Anti-pattern | Severity | Fix |
|---|---|---|
| Submitting a transfer without marking coins `SPENT_LOCALLY` first | blocking | mark first, rollback on failure |
| Truncating voucher batches | blocking | plan so proof count is exact |
| Hand-rolled keypair derivation | blocking | go through `CoinKeypairDerivation` |
| State holder fields living inside a `ChatBot` for the payment processor | major | use `*StateHolder` + dedicated VM (`architecture/chat-extension.md`) |
| Polling chain state instead of subscribing | major | use `.observe()` / `subscribeCoinsInfoFor` |
| `getOrThrow()` on a coinage `Result` | major | see `code/results-and-errors.md § getOrThrow` |
| Manual binary encoding of a payload | major | `BinaryScale` / `@Serializable` (`architecture/chain-integration.md`) |

## North star

- **Split-capable unload extrinsics.** Vouchers will support partial unload. Don't bake in full-nominal-unload assumptions.
- **Full ring-validation for unload.** Current degraded-privacy fallback is temporary. New code must not assume degraded privacy is permanent.
- **RFC-0010 W3S Allowance.** Coinage will eventually consume `PreimageSubmit` / payment-related off-chain artifacts via the allowance system.

If a new feature crosses any of these, name the alignment in the architect plan.

## Canonical examples

- Transfer (mark → submit → reconcile): `RealPrepareCoinsToSendUseCase` → `RealCoinageTransferSubmissionUseCase`.
- Chat-watches-chain pattern: `CoinagePaymentProcessingExtension`.
- Multi-key extrinsic submission: any caller of `submitExtrinsicsAndAwaitInBlock { keyPairs.forEach { ... } }`.
- Custom-origin via composition: `AsCoinageTxExtensionFactory.create(info)` — sealed-branch composition, not inheritance.

## Where new things live

| Concept | Goes in |
|---|---|
| New coin origin | `feature/coinage/impl/.../data/signer/origins/` (factory) + extension class |
| New voucher type | `feature/coinage/api/.../domain/model/` |
| New transfer strategy | new `tryGet*Plan()` on `TransferPlanner` |
| Cross-feature coinage use case | `feature/coinage/api/.../domain/usecase/` |
| External-payment state machine | `feature/coinage/impl/.../domain/externalPayment/state/` |
| Coinage worker | `feature/coinage/impl/.../data/worker/` (`code/workers-and-background-sync.md`) |
| DB changes (CoinLocal, VoucherLocal) | follow `code/database-and-scale.md` |
| Instance id config | `CoinageInstanceIdProvider` (remote config `coinage_instance_id`) |
| Instance asset unit | `CoinageInstanceUpdater` syncs `Coinage.Instances` into the storage cache; `CoinageInstanceRepository` reads it from the local source |
