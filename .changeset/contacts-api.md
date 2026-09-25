---
"@parity/truapi": minor
---

A `Contacts` trait lets a product ask the host to open its contact picker. The user selects one person and the
product receives one opaque 32-byte handle: never the list, a name, or an account. The handle is the same value
for that contact in every product and on every host of this user, keyed on the user's own entropy, and the core
resolves it back to an account: a transaction payload declares the handles its call names, and the host
replaces them with those accounts before the call is shown or signed. Hosts serve it through the optional `ContactsPlatform` capability, and a UniFFI host installs one with
`setContactsCallbacks` on the runtime; a host that installs none leaves `contacts.pick` answering
`Unsupported`.

`ProductAccountTxPayload` carries `contacts` as a required field, so a call naming nobody declares an empty
list. It is on the wire as well as in the type: a product and the host it talks to have to agree on it.
