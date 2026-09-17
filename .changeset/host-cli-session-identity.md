---
"@parity/truapi": patch
---

`truapi-host` keeps one base path on one signer identity. A `--session` name survives promotion and
keeps selecting the session it created, a lost or stale `current-session` pointer resolves against
the provisioned sessions instead of provisioning beside them, and `--serve` reports a missing signer
and announces the minutes-long first registration instead of staying silent.
