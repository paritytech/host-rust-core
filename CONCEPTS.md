# Concepts

Shared domain vocabulary for this project — entities, named processes, and status concepts with project-specific meaning. Seeded with core domain vocabulary, then accretes as ce-compound and ce-compound-refresh process learnings; direct edits are fine. Glossary only, not a spec or catch-all.

Seeded from the account-authority and statement-store area. Other areas of the system are not yet covered.

## Relationships

A Product Authority is fulfilled by exactly one role per connection — either a Pairing Host or a Signing Host — and a product cannot tell which from the calls it makes. Every Authority Call runs under a Call Context, which owns the Cancellation Token and the deadline that bound it. Writing to the Statement Store requires an Allowance, which the authority obtains on the product's behalf; on a Pairing Host that obtaining travels the SSO Channel, on a Signing Host it happens locally.

## Authority

### Authority Call
A request the product-facing runtime makes to the account authority on a product's behalf — fetching an account, allocating resources, obtaining allowance material, or signing a payload.

An Authority Call is bounded by its Call Context: when the deadline elapses or the token is cancelled, the caller raises the cancellation reason and then abandons the in-flight work rather than waiting for it. Abandoned work is dropped, never awaited to completion — the deadline is only real because the caller stops, not because the callee agrees to. Work already dispatched to a remote peer may still complete on the peer's side after the caller has walked away.

### Product Authority
The account-owning side of a product connection: the party that holds or reaches the account material a product asks for, and that answers Authority Calls. Distinct from the product itself, which never holds account material and can only ask.

Two roles fulfil it, and they differ in *where* the account material lives rather than in what the product may request.

### Pairing Host
A Product Authority whose account material lives with a remote, paired party. It answers an Authority Call by carrying a request over the SSO Channel and waiting for the remote side to approve and respond, so its calls can block on a human or on a network peer.

### Signing Host
A Product Authority whose account material is held locally. It answers an Authority Call directly — signing, or registering an Allowance on chain — without a remote approval round trip, so its calls block on chain progress rather than on a peer.

## Request context

### Call Context
The ambient per-request state threaded through a call: which request it belongs to, the Cancellation Token that can stop it, and the optional deadline it must finish within.

A Call Context is shared, not owned by any single call — clones observe the same cancellation. A context with no deadline is still cancellable; a context whose deadline has already elapsed cancels at the first opportunity rather than being treated as unbounded.

### Cancellation Token
The shared signal that a call should stop, carrying the reason it was stopped — an explicit cancellation, or an elapsed deadline.

Cancellation here is cooperative: the token records a reason and wakes whoever is watching, but work parked on something that never checks the token never learns of it. A token therefore requests termination and cannot guarantee it; a caller that needs a guarantee must stop waiting and drop the work itself. The reason is set once and stays readable afterwards, so latecomers can still learn why a call ended.

## Statements and allowances

### Statement Store
The shared store a product submits statements to and subscribes to by topic. It is the transport underneath cross-party exchanges as well as a destination in its own right — an SSO conversation is carried as statements in this store rather than over a private channel.

### Allowance
The permission material that lets a product write to a store, obtained through the Product Authority rather than held by the product.

Allowances are scoped to a time period and occupy a limited number of slots within it, so obtaining one is a claim against a contended resource, not a local computation: a slot is scanned for, claimed, and registered on chain. Because a period can be full, taking a slot may revoke another holder's — which makes duplicate or abandoned registration attempts costly rather than merely wasteful.

## Single sign-on

### SSO Channel
The request-and-response conversation between a host and its remote paired party, carried as statements through the Statement Store rather than a direct connection.

Each request carries an opaque message id that its response must match, so a response to a request the host has already abandoned is ignored rather than mismatched onto a later one. Both sides' statement streams are subscribed for the life of a request and released when it ends.
