---
"@parity/truapi-provider": minor
---

A light-client connection holds the requests it is sent until smoldot first reports the chain as synced, then forwards
them in the order they arrived, so every request is answered by a chain that has caught up. `chainSpec_v1_*` queries,
`statement_*` and `bitswap_*` calls, and the `lifecycle_unstable_*` subscription, which reports the sync itself, are forwarded straight
away. Held requests count against the 1024-frame budget of a connection, so a chain that never syncs refuses further
requests with "light client response queue full".

`provider.lifecycle(genesisHash)` watches the sync progress of a chain something is connected to. Each `next()` on the
returned watch resolves with a `ChainLifecycle`: the phase (`connecting`, `syncing` with `at` and `target`, or `ready`),
the connected peer count, and the health (`ok`, or `stalled` for `noPeers` or `noProgress`). The first call resolves
with the current state, later ones with each change, and `undefined` after `close()` or once nothing holds the chain.
