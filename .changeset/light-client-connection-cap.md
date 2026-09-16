---
"@parity/truapi-provider": minor
---

The embedded light client holds at most 32 connections at once. A `connect` past that is refused with "the light client
already holds 32 connections" instead of adding another chain, request queue, response stream and frame channel that
nothing will release. Closing a connection hands its slot back.

The ceiling is a backstop against connections a consumer never closes, not a budget to spend: the bundled catalog
resolves eight chains, so one reused connection per chain stays well under it.
