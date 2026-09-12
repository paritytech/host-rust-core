# @parity/truapi

## 0.16.0

### Minor Changes

- 4a93ac4: Add temporary deprecated unwatermarked signing for product and legacy accounts to unblock runtime ownership
  proofs while runtimes adopt watermarked verification (#612). Existing signing APIs retain their names and wrapping
  behavior. The temporary implementations log a deprecation warning when called. Raw signing reviews now include a
  `watermarked` flag; host confirmation UIs must display the matching bytes and warn that unwatermarked signatures may
  authorize transactions.

## 0.15.0

### Minor Changes

- e8ee375: Address every frame with a two-byte `(trait, method)` wire discriminant. The trait byte names the API trait
  and the method byte addresses a method within it, so each trait owns a full 256-slot method space and method ids
  restart at 0 in every trait.

  A third envelope byte, `message_type`, names which leg of a method's exchange a frame carries, so a method costs one
  id whatever its shape. The payload is the plain SCALE encoding of that leg's type and carries its own version.

  `TrUApiTransport.codecVersion`, `CreateTransportOptions.codecVersion` and `GeneratedClientTransport` are removed.
  Generated handshake calls read `TRUAPI_CODEC_VERSION` directly, so there is no longer a way to advertise a codec
  version that differs from the one the envelope is actually framed in. `CreateTransportOptions` itself remains,
  carrying `requestTimeoutMs` alone, and `createClient` takes a `TrUApiTransport` (every value that satisfied
  `GeneratedClientTransport` satisfies it unchanged).

  This is wire codec version 2. A codec version 1 peer cannot exchange frames with a codec version 2 peer in either
  direction: the handshake itself rides the changed envelope, so the mismatch cannot be negotiated in band. Hosts and
  products must move together.

### Patch Changes

- d36911f: Retry iframe readiness until the host transfers a channel, and reject unanswered requests after a
  configurable bounded deadline.

## 0.14.0

### Minor Changes

- Reserved person and identity keys derive under the network's dotNS suffix. `SigningHostConfig` carries that suffix,
  and every reserved derivation (`uid.<suffix>`, `peopl.<suffix>`) scopes to it, so one seed resolves to the same person
  across the WASM, native and CLI hosts on a given network. Derivation vectors for `.paseo` and `.testnet` are pinned
  against an independent RFC-0022 implementation.

  One seed therefore resolves to a different person than it did under the unsuffixed derivation, and the CLI requires
  version 2 account and pairing stores: existing signer state must be discarded and devices paired again.

## 0.13.1

### Patch Changes

- Follow the previewnet and paseo-next-v2 testnet wipes: the well-known chain genesis hashes, the `truapi-host` CLI
  preset, and the bundled light-client chain specs match the live chains again.

## 0.13.0

### Minor Changes

- Accept pasted pairing QR images in the `truapi-host` CLI terminal UI.
- Rename the PreviewNet dotNS top-level domain from `.test` to `.testnet`.

## 0.12.0

### Minor Changes

- 8983638: Add `development_createAccountProof`, a development-only helper for creating a proof with an exact 32-byte
  context.
- 654c0cf: Expose the host's selected language through `locale.subscribe()`.

## 0.11.0

### Minor Changes

- fa7d8db: Expose the current canonical product identifier through `system.getProductContext()`.

## 0.10.0

### Minor Changes

- d872d64: Export `PREVIEWNET_INDIVIDUALITY` and `PREVIEWNET_ASSET_HUB` well-known chains, so a product on previewnet
  can pin the genesis hashes it signs `CheckGenesis` over the same way a product on `paseo-next-v2` does. Pairs with the
  CLI gaining a `previewnet` network preset.
- d49f253: Add `createWebSocketProvider(url)` for hosts that serve protocol frames over a WebSocket, and
  `connectWebSocketHost(url)` on the sandbox path so a plain browser tab using such a host is detected as hosted and
  shares the cached client. Both native host READMEs already pointed products at `createWebSocketProvider`, which until
  now did not exist, so every browser product had to hand-write the bridge. `truapi-host signing-host --frame-listen` is
  now reachable from an ordinary tab, and the CLI's own TCP provider delegates to the shared implementation.

## 0.9.0

### Minor Changes

- Add the RFC-0024 ring-VRF key management surface. `account.registerRingVrfKey` registers a product-owned member key
  for a ring and returns its public key, `account.listRingVrfKeys` reports an owner product's registry entries at either
  `Anonymized` or `PublicKey` disclosure, and `account.ringVrfSign` signs bytes directly with a registered key.

  `account.getAccountAlias` and `account.createAccountProof` take a `keyHandle` naming the registered member key the
  host must use, and ring locations address the collection directly without a pallet-instance junction. Their error
  unions carry `KeyNotRegistered` and `KeyNotInRing`; proof creation also reports `NotAllowlisted` when a foreign key's
  owner has not allowlisted the caller.

## 0.8.0

### Minor Changes

- Add `chain.getChainInfo` (RFC 0026): products resolve a `ChainIdentifier` role (`Relay`, `AssetHub`, `People`,
  `Bulletin`) against the host's configured environment and receive the network string plus the chain's genesis hash, so
  genesis hashes no longer need to be hard-coded into product bundles.

## 0.7.0

### Minor Changes

- Publish the package version paired with the RFC-0022 mobile host cutover and the completed RFC-0023 account VRF
  signing flow.

## 0.6.0

### Minor Changes

- Represent product-account derivation indexes as tagged selectors that support both compact numeric values and raw
  32-byte values. Add the general-purpose sr25519 `account.signVrf` API and its generated request, response, transcript,
  error, and callback types.

## 0.5.1

### Patch Changes

- Support the sandbox client in legacy Nova and dotli iframe hosts while the Rust Core transport migration rolls out.

## 0.5.0

### Minor Changes

- Redesign account alias and ring-VRF proof requests around stable, junction-based ring locations and product-scoped
  proof contexts. Proof responses now include the contextual alias, ring index, and ring revision, with distinct
  `RingNotFound` and `NotMember` errors.

## 0.4.1

### Patch Changes

- Treat Firefox's masked `"null"` `location.ancestorOrigins` entries as an unknown host origin in the sandbox bootstrap.
  The ready ping falls back to the source-checked wildcard instead of throwing
  `SyntaxError: An invalid or illegal string was specified`, which left iframe-hosted products permanently offline in
  Firefox.

## 0.4.0

### Minor Changes

- Add the `coinPayment` client namespace (RFC 0017 Coinage Payment): `createPurse`, `queryPurse`, `rebalancePurse`,
  `deletePurse`, `deposit`, `refund`, `createCheque`, `createReceivable`, and `listenForPayment`, with the
  `CoinPayment*` / `HostCoinPayment*` / `VersionedHostCoinPayment*` request/response/error types and their wire
  discriminants.

  **Breaking:** the `CallError<D>` SCALE codec now decodes to a tagged `CallErrorValue<D>` union (`Domain` / `Denied` /
  `Unsupported` / `MalformedFrame` / `HostFailure`) instead of projecting only the domain error and throwing on
  framework-level failures. The `Transport.truapiVersion` field is removed and `Transport.codecVersion` is deprecated;
  generated handshake calls read the codec version directly.

## 0.3.2

### Minor Changes

- Rename the exported `Provider` transport type to `WireProvider` to make its role explicit. It is the low-level
  SCALE-wire-frame pipe (a `MessagePort` or iframe `postMessage` channel) that `createTransport` runs on. The
  `createIframeProvider` / `createMessagePortProvider` factories are unchanged; only the type name moves. Consumers
  importing `Provider` should import `WireProvider` instead.
- Add the `@parity/truapi/sandbox` entry point: host-environment detection (`isCorrectEnvironment`), a lazily-built
  cached client (`getClientSync`, `null` outside a host container), and a `subscribeConnectionStatus`
  connected/disconnected listener. Browser-embedded hosts can bootstrap a client without assembling the transport by
  hand.

## 0.3.1

### Patch Changes

- Fixed `HostPaymentTopUpError` SCALE variant ordering: `PartialPayment` (index 2) now precedes `Unknown` (index 3),
  matching the canonical wire layout.
- Fixed explorer 0.3.1 snapshot import paths.

## 0.1.0

### Minor Changes

- Initial public release of `@parity/truapi`: TrUAPI transport, SCALE codecs, and the generated TypeScript API client
  for protocol v1.0.
