---
"@parity/truapi": minor
"@parity/truapi-host": minor
---

The `Permissions` host callbacks name the product that asked: `devicePermission(product, request)` and
`remotePermission(product, request)` take the requesting `ProductContext` first, like the other product-scoped
callbacks, so a host can title the prompt with the product and key any grant it keeps itself by the product. Stored
decisions stay keyed by `productId` alone.

The `truapi-host` CLI names the requesting product in its permission approvals.
