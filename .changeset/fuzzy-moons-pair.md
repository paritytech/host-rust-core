---
"@parity/truapi-host": patch
---

A pairing attempt is bounded. The flow parks on three awaits — connecting to the statement store, subscribing to the pairing topic, and waiting for the wallet's handshake — and each is raced against a single 300s deadline for the attempt as a whole, beside the cancellation it already honoured.

A peer answering on a different SSO envelope publishes statements this host cannot open, which is indistinguishable from a peer that has not answered yet: both are silence on the topic. The attempt now ends with a reason naming that as the likely cause.
