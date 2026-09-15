# Migrating product-sdk's e2e suites onto the TrUAPI test host

`product-sdk-truapi-migration.patch` moves product-sdk's nine example suites off
`@parity/host-api-test-sdk` and onto `@parity/truapi-host/testing`. It applies
cleanly to product-sdk `origin/main` (verified with `git apply --check`), and is
a starting point for review rather than a finished PR — see the open items at
the end.

Apply from the product-sdk repo root:

```bash
git apply docs/migration/product-sdk-truapi-migration.patch
```

## What is in it

**Every suite: the fixture, and only the fixture.** `e2e/fixtures.ts` builds its
`testHost` from `@parity/truapi-host/testing/playwright` instead, and
`e2e/helpers.ts` changes one type import. The specs are otherwise untouched —
the method names on the new fixture deliberately match `TestHostAPI`'s so a
migrating suite changes its import, not its assertions.

**Five assertion rewrites, all one cause.** Four suites read
`@parity/host-api-test-sdk`'s *internal* storage keys out of the host page —
`localStorage.getItem("test-host:demo:mykey")` and friends. That is a test
coupled to one host's implementation rather than to product behaviour, and no
amount of API compatibility ports it. They now read through the control surface
(`findProductStorage`), which is the host's public contract:

- `storage-demo`: `kv-ops.spec.ts`, `prefix.spec.ts`
- `keys-demo`: `session.spec.ts`
- `host-demo`: `storage-ops.spec.ts`
- `signer-demo`: `persistence.spec.ts` (its `STORAGE_KEY` constant also carried
  the `test-host:` prefix, and it used that storage as a flush barrier)

**One behavioural rewrite.** `signer-demo/switch-account.spec.ts` asserted that
switching the host account leaves the product account unchanged. That held
because `host-api-test-sdk`'s `productAccounts` option pinned a product account
to a fixed dev keypair regardless of the active account. TrUAPI derives a
product account from the session root and has no multi-account session —
`account.getLegacyAccounts` returns an empty list by design — so switching is
switching *user*, and the account must change. The test now asserts that,
plus that switching back restores the same address (derivation is
deterministic) and that the session stays connected.

**One skip, proposed rather than decided.** `signer-demo/permission.spec.ts`
asserts that revoking a permission mid-run and reconnecting re-prompts the host.
A real TrUAPI core persists a decided authorization per (product, permission)
and answers from its own storage, so the second request never reaches the host.
It passes today only because `@parity/host-api-test-sdk` is a TypeScript
reimplementation of the protocol with no core behind it. No test host can make
it pass; the comment says so and the call is product-sdk's.

## Results

Against the TrUAPI test host, on the production Web Worker topology:

| Suite | Result |
| --- | --- |
| storage-demo | 8/8 |
| keys-demo | 8/8 |
| host-demo | 6/6 |
| signer-demo | 8/9, 1 skipped as above |
| chain-client-demo | 2/2, proxying the real Asset Hub |
| tx-demo | boots; writes blocked on unfunded accounts |
| contracts-demo | boots to `pallet-revive` account mapping, a write |
| statement-store-demo | connects over the real people chain; 3 control methods absent |
| cloud-storage-demo | already skipped upstream |

## Open items, which is why this is not a finished PR

- **The catalog entry is a placeholder.** `pnpm-workspace.yaml` gains
  `"@parity/truapi-host": ^0.12.0`; confirm against what is actually published
  before merging.
- **product-sdk does not compile against `@parity/truapi` 0.15+ as-is.**
  `packages/host/src/testing.ts` (`createFakeHost`) is missing
  `signRawUnwatermarkedDeprecated` and its `LegacyAccount` twin, and
  `PublicTruApiClient` is missing the `renderer` domain. Both are small, both
  are prerequisites, and neither is in this patch because they are a separate
  change: the codec-1 → codec-2 bump.
- **Write-dependent suites need funded accounts.** `tx-demo` and
  `contracts-demo` reach the chain and fail on fees. The addresses are
  deterministic per (dev account, product id) and funding them is an
  operational decision, not a code one.
