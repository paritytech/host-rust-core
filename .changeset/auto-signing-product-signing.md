---
"@parity/truapi": minor
---

An RFC-0010 `AutoSigning` grant covers `signing.sign_raw`, `signing.sign_payload` and
`signing.create_transaction` for the granting product's own accounts: the host serves them from the
granted key without a per-call confirmation, and a pairing host serves them without reaching the
signing host. The deprecated unwatermarked raw-signing API is never covered and always prompts.
A pairing host also signs product statement proofs under the grant, which the SSO raw-signing
protocol cannot carry otherwise.
