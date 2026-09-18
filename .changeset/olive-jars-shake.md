---
"@parity/truapi": minor
"@parity/truapi-debugger": patch
---

Request cancellation. Every generated request method takes `options?: CallOptions` last; aborting its `signal` sends a `Cancel` frame on that method's own address, correlated by the same `requestId`. The call still settles with exactly one response: a withdrawn call answers `CallError.Cancelled`, and a cancel that arrives too late is dropped so the real result stands. The client's own deadline sends `Cancel` before it rejects.

Additive on the wire. `CallError` gains `Cancelled` as its last variant, so every existing discriminant keeps its SCALE index, and `WIRE_CODEC_VERSION` is unchanged. A host that predates the `Cancel` leg drops the frame with no reply and the call settles on the client's deadline instead. A product cannot detect that first, so an abort such a host never understood is indistinguishable from one it honoured.
