# Is the draft ready to hand back

Run the gate first — it settles shape, and nothing below is worth doing while `## Detailed Design` is missing or template text is still in the file. What remains is judgement, and it is the part a reviewer will actually spend their attention on.

Read the draft once as each of these three readers.

## The implementer

They have the codebase open and want to start. For every new name in the RFC, can they say what its type is, where it is defined, and what it returns on failure? Walk one request end to end: product calls X, host does Y, response carries Z, and on a missing key the caller sees error E. If any hop needs a guess, the RFC is not done.

Specific things they will trip on:

- a type described in prose but never written out;
- an error variant named in one section and absent from the signature;
- ordering left implicit between two async operations;
- "the host handles this" with no statement of how a product observes the result;
- a version skew case — old product, new host, and the reverse — that the RFC never addresses.

## The sceptic

They think the change may be unnecessary. Does `## Motivation` name a failure that has actually happened or will demonstrably happen, rather than an aesthetic preference? Is the cheapest alternative — do nothing, fix it in the product, extend an existing method — considered in `## Alternatives` and rejected with a reason? Are the drawbacks the real ones, or a list picked because it is easy to dismiss?

An RFC that survives this reader states one cost it cannot argue away, and says why the change is still worth it.

## The maintainer

They will live with it. Is the new surface consistent with the surrounding API — naming, error shape, request/response symmetry, how existing methods carry a context? Does it add a second way to do something the API already does? What happens to it when the adjacent RFC in flight lands? If a migration is needed, does the RFC say who does what, and can old and new coexist while the rollout happens?

## Before handing it back

- Every claim traces to code you read, the author's words, or an explicit `## Unresolved Questions` entry — nothing plausible-but-invented.
- `owner` is the actual author.
- The `_index.md` row exists and links to the file.
- Uppercase RFC 2119 keywords appear only in `## Detailed Design`, and each one has a stated failure mode.
- Every section earns its place; the ones with nothing to say are gone rather than padded.
- Length matches the change.

Then say what you are unsure about. A draft handed back with "the Alternatives section is thin because you did not mention what you rejected — tell me and I will fill it" is more useful than one handed back silently complete.
