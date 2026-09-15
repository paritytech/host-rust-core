---
"@parity/truapi": major
---

Subscription interrupts carry a versioned error envelope. The nine subscriptions that reported a
bare `GenericError` now resolve a per-method wrapper whose V1 is that same payload, so an interrupt
frame is one byte longer and its domain error downgrades to the version the caller subscribed in.
