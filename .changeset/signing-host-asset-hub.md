---
"@parity/truapi-host": minor
---

Cap product identifiers at 256 bytes. `has_dotns_tld` only inspects the suffix
after the last `.`, so every length of `aaa...aaa.dot` was a distinct valid id,
and a cross-product call carries that string from the wire where it is
self-asserted. An identifier longer than the cap after NFC normalisation is now
rejected, reported by length rather than by echoing the value back into an error
string and a log line. This bounds the size of one identifier, not how many
exist.

Signing hosts also require an Asset Hub genesis hash. Product manifests are read
from the dotNS contracts deployed there, so without one no manifest resolves and
every cross-product `trustedProducts` grant not already cached is refused,
indistinguishably from the other product having granted nothing. A custom build
enabling the Rust `wasm-signing-host` feature must supply `runtimeConfig.assetHub`
alongside `runtimeConfig.networkSuffix`; the shipped bundle is built
`--no-default-features` and carries no signing constructor.
