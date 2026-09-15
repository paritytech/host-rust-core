---
"@parity/truapi": major
---

Remove the hard-coded well-known chain constants (`PASEO_NEXT_V2_ASSET_HUB`, `PASEO_NEXT_V2_INDIVIDUALITY`,
`PREVIEWNET_ASSET_HUB`, `PREVIEWNET_INDIVIDUALITY`) and the `WellKnownChain` type. Products resolve genesis hashes
through `chain.getChainInfo` (RFC 0026), which answers from the host's own configuration and therefore survives a
testnet wipe or an environment move without a new product bundle. It also covers Bulletin and Relay, which the constants
never did.

Replace `SOME_CHAIN.genesis` with the `genesisHash` from the matching role:

```ts
const assetHub = await truapi.chain.getChainInfo({ chain: "AssetHub" });
if (assetHub.isErr()) return;
const genesisHash = assetHub.value.genesisHash;
```

Genesis hashes are now only available asynchronously from a connected host, so code that needed one at module load has
to resolve it inside the call that uses it.
