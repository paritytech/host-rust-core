---
"@parity/truapi": minor
"@parity/truapi-host": minor
---

Address every frame with a two-byte `(trait, method)` wire discriminant. The
trait byte names the API trait and the method byte addresses a method within
it, so each trait owns a full 256-slot method space and method ids restart at
0 in every trait.

A third envelope byte, `message_type`, names which leg of a method's exchange
a frame carries, so a method costs one id whatever its shape. The payload is
the plain SCALE encoding of that leg's type and carries its own version.

`TrUApiTransport.codecVersion`, `CreateTransportOptions.codecVersion` and
`GeneratedClientTransport` are removed. Generated handshake calls read
`TRUAPI_CODEC_VERSION` directly, so there is no longer a way to advertise a
codec version that differs from the one the envelope is actually framed in.
`CreateTransportOptions` itself remains, carrying `requestTimeoutMs` alone,
and `createClient` takes a `TrUApiTransport` (every value that satisfied
`GeneratedClientTransport` satisfies it unchanged).

This is wire codec version 2. A codec version 1 peer cannot exchange frames
with a codec version 2 peer in either direction: the handshake itself rides
the changed envelope, so the mismatch cannot be negotiated in band. Hosts and
products must move together.
