---
"@parity/truapi": minor
"@parity/truapi-host": minor
---

Add `localStorage.subscribe` and worker pending operations (RFC 0027).

`localStorage.subscribe(key)` streams a key's value within the product's own namespace, emitting the current
value immediately and then one item per later write or clear from any of the product's runtimes. A write that
leaves the stored bytes unchanged emits nothing.

`worker.beginOperation` / `worker.endOperation` keep a product's worker runtime alive while it holds at least
one open operation. Both are gated to the Worker execution kind. `endOperation` is idempotent.

Hosts implement `ProductOperations` and `ProductStorage.subscribeStorage` to back these.
