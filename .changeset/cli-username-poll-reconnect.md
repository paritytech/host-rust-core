---
"@parity/truapi": patch
---

The CLI host's username registration reconnects to Asset Hub after a dropped socket instead of failing every remaining poll on the dead connection, so one connection reset during provisioning no longer costs the whole attestation.
