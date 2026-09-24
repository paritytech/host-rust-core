---
"@parity/truapi-host": minor
---

Load `verifiable` on demand in the browser. The core WASM is 2.64 MiB raw and 775 KiB brotli, down from 7.76 MiB and 5.40 MiB: `verifiable` and its 4.5 MiB of powers of tau live in a separate module, `truapi_verifiable.js` and `truapi_verifiable_bg.wasm` beside the core's files in each bundle, fetched in the background once a pairing session connects, or when a ring-VRF operation first runs. Bundlers that follow `new URL(…, import.meta.url)`, such as Vite, emit both files, and a host serving a bundle directory as a whole needs no change; a host that copies individual files out of it must copy both too.
