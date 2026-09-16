---
"@parity/truapi": minor
"@parity/truapi-host": minor
---

`sendPushNotification` carries an `urgency` level (#560), in a v0.2 notification payload whose v0.1 predecessor means
`Normal`. `Normal` is a notification the host shows. `Critical` is an alarm the host rings through the platform's alarm
framework until the user dismisses it, and opens the notification's `deeplink` when the user acts on it.

`Critical` is delivered as an alarm only to a product holding the new `Alarms` device permission. A host with no alarm
framework refuses that grant, so a `Critical` without it is delivered as `Normal` and the response carries the urgency
that was delivered. Ids, persistence, cancellation and limits follow RFC 0019 unchanged.

Hosts receive the resolved urgency beside the notification: `pushNotification` takes it as a second argument, which
every host implements. Products pass `urgency` on every `sendPushNotification` call.
