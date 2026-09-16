---
"@parity/truapi": minor
---

`hasTrustedRemotePermissions(productId)` answers whether a product is one the host grants every
`RemotePermission` without prompting. A host that mediates product network access in its own code — a webview
interceptor, a `fetch` shim, a service worker — asks this before prompting, so a first-party product is not
stopped by the host for access the core would have granted. Exported on both the UniFFI and wasm surfaces.
