---
"@parity/truapi-host": patch
---

Every native build of the core includes the localhost WebSocket bridge and the debug sink. There are no `ws-bridge` or `debug-sink` Cargo features: native targets compile both with the default `runtime` feature, and wasm32 builds never include them.
