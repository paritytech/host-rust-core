---
"@parity/truapi-host": minor
---

Serve the `game` service from the host runtime. A host supplies the optional `game` callbacks,
`scheduleGameReminder` and `cancelGameReminder`, to hold the calling product's next-game reminder;
`scheduleGameReminder` receives whether to ring an alarm or deliver an ordinary notification, and whether the product
holds the `Calendar` grant. A host that supplies none answers both `Unsupported`. The core serves `game` to the game
product, `dim2`, alone, so the mock test host answers `Unsupported` to its default `mock.dot` product; a suite that
exercises `game` passes `productId: "dim2.dot"`.
