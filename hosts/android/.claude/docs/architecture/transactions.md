# Transactions & Custom Origins

> **What this doc is:** rules for the extrinsic pipeline and custom origins.
> **What this doc is NOT:** a substrate primer. Read `feature/transactions/api/**` for that.

Classic signed extrinsics + a growing family of custom origins (People-Lite, AsPersonalAlias*, AsCoin, AsPgas, etc.). New origins plug in via composition; the core never grows special cases.

---

## Glossary

- **`TransactionOrigin`** = `(signerSource, paysFees, applyTo)`. The interface every origin implements.
- **`TransactionSignerSource`** — sealed: `None` | `Signed { FromAccount(metaAccount) | FromKeyPair(keypair, encryption) }`.
- **`SignedTransactionOrigin`** — classic signed tx; `paysFees = true`; applies `RestrictOrigins(false)`.
- **`SetTransactionExtensionOrigin(signerSource, extension)`** — wraps a custom `TransactionExtension`; typically `paysFees = false`. **This is the composition point for new origins.**
- **`TransactionExtension`** — substrate-sdk-android signed-extension interface. Custom subclasses (`AsCoin`, `AsPgas`, `AsPersonalAliasWithProof`, etc.) override `explicit(...)`.
- **`ExtrinsicService.submitExtrinsic` / `submitAndWatchExtrinsic`** — submission entry point. Use the lambda + origin model; never hand-build extrinsics outside this seam.
- **`ExtrinsicBuilderSequence`** — auto-nonce-incrementing iterator for multi-extrinsic batches keyed by `(ChainId, AccountId)`.
- **`ChainConnectionRefCounter`** — ref-counted connection enabler for background work. `withConnectionEnabled { ... }` for scoped use; `requestConnectionEnabled` + `release()` for long-lived (Service).

---

## Rules

1. **`blocking`** — Background work submitting extrinsics uses `ChainConnectionRefCounter.withConnectionEnabled(...)`. The default chain connection isn't active off-screen.
2. **`blocking`** — Keypairs are never shared across roles (identity ≠ device key ≠ wallet). Each role derives from its own path.
3. **`blocking`** — Multi-extrinsic batches where proof count must match on-chain operation count are not truncated to fit a cap. Plan the batching properly.
4. **`major`** — A new origin family adds to `SetTransactionExtensionOrigin` via a new `TransactionExtension`. Don't subclass `SignedTransactionOrigin` or compose a custom `TransactionOrigin` from scratch.
5. **`major`** — Manual binary encoding of arguments is forbidden when `BinaryScale` / `autoEncodedArgs` covers the case.
6. **`major`** — Origin's `paysFees` flag is the source of truth at the caller. Don't second-guess. Fee estimation uses it; submission uses it.
7. **`major`** — Multi-extrinsic submission from the same `(chainId, accountId)` uses `ExtrinsicBuilderSequence` for nonce management. Don't hand-roll.
8. **`major`** — When a new identity-proof origin is added, extend `AsPersonTransactionExtension` and expose via the matching `*Origins` factory (e.g. `PeopleOrigins`, `CoinageTransactionOrigins`). Composition, not inheritance from scratch.

## Seams

| Seam | What it does | When to extend it |
|---|---|---|
| `SetTransactionExtensionOrigin(signerSource, extension)` | Wraps a custom extension into a `TransactionOrigin` | New origin family |
| `TransactionExtension` (sdk interface) | Carries the explicit/implicit fields the runtime needs | New on-chain origin's proof-bearing data |
| `AsPersonTransactionExtension` (open base) | People-identity proof extensions | New identity-proof origin variant |
| Per-feature `*Origins` factory | Constructs origins for callers; injected via interface | New origin in a feature |
| `ExtrinsicService.submitExtrinsic { runtime, builder -> ... }` | Build + sign + submit + reconcile | All new submission flows go through this |
| `ExtrinsicBuilderSequence` | Auto-nonce iterator | Multi-extrinsic batches |
| `ChainConnectionRefCounter` | Connection-on-demand | Any background submission |

## Anti-patterns

| Anti-pattern | Severity | Fix |
|---|---|---|
| Submitting an extrinsic from background work without `ChainConnectionRefCounter` | blocking | `withConnectionEnabled(...)` |
| Sharing one keypair across roles | blocking | derive a separate keypair per role |
| Truncating proofs/batches to fit a cap | blocking | plan exactly |
| Manual binary encoding when `BinaryScale` works | major | `BinaryScale` + `autoEncodedArgs` |
| Origin's `paysFees` second-guessed at caller | major | trust the flag |
| Multi-extrinsic submission without `ExtrinsicBuilderSequence` | major | use the sequence |
| Inheritance from `AsPersonTransactionExtension` when composition via `SetTransactionExtensionOrigin` suffices | major | composition first |
| `getOrThrow()` on a chain `Result` | major | see `code/results-and-errors.md § getOrThrow` |
| `withSessionEnabled { awaitCancellation() }` for long-lived connections | major | use `requestConnectionEnabled` + `release()` |
| Marking on-chain state changes locally without a rollback path | major | architect plan must include rollback (this is a recurring risk, not a recipe) |
| Polling chain state instead of subscribing | minor | `.observe()` |

## North star

- **RFC-0010 W3S Allowance.** Slot allocation for storage/transactions/PGAS goes through the allowance system. Use the high-level allocator interfaces; don't reach into pallets.
- **`storageN<T>(name)` reified storage entries** are canonical (`architecture/chain-integration.md`). Legacy `binding = ::bindXxx` is forbidden for new code.

## Canonical examples

- Classic signed transfer: callers of `SignedTransactionOrigin` in `feature/transfers/impl/`.
- Custom proof-bearing origin end-to-end: `AsPersonalAliasWithProof` in `feature/people/impl/.../data/signer/origins/extension/`.
- Multi-extrinsic batch with per-coin keypair: `RealCoinageTransferSubmissionUseCase`.
- Fee estimation differentiated by origin: `RealExtrinsicService.estimateFee`.

## Where new things live

| Concept | Goes in |
|---|---|
| New origin family | `feature/<X>/impl/.../data/signer/origins/` (factory + extension class) |
| Custom `TransactionExtension` | `feature/<X>/impl/.../data/signer/origins/extension/` (or `feature/transactions/api/.../data/origins/` if generic) |
| `*Origins` factory interface | `feature/<X>/api/.../domain/` |
| New runtime API binding | `chains/.../call/api/<Pallet>RuntimeApi.kt` |
