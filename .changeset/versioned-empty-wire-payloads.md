---
"@parity/truapi": major
---

Every request, response and subscription item on the wire is an explicit versioned wrapper, empty
payloads included. `statementStore.submit` resolves a `RemoteStatementStoreSubmitResponse` whose V1
carries no payload, and the six subscriptions that take no request data send a payload-less V1
request envelope on their start frame. Two frame payloads therefore change size: a `submit` success
is two bytes, and a start frame for those subscriptions is one.
