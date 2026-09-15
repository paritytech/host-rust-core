---
"@parity/truapi": minor
"@parity/truapi-host": minor
---

Add `localStorage.subscribe` and worker pending operations.

`localStorage.subscribe(key)` streams a key's value within the product's own namespace, emitting the current
value immediately and then one item per later write or clear from any of the product's runtimes. A write that
leaves the stored bytes unchanged emits nothing.

`worker.beginOperation` / `worker.endOperation` keep a product's worker runtime alive while it holds at least
one open operation. Both are gated to the Worker execution kind. `endOperation` is idempotent. An open
operation counts as demand on the product's worker, so it reaches a host through the same worker-demand
signal an on-screen surface produces.

Hosts implement `ProductOperations` and `ProductStorage.subscribeStorage` to back these.
