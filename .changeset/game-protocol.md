---
"@parity/truapi": minor
---

Add the `game` service: `remindNextGame` holds one reminder for the calling product's next game, and `cancelNextGame`
drops it. Add the `Alarm` device permission that gates it. TypeScript code that switches exhaustively over the device
permission union needs an `Alarm` case, and a core built before this release answers an `Alarm` request with
`MalformedFrame`.
