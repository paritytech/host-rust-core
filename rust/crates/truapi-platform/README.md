# truapi-platform

Platform capability traits for TrUAPI host implementations.

Each host (web/WASM, desktop, iOS/UniFFI, Android/UniFFI) implements these
traits to provide the native capabilities the shared Rust runtime cannot reach
directly. The dispatcher in `truapi-server` calls this surface while the Rust
runtime owns product account management, SSO signing, statement-store protocol
flows, permission state, and auth state transitions.

## Type Imports

Most host-facing wire types are imported from `truapi::latest` by this crate and
are exposed through the trait signatures below. `ProductContext` and
`ProductExecutionKind` are defined here instead, and codegen emits their host
codecs from these definitions. Both are SCALE-encodable so they can cross the
wasm callback boundary, where every parameter is encoded with
`parity-scale-codec`; `ProductContext` decodes through its validating
constructor, so a context off the wire carries a normalized product id.

## Product Identity

`normalize_product_identifier` is the single chokepoint that turns a host- or
wire-supplied product id into the canonical form derivation, product storage and
permission scopes are keyed by; `is_product_identifier` is its boolean form.

Two TLD lists back it, and they are deliberately different sizes:

- `DOTNS_TLDS` (`dot`, `paseo`) — names navigation resolves back into the host's
  own product surface. A name classified this way bypasses the outbound domain
  grant, so this list stays narrow.
- `PRODUCT_ID_TLDS` (`dot`, `paseo`, `test`) — TLDs a product identifier may be
  scoped under. `test` is a legal product scope but not a dotNS name, so a
  `.test` URL stays external and keeps consuming a domain grant.

`REMOTE_PERMISSION_TRUSTED_LABELS` lists bare product labels — no TLD, so one
entry covers every network in `PRODUCT_ID_TLDS` — whose products hold every
`RemotePermission` without a user prompt, tested with
`has_trusted_remote_permissions`. It covers remote permissions only: device
permissions, identity disclosure and cross-product account access always prompt.
A stored decision outranks the list, so a `Denied` written through `CoreAdmin`
revokes the grant.

## Host Callback Traits

- `ProductStorage`: product-scoped key-value storage.
- `CoreStorage`: typed core-owned storage slots such as auth session, pairing
  identity, and permission authorization state.
- `Navigation`: open URLs in the system browser.
- `Notifications`: deliver and cancel push notifications.
- `Permissions`: prompt for device and remote authorizations.
- `Features`: report host feature support.
- `ChainProvider` / `JsonRpcConnection`: open JSON-RPC connections to chains.
- `AuthPresenter`: render core-owned auth state transitions.
- `UserConfirmation`: confirm signing, transaction, resource, alias, and
  preimage actions before the core asks the paired wallet.
- `ThemeHost`: stream the host theme into the runtime.
- `PreimageHost`: submit and look up preimages through the host-selected backend.
- `ChatPlatform`: create product-scoped native chat rooms, post messages into
  them, and stream the product's room list.

`Platform` is a blanket-implemented supertrait that combines the capability
traits above except `ChatPlatform`, which a host supplies separately and only
when it provides the Chat modality.

## Core-Owned Admin API

`CoreAdmin` is not part of the host-provided `Platform` callback surface. It is
the core-owned control API exposed to host UI for logout, pairing cancellation,
session-store refresh, and permission administration.
