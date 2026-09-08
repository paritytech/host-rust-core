# truapi-server

_Runtime core for TrUAPI: dispatcher, protocol frames, SCALE-coded wire envelope._

## What this crate is for

`truapi-server` is the runtime that turns trait implementations of the
`truapi` API into a working host. It owns:

- the [`ProtocolMessage`] wire envelope and SCALE codec
- the [`Dispatcher`] that routes incoming frames to per-method handlers
- the subscription lifecycle (start/receive/stop/interrupt)
- the [`Transport`] trait that platform-specific IPC backends implement
- the auto-generated dispatcher/wire-table tables shipped under
  [`crate::generated`]
- the host embedding surface: one long-lived role handle
  (`PairingHostRuntime` or `SigningHostRuntime`) per host application, exposing
  shared [`RuntimeServices`] plus one [`ProductRuntime`] per product connection

## Architecture

Two ownership bands. A **per-product-connection** band (byte frames →
dispatcher → role-neutral product runtime) is minted once per host↔product
connection by the role handle and lives for that product's whole session; a
**shared per-host** band owns role-neutral infrastructure (`RuntimeServices`)
and the role object (`PairingHost` or `SigningHost`), which is itself the
`ProductAuthority`. Pure `host_logic` is a no-I/O library both bands call, not a
stage in the frame path; the host's `Platform` impl is the syscall floor.

```text
   ┌───────────────────────────────────────────────────────┐
   │ product      sandboxed iframe · native WebView        │
   └───────────────────────────────────────────────────────┘
                              │  ▲
          SCALE frames        │  │  MessageChannel · loopback
          both directions     ▼  │  WS
   ┌───────────────────────────────────────────────────────┐
   │ binding layer :  host shell / transport adapter       │
   │ thin byte bridge  ·  no protocol logic                │
   └───────────────────────────────────────────────────────┘

 ══ per host→product connection ( one per connected product ) ══
   ┌───────────────────────────────────────────────────────┐
   │ ProductRuntime           frame endpoint               │
   │ decode each SCALE frame → dispatch one typed call     │
   └───────────────────────────────────────────────────────┘
                              │  typed method call
                              ▼
   ┌───────────────────────────────────────────────────────┐
   │ ProductRuntimeHost       role-neutral                 │
   │ validate · permission-gate · confirm                  │
   └───────────────────────────────────────────────────────┘
                              │  wallet-authority tail :
                              │  sign · alias · entropy · alloc
                              │  via  Arc<dyn ProductAuthority>
                              ▼

 ══ shared per host app ( one per host, all connections ) ══════
     the PairingHostRuntime | SigningHostRuntime handle owns both:
   ┌─────────────────────────────┐   ┌────────────────────────┐
   │ role  =  ProductAuthority   │   │ RuntimeServices        │
   │ PairingHost | SigningHost   │   │ platform · chain · RPC │
   └─────────────────────────────┘   └────────────────────────┘
              │
              │  PairingHost only : encrypted SSO channel
              ▼
       ┌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌┐
       ╎ remote signing host   ( external wallet ) ╎
       └╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌┘

   both bands call host_logic for pure work, never traverse it :
   ┌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌┐
   ╎ host_logic       pure library ( no I/O )              ╎
   ╎ crypto · codecs · derivation · policy                 ╎
   └╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌┘

 ══ host-owned floor · where every I/O above bottoms out ═══════
   ┌───────────────────────────────────────────────────────┐
   │ Platform impl  ( TS / Swift / Kotlin )                │
   │ storage · prompts · chain RPC · navigation            │
   └───────────────────────────────────────────────────────┘
```

`ProductRuntimeHost` handles everything role-neutral (id normalization,
permission gating, confirmation, soft product-key derivation), then delegates
the wallet-authority tail (`sign_*`, `create_transaction`, `account_alias`,
`create_proof`, `allocate_resources`, `derive_entropy`) through an
`Arc<dyn ProductAuthority>` handle with an `AuthoritySession` snapshot the
role revalidates before touching key material.

`runtime.rs` owns the product runtime and shared helpers. The trait adapters
are grouped by surface under `runtime/capabilities/`; cross-capability fixtures
and tests live in `runtime/tests.rs` and `runtime/tests/`.

### Permission flow

Permission grants are scoped by product id and typed request, so a grant for
one product never authorizes another product or another permission class.

Remote permissions carry one exception. A product whose label is listed in
`truapi_platform::REMOTE_PERMISSION_TRUSTED_LABELS` holds every
`RemotePermission` without a prompt: while nothing is stored the lookup reports
`Authorized` and writes nothing. A stored `Denied` still wins, so the admin
surface revokes it. Device permissions, identity disclosure and account access
always prompt.

```text
Product app
(product_id = "my-product")
        |
        | host API call
        | e.g. getUserId(), chain submit, camera, remote fetch
        v
Generated product client / host callback bridge
        |
        v
ProductRuntime
        |
        | attaches current ProductContext.product_id
        v
PermissionsService(storage, platform, product_id)
        |
        | builds storage key:
        |
        | CoreStorageKey::PermissionAuthorization {
        |   product_id: "my-product",
        |   request: PermissionAuthorizationRequest::...
        | }
        v
CoreStorage lookup
        |
        +-- Authorized ---------------> allow protected host/backend call
        |
        +-- Denied -------------------> return PermissionDenied / deny call
        |
        +-- NotDetermined / missing ---+   (remote + trusted label: allow,
                                       |    see below)
                                       v
                              Platform prompt callback
                                       |
                   +-------------------+-------------------+
                   |                   |                   |
                   v                   v                   v
          device_permission()   remote_permission()   confirm_user_action()
          camera/mic/etc        chain/preimage/etc    identity disclosure
                   |                   |                   |
                   +-------------------+-------------------+
                                       |
                                       v
                         user chooses Allow / Deny
                                       |
                                       v
                      write Authorized / Denied to CoreStorage
                      under the same product-scoped key
                                       |
                         +-------------+-------------+
                         |                           |
                         v                           v
                    Authorized                    Denied
                    allow call                    deny call
```

#### Auto-granted remote permissions

A remote permission resolves in this order:

1. `Remote { domains: [] }` is `Denied`. An empty bundle grants nothing, so
   failing closed outranks the whitelist.
2. A stored decision wins — the exact slot for a non-domain variant, or the most
   specific matching `remote_domain_candidates` entry for a domain.
3. Nothing stored and the product's label is trusted: `Authorized`, with no
   prompt and no write.
4. Nothing stored and the label is untrusted: `NotDetermined`, so the lookup
   prompts and persists the answer.

Because a trusted product's grant is never written, revoking its domain access
means writing `Denied` for the `*` pattern; denying a single host leaves every
other host granted.

Permission administration uses the same key without prompting:

```text
Product UI
  |
  | permission_authorization_status(request)
  | set_permission_authorization_status(request, status)
  v
HostAdmin / ProductRuntime
  |
  v
PermissionsService
  |
  v
CoreStorageKey::PermissionAuthorization { product_id, request }
```

A device permission also carries the host application's OS gate. Both the
request path and the `CoreAdmin` status read resolve it through the host's
`PermissionStatusHost`, so an OS refusal reads as `Denied` whatever is stored,
and the stored product decision is never overwritten by it. Remote,
identity-disclosure and account-access decisions have no OS gate.

The embedder builds a role handle, `PairingHostRuntime::new(...)` or
`SigningHostRuntime::new(...)`, then calls `product_runtime(product, sink)` for
each product connection. Role-specific operations live only on the matching handle:
`cancel_pairing`, `notify_session_store_changed`, `activate_stored_session`,
`activate_external_session`, and `reset_session_state` on the pairing handle,
`activate_local_session` on the signing handle. Both handles expose
`clear_product_state` to revoke one product's capability material without
touching the session or other products. Calling the wrong operation is
a compile error, not a runtime `Unavailable`.

`SigningHostConfig.network_suffix` is the network's bare dotNS TLD (`dot`,
`paseo`, or `testnet`). The shell supplies it alongside the chain genesis hashes
from the same network configuration used by wallet onboarding. It must match
the People chain's `NetworkSuffix.NetworkSuffix`: reserved identities derive
under `uid.<suffix>` and `peopl.<suffix>`, while the chain uses that suffix for
proof contexts. Configuration keeps local activation and key derivation
available offline. The core validates supported suffixes but does not
automatically check that the configured suffix matches the chain.

### The two roles

Both implement the role-neutral **`ProductAuthority`** trait; each owns its
role-specific lifecycle, so no method exists on a role that can't mean it:

- **`PairingHost`** (seedless): the user's keys live in an external wallet, so
  signing/aliases/entropy relay over an encrypted SSO channel (statement store
  on the People chain; the channel lives in `pairing_host/sso_channel.rs`,
  whose one generic `call(request)` sends any `SsoRequest` and returns its
  typed response payload). The v2 wire protocol uses raw X25519 keys,
  HKDF-SHA256, and ChaCha20-Poly1305. It owns pairing/login state, persisted
  auth-session reload, and remote signing-host liveness monitoring.
- **`SigningHost`** (wallet-local): signs on device from local BIP-39 entropy,
  no pairing flow. `signing_host/local_activation.rs` establishes a session
  from host-held secret material. Paired hosts' requests reach it through the
  `SigningHostSsoService` handlers (`signing_host/sso_service.rs`, one method
  per wire request in an inherent impl annotated with `#[sso_service]`). The
  macro generates the service's dispatcher. Handlers own consent prompts and
  revalidate the request's signing session after resource consent and allocation;
  `signing_host/sso_responder.rs` runs the statement-store serve loop and holds
  the shared allowance helpers. Those helpers use the caller's session through
  chain reads and revalidate it before allocation and key return.
  Its public identity is the RFC-0022
  `uid.<tld>` index-0 product account of the configured network. RFC-0024
  ring-VRF keys are explicit,
  product-owned registry entries; aliases, proofs, direct signatures, and
  internal personhood flows use the requested or user-selected registered key
  without a compiled-in fallback. It resolves RFC-0004 `RingLocation` values
  against the chain's `Members` pallet and pins membership, ring pages,
  exponent, and revision reads to one finalized block before creating a proof.
  Extrinsic-payload signing and v4 transaction construction work from
  pre-encoded payload fields, so no chain metadata is needed;
  statement-store and Bulletin allowance allocation are native-only (wasm
  builds report them as unavailable) and do need metadata, which they take from
  the `RuntimeServices`-owned per-chain cache rather than re-reading it per
  call.

`host_logic` stays pure: the orchestrators above call into it for codecs,
session/SSO crypto, SSO wire types and traits (`sso/wire.rs`), key derivation,
and permission policy. The runtime service supplies request/response pairing;
all I/O (statement-store RPC, storage, prompts, chain RPC) stays in the layers
above.

### Inter-host SSO

The hand-written `host_logic::sso::messages::v1::RemoteMessage` enum defines
the wire variants and their SCALE indices. `SsoWire` derives classification,
request wrapping, correlation helpers, and message names from that enum.
These helpers do not require a runtime service implementation. Response
structs derive `SsoResponse` to expose their `Result` payload and classify
its transcript outcome.

Each method in the annotated `impl SigningHostSsoService` names its wire request
and wire response directly. `#[sso_service]` derives request/response pairing
and an exhaustive `dispatch` method from those handler signatures. It wraps
ordinary `Result` bodies in `SsoReply<WireResponse>`, preserving `?` and early
returns. Constructors and helpers live in a separate, unannotated impl; service
methods use native async functions. Dispatch adds the correlation id and constructs
the wire response. Request context holds the call context and captured signing
session. The allocation handler collects
item failures locally and supplies a transcript outcome with those details;
other replies derive their outcome from the response payload.

An additional SSO operation requires payload definitions, wire variants, one
handler in the annotated impl, and a typed client call. The macro's checked-in
compiler tests cover valid handler bodies and reject incomplete or incompatible
contracts.

`PairingHost::call(request)` uses the generated pairing and rejects a response
of the wrong kind immediately. Alias, proof, and ring-VRF operations share
request types between the local authority and SSO service. Transcripts and the
client's `action` field use the service method name; forwarding spans distinguish
payload signing, raw signing, and transaction creation, with `account_kind`
identifying product, legacy, or identity accounts as applicable.

The SSO macros share `truapi-macros`' proc-macro infrastructure. They are
server-specific: their generated `crate::host_logic` and `crate::runtime`
paths resolve only when invoked inside `truapi-server`. The canonical `truapi`
crate uses the other macros and has no dependency on the server runtime.

Rust consumers of the public `host_logic::sso` module depend on its Rust API
as well as the wire format. Stable SCALE indices and payload layouts do not
make renamed types or removed helpers source-compatible. Construct outgoing
requests with `RemoteMessage::request(message_id, typed_request)`; decoded
`SsoSessionStatement::RemoteMessages` contains ordered wire messages, which can
be matched directly or unwrapped with `SsoResponse::from_message`.

## Wire envelope

Every frame on the wire is encoded as:

```text
[requestId: SCALE str][discriminant: u8][payload bytes...]
```

The discriminant identifies a method + frame kind via the auto-generated
[`crate::generated::wire_table::WIRE_TABLE`]. Each method's ids are exposed
as a named const (`PREIMAGE_SUBMIT`, ...); both `WIRE_TABLE` and the generated
dispatcher reference those consts. Method ordering is part of the wire
protocol; only ever append.

The payload bytes are the SCALE-encoded inner value, inlined without a
length prefix. The discriminant is carried directly as `Payload::id`, and the
dispatcher routes on that numeric id via id-keyed tables.
