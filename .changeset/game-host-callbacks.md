---
"@parity/truapi-host": minor
---

Serve the `game` service from the host runtime. A host supplies the optional `game` callbacks,
`scheduleGameReminder` and `cancelGameReminder`, to hold the calling product's next-game reminder;
`scheduleGameReminder` receives whether to ring an alarm or deliver an ordinary notification, and whether the product
holds the `Calendar` grant. A host that supplies none answers both `Unsupported`.
