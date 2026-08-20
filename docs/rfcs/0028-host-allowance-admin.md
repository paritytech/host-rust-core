# RFC-0028: Host allowance administration

|                 |                                                                                                          |
| --------------- | -------------------------------------------------------------------------------------------------------- |
| **RFC Number**  | 28                                                                                                       |
| **Start Date**  | 2026-08-20                                                                                               |
| **Description** | A non-secret host-facing surface on `HostAdmin` for administering product allowances, with an explicit host origin so host-initiated work is distinguishable from a product request |
| **Authors**     | Filippo Vecchiato                                                                                         |

This RFC changes no product-facing protocol method and nothing in
`rust/crates/truapi/`: the surface is host-side, which the crate invariants place
in `truapi-platform` and `truapi-server`.

## Summary

`HostAdmin` gains a non-secret allowance surface — allocate, status, and
invalidate — scoped to a product and a resource kind, with an explicit
`HostAllowanceOrigin` so the runtime can tell host-initiated allowance work from
a product's request. The wire protocol does not change and no new generated
method appears. The underlying operations already exist inside `truapi-server`;
today they are reachable only through the product dispatcher, which is what
forces hosts to synthesize product traffic and suppress the resulting consent
prompt to administer their own allowances.

## Motivation

[RFC-0010](0010-allowance.md) settled that products never manage slot tables, and
stated the consequence in its requirements: "allowance is entirely the Host's
concern". The product-facing half of that landed as
`host_request_resource_allocation`. The host-facing half did not. `HostAdmin`
(`rust/crates/truapi-server/src/host_core.rs`) exposes exactly
`disconnect_session`, `permission_authorization_status`,
`permission_authorization_statuses` and `set_permission_authorization_status`,
plus `get_session_chat_identity_key` and `get_device_encryption_key` through its
`CoreAdmin` impl. There is no allowance operation and no allowance status.

A host still has to administer allowances outside a product request: warm them at
startup so a product's first call does not stall, re-check them when returning to
the foreground, and re-acquire after a rejection. With no admin entry point, the
only route to the authoritative implementation is to impersonate a product.

### What the workaround costs

`brevity-dozer` does exactly that, and documents why.
`SigningHost::request_product_allowances` builds a `ProtocolMessage` around
`HostRequestResourceAllocationRequest::V1`, feeds it to a short-lived
`product_runtime` over a capturing frame sink, disposes the endpoint, then decodes
the single response frame and correlates the request id by hand. Its own doc
comment states the reason: "TrUAPI exposes that implementation only through its
generated product dispatcher, so this adapter creates a short-lived product
endpoint". The same pattern is reused for `register_personhood_ring_vrf_keys`, so
it is becoming load-bearing rather than incidental.

Three costs follow, and the third is the one that matters.

1. **A parallel type system.** `brevity-core/src/allowance_admin.rs` is 869 lines
   of `AllowanceResourceKind`, `AllowanceLifecycle`, `AllowanceTarget`,
   `AllowanceStatus`, `AllowanceAdminError`, an `AllowanceAdminBackend` execution
   seam and an observer stream — a lifecycle model every host needs and each one
   will otherwise rebuild. Its module doc calls itself "the temporary
   Brevity-side override".

2. **Capabilities that exist but are sealed.** That backend records what it
   cannot do: "inspect/invalidate remain a non-secret process-lifetime read model
   because the pinned `HostAdmin` exposes neither a chain status probe nor cache
   eviction". Upstream those primitives are already written —
   `evict_bulletin_allowance_key`, `clear_statement_store_allowance_keys`,
   `clear_bulletin_allowance_keys`, `remove_allowance_key` and the `cached_*`
   readers in `runtime/pairing_host.rs` and `runtime/allowances.rs` — but they are
   `pub(super)`. A host reimplements a weaker version of code that already exists.

3. **Consent has to be bypassed out of band.** `ResourceAllocation::request`
   (`runtime.rs`) gates on
   `platform.confirm_user_action(UserConfirmationReview::ResourceAllocation(..))`
   before calling the authority. That gate is right for a product and wrong for
   the host, which would be prompting itself about its own maintenance. Because a
   forged frame is indistinguishable from a real one, the host cannot say "this
   one is mine" — so it arms a token instead. `HostAllowanceAutoConfirm` keys a
   counter by `(product_id, resource_tag)`, and the host's consent delegate
   silently returns approval when the token matches
   (`brevity-viewmodel/src/ux.rs`).

   That registry is carefully scoped — one token, single-resource matches only,
   RAII-withdrawn when the dispatch ends — but the matching is heuristic by
   construction. A genuine product-initiated request for the same product and the
   same single resource, arriving while a host dispatch is armed, consumes the
   token and is approved without asking the user. Nothing outside the runtime can
   close that window, because the runtime is the only party that knows which call
   it originated.

That third cost is the argument for this RFC. The rest is duplication; this is a
consent decision made by pattern-matching because the API offers no way to state
it.

## Stakeholders

- **Host developers** — gain a supported surface for startup warm-up, foreground
  re-check and recovery, and can delete their forged-frame adapters and
  auto-confirm registries.
- **Product developers** — unaffected. `host_request_resource_allocation` and its
  confirmation review are unchanged.
- **Account Holder developers** — unaffected; the authority operation invoked is
  the one the product path already invokes.

## Explanation

### `HostAdmin` methods

```rust
impl HostAdmin {
    /// Allocate product-scoped resources on the host's own initiative.
    pub async fn allocate_allowances(
        &self,
        resources: Vec<v01::AllocatableResource>,
        origin: HostAllowanceOrigin,
    ) -> Result<Vec<v01::AllocationOutcome>, v01::GenericError>;

    /// Non-secret lifecycle for one resource kind.
    pub async fn allowance_status(
        &self,
        resource: HostAllowanceResource,
    ) -> Result<AllowanceLifecycle, v01::GenericError>;

    /// Drop cached allowance key material for one resource kind, so the next
    /// use re-derives or re-requests it.
    pub async fn invalidate_allowance(
        &self,
        resource: HostAllowanceResource,
    ) -> Result<(), v01::GenericError>;
}
```

`HostAdmin` is already product-scoped and holds both collaborators it needs —
`authority: Arc<dyn ProductAuthority>` and `product_runtime: Arc<ProductRuntimeHost>`
— so reaching the work needs no new plumbing.

### Origin

```rust
pub enum HostAllowanceOrigin {
    StartupReadiness,
    ForegroundRenewal,
    Recovery,
}
```

`origin` is recorded in tracing and passed through to the host. It exists so the
runtime and the host can distinguish lifecycle moments without inventing a
product identity, and so a prompting policy can be added later without changing
any signature. The names mirror brevity's `HostAllowanceReason`, which lets that
module become a thin adapter rather than a rewrite.

### Consent

The admin path does not raise `UserConfirmationReview::ResourceAllocation`. That
review's contract is "a product asked for this, approve or decline", and no
product is asking. `ResourceAllocation::request` keeps it unchanged for products.

This deliberately moves the prompting decision into host code. That is the point:
a host that wants to ask the user about a first-ever grant can, and one doing
routine maintenance does not have to manufacture a bypass. It is also strictly
safer than the status quo, where the forged path already auto-approves — just
invisibly, and with a matching window that can catch a real product request.

### Status and invalidate

Both resolve against the existing per-role machinery:

- **Status** reads the `cached_*` accessors for cache and persisted-store
  presence, and can escalate to a chain probe through the already-public
  `truapi_server::statement_allowance` (`scan_collections`, `allocated_in`,
  `fetch_bulletin_allowance`). Cache-only is the cheap default.
- **Invalidate** surfaces `evict_bulletin_allowance_key`, the two
  `clear_*_allowance_keys` methods, and `allowances::remove_allowance_key`.

The caches live on the concrete runtimes rather than behind the trait, so both
need seams on `ProductAuthority`, implemented for `PairingHost` and `SigningHost`.
That trait already carries `refresh_bulletin_allowance_key`, so allowance
lifecycle is established as its concern and these are consistent additions.

The two roles mean different things by "status", and this is the part that needs
agreement before implementation:

- `PairingHost` holds keys obtained from the Account Holder over SSO, cached in
  memory and in `CoreStorage`. Presence is well defined, and eviction is exactly
  the `pub(super)` primitives above.
- `SigningHost` *is* the Account Holder. It provisions on demand through
  `sso_responder::allocate_*_allowance` with `OnExistingAllowancePolicy::Ignore`,
  so a key is always derivable and "cached presence" is not the right question. A
  meaningful status here is an on-chain slot probe, and a meaningful invalidate
  may be a no-op.

`AllowanceLifecycle` is status-only — `Active`, `Absent`, `Expired`,
`Unavailable { code }` — mirroring the model `allowance_admin.rs` arrived at
independently. `HostAllowanceResource` covers `StatementStore` and `Bulletin`,
the two the runtime administers.

**No type in this surface carries key material, statement bytes, or a chain
payload.** That is the discipline `allowance_admin.rs` holds itself to, and it is
what makes the surface safe to expose over UniFFI.

### Native surface

The methods get UniFFI exposure next to the renewal surface
[#308](https://github.com/paritytech/host-rust-core/pull/308) already ships
(`renew_statement_allowances`, `start_statement_allowance_renewal` in
`native.rs`). Renewal reaching the FFI while allocation and status stay Rust-only
is the asymmetry this closes: today a Swift or Kotlin host can keep an allowance
alive but cannot obtain one or ask about it.

## Implementation status

`allocate_allowances` and `HostAllowanceOrigin` are implemented in this change:
`ProductRuntimeHost::allocate_resources_for_host` calls
`ProductAuthority::allocate_resources` directly, with a unique correlation id per
call because the SSO channel matches responses on it. Tests cover the
no-session rejection, request-id uniqueness, and — asserting the product path
raises exactly one review first, so the check cannot pass vacuously — that the
host path raises none.

`allowance_status`, `invalidate_allowance` and the native bindings are not in
this change. Status and invalidate need the per-role semantics above settled
first, and the native surface is a separately CI-gated step
(`make uniffi && ios/truapi-host/scripts/sync-bindings.sh`, with committed
bindings). Landing allocation alone already removes both the forged frame and the
auto-confirm registry, which is the security-relevant half.

## Drawbacks

- **`HostAdmin` grows a third concern.** It is currently a small
  session-and-permissions handle. A separate `AllowanceAdmin` reachable from
  `HostAdmin` would keep it narrow, at the cost of one more type to discover.
  Both are source-compatible for callers going through `HostAdmin`.
- **Two paths to allocation.** Products go through the dispatcher with consent;
  hosts go direct. That is intended, but it puts the consent question in host
  code, where a careless host could allocate without ever asking. The
  counter-argument is that this is already true today, less visibly.
- **Status semantics differ per resource.** "Active" for Statement Store means a
  slot is allocated in the current period; for Bulletin it means allocated and
  inside expiry-plus-grace. One enum spanning two lifetimes invites misreading;
  the honest mitigation is documentation on each variant.

## Alternatives

- **A host-origin flag on the wire.** Rejected: it puts a host-only concept in
  the product protocol, and a product could then claim host origin.
- **Treat `statement_allowance` as the answer.** It is already public and
  `truapi-host-cli` administers allowances entirely through it
  (`register_pairing_allowances`, talking to chain over its own `RpcClient`). But
  those are free functions over a subxt client with no product scoping, no
  session awareness and no lifecycle model — usable from a Rust binary, not from
  a Swift host, and not an admin API. It is the right layer underneath this one,
  not a replacement.
- **Leave it downstream.** Viable while brevity-dozer is the only host that needs
  it. It stops being viable at the second host, and it leaves the consent
  matching window in place permanently.
- **Bless the dispatcher for host use.** The current workaround, promoted to a
  supported API. Rejected: it preserves the consent ambiguity, which is the
  problem worth solving.

## Unresolved Questions

- What does `allowance_status` mean on `SigningHost`, and is a chain probe in
  scope for the first cut or is cache-presence-plus-`Unavailable` acceptable?
- Should a host-origin allocation ever prompt? A first grant for a product the
  user has never seen is a plausible exception to "don't ask about maintenance".
- Should `allowance_status` expose the period boundary so hosts can schedule, or
  does #308's renewal scheduler already own scheduling?
- Does brevity's `AllowanceTarget::session_id` belong upstream? It exists because
  paired storage operations need a session id while a direct signing host does
  not; `HostAdmin` is already session-scoped, which may make it redundant.
- PGAS: brevity models it as a third resource kind, but RFC-0010 treats
  smart-contract allowance as an anonymous per-user claim rather than a slot
  table, and the runtime administers no PGAS state. Out of scope here — should it
  stay out?
