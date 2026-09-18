# @parity/truapi

## 0.17.0

### Major Changes

- 75a9f2e: Remove the hard-coded well-known chain constants (`PASEO_NEXT_V2_ASSET_HUB`, `PASEO_NEXT_V2_INDIVIDUALITY`,
  `PREVIEWNET_ASSET_HUB`, `PREVIEWNET_INDIVIDUALITY`) and the `WellKnownChain` type. Products resolve genesis hashes
  through `chain.getChainInfo` (RFC 0026), which answers from the host's own configuration and therefore survives a
  testnet wipe or an environment move without a new product bundle. It also covers Bulletin and Relay, which the
  constants never did.

  Replace `SOME_CHAIN.genesis` with the `genesisHash` from the matching role:

  ```ts
  const assetHub = await truapi.chain.getChainInfo({ chain: "AssetHub" });
  if (assetHub.isErr()) return;
  const genesisHash = assetHub.value.genesisHash;
  ```

  Genesis hashes are now only available asynchronously from a connected host, so code that needed one at module load has
  to resolve it inside the call that uses it.
- a9731b1: Every request, response and subscription item on the wire is an explicit versioned wrapper, empty payloads
  included. `statementStore.submit` resolves a `RemoteStatementStoreSubmitResponse` whose V1 carries no payload, and the
  six subscriptions that take no request data send a payload-less V1 request envelope on their start frame. Two frame
  payloads therefore change size: a `submit` success is two bytes, and a start frame for those subscriptions is one.
- a9731b1: Subscription interrupts carry a versioned error envelope. The nine subscriptions that reported a bare
  `GenericError` now resolve a per-method wrapper whose V1 is that same payload, so an interrupt frame is one byte
  longer and its domain error downgrades to the version the caller subscribed in.
- a9731b1: The wire codec version is 3. Seven frame legs change shape, so a peer built against codec 2 is refused at the
  handshake rather than failing per call when the first mismatched frame arrives. Hosts and products negotiate this at
  connect time and need no coordinated deploy.

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
- befde58: The unprefixed name for a versioned type belongs to the newest version any wrapper selects.
  `HostLocalStorageReadError` is the v02 shape; the v01 one is `V01HostLocalStorageReadError`.
- 0e86a3a: Add the `pocket` service: `listSubscribe` over the calling product's cards, and `removeCard`.

### Patch Changes

- 4034118: The chat key a host publishes on chain is the X25519 key it actually holds, so a peer that looks up that
  identity can encrypt to it. It was previously derived from an unrelated key tree, which left chat unreachable for
  every identity a host registered. Identities registered before this carry an unusable key and have to be
  re-registered.
- cc1823d: `truapi-host` keeps one base path on one signer identity. A `--session` name survives promotion and keeps
  selecting the session it created, a lost or stale `current-session` pointer resolves against the provisioned sessions
  instead of provisioning beside them, and `--serve` reports a missing signer and announces the minutes-long first
  registration instead of staying silent.

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
