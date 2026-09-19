---
"@parity/truapi-host": patch
---

Product executions under one host runtime share a single localhost WebSocket listener, each with its own token. Closing a
connection disposes the runtime that served it, so its host-core subscriptions and chat state are released rather than
held for the life of the listener. Admitted connections are bounded per execution and listener-wide, with the
per-execution cap a share of the listener-wide one; handshakes in flight are bounded separately, and a full backlog
evicts its oldest entry so a stalled peer cannot lock out other executions.
