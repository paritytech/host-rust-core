---
"@parity/truapi": minor
---

`hasTrustedRemotePermissions(productId)` answers whether a product is one the host grants every
`RemotePermission` without prompting. It reads the compiled-in list alone: a stored user decision wins over
that list, so a host mediating product network access in its own code — a webview interceptor, a `fetch` shim,
a service worker — asks it only for the branch where its own store reads undetermined, and a host holding a
runtime asks `permissionAuthorizationStatus` instead, which folds both together. Exported on the UniFFI and
wasm surfaces.
