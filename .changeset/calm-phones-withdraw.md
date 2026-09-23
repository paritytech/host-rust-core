---
"@parity/truapi-host": minor
---

SSO request cancellation. A pairing host whose caller withdraws a request it has published sends a `Cancel` naming it, when that request is still the newest one on the session; a host timeout sends nothing. The core's signing-host responder reads `Cancel` while it is still serving earlier requests: a running request stops at its confirmation prompt or before its next allocation step and posts no response, and one not yet started never runs. `Cancel` is appended to the SSO catalog at the next index, so a peer that predates it logs the message and serves the request as before.
