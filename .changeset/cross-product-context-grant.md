---
"@parity/truapi": minor
"@parity/truapi-host": minor
---

Make the `context` scope effective. A `trustedProducts` grant of `context` now
admits a cross-product ring-VRF proof or signature against the granting
product's key, where before the runtime admitted the caller and the authority
holding the keys refused it again with the same error a product granting nothing
would produce. Each authority resolves the grant from the owner's published
manifest itself rather than accepting a verdict relayed by the caller, because on
a paired host the calling product id arrives over the wire as a self-asserted
field.

The authority derives the key from the identity it authorised rather than the
spelling it was handed, so authorisation and derivation cannot diverge. A granted
call is held to the caller's own proof context: the contextual alias is a
function of the owner's key and the context, so an unconstrained context would
let a grantee produce the alias the owner presents to a third product that
granted nothing and cannot consent.

The identity read `context` names is covered by the grant rather than prompted
for again. The contextual alias and the ring-VRF proof come out of one VRF
evaluation, so a grantee that may `create_account_proof` already holds the alias
that proof attests; `get_account_alias` accepting the same grant makes the two
calls agree about what the scope means. A product without a grant still takes
the prompt.

A stored account-access refusal still overrides a grant, and is now recorded
against the product on both sides rather than one spelling of it, matching the
granularity a manifest grant uses: a refusal for `peopl.dot` also covers
`app.peopl.dot`. Decisions written by earlier releases under the full product id
are still honoured, so upgrading does not discard a refusal a user has already
given.

`create_account_proof` with a foreign key handle and no active session now
answers `Rejected` where it previously answered `NotAllowlisted`. The session is
consulted before the grant so that the pair of refusals cannot be used to probe
which product granted which; a product branching on the old tag for that case
sees a different one.

Product identifiers are rejected when they carry no name: an empty label, control
characters, invisible bidirectional or zero-width formatting, whitespace, or path
separators. Each of these reached the grant key, the manifest cache key, the
account-access prompt and the logs. Internationalised names are unaffected.

A granted cross-product access is logged. It raises no prompt and writes no
stored decision, so previously only the refusal was audible: a publisher's grant
could let one product act with another's keys leaving no trace on the device.
This does not make the access revocable, which needs a surface for the user to
record a decision about a pair they were never asked about.

Resolving a grant can require reading a product manifest from dotNS, so the
lookup is bounded by the caller's timeout and cancellation rather than running
outside both. A manifest is cached under the label it resolves by, so every
executable of one product shares one entry, and an entry stamped in the future is
re-read rather than treated as fresh forever. Entries written by earlier releases
under the full product id are no longer read and nothing evicts them, so they sit
in core storage until the cache is cleared.
