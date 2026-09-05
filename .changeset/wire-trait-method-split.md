---
"@parity/truapi": minor
"@parity/truapi-host": minor
---

Address every frame with a two-byte `(trait, method)` wire discriminant. The
trait byte names the API trait and the method byte addresses a method within
it, so each trait owns a full 256-slot method space and method ids restart at
0 in every trait.

This is wire codec version 2. A codec version 1 peer cannot exchange frames
with a codec version 2 peer in either direction: the handshake itself rides
the changed envelope, so the mismatch cannot be negotiated in band. Hosts and
products must move together.
