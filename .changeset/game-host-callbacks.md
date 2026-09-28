---
"@parity/truapi-host": minor
---

Serve the `game` service from the host runtime. A host supplies the optional `game` callbacks,
`scheduleGameReminder` and `cancelGameReminder`, to hold the calling product's next-game reminder; a host that supplies
none answers both `Unsupported`.
