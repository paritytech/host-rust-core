---
"@parity/truapi-host": minor
"@parity/truapi": patch
---

`create_transaction` and `create_transaction_with_legacy_account` read `txExtVersion` as the transaction extension version, the same way the mobile hosts do. With `0` the host builds a V5 general transaction when pipeline 0 declares `VerifyMultiSignature`, and a signed V4 transaction otherwise. A non-zero value builds V5 on that pipeline. A version the runtime does not declare, such as `5`, returns `NotSupported` naming the declared versions.
