---
"@parity/truapi-host": minor
"@parity/truapi": patch
---

`create_transaction` and `create_transaction_with_legacy_account` read `txExtVersion` as the transaction extension version, which selects the transaction extension set `extensions` follows. With `0` the host builds a V5 general transaction when transaction extension version 0 includes `VerifyMultiSignature`, and a signed V4 transaction otherwise. A non-zero value builds V5 with that version. A version the runtime does not declare returns `NotSupported` naming the declared versions.
