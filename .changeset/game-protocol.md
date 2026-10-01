---
"@parity/truapi": minor
---

Add the `game` service: `remindNextGame` holds one reminder for the calling product's next game, and `cancelNextGame`
drops it. Only the game product, `dim2`, is served; any other product gets `Unsupported`. A host that fails to hold
the reminder answers with a host failure carrying its reason. Add the `Alarm` device permission that gates it; denying
`Alarm` falls back to an ordinary notification when `Notifications` is granted. Add the optional `Calendar` device
permission that lets the host also add the game to the user's calendar.
TypeScript code that switches exhaustively over the device permission union needs `Alarm` and `Calendar` cases, and a
core built before this release answers either request with `MalformedFrame`.
