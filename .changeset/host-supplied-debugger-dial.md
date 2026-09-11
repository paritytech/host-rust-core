---
"@parity/truapi-host": minor
---

Take the wire debugger's dial from the embedding host instead of `localStorage`.

`createWebWorkerPairingHostRuntime` accepts a `debugger` option, and a dev build publishes
`__truapi.debugger.attach(url)` / `.detach()` / `.status()` to repoint a running session without a reload. A build may
still carry a default in `VITE_TRUAPI_DEBUGGER_URL`; the host's own value wins, and `null` or `""` refuses the dial
outright.

**Breaking for anyone enabling the debugger today:** the `truapi:debugger` `localStorage` key is no longer read, and
setting it has no effect. Pass the option, or call `__truapi.debugger.attach()`.
