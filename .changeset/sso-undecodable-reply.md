---
"@parity/truapi-host": patch
---

An SSO request waiting on the paired signing host fails on an undecodable message only when that message is its own reply. The host reads the `responding_to` id ahead of the payload, so a reply whose payload does not decode fails its request at once with the decode error, while an undecodable message answering another request is skipped. Stale replies left on the session channel, such as an AutoSigning allocation without `ring_vrf_domain_entropy`, no longer fail later backups, identity publishing or `getProductAccount` calls. The idle peer-disconnect monitor skips undecodable messages the same way.
