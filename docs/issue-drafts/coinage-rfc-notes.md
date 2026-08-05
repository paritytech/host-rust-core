---
title: "Coinage RFC — working notes"
status: "Working notes"
---

# Coinage RFC — working notes

Scratch material collected while implementing the coinage base layer in
`truapi-server`. Everything here is either a correction to an existing document
or a decision that needs to be written down somewhere permanent.

**Much of this has now landed.** `docs/design/coinage-layer.md` is the
authoritative specification and has absorbed every correction that was addressed
to it, plus the pallet facts, the derivation scheme and the RFC‑0022 interaction.
Do not re-apply those; see §3 for the map of what went where.

What remains here is destined for a **new coinage RFC** (§2, the RFC‑0017
amendments) or is a **non-document follow-up** (§7). Fold those into their
destinations and delete this file.

Sources of truth used throughout: `paritytech/individuality`
`pallets/coinage/src/{lib.rs, extension.rs}` and the runtime configuration in
`runtimes/next-people-paseo/src/people.rs`.

## 1. Pallet facts worth recording

The runtime configuration nobody had written down, and which several documents
approximate incorrectly.

| Constant | Value on `next-people-paseo` |
|---|---|
| `MinimumExponent` | `0` (type is `i8`) |
| `MaximumExponent` | `14` — largest coin is 16,384 cents, i.e. $163.84 |
| `MaximumAge` | `16` |
| `MaxSplitOutputs` | `32` |
| `MaxConsolidation` | `64` |
| `RecyclerExpirationTime` | 90 days |
| `UnloadTokenTimePeriodPeopleLitePeople` | 1 day |
| `MaxFreeUnloadTokensPerTimePeriod` | `1000` |
| `MaxBatchUnpaidLoad` | `10` — entries one unpaid external-asset load may create |
| `UnderlyingAssetUnit` | `10^4` base units per cent |
| `CoinFailureLockPeriod` | 60 seconds (base; the applied lock doubles per retry) |

Other pallet details the implementation depends on:

- `pub type CoinValue = i8` — the denomination exponent is **signed**. Today
  `MinimumExponent` is 0, but the type permits sub-cent denominations.
- `Coin { value: CoinValue, age: u16 }`.
- `RingIndex = u32`, `RevisionIndex = u32`, `Alias = [u8; 32]`.
- Free-token personhood proof context: `pop:polkadot.net/coinftk` followed by
  the period and counter as little-endian `u32`s. Proven message is
  `blake2_256(alias_proofs.encode() ++ inherited_implication)`.
- Recycler contextual-alias context: `pop:polkadot.network/coinrecyclr`.
  Note the two contexts use different domains (`.net` and `.network`); this is
  the pallet's own inconsistency, not a transcription error.
- Individual alias proofs sign `blake2_256(inherited_implication)`.
- Recycler collection id: 32 bytes of `b"coinage/recycler"` with the exponent
  byte at index 16.
- Coinage lives on the People chain.
- `AsCoinage(Option<AsCoinageInfo>)` with variants `AsCoin`,
  `AsUnloadTokenPeople`, `AsUnloadTokenLitePeople`, `AsUnloadTokenPaid`,
  `AsUnloadTokenFromOutput`, `InfallibleUnpaidSigned`. The extension consumes
  the coin or the token in `prepare`, **before** dispatch. What a failed
  dispatch then costs is not uniform — see §1.1.

### 1.1 A failed dispatch does not cost the same thing in every flow

`AsCoinage::post_dispatch_details` partially undoes what `prepare` did, and the
asymmetry between the cases is load-bearing for a wallet:

| Origin | On `ExtrinsicFailed` |
|---|---|
| `AsCoin` | The coin is **restored** to `CoinsByOwner`, and a `LockedCoins` entry refuses it as an origin until `now + 2^retries × CoinFailureLockPeriod` |
| `AsUnloadTokenFromOutput` | The first alias is **restored**, as `AliasState::Locked` with the same exponential backoff |
| `AsUnloadTokenPeople` / `LitePeople` / `Paid` | The token is **gone**. Nothing restores it |
| `InfallibleUnpaidSigned` | Cannot happen — the pallet returns `InvalidTransaction::Custom(InternalError)` from `post_dispatch`, so the extrinsic is not included at all |

Three consequences for the layer:

1. **Nothing must be retired on a failed dispatch.** The records the operation
   held still exist; treating the failure as "the coin was spent" would delete
   a record the chain still honours.
2. **Nothing must be released as immediately reusable either.** `LockedCoins`
   and `RecyclerAliasStates` are checked in `validate`, so a coin reselected
   inside its lock produces an extrinsic that is refused — after a fresh unload
   token has already been spent building it. Every retry doubles the wait, so a
   naive retry loop converges on burning a token per attempt.
3. **`LockedCoins` is a read the layer has to make**, alongside `CoinsByOwner`,
   and the coin record needs a chain-side lock expiry orthogonal to its local
   lifecycle state. `CoinFailureLockPeriod` is `#[pallet::constant]` and does
   come back from metadata, unlike the two constants in §6.

## 2. RFC-0017 amendments

### 2.1 Appendix A's derivation scheme is unsafe and must be superseded

RFC-0017 Appendix A specifies
`//coinage//<PURSE>//<PAGE><DERIV_SEC>/<ITEM>` — a secret component inside a
path segment and a **soft** junction at the item.

RFC-0022's Motivation establishes that sr25519 soft derivation is invertible
from the child side: a child secret key, the parent public key and the path
together recover the parent secret, and salting a segment with a secret
component does not restore the firewall.

RFC-0017's entire model is built on transmitting coin secrets — that is what a
cheque is. So under Appendix A, cashing a single cheque would expose the purse
root and with it every other coin in the purse, past and future.

Nothing implements Appendix A, so there is no migration cost. The new RFC should
supersede it explicitly with all-hard junctions and state the reason inline, or
somebody will reintroduce soft derivation later to regain enumerable public keys.

### 2.2 Missing permission variant

RFC-0017 requires a `UserAgentPermission::CoinPayment`. `v01::permissions.rs`
has only `HostDevicePermissionRequest` and `RemotePermission`. There is
currently **no protocol-level way to grant or deny CoinPayment access**, so
consent for purse operations cannot be expressed at all. This blocks an honest
implementation of even `create_purse`.

### 2.3 Balance units disagree

`v01::coin_payment::CoinPaymentBalance` is `u32` cents. `v01::payment::Balance`
is `u128`. They meet at the purse selectors RFC-0017 added to the RFC-0006
calls, and nothing reconciles them.

**Decision: `u32` cents.** The largest coin is 2^14 cents, so `u32` covers
roughly $42.9M — ample. The implementation works in `u64` cents internally so
sums cannot overflow, and narrows to the wire type through a fallible
conversion.

### 2.4 Cheque encryption is unspecified

`CoinPaymentCheque.encrypted_secrets` is declared opaque. But a cheque crosses
from the *payer's* host to the *receiver's* host, so both sides must agree on
the KEM, the AEAD and the coin-secret encoding. As written, cross-vendor payment
is impossible.

Two decisions to record:

1. **Specify one scheme.** The receivable is already a 32-byte public key
   produced by the receiver's coinage subsystem, so the natural construction is
   a sealed box — ephemeral key, HKDF, AEAD over the SCALE-encoded secrets. The
   core already has an encrypted-channel construction in its SSO session-message
   code; reuse it rather than inventing one. The receivable's key type still
   needs pinning; RFC-0022 touches P-256 ECDH keys but does not settle this use.
2. **Version the blob.** Even with a single implementation, a cheque crosses
   between hosts on different app versions. The blob needs a version byte and a
   stated rule for what a receiver does with a version it does not know. Cheap
   now, painful to retrofit.

### 2.5 Purse identifiers

RFC-0017 says purse ids are "randomly assigned by the user agent". The
implementation assigns them sequentially from a monotonic counter.

**Decision: assignment is host-local; non-reuse is normative.** A purse id names
a derivation namespace, so reusing one lets a new purse inherit the on-chain
history of a closed one. That property is the security-relevant half and should
be stated as a requirement. The assignment method is not, and sequential
assignment is deterministic and testable.

This matters because the earlier iOS implementation
(`polkadot-app-ios-v2#872`) allocated `max(existing) + 1`, so deleting the
highest purse and creating a new one **reused its derivation namespace**. Worth
naming in the RFC as the failure the requirement prevents.

### 2.6 Smaller RFC-0017 items

- `MAIN_PURSE` is `u32::MAX` in RFC-0017 and "e.g. `0`" in the design doc. The
  implementation uses `0`. Pick one and fix the other document.
- `refund` takes only `receivable` in RFC-0017; the design's contract doc adds
  `amount: Amount?`.
- The purse-delete precondition differs between the two design docs: "no open
  receivables" versus "no in-flight operations". The base layer cannot see
  receivables, so the latter is the base-layer rule and the former belongs above
  the seam.

### 2.7 RFC-0021 deprecation, sequenced

RFC-0021's `PaymentTopUpSource::Coins` lets a product handle raw coin secret
keys in the clear, explicitly bypassing the cheque ceremony. It exists because
the two large RFC-17 PRs were too big to review before a demo, and it should go
once RFC-17 lands.

It cannot go earlier: the T3rminal/W3S flow is its live consumer, and that is
what `W3S_AUTH_KEY` / `/top-up` exercises in the CLI host. Order is: cheques
land → W3S moves to cheques → RFC-0021 deprecated. Write the dependency into the
new RFC so the stopgap does not become permanent.

## 3. Corrections to `docs/design/coinage-layer.md` — all applied

Every item in this section has been folded into the specification. Kept as a map
so a future reader can see what changed and why, without re-applying it.

| Correction | Where it landed |
|---|---|
| A.10 `max_recycler_entries_per_group` is `64`, not `8`, and is a chain constant | Appendix A.0 (`MaxConsolidation`), A.9–A.10 withdrawn |
| A.5's rationale was wrong — the chain allows `1000`, so `[0, 10)` is a policy choice bounded by the constant | Appendix A.5, A.0 |
| A.9 `max_split_outputs` belongs with the chain constants | Appendix A.0 (`MaxSplitOutputs`) |
| Chain-enforced caps and policy tunables are different kinds of fact and must be separated | Appendix A.0 vs A.1–A.14; §6.7 validates the former at connection |
| Denomination exponents are signed (`i8`); reject negatives, refuse a negative-`MinimumExponent` runtime | §3.6, §6.7, Appendix A.0 |
| Entries need a ring *revision*, not just an index; grouping keys on both | §3.7 (ring location), §5.2, §6.3, §6.4, §8.6 |
| Selection is policy-free — readiness already encodes the anonymity floor | §6.3 |
| A third selection error is needed: value present, shape impossible | §6.3 three-way table, §10 `UnsatisfiableOutputs` |
| Events must be drained and published before the store is persisted | §7.9 |
| `coinage-management.md` / `coinage-management-contract.md` are superseded | §2.4 |

Also folded in from elsewhere in this file: the pallet constants and their
discoverability (§1, §6 → Appendix A.0), the failed-dispatch asymmetry
(§1.1 → §5.6), the adopted derivation scheme and its hard-junction requirement
(§5, §2.1 → Appendix B), the RFC‑0022 interaction (§4 → Appendix B), the
main-purse identifier and purse-id non-reuse rule (§2.5, §2.6 → §3.1, §4.3), and
the balance-unit decision (§2.3 → §3.6).

Two items from §2 are recorded in the spec only as open questions, because they
belong above the seam: the missing `UserAgentPermission::CoinPayment` (§2.2) and
the unspecified cheque encryption (§2.4). They still need the RFC.

## 4. RFC-0022 interaction

RFC-0022 **defers coinage by name, twice** — in the built-in-features table
("Not coercible to a product | Coinage | — | Deferred to a separate RFC") and
again for ring-VRF keys ("Coinage's ring-VRF keys (recyclers/vouchers) are
deferred to the coinage RFC"). The new coinage RFC is that deferred RFC, which
is the cleanest possible position: it fills a declared gap rather than
overriding anything.

Three points to carry:

1. **Reuse RFC-0022's keyed-hash HDKD for entry keys.** Its
   `derive_ringvrf_hard(parent, code) = hash(parent, code)` fold, hard-only, is
   the right primitive. Adopt the function rather than defining a parallel one.
2. **Root coinage under a reserved domain.** RFC-0022 shapes that tree as
   `//{domain}//{index}` with the domain always a product's dotNS identifier,
   which coinage cannot supply. Coinage takes `coinage` as a reserved domain —
   unambiguous because every product domain is a dotNS name — and extends the
   path with the purse and index structure it needs.
3. **Correct RFC-0022's notation.** It records coinage's current layout as
   `//pps//coin/{index}` and `//pps//ring-vrf/{index}`, with a *single* slash
   before the index implying a soft junction. Both mobile implementations use
   `//pps//coin//<n>` — hard. Probably loose notation in a table cell, but given
   §2.1 it is worth being precise about.

Also note RFC-0022 set the precedent for the breaking-change posture: "There are
no production deployments … the selector change is wire-breaking … and is made
freely, with no migration path."

## 5. The adopted derivation scheme

Appendix B of `coinage-layer.md`, unchanged, and now implemented:

```text
coins:            //coinage//coin//<purse>//<page>//<index>   sr25519
recycler entries: //coinage//<purse>//<page>//<index>         bandersnatch,
                                                             folded into
                                                             RFC-0022's tree
```

- **Every junction is hard**, for the reason in §2.1. This is a security
  requirement and the RFC should say so inline.
- **The key-type split** lets recovery enumerate each subtree independently —
  coins against `CoinsByOwner`, entries against recycler-location storage —
  without probing indices that could only belong to the other.
- **`<page>` is always 0** in this version. The junction is present anyway, so
  adding pages later does not move existing accounts.
- This is a clean break from the shipped `//pps//…` layout. Existing testnet
  coins become unreachable, which is accepted.

## 6. Four pallet constants are not discoverable

Two were found first and are the dangerous pair; §6.4 adds two more from the
paid-token work. All four are absent from `paseo-people-next`'s metadata and are
carried as per-network configuration, refused if a newer runtime disagrees.

Verified against `paseo-people-next` by
`rust/crates/truapi-server/examples/coinage_chain_agreement.rs`. Eight of the
ten values the layer needs come back from metadata and match; **two do not
appear at all**:

| Constant | Why absent | Consequence |
|---|---|---|
| `MaximumAge` | Declared in the pallet's `Config` **without** `#[pallet::constant]` | Drives `recycle_at_age = MaximumAge − 2`. A runtime that lowers it goes unnoticed, and the layer would then recycle later than the chain allows — coins age out unusable |
| `RecyclerExpirationTime` | Marked `#[pallet::constant]` in the pallet source but absent from the deployed runtime's metadata, so the deployed runtime predates that attribute | Drives the rescue margin. A runtime that shortens it without our noticing makes the ring-expiration sweep fire too late |

Both must be carried as per-network configuration. The uncomfortable part is
that **these are exactly the two values that guard the two fund-loss paths** —
coins aging out, and entries expiring in a ring. Everything else the layer can
verify against the chain at connection time; these two it must be told.

`PaidUnloadTokenTimePeriod` and `PaidUnloadTokenRingExpirationTime` are the other
two; see §6.4. Both are `#[pallet::constant]` in the source and absent from the
deployment, so they share `RecyclerExpirationTime`'s diagnosis.

Two asks worth raising with the pallet authors:

1. Add `#[pallet::constant]` to `MaximumAge`.
2. Confirm whether the `RecyclerExpirationTime`,
   `PaidUnloadTokenTimePeriod` and `PaidUnloadTokenRingExpirationTime` attributes
   are newer than the deployed runtime, and if so when they land. Three constants
   with the same story suggests one runtime upgrade settles all of them.

Until then the layer should treat a mismatch between configured and observed
values as a hard failure wherever it *can* observe, and the RFC should state
that these two are configuration rather than implying every constant is
discoverable.

### Confirmed against the live runtime

Worth recording, since it validates several assumptions the implementation was
built on:

- Coinage is pallet index **68**; `split` 0, `transfer` 1,
  `load_recycler_with_coin` 2, `unload_recycler_into_coins` 13 — all resolvable
  by name.
- All six `AsCoinageInfo` variants exist at indices **0–5** in declaration
  order. `InfallibleUnpaidSigned` is 5, which matches the byte layout the CLI
  host already submits successfully, independently confirming the ordering the
  encoder assumes.
- `MaxConsolidation` is **64**, confirming Appendix A.10's 8 is wrong.
- `MaxFreeUnloadTokensPerTimePeriod` is **1000**, confirming A.5's rationale is
  wrong.
- `CoinFailureLockPeriod` is **60 seconds** and *is* discoverable, so the
  failure-lock backoff in §1.1 needs no configuration.

## 7. Non-document follow-ups

These are not RFC content but were found alongside it and should not be lost.

### 6.1 iOS silent loss of funds — unfiled, security-grade

`CoinageRecyclingService` on `polkadot-app-ios-v2` recycles coins **into**
recycler entries but never unloads entries **out**. If a user tops up and does
not open the app before the ring is cleaned up (`immutable_since +
RecyclerExpirationTime`, i.e. 90 days), the entry's backing value is destroyed by
the pallet.

This is the only way for value to disappear from a wallet whose root entropy and
chain identity are otherwise intact. The Quint model in PR #122 finds traces
matching it. It has been sitting in the work notes since May 2026 and is still
unfiled; it affects shipping `develop`.

Note the fix is not purely core-side. Three conditions must hold: the core
implements the entry→coin rescue sweep, **the host schedules it in the
background**, and the app routes its coinage through the core. The middle one is
the general scheduling gap — the core has no clock outside a live session — and
the failure mode is precisely "the user did not open the app", so a
foreground-only sweep narrows the window without closing it.

### 6.2 Balance drift after restore

pgherveou reports that the displayed cash value is sometimes wrong, and that
restoring from backup yields a different amount. Restore rescans derivation
indices against chain state and reconstructs the true set, so this is consistent
with local records having drifted — either value destroyed by ring expiry (§6.1)
or entries consumed on chain but never reconciled locally. Worth capturing as a
test case for the core implementation rather than chasing in the app.

### 6.3 The apps still have to retire their own coinage engines

Neither mobile integration PR migrates coinage: they delete the host-API
dispatch layer, and `feature/coinage` / `Packages/Coinage` survive untouched. So
core-side coinage will be available to *products* while the apps' own wallet UI
still runs the native engine — two engines, two coin stores, cleanly disjoint
only because the derivation break makes them so. Retiring the native engines is
a third project after RFC-17-in-core and after the integrations, and it is real
UI work in both apps.

### 6.4 The paid unload-token ring — resolved from the pallet source

**Closed.** Read out of `pallets/coinage/src/{lib.rs, paid_tkn_manager.rs}` in the
sibling `individuality` checkout. Every fact the fallback needed:

| Fact | Value |
|---|---|
| Collection identifier | `b"coinage/paidtkn!"` (16 bytes, `!` included) ‖ period as LE `u32` ‖ zeros |
| Proof context | `b"pop:polkadot.net/coinpaidtok"` (28 bytes) ‖ period as LE `u32` — **no counter** |
| Signed message | `blake2_256(alias_proofs.encode() ‖ inherited_implication)` — identical to the free token's |
| Period | `unix_secs / PaidUnloadTokenTimePeriod`, a **different constant** from the free period: 3 days against 1 |
| Ring expiry | `(period + 1) * period_length + PaidUnloadTokenRingExpirationTime`; 4 days on the reference runtime |
| Join calls | `pay_for_recycler_unload_fee_token_with_coin` (6), `_with_native` (7), `_with_external_asset` (8) |
| Join arguments | `member_key` plus `proof_of_ownership`, the latter signing the origin account's encoded bytes — the same rule as §6.6 |
| Onboarding size | 1, so a joined key reaches a ring quickly — but *which* ring is the chain's choice |
| Ring exponent | `PaidUnloadTokenRingExponent`, `R2e10`; this one *is* in metadata |

Three things about it were not anticipated by the design doc, and all three are now
folded into `coinage-layer.md` §6.5:

1. **One paid key is one token per period,** because the context carries no
   counter. `N` paid tokens means `N` keys, `N` joins and `N` fees. The design doc
   described a single join per period, which is wrong.
2. **Joining and becoming provable are two steps.** The key is registered
   immediately; the members pallet onboards it into a ring afterwards, and the
   proof needs the ring. In between, the slot is paid for and unusable.
3. **The join call takes no period.** It uses the chain's clock at dispatch, so a
   join near a boundary lands in the next period.

Two smaller traps worth recording:

- The pallet spells the period **little-endian** in the collection identifier and
  **big-endian** in `PaidTokenCollectionsCreated` / `PaidUnloadTokenConsumed`,
  whose `Identity` hashers need lexicographic order to match numeric order. Both
  are pinned by golden tests.
- `PaidUnloadTokenTimePeriod` and `PaidUnloadTokenRingExpirationTime` are marked
  `#[pallet::constant]` in the source but are **absent from the deployed runtime's
  metadata** — the same situation as `RecyclerExpirationTime` (§6). So the
  configured-constant list grows from two to four. These two cannot lose value,
  but a wrong paid period spends a join fee on a token that proves against a
  collection nobody is verifying against.

A third drift worth flagging to the pallet authors: the deployed runtime names the
third join's event `PaidUnloadTokenRegisteredWithStable`, where the source says
`...WithExternalAsset`. The source is ahead of the deployment here too.

Note that from-output fees blunt the whole question in practice: an unfunded fee
account spends no free slot at all (§6.6), so the allowance is only consumed by
wallets that *can* pay prepaid.

### 6.5 Which side's index `MemoEntry::derivation_index` carries is unsettled

§8.3's `MemoEntry` has `sender_coin_account`, `recipient_account` and
`derivation_index`, and nothing says whose index the third field is. Two readings:

- **The payer's** index for the origin coin. Derivable by the layer, useless to
  the payee, and mildly leaky — though the entry already names the payer's coin
  account, which is strictly more revealing and is public on chain anyway.
- **The payee's** index for `recipient_account`, echoed back so the payee can
  locate the coin without a scan. Far more useful, and consistent with RFC‑0017's
  flow where the payee generates the receivable — but the payer only knows it if
  the caller supplies it, so it would have to become an input to `transfer`.

The implementation carries the payer's index and documents the choice. The new
RFC should settle it; the second reading is the better API and costs one field on
the transfer request.

### 6.6 `proof_of_ownership` signs the origin account, raw

Settled. Both `load_recycler_with_coin` and
`load_recycler_with_external_asset_unpaid_batch` carry a 64-byte
`proof_of_ownership` beside the member key they publish, and unlike every other
proof in this pallet it is checked by the *call* rather than by the extension —
so its message cannot be the inherited implication, which a dispatch cannot see.

The message is the **origin account's 32 bytes, raw and unhashed**, signed by the
entry's own Bandersnatch secret. Confirmed against the shipped top-up flow in
truapi#323, which signs the temporary external-asset holder's account id exactly
this way; the coin-origin case signs the recycling coin's account by the same
rule. What the proof establishes is that whoever controls the value being
converted also controls the key being published.

### 6.7 A recovery scan is expensive before it is anything else

Appendix A.7 and A.8 recommend a batch of 500 and a gap limit of 4, which means a
scan of an *empty* purse still derives 2,000 coin accounts and 2,000 recycler
member keys before it can conclude there is nothing there. The coin side is
sr25519 hard derivation; the entry side is Bandersnatch, which is slower. On a
laptop that is seconds per purse, and a recovery names several purses.

The chain reads themselves are fine — one bulk `state_queryStorageAt` per batch —
so the cost is entirely local key derivation. Worth knowing before someone runs a
recovery on a phone. Two obvious mitigations if it bites: derive the batch's keys
in parallel, or let the caller narrow the window when it knows the wallet is
small.
