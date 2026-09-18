---
"@parity/truapi": minor
---

`truapi-host` streams product frames to a wire debugger behind `--debugger <ws-url>`
(or `TRUAPI_DEBUGGER_URL`).

The switch is resolved by the commands that serve frames — `pairing-host`, `dev` and
`signing-host` — before their frame listener binds, so a non-loopback URL fails startup
rather than at first dial. Each of those commands reports the outcome once as a
lifecycle event, naming the endpoint and the switch that supplied it, or saying the
debugger is off. Each accepted connection gets its own channel id, `<product-id>#<n>`,
so concurrent peers under one host do not share a trace key.
