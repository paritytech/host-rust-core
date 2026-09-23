---
"@parity/truapi-host": minor
---

Load `verifiable` on demand in the browser. The core WASM is 2.63 MiB raw and 773 KiB brotli, down from 7.76 MiB and 5.40 MiB: `verifiable` and its 4.5 MiB of powers of tau live in a separate module, in the `verifiable/` directory of each bundle, fetched in the background once a pairing session connects, or when a ring-VRF operation first runs. Hosts serving a bundle directory as a whole need no change; a host that copies individual files out of it must copy `verifiable/` too.
