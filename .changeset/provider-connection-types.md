---
"@parity/truapi-provider": patch
---

`ChainProviderBuilder.setConnectionTypes(types)` limits the kinds of connection the light client opens to peers.
`ConnectionTypes` has `secureWebSocket`, `localWebSocket` and `remoteWebSocket`, all `true` by default; a page served
over `https` can turn `remoteWebSocket` off, since the browser blocks plain `ws://` to non-localhost peers there as mixed
content.
