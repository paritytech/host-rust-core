---
"@parity/truapi": minor
---

`RemotePermission` gains a `Credential { domain, path, method }` variant, granting outbound access to one endpoint
rather than a whole domain. Requests the grant covers carry an sr25519 identity the host derives per wallet, product
and endpoint, so a backend holding an API key can meter callers without accounts. Hosts obtain the headers through
`credentialRequestHeaders`, on both the wasm surface and `NativeProductExecution`, and drop a product's own
identity headers using `isReservedCredentialHeader`.
