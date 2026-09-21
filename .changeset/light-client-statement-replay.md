---
"@parity/truapi-provider": patch
---

The embedded light client answers `statement_subscribeStatement` the way a full node does: the
subscription id is followed immediately by a snapshot batch carrying `remaining: 0`, empty when
nothing matches, so a client that waits for the end of the replay before issuing its first query
resolves rather than hanging. Live notifications still omit `remaining`, keeping a snapshot
distinguishable from a gossiped statement.
