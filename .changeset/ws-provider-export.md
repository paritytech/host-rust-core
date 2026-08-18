---
"@parity/truapi": minor
---

Add `createWebSocketProvider(url)` for hosts that serve protocol frames over a
WebSocket, and `connectWebSocketHost(url)` on the sandbox path so a plain
browser tab using such a host is detected as hosted and shares the cached
client. Both native host READMEs already pointed products at
`createWebSocketProvider`, which until now did not exist, so every browser
product had to hand-write the bridge. `truapi-host signing-host --frame-listen`
is now reachable from an ordinary tab, and the CLI's own TCP provider delegates
to the shared implementation.
