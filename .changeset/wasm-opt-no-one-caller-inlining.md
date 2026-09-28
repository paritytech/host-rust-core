---
"@parity/truapi-host": patch
---

Build the core WASM without wasm-opt's one-caller inlining, which merges functions into bodies that compress poorly. The `web` core is 719.5 KiB brotli and 952.5 KiB gzip, down from 775.4 KiB and 1.02 MiB; the raw size is unchanged at 2.66 MiB.
