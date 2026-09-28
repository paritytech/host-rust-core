---
"@parity/truapi-host": patch
"@parity/truapi-provider": patch
---

Follow previewnet through its 2026-09 wipe. Every previewnet chain (relay, Asset Hub, People, Bulletin) reports a new genesis hash; the host resolves chains by genesis, so `truapi-host dev --network previewnet` declined every People, Asset Hub and Bulletin request from a product asking for the live hash (`ChainNotSupportedError` / `host-declined-chain`), and the bundled smoldot specs described chains that no longer exist. The CLI preset, its SPEC.md table, the provider catalog and the bundled specs (including a fresh relay checkpoint) now match the live chains.
