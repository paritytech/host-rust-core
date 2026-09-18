---
"@parity/truapi": minor
"@parity/truapi-host": minor
---

A `context` grant admits the grantee acting in the granting product's own proof
context as well as in its own. The contextual alias is a function of the owner's
key and the context, so a third product's context stays refused: that product
granted nothing and cannot consent. The owner's context is not that case, and it
is the one a chain-wide proof context resolves to —
`PeopleLite.set_alias_account` verifies against `Score.score_context`, which
names the personhood product for every prover, so admitting only the grantee's
own context admits no proof such a chain accepts. Both the ring-VRF proof and the
contextual alias read follow the same rule, because they come out of one VRF
evaluation.
