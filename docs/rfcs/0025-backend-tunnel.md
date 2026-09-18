---
title: "Deployer backend tunnel"
owner: "@BigTava"
authors: ["@BigTava", "@filvecchiato"]
status: draft
---

# RFC-0025 — Deployer backend tunnel

## Summary

A product names a backend and a request against it; the host performs that request against the deployer's backend with a credential the product never sees, and returns the answer. The backend is what reaches the third-party provider, with its own key — the host never holds that key and never calls the provider. A new `Backend` trait carries this, served by a new optional host capability. The core screens the request, forwards it, and holds no secret of its own.

## Motivation

A product cannot hold a server-side API key. It runs on the user's device, so anything it holds is readable there — [Meld](https://docs.meld.io/docs/meld-api/getting-started) says so directly: "Always call Meld from your backend. Direct calls from a browser or mobile app expose your API key."

So the key lives in a backend the deployer runs, and the question is how a product reaches it. Answering that with a caller identity — a signature the host attaches to the product's own outbound request — answers a different question. It tells a backend *who* is calling, but a deployer's backend does not need to identify the user; it needs to know the call came through a host it trusts, so it can decide whether to spend its own quota on it.

There are two credentials, belonging to different parties: the **third-party key** lives in the deployer's backend, the only place it can; the **backend's own credential** lives in the host, which already ships secrets. The product holds neither and needs to hold neither.

## Approach

```
product   ──  backend.request { backend, method, path, query, body }
   │
core      ──  screens the request; resolves nothing, holds nothing
   │
host      ──  backend id → base URL + host's own credential
   │              ↓ HTTPS, Authorization: Bearer <host↔backend credential>
backend   ──  the deployer's service; holds the third-party key
   │              ↓ HTTPS, authenticated with the third-party key
provider  ──  Meld and the like
```

Two hops, two credentials, and the host is only on the first one. It authenticates *itself to the deployer's backend*; it never holds the third-party key and never calls the provider. That is the whole point of the split: the key the product cannot hold is a key the host does not hold either.

The product supplies an opaque identifier and a request relative to it. It never supplies an origin: scheme, host, port and userinfo have no field to travel in. Which base URL the identifier resolves to, and what authenticates the host to it, is host configuration — not protocol, not manifest, and not readable by a product.

The identifier resolves per call rather than at startup, so a host can add a backend or refresh a credential without the core knowing. An identifier a host does not serve is an error, not a missing capability.

`Backend::list` answers which identifiers a host serves the calling product, so a product can check before it depends on one rather than discovering the gap from a failed call. It is product-scoped: a registry that pins its entries to product ids answers each product with its own set, and an empty list means this host serves *this product* nothing, not that it has no backends. It carries identifiers only — where a backend lives stays host-side, which is the whole point of naming one by id.

A URL in the product's hands would be a deployment detail in every product's source and every debugger frame, and a value the product could vary. An identifier is neither.

**A registered base must be a service the deployer runs, never a third-party API directly.** Nothing in the core can tell the two apart — a host could point an entry straight at `api.meld.io` with a Meld key beside it, and every mechanism here would work. It would also move the third-party key into the host, where it ships in an app binary or, on a browser host, sits in devtools. The Motivation for this RFC applies one layer up: a host is a better place for a credential than a product, and still the wrong place for the provider's.

### What the core screens

Moving outbound HTTP into the protocol is what a proxy design does, and the usual objection is that a proxy needs SSRF rules, redirect handling and size bounds.

**It needs no SSRF rules, because the product cannot express an origin.** There is nothing to smuggle. That holds only while the path and query cannot reconstitute one:

| Field | Rule |
| --- | --- |
| `backend` | non-empty, ≤64 bytes, `[a-z0-9-]`, no leading or trailing hyphen |
| `path` | absolute; no `//` prefix; no empty, `.` or `..` segments; no `?`, `#`, `\`, `%`, space, control or non-ASCII byte; ≤2048 bytes |
| `query` | ≤64 items, ≤4096 bytes total; names `[A-Za-z0-9_.-]`; values may hold any URL syntax, because the host encodes them |
| `body` | present only on `POST`/`PUT`/`PATCH`; `Json` must be UTF-8; ≤1 MiB |

`%` is banned rather than validated: `%2e%2e%2f` and `%2f` pass a check for the literal characters and become traversal once a URL parser normalizes them. Variable data belongs in the query.

Rules reject rather than normalize, so no normalizer has to stay in step across the boundary.

### What the host owns

The base URL, TLS, DNS, timeouts and the credential — plus four things the core cannot check:

1. **Set the path on the parsed base; never concatenate.** Refuse a base carrying a query or fragment: appended to `https://api.example.com/v1?key=abc`, a path lands inside the query. This is the one way a screened request can still reach somewhere unintended.
2. **Do not follow redirects.** Return the `3xx`.
3. **Cap the response** rather than truncating it.
4. **Return only the allowlisted headers.**

The core re-screens the response, so a host that forgets cannot reach a product through this call.

### The body carries its content type

`Json` and `Form` rather than bytes plus a content-type string. A free-form content type is a header the product writes; bytes with no content type is a header each host guesses differently — `fetch` labels a string body `text/plain`, the native clients label nothing, and a backend expecting JSON refuses two of three. Pinning the type to the variant is what makes one call behave the same everywhere.

### What comes back

Status, body, and a fixed allowlist: `content-type`, `retry-after`, `link`, and the `x-ratelimit-*` trio. Enough to parse the answer and to honour a backend asking the caller to slow down.

Everything else is dropped, so what a backend could achieve with a header is not a question that needs answering. `set-cookie` would be ambient authority in the product's realm; `location` would name the origin the tunnel keeps to itself.

### The calling product

The host forwards the connection's product id as `X-Polkadot-Product`, overwriting any header of that name, so a backend can meter or refuse per product. It comes from the connection the host opened, not from anything the product sent. It is host-attested, not cryptographic: a modified host can claim any product id.

## Trade-offs

- **Any product the host runs can call any backend in its registry.** There is no consent prompt and no per-product allowlist in the core. What bounds it is that the registry is first-party — the host ships it, so which services are reachable at all is the host vendor's decision. Beyond that it is the backend's job: **a backend registered on a host that runs more than one product must authorize on the forwarded product id**, and should rate-limit on it, since nothing in the core stops a product from looping.
- A registry entry can pin the product ids it serves. That is host configuration at no protocol cost, and it is the difference between the paragraph above being policy and being hope. Hosts should ship it from the start.
- **"Registers none" does not read the same on every host.** A host with no tunnel answers `Unsupported`; a native host installs one per execution, so it answers `UnknownBackend` instead. Both mean the same thing to a product, but only one of them is the capability gap it looks like.
- **Browser-based hosts cannot hold a credential secretly** — anything dotli or the web host ships is readable in devtools, which is this RFC's opening argument one layer up. They register no backends and answer `Unsupported`.
- **Outbound HTTP now exists in the protocol**, which [RFC-0002](0002-permission-model.md) assigned to the sandbox. The screening rules pay for that, and the scope is narrow: one method, no streaming, no multipart, no cookies, 1 MiB each way.
- **No `Link`-header pagination and no auth challenges are reachable.** Both follow from the header allowlist.
- **On a browser host every host-side failure collapses to one variant**, since a JS host can only reject with a string. Native hosts and the CLI return them typed.
- **Adding a backend needs a host release.** That is the cost of the registry being the trust boundary. `Backend::list` is what keeps that from being invisible to a product shipped against an id the host in front of it does not serve.
- **Rejected: a caller identity the host attaches to the product's own request.** It answers "which user" when the deployer asks "which host", it needs the host to intercept an outbound request — which Android's `shouldInterceptRequest` cannot do for a body and dotli cannot do at all — and it leaves the product's own network stack carrying the call, with CORS and interception differing per platform.
- **Rejected: a core-side rate limit.** The backend holds the quota and is the only party that knows its own limits.

## Open questions

1. **Is the response-header allowlist the right set?** It is the smallest one that lets a product parse an answer and back off, but widening it later is a wire change.
2. **How is a registry provisioned and rotated across hosts?** Today each host ships its own, so a credential rotation is a release per host.
3. **Should the base-URL join be a shared helper rather than prose?** "Set the path on the parsed base, refuse a base carrying a query" is an obligation every host reimplements and the core cannot check. A `truapi_platform` function would make it mechanical.
4. **Should pinning allowed product ids be protocol rather than host configuration?** Protocol would let the core enforce it; host-side keeps the core free of a policy it cannot verify.
