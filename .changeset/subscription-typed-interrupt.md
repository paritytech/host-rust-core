---
"@parity/truapi": minor
"@parity/truapi-host": minor
---

Subscriptions can fail at any point, not only at start. A stream that breaks ends with a typed reason that reaches the
product's `error` handler, so a platform failure surfaces instead of freezing the last value or passing for a clean
finish; a method the host has not implemented, and a chain follow that cannot be opened, say so rather than completing
quietly. A product that serves a host-initiated subscription, today only the chat custom renderer, now takes a handler
of the request plus `send` and `interrupt` callbacks instead of returning an observable, which retires
`ObservableSource`. Subscription consumers keep the shapes they had, and the wire bytes are unchanged.
