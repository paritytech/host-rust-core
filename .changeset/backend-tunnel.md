---
"@parity/truapi": minor
---

A `Backend` trait carries product requests to a backend the host holds a credential for. The product names a
backend identifier plus a method, path, query and body; the host resolves it to a base URL and its own
credential, performs the call, and returns the status, an allowlisted set of headers and the body. The core
screens the request so it cannot address anything outside the backend's origin, and holds no credential itself.
`Backend::list` reports the identifiers a host serves the calling product, so a product can check before it
depends on one. Hosts serve both through the optional `BackendHost` capability; a host with no tunnel answers
`Unsupported`, and one that has a tunnel but not the named backend answers `UnknownBackend`.
