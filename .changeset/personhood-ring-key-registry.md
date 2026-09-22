---
"@parity/truapi": patch
---

Record the person's own personhood ring-VRF keys when a signing host activates a local session, so a product can borrow one to prove personhood. The registry only holds what was registered through the host and a product may only register under itself, so `listRingVrfKeys("peopl.<tld>")` came back empty on a wallet whose key is in the ring and every proof-authorized call died on a handle it could not find. Entries go under `peopl.<tld>` at derivation index 1 for people-lite and 0 for people, addressed by collection alone. Recording is best effort: a session that cannot record them still works for everything that does not prove personhood.
