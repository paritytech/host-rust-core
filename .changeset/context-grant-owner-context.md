---
"@parity/truapi": minor
"@parity/truapi-host": minor
---

A `context` grant admits the grantee acting in the granting product's own proof
context as well as in its own. Both are matched by product label within one
network, so a product's other executables count and a namesake on another
network does not.

Refusing the granting product's context left the scope unusable:
`PeopleLite.set_alias_account` verifies against `Score.score_context`, which
names the personhood product for every prover, so a grantee held to its own
context alone can produce no proof such a chain accepts. A context naming a
third product is still refused, as is the `raw:` development context. A grantee's
own namesake on another network is refused too, which is new. Both the ring-VRF proof and the contextual alias
read follow the same rule, because they come out of one VRF evaluation.
