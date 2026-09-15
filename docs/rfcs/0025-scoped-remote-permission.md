---
title: "Credential-endpoint remote permission"
owner: "@BigTava"
authors: ["@BigTava", "@filvecchiato"]
status: draft
---

# RFC-0025 — Credential-endpoint remote permission

## Summary

`RemotePermission` ([RFC-0002](0002-permission-model.md)) gains a `Credential { domain, path, method }` variant, granting a product outbound access to one endpoint instead of a whole domain. For every request the grant covers, the host attaches a caller identity it derives from the user's wallet, scoped to that product and that endpoint.

## Motivation

A product cannot hold a server-side API key. It runs on the user's device, so anything it holds is readable there — [Meld](https://docs.meld.io/docs/meld-api/getting-started) says so directly: "Always call Meld from your backend. Direct calls from a browser or mobile app expose your API key."

So the deployer runs a backend that holds the credential, and the product calls it for a derived token. `Remote` already permits that call and is the wrong shape for it twice over. It is domain-wide, so a user approving "access to onramp.example.com" cannot tell one payment session from every other endpoint the deployer runs. And it carries no caller identity, so the backend has nothing to meter and must either trust every caller equally or build accounts.

What a grant has to give the deployer:

1. The credential never reaches the product — only a derived token does.
2. The user can tell what they approved: one operation, not a set.
3. A backend can meter one caller, across sessions, without accounts.
4. A backend can refuse other products.
5. Nothing depends on the host platform, and nothing depends on a chain.

## Approach

The grant names one `(domain, path, method)` triple. A second triple is a second prompt. `https` only, no wildcards, and no port or userinfo — the grant is keyed by domain, so accepting those would let a grant for one origin cover a service on another.

The grant and the request it covers are named by different parties: the product asks for a triple, the host later parses a live URL. Both are canonicalised the same way, and **the prompt names the canonical form**, so the endpoint the user sees is the endpoint that gets granted. A path like `/session/../../admin` resolves to `/admin` before the user is asked about it.

`Credential` is appended to the enum rather than folded into `Remote`, because the enum is encoded into the persisted permission key and amending it would re-key every decision a user has already made, which [RFC-0002](0002-permission-model.md) requires to persist. A grant occupies one slot: none of `Remote`'s domain-bundle machinery applies, and a `Remote` grant over a domain never becomes a `Credential` grant on its endpoints.

A request is refused without a prompt when it could never yield an identity — no session ([RFC-0009](0009-unauthenticated-product-access.md)), or a triple naming something no request can match. A product a host already trusts holds `Credential` without a prompt, as it holds every other remote permission.

### The identity

Each covered request carries `X-Polkadot-Key`, `-Signature`, `-Timestamp` and `-Nonce`. The key is sr25519, derived by the host from the user's root entropy and scoped to the wallet, the product and the endpoint — stable for one caller on one endpoint across sessions, and unrelated across endpoints and products. The signature covers the method, domain, path, query, timestamp, nonce and body, so it cannot be lifted onto a different request.

Two properties carry the design and are worth stating plainly:

- **The derivation is out of the product's reach.** It hangs off a namespace that `host_derive_entropy` ([RFC-0007](0007-derive-entropy.md)) cannot address. If a product could derive its own credential key it could sign covered requests with no grant at all, and the permission would mean nothing.
- **The host attaches the identity, never the product.** Hosts strip caller-supplied `X-Polkadot-*` headers before attaching their own, and emit one encoding across platforms so a backend sees the same caller whichever host the request came from.

A backend verifies the signature against the key in the header and meters on that key, never on any other field. It needs an sr25519 implementation and nothing else.

The grant is the consent: it authorises these signatures without a per-call dialog, which would be unusable. A request to an endpoint with no grant is refused rather than prompted, since an HTTP request cannot raise one.

## Trade-offs

- **The identity is per wallet, not per person.** One person with several wallets is several callers, so this meters use rather than resisting Sybil attack.
- **A ring VRF personhood proof** ([RFC-0004](0004-ringlocation-redesign.md)) would give one-per-person, and was the original shape of this RFC. It costs a People chain read per grant and per request, a ring revision to cache, a verifier library in every backend, and it refuses non-members. It is also worse where this is most needed: the signing host is native-only, so Desktop and web would need a round trip to a paired phone per request, where entropy derivation is local on both sides. Worth revisiting for an endpoint that genuinely needs one-per-person.
- **More prompts for chatty products.** `Remote` remains for one broad grant.
- **No revocation.** [RFC-0002](0002-permission-model.md) defines none, so a grant persists until cleared in host settings.
- **Product-binding is host-attested.** A modified host can sign under any product id. Wallet-binding is cryptographic: the key comes from root entropy a host cannot invent.
- **Rejected: a `secrets.request` method proxying the call through the host.** It moves outbound HTTP into the protocol, which [RFC-0002](0002-permission-model.md) assigned to the sandbox, and then needs SSRF rules, redirect handling and size bounds to contain what that creates. On the web host CORS still applies, so the same call behaves differently per platform.
- **Rejected: letting the product attach its own identity.** It can already derive a key and sign with it. What it cannot do is tell the user, at grant time, which endpoint receives that identity — and a key the product holds is a key it can hand to anyone.
- **Rejected: path prefixes in the grant.** Fewer prompts, but a prompt naming a prefix asks the user to reason about a set, which is what domain grants already do badly.

## Open questions

1. **Two hosts cannot implement this as specified.** Android's `shouldInterceptRequest` hands over a read-only request that never exposes the body, so it can neither sign a POST correctly nor attach a header; dotli has no outbound interception at all. Each needs its own design. Desktop and iOS are unblocked.
2. **Should a grant expire?** With no revocation, a credential grant authorises signing indefinitely once given.
