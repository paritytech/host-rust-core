---
"@parity/truapi-host": patch
---

An SSO request waiting on the paired signing host skips an undecodable message that answers another request. The host reads the `responding_to` id ahead of the payload, so a reply whose payload does not decode fails its own request at once with the decode error, and a stale reply left on the session channel, such as an AutoSigning allocation without `ring_vrf_domain_entropy`, is skipped, so later backups, identity publishing and `getProductAccount` calls complete. An undecodable `Cancel` is never read as a reply, an undecodable `Disconnected` still ends the session, and a message whose header does not decode fails the wait at once.
