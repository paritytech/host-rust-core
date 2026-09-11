---
"@parity/truapi": minor
"@parity/truapi-host": minor
---

Add `signRawWatermarked` and `signRawWatermarkedWithLegacyAccount`, retaining the existing names as deprecated
compatibility aliases. Add explicitly deprecated unwatermarked signing for product and legacy accounts to unblock
runtime ownership proofs while runtimes adopt watermarked verification (#612). Deprecated client requests emit a warning
when called.
