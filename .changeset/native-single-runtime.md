---
"@parity/truapi-host": patch
---

Native hosts run the whole core on one process-wide tokio runtime. Subscriptions and background loops spawned by the core and the localhost WebSocket bridge's connections share its workers, so a bridged product's request and the subscriptions it opens run on the same executor.
