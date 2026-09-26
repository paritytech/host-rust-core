---
"@parity/truapi-host": minor
"@parity/truapi": patch
---

`create_transaction` and `create_transaction_with_legacy_account` read `txExtVersion` as the version of the transaction extensions in `extensions`, as the runtime numbers them. Current runtimes only define version 0. With `0` the host builds a V5 general transaction when transaction extension version 0 includes `VerifyMultiSignature`, and a signed V4 transaction otherwise. A non-zero value builds V5 with that version. A version the runtime does not declare returns `NotSupported` naming the declared versions.
