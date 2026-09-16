---
"@parity/truapi": patch
---

The chat key a host publishes on chain is the X25519 key it actually holds, so a peer that looks up
that identity can encrypt to it. It was previously derived from an unrelated key tree, which left
chat unreachable for every identity a host registered. Identities registered before this carry an
unusable key and have to be re-registered.
