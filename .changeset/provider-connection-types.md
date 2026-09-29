---
"@parity/truapi-provider": patch
---

`ChainProviderBuilder.setConnectionTypes({ secure, localhost, unsecure })` limits the kinds of connection the light
client opens to peers: `wss://`, plain `ws://` to localhost, and plain `ws://` to any other peer. Each defaults to
`true`; a page served over `https` can pass `{ unsecure: false }`, since the browser blocks those dials there as mixed
content.
