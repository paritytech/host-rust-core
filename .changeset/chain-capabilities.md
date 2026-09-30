---
"@parity/truapi": patch
---

The core has shared chain capabilities for host services: `ChainHeads` (finalized and best heads, head events), `BlockBackend` (block hash by number, block number, extrinsic hashes, dispatch outcome), `TxValidator` and `TxSubmitter`, with one `SubxtChain` implementation. Block reads go through a subxt client on the legacy JSON-RPC methods, so they reach blocks a chainHead follow no longer pins. Validation and submission go through the existing chainHead client. Both clients on a connection share one chain config, so runtime metadata is downloaded once per spec version.
