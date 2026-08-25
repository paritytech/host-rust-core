# MUST, must, or should

Uppercase keywords are a contract with implementers, and their meanings are fixed by [IETF RFC 2119](https://datatracker.ietf.org/doc/html/rfc2119):

- **MUST, MUST NOT, SHALL, SHALL NOT, REQUIRED** — absolute; an implementation that ignores it is wrong. Reserve these for what interoperability and security actually require.
- **SHOULD, SHOULD NOT, RECOMMENDED, NOT RECOMMENDED** — there are limited valid circumstances for ignoring it, and the RFC should name them.
- **MAY, OPTIONAL** — genuinely free, and implementations that choose differently still interoperate.

Uppercase is rare in the corpus and that is the house style: 7 of the 16 numbered RFCs in `docs/rfcs/` use any uppercase keyword (measured 2026-08-14). An RFC that sprinkles MUST over every paragraph has told an implementer nothing about which sentences are the load-bearing ones.

## Where they belong

In `## Detailed Design`, in the sentences that bind an implementation, next to the type or method they constrain:

> The host must preserve delivery order: all `isComplete = false` pages precede the first `isComplete = true` page; no `isComplete = false` page may be emitted afterwards.
> — `docs/rfcs/0008-statement-store.md`, immediately below the struct it governs

That one is written lowercase, which is the corpus norm and fine — placement is doing the work. Reach for the uppercase form when an implementation that disagrees would break interoperability or security, and the sentence needs to be unmistakable.

Not in `Summary`, `Motivation`, `Drawbacks`, `Alternatives`, `Non-goals`, or `Unresolved Questions`. Those sections describe and argue. A requirement stated only there is one an implementer will never find; a requirement stated in both places drifts out of sync the first time the design changes. The gate warns on an uppercase keyword in any of them.

## Choosing the strength

Ask what happens when an implementation ignores it:

- two implementations stop interoperating, or a security property breaks → **MUST**;
- the system still works but a product gets a worse outcome → **SHOULD**, plus the circumstances that justify the exception;
- both choices interoperate → **MAY**, or drop the keyword and describe the freedom in prose.

Every MUST owes a failure mode: what the host does when a caller violates it, and which error variant it returns. A MUST with no defined violation behaviour is an assertion, and the implementer will invent one.

## Lowercase is fine

Ordinary modal verbs in explanation carry no contract: "a product must already hold a genesis hash to make a chain call" describes today rather than legislating tomorrow. Keeping the uppercase form for the sentences an implementer will be held to is what makes those sentences findable.
