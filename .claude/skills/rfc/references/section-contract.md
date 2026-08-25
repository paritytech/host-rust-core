# What each section owes, and which ones to leave out

Counts are the 16 numbered non-template RFCs in `docs/rfcs/`, measured 2026-08-14. They describe what the corpus does; they are not a quota.

## Around the sections

Frontmatter is `title` and `owner`, both quoted strings. Optional keys attested in the corpus: `type: rfc`, `status`, `pr`, `breaking`. Six of sixteen files carry no frontmatter at all — that is drift, not licence; the template has it and the gate errors without it.

H1 is `# RFC NNNN — Title` (8/16) or `# RFC-NNNN: Title` (6/16). Either passes the gate; the em-dash form is the template's. The number must match the filename.

An optional metadata table under the H1 (`**RFC Number**`, `**Start Date**`, `**Description**`, `**Authors**`) appears in the newest RFC, `0026-supported-chains.md`. Use it or don't.

## The sections

| Section | Present | Owes |
| --- | --- | --- |
| `## Summary` | 16/16 | One paragraph: what changes and what it buys. A reader who stops here can still say what the RFC does. |
| `## Motivation` | 16/16 | The failure that exists today, named concretely — a wiped testnet invalidating baked-in hashes, a product paying two round trips, a user seeing a cost they never agreed to. Then the requirements a solution has to meet. Link the tracking issue. A Motivation with no concrete failure reads as a preference. |
| `## Detailed Design` | 10/16 | Enough for someone who knows the codebase to implement it without asking a question: exact types, signatures, request ids, error variants, ordering guarantees, and the file each definition lands in. Fenced blocks in the language of the surface being changed. Subsections are normal — `### API changes`, `### Data model changes`, `### Migration strategy`. |
| `## Drawbacks` | 14/16 | Real costs, in the author's own voice: "one more round trip", "hosts carry a second filter path", "breaking for every product". Strawmen here read as advocacy and cost you the reviewer's trust in the rest. |
| `## Alternatives` | 12/16 | Designs considered and what killed each. Include the strongest rejected option — its absence tells a reviewer the design space was never explored. |
| `## Unresolved Questions` | 8/16 | Forks the author cannot settle alone. Leave it out when there are none; do not manufacture doubt. |

Four files use `## Explanation`, `## Stakeholders`, and `## Prior Art and References` instead — the Polkadot Fellowship's section names, which an earlier version of this skill taught. Do not copy them.

Add a section when the material demands one, and the corpus has precedent: `## Non-goals` or `## Out of Scope` (2/16) when scope is contested, `## Definitions` (2/16) when the RFC introduces vocabulary, `## Security Considerations`, `## Testing`, or an appendix for a derivation. Two RFCs use `mermaid` diagrams for multi-party flows; a diagram is worth it when the ordering between three or more parties is the point.

## Interface changes state the interface

Every consequential RFC in the corpus carries the literal signature rather than a description of it — `0022-account-derivations.md` has 16 fenced blocks, `0017-coinage-payment.md` 12, `0008-statement-store.md` 5. Write the Rust for a trait method or SCALE type, the TypeScript for a codec or adapter interface, and put both when the change crosses the wire in both directions. Doc comments on the signature carry the semantics that prose would otherwise repeat.

## Omission over padding

A section you have nothing to say in is deleted, not filled. "N/A", "None at this time", and a restatement of the heading each cost a reviewer the same attention as real content and return none. The gate errors on a heading with neither prose nor subsections and on surviving template sentences; it warns when `Drawbacks`, `Alternatives`, or `Unresolved Questions` is absent, which is a prompt to justify the omission rather than to invent content.

`Summary`, `Motivation`, and `Detailed Design` are never omitted.
