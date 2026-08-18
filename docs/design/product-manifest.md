---
title: "Product Manifest — Host Implementation Guide"
type: design
---

# Product Manifest — Host Implementation Guide

This document complements [RFC — Product Manifest Format](../rfcs/product-manifest.md) with concrete data structures and a step-by-step guide for host implementors. The RFC is the normative source; this page is a quick-reference.

## Data Structures

The manifest system uses two layers of structured data: a **root manifest** at the product's dotNS base name and one **executable manifest** per modality subname.

### Root Manifest

```typescript
type RootManifest = {
  $v: 1;
  displayName: string;
  description: string;
  icon: Icon;                                  // presentational; no icon failure blocks a launch
  trustedProducts?: Record<string, Granted[]>; // product id, no TLD → what that product may do to THIS one
};

type Icon = {
  cid: string;            // Bulletin-chain CID
  format: "jpeg" | "png"; // v1 formats; an unrecognised value is tolerated, not fatal
};

type Granted = "all";     // only v1 grant; unrecognised values are tolerated, not fatal
```

### Executable Manifest

```typescript
type ExecutableManifest = AppManifest | WidgetManifest | WorkerManifest;

type CommonExecutableFields = {
  $v: 1;
  appVersion: SemVer;
};

type AppManifest = CommonExecutableFields & {
  kind: "app";
};

type WidgetManifest = CommonExecutableFields & {
  kind: "widget";
  description?: string;
  dimensions: {
    height: number[];    // supported grid-step heights
    width?: number;      // defaults to 1
  };
};

type WorkerManifest = CommonExecutableFields & {
  kind: "worker";
  entrypoint: string;
  includes: { 
    pocket?: boolean; 
    chat?: boolean; 
    input?: boolean;
  };
};

type SemVer = [major: number, minor: number, patch: number, build?: string];
```

### Subname Convention

| Subname                     | Text-record key | Carries                    |
|-----------------------------|-----------------|----------------------------|
| `<product_id>.<tld>`        | `manifest`      | Root manifest              |
| `app.<product_id>.<tld>`    | `executable`    | App executable manifest    |
| `widget.<product_id>.<tld>` | `executable`    | Widget executable manifest |
| `worker.<product_id>.<tld>` | `executable`    | Worker executable manifest |

Absence of a subname means the product does not provide that executable. Each executable subname
also holds an IPFS-codec `contenthash` — the Bulletin CID of its bytes, and the reason no
executable manifest carries a CID field.

## Resolution Flow

A host resolves a product from its dotNS base name `B` in eight steps:

```
1. node = namehash(B)
2. resolver = IDotnsRegistry.resolver(node)
   └─ address(0) → product does not exist; stop
3. json = IDotnsContentResolver.text(node, "manifest")
   └─ empty → product does not exist; stop
4. Parse JSON, validate $v and RootManifest schema
   └─ failure → malformed; surface diagnostic
   └─ exempt: unrecognised icon.format and unrecognised trustedProducts
      grant values still validate
5. (optional) author = IDotnsRegistry.owner(node)
6. For each executable type the host can render:
   subnode = namehash("<type>.<product_id>.<tld>")
   repeat steps 2–4 with text(subnode, "executable")
7. (optional) Verify owner(subnode) == owner(node)
8. cid = decode(IDotnsContentResolver.contenthash(subnode))
   └─ unset / non-IPFS codec / undecodable → cannot launch; diagnostic
   Fetch executable bytes: GET <gateway>/ipfs/<cid>
   └─ unreachable → cannot launch that executable; surface diagnostic
   icon: same fetch against icon.cid
   └─ any failure → placeholder; product still launches
```

v1 defines no byte-level CID verification for either fetch; integrity rests on the gateway.
See the RFC's Unresolved Questions.

### dotNS Dry-Run Origin

All reads use a `ReviveApi.call(origin, ...)` dry-run RPC. The origin MUST be the deterministic Revive system account, not a real keypair:

```rust
fn pallet_account(pallet_id: &[u8; 8]) -> [u8; 32] {
    let mut account = [0u8; 32];
    account[..4].copy_from_slice(b"modl");
    account[4..12].copy_from_slice(pallet_id);
    account
}

let origin = pallet_account(b"py/reviv");
// 0x6d6f646c70792f7265766976000000...0000
```

This account need not exist or hold a balance.

## Bulletin Constants

Fixed by the Bulletin chain protocol.

| Constant                  | Value                    | Meaning                                |
|---------------------------|--------------------------|----------------------------------------|
| CID version               | `1`                      | CIDv1                                  |
| Multihash code            | `0xb220` (`blake2b-256`) | Hash algorithm for the CID             |
| Digest length             | `32` bytes               | BLAKE2b-256 output size                |
| Multicodec — single blob  | `0x55` (`raw`)           | Bytes addressed as a raw payload       |
| Multicodec — archive root | `0x70` (`dag-pb`)        | Root of a merkleized UnixFS directory  |

A one-block blob is `CIDv1(raw, blake2b-256(data))`. An executable is a CAR-packed UnixFS
directory, so its root CID is `dag-pb` — a raw block has no links and cannot be a DAG root.

## Cross-Product Trust

Running products interact through the host — reading another product's account, asking it to
sign. Normally each is a consent prompt; `trustedProducts` skips the prompt for products the
publisher pre-approved.

Grants point inward — A's manifest says what others may do **to A**:

```
A's manifest:  trustedProducts: { "game": ["all"] }
               → game may act on A
               → A gets nothing on game
               → products game trusts get nothing on A
```

Keys carry no TLD: `game`, not `game.dot`. Append the TLD of the network you resolve against
before matching. Missing field, empty record, empty array all mean "prompt as usual".

Two rules the host owes the user:

- A grant waives the *publisher's* prompt, never a denial the user already gave.
- Revocation is a text-record edit with no signal, so cached grants must expire (see
  [Caching](#caching)).

## Error Handling

| Condition                                | Host action                              |
|------------------------------------------|------------------------------------------|
| No resolver / empty root manifest        | Product does not exist                   |
| Unknown `$v`                             | Undiscoverable; skip, surface diagnostic |
| Malformed JSON / schema validation fail  | Do not launch; surface diagnostic        |
| Unknown `icon.format`                    | Placeholder; never sniff or auto-correct |
| Unknown `Granted` value                  | Ignore it; manifest stays valid          |
| `trustedProducts` key does not resolve   | Entry inert; manifest stays valid        |
| `trustedProducts` key carries a TLD      | Does not resolve; entry inert            |
| Icon CID unreachable                     | Render placeholder; product launchable   |
| Icon bytes do not decode as `format`     | Render placeholder; product launchable   |
| Missing executable subname               | Product does not provide that executable |
| `kind` does not match subname label      | Skip that executable                     |
| `contenthash` unset / non-IPFS codec     | Cannot launch that executable            |
| Executable CID unreachable               | Cannot launch that executable            |
| Subname owner differs (strict provenance)| Skip that executable                     |

## Caching

Cache the **content**, and invalidate on the content's identity — the `contenthash`. Manifests are
metadata about a product; they are not what has to stay fresh.

- **Executables**: store the manifest fields together with the `contenthash` you resolved at — that
  pair is the installed executable. To check for a new deployment, re-read `contenthash(subnode)`
  and compare; a different value means new bytes, an equal value means you are current. A subname
  that stopped resolving is not drift. `appVersion` is for showing the user which release this is,
  never for detecting that a release happened.
- **Icon and executable bytes**: cacheable indefinitely by CID (content-addressed; same CID = same
  bytes). Fetch only when the `contenthash` moves.
- **Manifests**: metadata, re-read on whatever schedule suits. One exception to keep in mind — a
  revoked trust grant only takes effect once the root manifest is re-read, so bound how long a
  cached `trustedProducts` is honoured.
- dotNS provides no push notifications; hosts must poll.
