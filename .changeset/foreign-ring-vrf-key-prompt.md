---
"@parity/truapi-host": minor
---

A product using another product's registered ring-VRF key reaches the user as a
`ForeignRingVrfKey` confirmation, naming the calling product, the owning product,
and whether the key would produce a context-scoped proof or an unscoped member-key
signature. Hosts must present it per call and must not persist the answer, so one
approval never becomes a standing grant over the owner's key. A declined request is
`Rejected`; `NotAllowlisted` is now reserved for an owner's manifest allowlist
refusing the caller.
