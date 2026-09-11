---
"@parity/truapi": minor
"@parity/truapi-host": minor
---

Add temporary deprecated unwatermarked signing for product and legacy accounts to unblock runtime ownership proofs
while runtimes adopt watermarked verification (#612). Existing signing APIs retain their names and wrapping behavior.
The temporary implementations log a deprecation warning when called.
