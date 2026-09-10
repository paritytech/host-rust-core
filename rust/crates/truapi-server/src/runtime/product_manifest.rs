//! Root manifest resolution over dotNS.
//!
//! Resolves a product id to the JSON its base name publishes at the `manifest`
//! text record, following [RFC — Product Manifest Format][manifest]: derive the
//! node under the network's own TLD, find the resolver through the registry,
//! read the record. Parsing that JSON is
//! [`crate::host_logic::product_manifest`]'s job.
//!
//! [manifest]: ../../../../docs/rfcs/product-manifest.md

use parity_scale_codec::{Decode, Encode};
use tracing::{debug, instrument, warn};
use truapi::v01;
use truapi_platform::{
    CoreStorageKey, HostChainSet, PermissionAuthorizationRequest, PermissionAuthorizationStatus,
    Platform, normalize_product_identifier,
};

use crate::chain_runtime::ChainRuntime;
use crate::host_logic::dotns_gateway::{
    DotnsTransport, DotnsViewError, call_bytes32, call_bytes32_string, call_no_args,
    decode_address, decode_string, discover_pop_controller, namehash_under, network_tld,
    protocol_component, tld_node,
};
use crate::host_logic::permissions::PermissionsService;
use crate::host_logic::product_manifest::{Granted, RootManifest, bare_product_label};
use crate::host_logic::sso::messages::RingVrfError;
use crate::host_logic::statement_store::current_unix_secs;
use crate::runtime::dotns_lookup::DotnsLookup;
use crate::runtime::services::RuntimeServices;

/// Text record a base name publishes its root manifest at.
const MANIFEST_RECORD_KEY: &str = "manifest";

/// Reads `product_id`'s root manifest JSON.
///
/// `Ok(None)` means the product does not exist as far as dotNS is concerned:
/// either the node has no resolver, or its resolver holds no manifest record.
/// The two are one answer because a caller cannot act on the difference.
///
/// The TLD the identifier carries is discarded and the node re-derived under
/// the TLD the network reports. A product id is minted on one network but
/// [`DOTNS_TLDS`][tlds] spans them all, so `dim2.dot` reaching a `.paseo`
/// deployment has to resolve there rather than hash a name no registry holds.
///
/// [tlds]: truapi_platform::DOTNS_TLDS
#[instrument(skip_all, fields(runtime.method = "product_manifest.fetch"))]
pub(crate) async fn fetch_root_manifest(
    chain: &ChainRuntime,
    asset_hub_chain_genesis_hash: [u8; 32],
    product_id: &str,
) -> Result<Option<String>, String> {
    let mut lookup = DotnsLookup::pinned_to_best_block(
        chain,
        asset_hub_chain_genesis_hash,
        &format!("manifest:{product_id}"),
    )
    .await?;

    let Some(protocol_registry) = protocol_registry(&mut lookup).await? else {
        return Ok(None);
    };

    let tld = network_tld(&mut lookup, &protocol_registry).await?;
    let node = namehash_under(&tld_node(&tld), bare_product_label(product_id));

    let registry = protocol_component(&mut lookup, &protocol_registry, "registry").await?;
    let resolver_output = lookup
        .view(&registry, call_bytes32("resolver(bytes32)", &node))
        .await
        .map_err(|err| format!("DotnsRegistry.resolver(): {err}"))?;
    let resolver = decode_address(&resolver_output)
        .map_err(|err| format!("DotnsRegistry.resolver(): {err}"))?;
    if resolver == [0u8; 20] {
        return Ok(None);
    }

    let manifest_output = match lookup
        .view(
            &resolver,
            call_bytes32_string("text(bytes32,string)", &node, MANIFEST_RECORD_KEY),
        )
        .await
    {
        Ok(output) => output,
        // The dotNS-issued default resolver does not implement `text`, which is
        // the same outcome as an unpublished manifest.
        Err(DotnsViewError::Reverted(_)) => return Ok(None),
        Err(err @ DotnsViewError::Failed(_)) => {
            return Err(format!("ContentResolver.text(): {err}"));
        }
    };
    let manifest =
        decode_string(&manifest_output).map_err(|err| format!("ContentResolver.text(): {err}"))?;
    if manifest.is_empty() {
        return Ok(None);
    }
    Ok(Some(manifest))
}

/// The deployment's `DotnsProtocolRegistry`, read from the controller.
/// `Ok(None)` when the gateway is not deployed.
///
/// [`discover_pop_controller`] resolves the controller, because
/// `DotnsGateway.DispatcherAddress` holds either the controller or a
/// `RootGatewayDispatcher` that fronts it, and both are in service. Calling
/// `protocolRegistry()` on the stored address directly reverts on a chain that
/// still keeps its dispatcher, which would refuse every grant on that chain
/// while username resolution kept working.
async fn protocol_registry<T: DotnsTransport + ?Sized>(
    transport: &mut T,
) -> Result<Option<[u8; 20]>, String> {
    let Some(controller) = discover_pop_controller(transport).await? else {
        return Ok(None);
    };
    let output = transport
        .view(&controller, call_no_args("protocolRegistry()"))
        .await
        .map_err(|err| format!("DotnsPopController.protocolRegistry(): {err}"))?;
    decode_address(&output)
        .map(Some)
        .map_err(|err| format!("DotnsPopController.protocolRegistry(): {err}"))
}

#[cfg(test)]
mod tests {
    use super::*;

    /// The node a product id resolves to on a network serving `tld`.
    fn node_on(tld: &str, product_id: &str) -> [u8; 32] {
        namehash_under(&tld_node(tld), bare_product_label(product_id))
    }

    #[test]
    fn a_node_matches_the_chain_derivation() {
        // Pinned against paseo-v2, where `ProtocolRegistry.tldNode()` reads
        // 0x096b43… and the dotNS SDK derives `browse.paseo` as 0x185056….
        assert_eq!(
            hex::encode(tld_node(".paseo")),
            "096b436ee9a398429fe33ad4b359bad4398dd74b412ec1dd043c93dfbf581874"
        );
        assert_eq!(
            hex::encode(node_on(".paseo", "browse")),
            "1850561ffded63ac23dac8fd5e793fca1f349729ed6ade91c45f44a9f7b6b781"
        );
    }

    #[test]
    fn the_tld_an_identifier_carries_does_not_change_the_node_it_resolves_to() {
        // A product id minted on `.dot` has to resolve against a `.paseo`
        // deployment; the suffix it was written with names no node of its own.
        let expected = node_on(".paseo", "dim2");
        assert_eq!(node_on(".paseo", "dim2.dot"), expected);
        assert_eq!(node_on(".paseo", "dim2.paseo"), expected);
    }

    #[test]
    fn one_identifier_resolves_differently_on_two_networks() {
        // The other half of the same property: the network's TLD is what
        // separates deployments, so the same id must not collide across them.
        assert_ne!(node_on(".paseo", "dim2.dot"), node_on(".dot", "dim2.dot"));
    }

    #[test]
    fn a_text_call_encodes_the_key_as_a_dynamic_argument() {
        let call = call_bytes32_string("text(bytes32,string)", &[0x11; 32], "manifest");
        // selector, node, offset, length, one padded word for an 8-byte key.
        assert_eq!(call.len(), 4 + 32 * 4);
        assert_eq!(&call[4..36], &[0x11; 32]);
        assert_eq!(call[67], 64, "key offset follows the node");
        assert_eq!(call[99], 8, "key length precedes its bytes");
        assert_eq!(&call[100..108], b"manifest");
    }
}

/// How long a cached root manifest is honoured.
///
/// This is a revocation bound, not a performance knob: dotNS attaches no signal
/// to a record edit, so a grant a publisher withdraws stays in force until the
/// manifest is read again.
pub(crate) const MANIFEST_TTL_SECS: u64 = 24 * 60 * 60;

/// A cached root manifest lookup and when it was made.
///
/// The document is stored verbatim rather than reduced to the grants this core
/// reads today, so a later consumer needs no cache migration.
#[derive(Debug, Clone, PartialEq, Eq, Encode, Decode)]
pub(crate) struct CachedManifest {
    /// Seconds since the Unix epoch at which the lookup was made.
    pub(crate) fetched_at_secs: u64,
    /// The manifest JSON exactly as published, or `None` where the chain
    /// answered that the product publishes none.
    ///
    /// A miss is cached because refusing is the common outcome: without it every
    /// refused call reopens a chainHead follow and re-reads the contracts, and
    /// the round trip tells the caller which targets have a manifest and which
    /// do not — the distinction one uniform refusal exists to hide.
    pub(crate) json: Option<String>,
}

/// Encode a root manifest the way the core caches it, for a host that seeds a
/// grant instead of resolving one.
///
/// Write the bytes under [`CoreStorageKey::ProductManifest`] for the product the
/// manifest belongs to. The core reads that entry before it consults the Asset
/// Hub, so a seeded manifest answers a grant on a host with no dotNS access at
/// all — which is what makes a cross-product flow reachable locally, before
/// either product is deployed.
///
/// `json` is `None` for a product that publishes no manifest, the outcome the
/// core caches for the same lifetime as a document. `fetched_at_secs` is when
/// the lookup counts as having happened: the current time for a live entry, or
/// something older than the cache lifetime to exercise a grant expiring.
///
/// A development and testing seam. Nothing enforces that a seeded manifest
/// matches what the product actually publishes, so a host offering this owes
/// the developer a way to tell the two apart.
pub fn encode_cached_root_manifest(json: Option<&str>, fetched_at_secs: u64) -> Vec<u8> {
    CachedManifest {
        fetched_at_secs,
        json: json.map(str::to_string),
    }
    .encode()
}

/// Scopes `target`'s published manifest grants `caller_id`.
///
/// A grant that cannot be established answers `false` whatever the reason — the
/// product does not resolve, it published no manifest, the fetch failed, or the
/// manifest names this caller with a narrower scope. Callers turn that into one
/// refusal, so the outcome never reveals which of those it was. Failing closed
/// also means an unreachable chain withdraws grants rather than assuming them.
///
pub(crate) async fn grants_scope(
    services: &RuntimeServices,
    platform: &dyn Platform,
    caller_id: &str,
    target: &str,
    scope: Granted,
) -> bool {
    // A publisher's grant waives the publisher's own prompt. It does not reach
    // a refusal the user already gave, so the stored decision is consulted
    // first, read-only: raising the prompt here would turn a grant into a way
    // to ask again.
    if scope == Granted::Context && user_denied_account_access(platform, caller_id, target).await {
        return false;
    }
    let Some(json) = root_manifest(services, platform, target).await else {
        return false;
    };
    let Ok(manifest) = RootManifest::parse(&json) else {
        return false;
    };
    manifest.grants(bare_product_label(caller_id), scope)
}

/// Warn when the Asset Hub hash this host was *configured* with is not the one
/// it *serves*.
///
/// There are two sources of truth for Asset Hub on the signing role and they
/// are not reconciled anywhere. `SigningHostConfig::asset_hub` is a hash the
/// embedder supplies, and it reaches `platform.connect()` with only a length
/// check — nothing verifies it is an Asset Hub at all. The PGAS path next door
/// in `sso_responder::allocate_smart_contract_allowance` instead derives it
/// from `features::supported_chains`, and its doc comment argues for that
/// precisely so a host cannot claim "against whatever chain a stale hash
/// happens to reach".
///
/// Both can be live at once. A host whose config and `supported_chains()`
/// disagree resolves manifests from one chain's dotNS while allocating PGAS on
/// another, so whoever holds the product name on the other network's registry
/// decides who may read the victim product's storage.
///
/// Run once per runtime, spawned at construction rather than awaited from a
/// manifest lookup. On the native hosts `supported_chains` is a synchronous
/// UniFFI callback with no timeout, so awaiting it on the lookup path would let
/// a slow or wedged host stall a grant decision for a diagnostic.
///
/// This does not pick a winner — the configured hash still wins, as #660
/// specifies — it only makes the divergence audible instead of silent. Which
/// source should be authoritative is a design question for #660/#454.
pub(crate) async fn warn_if_asset_hub_disagrees_with_chain_set(
    platform: &dyn Platform,
    configured: [u8; 32],
) {
    use crate::host_logic::features;

    // A host that cannot answer `supported_chains` is not evidence of a
    // mismatch, so stay quiet rather than cry wolf on an unrelated failure.
    let Ok(chains) = features::supported_chains(platform).await else {
        return;
    };
    match asset_hub_agreement(&chains, configured) {
        AssetHubAgreement::Diverges { served } => warn!(
            configured = %hex::encode(configured),
            served = %hex::encode(served),
            "the configured Asset Hub genesis hash is not the one this host \
             serves: manifest grants resolve against the configured chain \
             while PGAS is allocated on the served one"
        ),
        AssetHubAgreement::NotServed => warn!(
            configured = %hex::encode(configured),
            "an Asset Hub genesis hash is configured but this host's chain set \
             serves no Asset Hub"
        ),
        AssetHubAgreement::Agrees => {}
    }
}

/// What comparing the configured Asset Hub against the host's chain set found.
#[derive(Debug, PartialEq, Eq)]
enum AssetHubAgreement {
    /// The host serves the hash it was configured with.
    Agrees,
    /// The host serves a different Asset Hub than the one configured.
    Diverges {
        /// The hash the host's chain set reports.
        served: [u8; 32],
    },
    /// The host's chain set carries no Asset Hub at all.
    NotServed,
}

/// The comparison behind [`warn_if_asset_hub_disagrees_with_chain_set`], split
/// out so it can be tested without a log capture: the wrapper is then only the
/// `supported_chains` call and the wording.
fn asset_hub_agreement(chains: &HostChainSet, configured: [u8; 32]) -> AssetHubAgreement {
    use truapi::latest::ChainIdentifier;

    use crate::host_logic::features;

    match features::genesis_for(chains, ChainIdentifier::AssetHub) {
        Some(served) if served == configured => AssetHubAgreement::Agrees,
        Some(served) => AssetHubAgreement::Diverges { served },
        None => AssetHubAgreement::NotServed,
    }
}

/// Whether the user has already refused `caller_id` access to `target`'s account.
///
/// Reads the stored decision without raising a prompt: `NotDetermined` is not a
/// refusal, and the prompt that would settle it belongs to the call the user
/// actually made, not to a grant lookup.
async fn user_denied_account_access(
    platform: &dyn Platform,
    caller_id: &str,
    target: &str,
) -> bool {
    let request = PermissionAuthorizationRequest::AccountAccess {
        target_product_id: target.to_string(),
    };
    let service = PermissionsService::new(platform, platform, caller_id);
    matches!(
        service.authorization_status(&request).await,
        Ok(PermissionAuthorizationStatus::Denied)
    )
}

/// Whether `calling_product_id` may act on `handle`'s ring-VRF key, adjudicated
/// by the component that holds the key.
///
/// The caller owns the key, or the owner's published manifest grants the caller
/// `context` and the user has not already refused, resolved against the chain
/// here rather than accepted from the request. On a paired host the request
/// arrives over the wire, and a verdict relayed by the caller would take the
/// manifest out of this decision entirely: the peer would reach every handle on
/// the device by setting one field, instead of only the handles a publisher
/// really granted.
///
/// The owner check runs first and costs nothing, so a product proving with its
/// own key never touches the network. Everything after it is a cross-product
/// access, and every reason it is refused answers the same way.
pub(crate) async fn ring_vrf_key_access_granted(
    services: &RuntimeServices,
    platform: &dyn Platform,
    calling_product_id: &str,
    handle: &v01::ProductAccountId,
) -> Result<(), RingVrfError> {
    let caller = normalize_product_identifier(calling_product_id).map_err(|error| {
        RingVrfError::Unknown {
            reason: error.to_string(),
        }
    })?;
    // The handle is normalized here, not only at the frontend. The frontend
    // does it before delegating, but `sso_responder` hands a wire request
    // straight to the authority unnormalized, so without this the two doors
    // disagree: an owner naming its own key `PEOPL.DOT` over the wire is
    // refused where the same request from a local product runtime succeeds.
    //
    // A handle that does not normalize names no product, so it owns no key and
    // no manifest can grant it: it takes the same refusal as a product that
    // granted nothing, rather than a distinguishable error.
    let Ok(owner) = normalize_product_identifier(&handle.dot_ns_identifier) else {
        return Err(RingVrfError::NotAllowlisted);
    };
    if caller == owner {
        return Ok(());
    }
    if grants_scope(services, platform, &caller, &owner, Granted::Context).await {
        return Ok(());
    }
    // The wire answer is one refusal for every reason, so the reason lives here
    // or nowhere. Which door the request came through is not repeated: the
    // enclosing span already says it (`account.*` for a local product runtime,
    // `sso_responder.*` for a paired peer).
    //
    // That span is also what says how far to trust `caller`. Under `account.*`
    // it is the product id the host bound to the connection. Under
    // `sso_responder.*` it is `calling_product_id` as decoded from the peer's
    // message: what the authenticated paired host said, not something this host
    // verified. The refusal is sound either way, because the grant is resolved
    // from the owner's manifest and never from this field, but an operator
    // reading the line should not take it as proof of who asked.
    debug!(
        caller = %caller,
        owner = %owner,
        "ring-VRF key access refused: no context grant"
    );
    Err(RingVrfError::NotAllowlisted)
}

/// `target`'s root manifest JSON, from cache when it is younger than
/// [`MANIFEST_TTL_SECS`] and from dotNS otherwise.
///
/// A freshly read manifest is cached even though the caller may not be granted
/// anything by it: the document describes the product, not the asker. So is the
/// chain's answer that there is no manifest, which is authoritative for the same
/// TTL.
///
/// A failed lookup is not cached. It says nothing about the product, only that
/// the chain could not be read, and holding that for a day would turn one blip
/// into a day of withdrawn grants.
///
/// The cache dedupes misses only once one has *finished*. Concurrent misses for
/// the same target each open their own dotNS follow, and nothing upstream caps
/// how many dispatches a product may have in flight, so a product can hold N
/// follows for up to `OPERATION_TIMEOUT` each. That shape predates this path —
/// `ProductRuntime::in_flight` and the `ws_bridge` task spawn are both
/// uncapped — but a chain round trip per request makes each one dearer than it
/// was. A real fix is a single-flight keyed by target, or a dispatch
/// concurrency cap; both belong with the request pipeline rather than here.
async fn root_manifest(
    services: &RuntimeServices,
    platform: &dyn Platform,
    target: &str,
) -> Option<String> {
    let key = CoreStorageKey::ProductManifest {
        product_id: target.to_string(),
    };
    let now = current_unix_secs();
    if let Ok(Some(bytes)) = platform.read_core_storage(key.clone()).await
        && let Ok(cached) = CachedManifest::decode(&mut bytes.as_slice())
        && now.saturating_sub(cached.fetched_at_secs) < MANIFEST_TTL_SECS
    {
        return cached.json;
    }

    let genesis_hash = services.asset_hub_chain_genesis_hash()?;
    let json = match fetch_root_manifest(&services.chain, genesis_hash, target).await {
        Ok(json) => json,
        Err(reason) => {
            warn!(%target, %reason, "root manifest lookup failed");
            return None;
        }
    };
    let _ = platform
        .write_core_storage(
            key,
            CachedManifest {
                fetched_at_secs: now,
                json: json.clone(),
            }
            .encode(),
        )
        .await;
    json
}

#[cfg(test)]
mod asset_hub_agreement_tests {
    use truapi::latest::ChainIdentifier;
    use truapi_platform::{HostChainEntry, HostChainSet};

    use super::{AssetHubAgreement, asset_hub_agreement};

    /// A host chain set serving `chains`.
    fn chain_set(chains: &[(ChainIdentifier, [u8; 32])]) -> HostChainSet {
        HostChainSet {
            network: "paseo".to_string(),
            chains: chains
                .iter()
                .map(|(identifier, genesis_hash)| HostChainEntry {
                    identifier: *identifier,
                    genesis_hash: *genesis_hash,
                })
                .collect(),
        }
    }

    #[test]
    fn a_host_serving_the_configured_asset_hub_agrees() {
        let chains = chain_set(&[(ChainIdentifier::AssetHub, [0xcc; 32])]);
        assert_eq!(
            asset_hub_agreement(&chains, [0xcc; 32]),
            AssetHubAgreement::Agrees
        );
    }

    #[test]
    fn a_host_serving_a_different_asset_hub_diverges() {
        // The case the warning exists for: manifests resolve against the
        // configured registry while PGAS is allocated on the served one, so
        // whoever holds the product name on the other network decides who may
        // read this product's storage.
        let chains = chain_set(&[(ChainIdentifier::AssetHub, [0xdd; 32])]);
        assert_eq!(
            asset_hub_agreement(&chains, [0xcc; 32]),
            AssetHubAgreement::Diverges { served: [0xdd; 32] },
            "a served hash that differs from the configured one is the divergence"
        );
    }

    #[test]
    fn a_host_serving_no_asset_hub_is_not_silently_agreement() {
        // Distinct from `Agrees`: reporting no Asset Hub while one is
        // configured is its own misconfiguration, and collapsing it into
        // agreement would silence exactly the host that cannot serve manifests.
        let chains = chain_set(&[(ChainIdentifier::People, [0xaa; 32])]);
        assert_eq!(
            asset_hub_agreement(&chains, [0xcc; 32]),
            AssetHubAgreement::NotServed
        );
    }

    #[test]
    fn the_comparison_reads_asset_hub_and_not_whatever_is_first() {
        // `genesis_for` searches by identifier. A lookup that took the first
        // entry instead would agree here by accident, since People carries the
        // configured value and Asset Hub does not.
        let chains = chain_set(&[
            (ChainIdentifier::People, [0xcc; 32]),
            (ChainIdentifier::AssetHub, [0xdd; 32]),
        ]);
        assert_eq!(
            asset_hub_agreement(&chains, [0xcc; 32]),
            AssetHubAgreement::Diverges { served: [0xdd; 32] },
            "the People entry carrying the configured hash must not mask the divergence"
        );
    }
}
