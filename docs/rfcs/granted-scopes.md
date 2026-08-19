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

`Granted` gains two narrow values alongside the `all` wildcard: `storage` (read the granting product's host-local storage) and `context` (the cross-product account and identity interactions the Host mediates). `trustedProducts` keeps its existing `Record<string, Granted[]>` shape, so a publisher pre-approves a scope list per product instead of choosing between everything and nothing.

## Motivation

[RFC — Product Manifest Format][manifest] defines one grant value:

```typescript
type Granted = 'all';
```

`all` is deliberately unenumerated: it resolves against the complete set of cross-product interactions the Host mediates at the moment the grant is used, so it also covers interactions added after the manifest was published. That is the right default for a product's own companion apps and the wrong one for everything else.

A wallet that wants a portfolio tracker to read its holdings has to grant `all`, which also pre-approves every account and signing interaction the Host mediates now or later. The publisher's actual intent — "read my stored data, prompt for anything else" — is not expressible. The consequence is not a missing feature but a pressure to over-grant: `all` is the only value, so `all` is what gets published.

The manifest RFC reserves this change in its Future Directions, and `trustedProducts` values are already an array, so the narrower values need no new field, no new shape, and no `$v` bump.

## Detailed Design

`Granted` becomes:

```typescript
type Granted = 'all' | 'storage' | 'context';
```

`trustedProducts` is unchanged:

```typescript
trustedProducts?: Record<string, Granted[]>;
```

| Value     | Pre-approves                                                                                            |
| --------- | ------------------------------------------------------------------------------------------------------- |
| `all`     | Every cross-product interaction the Host mediates on the granting product's behalf, present and future. |
| `storage` | Reading the granting product's host-local storage. Read-only.                                           |
| `context` | Reading the granting product's account and the identity that follows from it.                           |

### `all` stays the wildcard

`all` is a superset, not a peer: `["all"]` implies `storage` and `context`. Two rules follow.

- `["all", "storage"]` is `["all"]`. A Host MUST NOT read a narrower value as a restriction on `all`. There is no way to subtract from a wildcard, and treating one as a subtraction would silently narrow grants that are already published.
- `["storage", "context"]` covers the same interactions as `["all"]` today, but does **not** widen when a fourth value is defined. That difference is the whole point of enumerating: an enumerated grant is a statement about a fixed set, a wildcard is a standing delegation.

### Values are a set

Order is not significant and duplicates collapse — `["storage", "storage"]` is `["storage"]`. Hosts MUST NOT attach meaning to position.

### Scopes are independent

`["storage"]` waives the prompt for storage reads and leaves account interactions prompting as usual. `["context"]` is the mirror image. Neither scope implies the other.

### Unchanged rules

Everything the manifest RFC already says about grants holds with three values in play:

- Hosts MUST ignore unrecognised values, keep the recognised ones in the same entry, and MUST NOT fail validation over them. A Host that knows only `all` therefore reads `["storage"]` as an empty grant and prompts — the correct degradation, since it cannot honour a scope it does not implement.
- Publishers MUST NOT emit a value outside `Granted`.
- A grant waives the publisher's prompt, never a denial the user already gave.
- Absence, an empty record, and an empty array remain equivalent.

### Runtime mechanics stay out of the manifest

The manifest RFC defines how grants are published and read, and defers which interactions a Host mediates to the Host runtime contracts. That split is unchanged: `storage` and `context` name what a grant covers, while the calls each one gates belong to the Host API surface. Addressing another product's local storage is its own runtime contract — a `storage` grant is what makes such a read promptless, not what makes it possible.

## Drawbacks

- **`storage` is read-only, so "read and write, nothing else" stays inexpressible.** A publisher who wants a trusted product to write has to grant `all`. This is the same over-granting pressure the RFC reduces, narrowed to writes rather than removed.
- **`all` still widens silently.** A publisher who wants to stay narrow has to revisit the manifest whenever a new scope is defined. Enumerating buys precision at the cost of maintenance and the wildcard buys the reverse; there is no third option that is both precise and maintenance-free.
- **Three values do not partition the mediated set.** Signing is mediated but has no scope of its own, so it stays reachable only through `all`. Until it gets one, "let this product sign on my behalf but touch nothing else" cannot be published.
- **A narrow grant is not portable across Hosts.** Ignore-unrecognised means a Host implementing only `all` degrades a scoped grant to a prompt, so `["storage"]` is a weaker guarantee to the publisher than `["all"]`. Correct, but it makes the effect of a grant depend on Host version.

## Alternatives

- **A separate field per scope**, for example a foreign-storage record beside `trustedProducts`. Discarded because it splits one question — what may this product do to me — across fields that must be read together, and every future scope then costs another top-level field and another branch in every validator. The array already exists to carry this.
- **Per-scope operations**, `{ storage: ["read", "write"] }`. Discarded for v1: it adds a second dimension to the manifest's only unbounded field, and read-versus-write is the sole place that dimension currently pays off. A `storage-write` value can land later under the same ignore-unrecognised rule.
- **Leave `all` alone and narrow at the Host prompt instead.** Discarded because it turns a publisher declaration into a per-Host UX decision: the same manifest would mean different things on different Hosts, and the publisher's intent would never be recorded anywhere durable.

## Unresolved Questions

1. **Is `context` the right name?** It covers account and identity reads, which `account` would say more directly. `context` also sits awkwardly beside the `context` parameter [RFC 0020][0020] removed from `create_transaction`.
2. **Does `storage` need a write counterpart here?** Deferring it keeps this change small but leaves writes on the wildcard, which is where the over-granting pressure is strongest.
3. **Should a Host distinguish a scoped grant from a wildcard one in its permission UI**, so a user can see that a product was pre-approved narrowly rather than completely?

[manifest]: product-manifest.md
[0020]: 0020-create-transaction.md
