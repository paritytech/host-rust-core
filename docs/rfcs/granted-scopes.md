---
title: "Scoped grants in trustedProducts"
owner: "@filippovecchiato"
---

# RFC — Scoped grants in `trustedProducts`

|                 |                                                                                    |
| --------------- | ---------------------------------------------------------------------------------- |
| **Start Date**  | 2026-08-19                                                                         |
| **Description** | Widen `Granted` from the single `all` wildcard to `all`, `storage`, and `context`. |
| **Authors**     | Filippo Vecchiato                                                                  |

## Summary

`Granted` gains two narrow values alongside `all`, so a publisher pre-approves a scope list per product instead of choosing between everything and nothing.

## Motivation

`all` resolves against every cross-product interaction the Host mediates at the moment the grant is used, including interactions added after publication. A wallet that wants a portfolio tracker to read its holdings has to grant `all`, which also pre-approves every account and signing interaction. "Read my stored data, prompt for anything else" is not expressible, so `all` is what gets published.

## Detailed Design

[RFC — Product Manifest Format][manifest] gains two `Granted` values:

```typescript
type Granted = 'all' | 'storage' | 'context';
```

| Value     | Pre-approves                                                                                            |
| --------- | ------------------------------------------------------------------------------------------------------- |
| `all`     | Every cross-product interaction the Host mediates on the granting product's behalf, present and future. |
| `storage` | Reading the granting product's host-local storage. Read-only.                                           |
| `context` | Acting as the granting product's account: reading it and the identity that follows from it, and producing proofs and signatures under its keys. |

`trustedProducts` keeps its `Record<string, Granted[]>` shape, so this needs no new field and no `$v` bump.

- **`all` is a superset, not a peer.** `["all"]` implies `storage` and `context`, so `["all", "storage"]` is `["all"]`. A Host MUST NOT read a narrower value as a restriction on `all`. Enumerating the narrow values covers the same interactions today but does not widen when a further value is defined — that difference is the point of enumerating.
- **Values are a set.** Order is not significant, duplicates collapse.
- **Scopes are independent.** `["storage"]` leaves account interactions prompting as usual, and vice versa.
- **Existing rules are unchanged.** Hosts MUST ignore unrecognised values and MUST NOT fail validation over them, so a Host implementing only `all` reads `["storage"]` as an empty grant and prompts. Publishers MUST NOT emit a value outside `Granted`. A grant never overrides a denial the user already gave.
- **A key names a product, and a product is all its executables.** The key is the segment above the TLD, so `dim2.dot`, `app.dim2.dot` and `worker.dim2.dot` are one grantee: granting `dim2` grants every executable published beneath it. A subname of another domain is that domain — `dim2.attacker.dot` reads as `attacker` and collects nothing published for `dim2`.

Which calls each scope gates remains a Host runtime contract, as it already is for `all`. A grant is a standing answer, so a call it does not cover refuses rather than prompts wherever prompting would itself disclose something — a cross-product storage read answers one refusal for every reason, and a prompt naming the target would say the target exists.

`context` gates `create_account_proof` and `ring_vrf_sign` on the granting product's keys. Both are adjudicated twice, in two different components, and both checks are load-bearing rather than one being a duplicate of the other:

- The **runtime frontend** refuses a cross-product caller before any authority is reached. The calling product id there is the one the Host bound to the connection, so this is the gate for a product running on this Host.
- The **authority holding the keys** resolves the granting product's manifest again, for itself. On a paired Host the authority request arrives over the wire from another Host, which names the product it is acting for. Relaying the frontend's verdict as a flag would take the manifest out of that decision entirely and let a peer reach every handle on the device rather than only the ones a publisher really granted.

A grant never overrides a refusal the user already gave: the stored account-access decision is read before the manifest, and read-only, so a grant lookup never raises the prompt that would settle an undecided one.

The account and identity *reads* `context` also names still take the user prompt.

## Drawbacks

Writes stay on the wildcard: `storage` is read-only, so "read and write, nothing else" is still inexpressible. `context` bundles reading an account with signing under it, so "see who I am, sign nothing" is not expressible either — splitting them costs a third value and neither half has a use without the other yet. And `all` still widens silently, so staying narrow means revisiting the manifest as scopes are added.

## Alternatives

A separate field per scope (a foreign-storage record beside `trustedProducts`) splits one question — what may this product do to me — across fields that must be read together, and costs a top-level field per future scope. Per-scope operations (`{ storage: ["read", "write"] }`) add a second dimension to the manifest's only unbounded field; a `storage-write` value can land later under the ignore-unrecognised rule.

## Unresolved Questions

1. Is `context` the right name? `account` says it more directly, and `context` sits awkwardly beside the `context` parameter [RFC 0020][0020] removed from `create_transaction`.
2. Should `storage` gain a write counterpart rather than leaving writes reachable only through `all`? A cross-product write is a larger step than a read, and no consumer has asked for one yet, but leaving it on the wildcard means a publisher who wants to allow it must also pre-approve everything else.

[manifest]: product-manifest.md
[0020]: 0020-create-transaction.md
