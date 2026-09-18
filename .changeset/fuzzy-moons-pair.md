---
"@parity/truapi-host": patch
---

A pairing attempt is bounded. Reading the stored pairing identity, connecting to the statement store, subscribing to the pairing topic and waiting for the wallet's handshake are each raced against a single 300s deadline, beside the cancellation they already honoured. Resolving the session and persisting it carry their own budgets and are not covered by it.

A peer answering on a different SSO envelope publishes statements this host cannot open, which is indistinguishable from a peer that has not answered yet: both are silence on the topic. The attempt now ends with a reason naming that as the likely cause.
