---
"@parity/truapi": minor
---

Export `PREVIEWNET_INDIVIDUALITY` and `PREVIEWNET_ASSET_HUB` well-known chains,
so a product on previewnet can pin the genesis hashes it signs `CheckGenesis`
over the same way a product on `paseo-next-v2` does. Pairs with the CLI gaining a
`previewnet` network preset.
