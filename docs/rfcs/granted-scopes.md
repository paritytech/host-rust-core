---
title: "Scoped grants in trustedProducts"
owner: "@filippovecchiato"
---

# RFC — Scoped grants in `trustedProducts`

|                 |                                                                                    |
| --------------- | ---------------------------------------------------------------------------------- |
| **Start Date**  | 2026-08-19                                                                         |
| **Description** | Widen `Granted` from the single `all` wildcard to `all` and `storage`.             |
| **Authors**     | Filippo Vecchiato                                                                  |

## Summary

`Granted` gains a narrow value alongside `all`, so a publisher pre-approves a scope list per product instead of choosing between everything and nothing.

## Motivation

`all` resolves against every cross-product interaction the Host mediates at the moment the grant is used, including interactions added after publication. A wallet that wants a portfolio tracker to read its holdings has to grant `all`, which also pre-approves every account and signing interaction. "Read my stored data, prompt for anything else" is not expressible, so `all` is what gets published.

## Detailed Design

[RFC — Product Manifest Format][manifest] gains one `Granted` value:

```typescript
type Granted = 'all' | 'storage';
```

| Value     | Pre-approves                                                                                            |
| --------- | ------------------------------------------------------------------------------------------------------- |
| `all`     | Every cross-product interaction the Host mediates on the granting product's behalf, present and future. |
| `storage` | Reading the granting product's host-local storage. Read-only.                                           |

`trustedProducts` keeps its `Record<string, Granted[]>` shape, so this needs no new field and no `$v` bump.

- **`all` is a superset, not a peer.** `["all"]` implies `storage`, so `["all", "storage"]` is `["all"]`. A Host MUST NOT read a narrower value as a restriction on `all`. Enumerating the narrow values covers the same interactions today but does not widen when a further value is defined — that difference is the point of enumerating.
- **Values are a set.** Order is not significant, duplicates collapse.
- **Scopes are independent.** `["storage"]` leaves every other interaction prompting as usual, and a scope defined later grants nothing retroactively.
- **Existing rules are unchanged.** Hosts MUST ignore unrecognised values and MUST NOT fail validation over them, so a Host implementing only `all` reads `["storage"]` as an empty grant and prompts. Publishers MUST NOT emit a value outside `Granted`. A grant never overrides a denial the user already gave.
- **A key names a product, and a product is all its executables.** The key is the segment above the TLD, so `dim2.dot`, `app.dim2.dot` and `worker.dim2.dot` are one grantee: granting `dim2` grants every executable published beneath it. A subname of another domain is that domain — `dim2.attacker.dot` reads as `attacker` and collects nothing published for `dim2`.

Which calls each scope gates remains a Host runtime contract, as it already is for `all`. A grant is a standing answer, so a call it does not cover refuses rather than prompts wherever prompting would itself disclose something — a cross-product storage read answers one refusal for every reason, and a prompt naming the target would say the target exists.

## Drawbacks

Storage is the only interaction a publisher can name. Reading another product's account and signing under its keys still have no scope of their own, so a publisher who wants to pre-approve either is back to `all` — #655 covers giving them one. Writes stay on the wildcard too: `storage` is read-only, so "read and write, nothing else" is inexpressible. And `all` widens silently, so staying narrow means revisiting the manifest as scopes are added.

## Alternatives

A separate field per scope (a foreign-storage record beside `trustedProducts`) splits one question — what may this product do to me — across fields that must be read together, and costs a top-level field per future scope. Per-scope operations (`{ storage: ["read", "write"] }`) add a second dimension to the manifest's only unbounded field; a `storage-write` value can land later under the ignore-unrecognised rule.

## Unresolved Questions

1. Should `storage` gain a write counterpart rather than leaving writes reachable only through `all`? A cross-product write is a larger step than a read, and no consumer has asked for one yet, but leaving it on the wildcard means a publisher who wants to allow it must also pre-approve everything else.

[manifest]: product-manifest.md
