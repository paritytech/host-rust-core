---
"@parity/truapi": minor
---

Keep the same client after a native host connection is interrupted. The shared SDK
transport replaces its WebSocket, while pending
calls and subscriptions fail with `ConnectionResetError` without replay.
Providers can recreate their read/watch subscriptions after reconnection.
Older SDKs still start through the MessagePort but need a page reload after
connection loss.

Browser permission checks use generated internal SDK calls. Hosts protect their
shared authorization dependencies before product code runs; public SDK methods
remain replaceable, but products cannot patch the protected built-in prototypes.

SCALE boolean decoding rejects values other than 0 and 1.
