# @parity/truapi-host

## 0.17.0

### Minor Changes

- 221d972: Make the `context` scope effective. A `trustedProducts` grant of `context` now admits a cross-product
  ring-VRF proof or signature against the granting product's key, where before the runtime admitted the caller and the
  authority holding the keys refused it again with the same error a product granting nothing would produce. Each
  authority resolves the grant from the owner's published manifest itself rather than accepting a verdict relayed by the
  caller, because on a paired host the calling product id arrives over the wire as a self-asserted field.

  The authority derives the key from the identity it authorised rather than the spelling it was handed, so authorisation
  and derivation cannot diverge. A granted call is held to the caller's own proof context: the contextual alias is a
  function of the owner's key and the context, so an unconstrained context would let a grantee produce the alias the
  owner presents to a third product that granted nothing and cannot consent.

  The identity read `context` names is covered by the grant rather than prompted for again. The contextual alias and the
  ring-VRF proof come out of one VRF evaluation, so a grantee that may `create_account_proof` already holds the alias
  that proof attests; `get_account_alias` accepting the same grant makes the two calls agree about what the scope means.
  A product without a grant still takes the prompt.

  A stored account-access refusal still overrides a grant, and is now recorded against the product on both sides rather
  than one spelling of it, matching the granularity a manifest grant uses: a refusal for `peopl.dot` also covers
  `app.peopl.dot`. Decisions written by earlier releases under the full product id are still honoured, so upgrading does
  not discard a refusal a user has already given.

  `create_account_proof` with a foreign key handle and no active session now answers `Rejected` where it previously
  answered `NotAllowlisted`. The session is consulted before the grant so that the pair of refusals cannot be used to
  probe which product granted which; a product branching on the old tag for that case sees a different one.

  Product identifiers are rejected when they carry no name: an empty label, control characters, invisible bidirectional
  or zero-width formatting, whitespace, or path separators. Each of these reached the grant key, the manifest cache key,
  the account-access prompt and the logs. Internationalised names are unaffected.

  A granted cross-product access is logged. It raises no prompt and writes no stored decision, so previously only the
  refusal was audible: a publisher's grant could let one product act with another's keys leaving no trace on the device.
  This does not make the access revocable, which needs a surface for the user to record a decision about a pair they
  were never asked about.

  Resolving a grant can require reading a product manifest from dotNS, so the lookup is bounded by the caller's timeout
  and cancellation rather than running outside both. A manifest is cached under the label it resolves by, so every
  executable of one product shares one entry, and an entry stamped in the future is re-read rather than treated as fresh
  forever. Entries written by earlier releases under the full product id are no longer read and nothing evicts them, so
  they sit in core storage until the cache is cleared.

- b0d95f0: Serve the `pocket` service from the host runtime. A host supplies the optional `pocket` callbacks to back
  `listSubscribe` and `removeCard` over the calling product's cards; a host that supplies none answers both with
  `Unsupported`.
- 221d972: Cap product identifiers at 256 bytes. `has_dotns_tld` only inspects the suffix after the last `.`, so every
  length of `aaa...aaa.dot` was a distinct valid id, and a cross-product call carries that string from the wire where it
  is self-asserted. An identifier longer than the cap after NFC normalisation is now rejected, reported by length rather
  than by echoing the value back into an error string and a log line. This bounds the size of one identifier, not how
  many exist.

  Signing hosts also require an Asset Hub genesis hash. Product manifests are read from the dotNS contracts deployed
  there, so without one no manifest resolves and every cross-product `trustedProducts` grant not already cached is
  refused, indistinguishably from the other product having granted nothing. A custom build enabling the Rust
  `wasm-signing-host` feature must supply `runtimeConfig.assetHub` alongside `runtimeConfig.networkSuffix`; the shipped
  bundle is built `--no-default-features` and carries no signing constructor.

### Patch Changes

- Updated dependencies [4034118]
- Updated dependencies [221d972]
- Updated dependencies [befde58]
- Updated dependencies [75a9f2e]
- Updated dependencies [cc1823d]
- Updated dependencies [0e86a3a]
- Updated dependencies [a9731b1]
- Updated dependencies [a9731b1]
- Updated dependencies [a9731b1]
  - @parity/truapi@0.17.0

## 0.16.0

### Minor Changes

- 4c20296: Subscriptions can fail at any point, not only at start. A stream that breaks ends with a typed reason that
  reaches the product's `error` handler, so a platform failure surfaces instead of freezing the last value or passing
  for a clean finish; a method the host has not implemented, and a chain follow that cannot be opened, say so rather
  than completing quietly. A product that serves a host-initiated subscription, today only the chat custom renderer, now
  takes a handler of the request plus `send` and `interrupt` callbacks instead of returning an observable, which retires
  `ObservableSource`. Subscription consumers keep the shapes they had, and the wire bytes are unchanged.
- 4a93ac4: Add temporary deprecated unwatermarked signing for product and legacy accounts to unblock runtime ownership
  proofs while runtimes adopt watermarked verification (#612). Existing signing APIs retain their names and wrapping
  behavior. The temporary implementations log a deprecation warning when called. Raw signing reviews now include a
  `watermarked` flag; host confirmation UIs must display the matching bytes and warn that unwatermarked signatures may
  authorize transactions.
- 9252985: `Renderer` is the one service through which a product draws a body inside a host surface. The host starts
  `renderer.onRender` with a `RenderContext` (`ChatMessage`, `InputWidget`, `PocketCard`) and an opaque payload; the
  product streams `RendererNode` trees, and a press inside a tree reaches `renderer.actionSubscribe` as
  `{ context, actionId, payload }`. `Chat` has no `custom_message_render`; a `Custom` chat message renders through
  `Renderer` with a `ChatMessage` context, and `ChatActionPayload.ActionTriggered` carries only host-drawn `Actions`
  button presses.

  `RendererNode` replaces `CustomRendererNode` with `Image` (`ImageSource`, `ImageFit`), `Effect`, `Shape.Square`,
  `Modifier.Opacity` and `Modifier.BlendingMode`; `Spacer`, `TextField` and `Image` carry no `children`, and the
  single-field `Modifier` and `Shape` variants are tuple variants.

  Hosts call `provider.render(request, sink)` and `provider.publishRendererAction(item)`; `publishChatAction` is the
  path for posted messages, commands and host-drawn `Actions` buttons.

- fa67882: The core counts references on each product's worker and tells the host when that count crosses zero, so a
  worker runs only while something needs it.

  `acquireWorker(productId)` takes one reference for a modality holder that is on screen or in flight, and
  `releaseWorker(productId)` gives it back; releasing with none held is a no-op. The first reference and the last
  release are the only ones that report anything. `subscribeWorkerDemand(listener)` is where that report arrives: the
  listener receives every product wanted right now, then each change as it happens, and `wanted: false` for everything
  still wanted when the runtime is disposed. Starting and stopping the worker executable stays with the host, and a
  `wanted: false` is permission to stop rather than an order, so a host may keep one warm. The core keeps no clock and
  runs no timers.

### Patch Changes

- Updated dependencies [4c20296]
- Updated dependencies [4a93ac4]
- Updated dependencies [9252985]
  - @parity/truapi@0.16.0

## 0.12.0

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

- Updated dependencies [d36911f]
- Updated dependencies [e8ee375]
  - @parity/truapi@0.15.0

## 0.11.0

### Minor Changes

- Reserved person and identity keys derive under the network's dotNS suffix. `SigningHostConfig` carries that suffix,
  and every reserved derivation (`uid.<suffix>`, `peopl.<suffix>`) scopes to it, so one seed resolves to the same person
  across the WASM, native and CLI hosts on a given network. Derivation vectors for `.paseo` and `.testnet` are pinned
  against an independent RFC-0022 implementation.

  One seed therefore resolves to a different person than it did under the unsuffixed derivation, and the CLI requires
  version 2 account and pairing stores: existing signer state must be discarded and devices paired again.

### Patch Changes

- Updated dependencies
  - @parity/truapi@0.14.0

## 0.10.1

### Patch Changes

- Preserve buffered subscription event order.
- Resolve the dotNS controller whether the gateway stores a dispatcher or the controller.
- Page dotNS `pendingClaims` through its `(address,uint256,uint256)` view, and retain claims from complete earlier pages
  when a later page reverts.
- Read Resources parameters through runtime view functions.
- Updated dependencies
  - @parity/truapi@0.13.1

## 0.10.0

### Minor Changes

- Rename the PreviewNet dotNS top-level domain from `.test` to `.testnet`.

### Patch Changes

- Updated dependencies
- Updated dependencies
  - @parity/truapi@0.13.0

## 0.9.0

### Minor Changes

- 8983638: Support the development-only raw proof context used by `development_createAccountProof`.
- 654c0cf: Expose the host's selected language through `locale.subscribe()`.

### Patch Changes

- Updated dependencies [654c0cf]
  - @parity/truapi@0.12.0

## 0.8.0

### Minor Changes

- fa7d8db: Expose the current canonical product identifier through `system.getProductContext()`.

### Patch Changes

- Updated dependencies [fa7d8db]
  - @parity/truapi@0.11.0

## 0.7.0

### Minor Changes

- Host runtime over the current Rust core. A JS host can serve Chat as an optional capability: bot registration, every
  message variant forwarded, manifest execution-kind matching, and custom chat rendering. The runtime retains and
  exposes session identity material, emits the opening auth state with a typed `LoginFailed` kind, forwards session
  activation, yields the named theme from `subscribe_theme`, and reads person usernames from Asset Hub dotNS. External
  navigation is gated on a per-host remote grant, own-account subtree consent is gated with a bounded deadline, and
  statement-store allowance renewal pools PGAS slots and reports what the last pass achieved. Fixes: workers are
  disposed cleanly, a misbehaving product or host no longer aborts the process, and the wasm glue is imported by a
  literal specifier.

### Patch Changes

- Updated dependencies [d872d64]
- Updated dependencies [d49f253]
  - @parity/truapi@0.10.0

## 0.6.0

### Minor Changes

- The host runtime backs the ring-VRF registry with a product-scoped key store, so registration, listing, and direct
  signing resolve against registered member keys, and a foreign key is refused unless its owner allowlisted the caller.

  Statement-store allowances renew themselves as they approach expiry and replace the oldest slot once a period is full,
  so long-lived products keep a usable slot without a manual top-up. Allowance operations reuse cached chain metadata,
  rings, and a single shared extension-info resolver instead of re-reading them per call.

  Product identifiers accept per-network dotNS TLDs, so a product name resolves against the host's configured network
  rather than a single hard-coded suffix.

### Patch Changes

- Updated dependencies
  - @parity/truapi@0.9.0

## 0.5.0

### Minor Changes

- Host callbacks gain `supportedChains()`, returning the host's environment plus one `(ChainIdentifier, genesisHash)`
  entry per chain role. The core answers `chain.getChainInfo` (RFC 0026) from this single callback; web hosts implement
  it on the `features` callback group.

### Patch Changes

- Updated dependencies
  - @parity/truapi@0.8.0

## 0.4.0

### Minor Changes

- Publish the RFC-0022 mobile host cutover and completed RFC-0023 account VRF signing runtime. Pairing hosts persist
  product-scoped AutoSigning keys, sign matching same-product requests locally, and require structured host and Account
  Holder confirmations before forwarding every other request.

### Patch Changes

- Updated dependencies
  - @parity/truapi@0.7.0

## 0.3.0

### Minor Changes

- Update the WASM host runtime and generated callbacks for tagged 32-byte product-account derivation indexes. Implement
  sr25519 VRF signing through both local AutoSigning authorization and account-holder confirmation flows.

### Patch Changes

- Updated dependencies
  - @parity/truapi@0.6.0

## 0.2.1

### Patch Changes

- Update the WASM host runtime so Bulletin preimage submission survives `chainHead_follow` interruptions without
  double-storing: an interrupted watch re-checks finalized blocks for the already-broadcast transaction before any
  retry, retries re-broadcast the identical signed bytes instead of re-signing with a fresh nonce, and a bounced
  re-broadcast surfaces as inclusion-unverified rather than a failure. Allowance propagation waits are now bounded by
  wall-clock time instead of a best-block count, keeping the budget stable across changes in Bulletin's block cadence.

## 0.2.0

### Minor Changes

- Update the WASM host runtime for junction-based ring locations and contextual alias/proof reviews. The runtime also
  exposes login progress after wallet approval, routes product and DotNS identity raw signing through their matching
  account-holder messages, and retries transient preimage inclusion lookups.

### Patch Changes

- Updated dependencies
  - @parity/truapi@0.5.0

## 0.1.0

### Minor Changes

- Initial public release of `@parity/truapi-host`: a WASM-backed TrUAPI host runtime that embeds the Rust core. Subpath
  entries expose the shared host types (`.`), the browser iframe + Web Worker runtime (`/web`), the Worker entry
  (`/worker-runtime`), and the packaged WASM bundle (`/wasm/web`).
