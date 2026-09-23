---
"@parity/truapi": minor
"@parity/truapi-host": minor
---

The `Permissions` host callbacks name the product that asked: `devicePermission(product, request)` and
`remotePermission(product, request)` take the requesting `ProductContext` first, like the other product-scoped
callbacks. A host can key an `AllowOnce` grant it enforces natively (for example a camera or microphone gate) by
`productId` and `executionKind`, and title the prompt with the product.

The `truapi-host` CLI names the requesting product in its permission approvals.
