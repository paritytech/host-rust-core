---
"@parity/truapi": minor
"@parity/truapi-host": minor
---

A `context` grant admits the grantee acting in the granting product's own proof
context as well as in its own. The granting product is matched by its full
identifier, so a grant on one network does not reach a namesake's context on
another.

The scope already gives a grantee the owner's keys. Refusing the owner's context
left it unusable: `PeopleLite.set_alias_account` verifies against
`Score.score_context`, which names the personhood product for every prover, so a
grantee held to its own context alone can produce no proof such a chain accepts.

What stays refused is a context naming a third product, and the `raw:`
development context. On a chain whose contexts are personhood-owned that is a
narrower protection than it sounds, because the owner's context is the pseudonym
the owner presents to every product in the score system. Both the ring-VRF proof
and the contextual alias read follow the same rule, because they come out of one
VRF evaluation.
