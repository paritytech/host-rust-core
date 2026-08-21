# Concepts

Shared domain vocabulary for this project — entities, named processes, and status concepts with project-specific meaning. Seeded with core domain vocabulary, then accretes as ce-compound and ce-compound-refresh process learnings; direct edits are fine. Glossary only, not a spec or catch-all.

## Host and Product

### Product
A web application that calls TrUAPI methods on the Host embedding it. A Product holds no keys and performs no signing itself; every privileged action is a request to its Host.

### Host
The native Polkadot application that embeds a Product, owns the keys and the user-facing prompts, and answers the Product's TrUAPI calls. Host and Product run in separate execution contexts and share no memory, so everything between them crosses a process boundary as bytes.

### Action
The wire-level unit a TrUAPI method expands into: a plain call becomes a request/response pair, a subscription becomes a start/stop/interrupt/receive lifecycle. Each action carries a discriminant id that is append-only and never reused, which is what lets a newer Host and an older Product still understand each other.

### Remote authority
A separately paired device or host that answers on the user's behalf when the embedding Host cannot answer locally — the signing side of an SSO pairing. A remote-authority answer is bounded by a deadline the Host sets, not by the Product; a Product that bounds such a call more tightly than the Host does is choosing to abandon an answer the Host is still willing to deliver.

## Request bounds

### Request timeout floor
The minimum bound a client applies to one specific method, overriding a shorter bound the embedding product configured, so a request is never abandoned while the Host is still permitted to answer it.

The effective bound for a request is the larger of the product's configured bound and the method's floor; a per-request override, when supplied, wins outright over both. When a bound fires, the client drops its correlation entry, so a reply that arrives afterwards is inert rather than late. Nothing is sent to the Host on expiry — requests have no cancel action, unlike subscriptions, which have a stop — so a timed-out call may still complete Host-side, and a caller retrying a call with side effects can cause it to happen twice.

### Prompt-backed request
A request whose answer waits on a person — a consent dialog, a pairing approval, a payment confirmation — rather than on computation or a chain. Such calls carry no Host-side deadline at all, so they are the slowest calls in the system and cannot be bounded by reasoning about Host deadlines. Its complement is a prompt-free request, which the Host answers without involving anyone.
