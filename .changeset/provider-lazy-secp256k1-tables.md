---
"@parity/truapi-provider": patch
---

The browser bundle is 4.25 MiB raw and 0.94 MiB brotli, down from 5.31 MiB and 2.01 MiB. smoldot's secp256k1 multiplication tables are built the first time a runtime call uses a secp256k1 host function, in about 10 ms, instead of shipping as 1 MiB of precomputed points.
