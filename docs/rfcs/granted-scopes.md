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
| `context` | Reading the granting product's account and the identity that follows from it.                           |

`trustedProducts` keeps its `Record<string, Granted[]>` shape, so this needs no new field and no `$v` bump.

- **`all` is a superset, not a peer.** `["all"]` implies `storage` and `context`, so `["all", "storage"]` is `["all"]`. A Host MUST NOT read a narrower value as a restriction on `all`. Enumerating the narrow values covers the same interactions today but does not widen when a further value is defined — that difference is the point of enumerating.
- **Values are a set.** Order is not significant, duplicates collapse.
- **Scopes are independent.** `["storage"]` leaves account interactions prompting as usual, and vice versa.
- **Existing rules are unchanged.** Hosts MUST ignore unrecognised values and MUST NOT fail validation over them, so a Host implementing only `all` reads `["storage"]` as an empty grant and prompts. Publishers MUST NOT emit a value outside `Granted`. A grant never overrides a denial the user already gave.

Which calls each scope gates remains a Host runtime contract, as it already is for `all`.

## Drawbacks

Writes stay on the wildcard: `storage` is read-only, so "read and write, nothing else" is still inexpressible. Signing has no scope of its own either. And `all` still widens silently, so staying narrow means revisiting the manifest as scopes are added.

## Alternatives

A separate field per scope (a foreign-storage record beside `trustedProducts`) splits one question — what may this product do to me — across fields that must be read together, and costs a top-level field per future scope. Per-scope operations (`{ storage: ["read", "write"] }`) add a second dimension to the manifest's only unbounded field; a `storage-write` value can land later under the ignore-unrecognised rule.

## Unresolved Questions

1. Is `context` the right name? `account` says it more directly, and `context` sits awkwardly beside the `context` parameter [RFC 0020][0020] removed from `create_transaction`.

[manifest]: product-manifest.md
[0020]: 0020-create-transaction.md
