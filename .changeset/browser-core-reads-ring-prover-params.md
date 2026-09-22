---
"@parity/truapi-host": minor
---

Ship the browser core without the ring-VRF prover's powers of tau. The WASM bundle is 2.87 MiB raw and 848 KiB brotli, down from 7.76 MiB and 5.40 MiB, because the 4.5 MiB incompressible SRS no longer travels with every session that never proves.

`dist/wasm/web/` now carries one `srs-domain*.bin` beside the bundle, and the core reads the one it needs on the first local ring-VRF proof. Hosts serving that directory as static files need no change; a host that copies individual files out of it must copy the `.bin` files and the `snippets/` directory too, or the core delegates proving to the paired signer instead.
