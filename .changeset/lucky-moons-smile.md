---
"@parity/truapi-host": minor
---

The test host answers a product account's address from the fixture, derived
from the active session's root, so a suite can fund or assert on that account
without reading it out of the product's own UI. `productAccountAddress` works
the same address out with no host running, which is what a suite funding that
account once, in setup, reaches for.

The signing runtime serves the fixture through its existing asynchronous
`productSubtreePublicKey` method, matching the pairing runtime and retaining
the optional timeout argument.
