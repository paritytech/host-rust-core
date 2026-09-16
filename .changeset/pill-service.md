---
"@parity/truapi": minor
"@parity/truapi-host": minor
---

A `Pill` service lets a product put a countdown on the host's own surfaces (#558, #559). `declarePill` carries a
product-chosen key, the instant the pill appears, the deadline at which it goes away, the destination the host opens, a
title, and `openAtDeadline`. The host draws the countdown, opens the destination on tap, and at the deadline withdraws
the pill; with `openAtDeadline` it also opens the destination then. `withdrawPill` takes the key and is idempotent.
Declarations are keyed: declaring again with a key already in use replaces that declaration.

The core parses `destination` as it parses a `navigateTo` URL and refuses what that would refuse, and refuses a
declaration whose window ends before it starts or whose deadline is zero. The pill carries no permission, and the
per-domain grant `navigateTo` takes for an external host is not taken here: a product can name a destination it could
not navigate to itself, and the host opens it on tap or at the deadline.

Drawing pills is an optional host capability. A host that serves none answers `Unsupported`. A native host passes a
`PillHostBridge` to `openProductExecution` beside its chat bridge, a browser host supplies a `pill` callback group, and a
Rust host installs one with `set_pill_host` on its runtime.
