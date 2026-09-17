---
"@parity/truapi-host": minor
---

Serve the `pocket` service from the host runtime. A host supplies the optional `pocket` callbacks to back
`listSubscribe` and `removeCard` over the calling product's cards; a host that supplies none answers both with
`Unsupported`.
