---
"@parity/truapi": patch
---

A visible page retries a failed host reconnect after 250 ms, 1 s and 4 s before it waits for its next call. A page that returns to the foreground while the host is still rebinding its listener reconnects on its own instead of staying offline until the product calls again.
