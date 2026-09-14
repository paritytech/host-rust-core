---
"@parity/truapi-host": minor
---

The core counts references on each product's worker and tells the host when that count crosses zero, so a worker runs
only while something needs it.

`acquireWorker(productId)` takes one reference for a modality holder that is on screen or in flight, and
`releaseWorker(productId)` gives it back; releasing with none held is a no-op. The first reference and the last release
are the only ones that report anything. `subscribeWorkerDemand(listener)` is where that report arrives: the listener
receives every product wanted right now, then each change as it happens, and `wanted: false` for everything still wanted
when the runtime is disposed. Starting and stopping the worker executable stays with the host, and a `wanted: false` is
permission to stop rather than an order, so a host may keep one warm. The core keeps no clock and runs no timers.
