//! Root manifest resolution over dotNS.
//!
//! Resolves a product id to the JSON its base name publishes at the `manifest`
//! text record, following [RFC — Product Manifest Format][manifest]: derive the
//! node under the network's own TLD, find the resolver through the registry,
//! read the record. Parsing that JSON is
//! [`crate::host_logic::product_manifest`]'s job.
//!
//! [manifest]: ../../../../docs/rfcs/product-manifest.md

use tracing::instrument;

use crate::chain_runtime::ChainRuntime;
use crate::host_logic::dotns_gateway::{
    DotnsTransport, DotnsViewError, call_bytes32, call_no_args, decode_address, decode_string,
    dispatcher_address_key, namehash_under, network_tld, registry_key, tld_node,
};
use crate::host_logic::product_manifest::bare_product_label;
use crate::runtime::dotns_lookup::DotnsLookup;

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
        .view(&resolver, call_text_record(&node, MANIFEST_RECORD_KEY))
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

/// The deployment's `DotnsProtocolRegistry`, found through the gateway's
/// dispatcher. `Ok(None)` when the gateway is not deployed.
async fn protocol_registry<T: DotnsTransport + ?Sized>(
    transport: &mut T,
) -> Result<Option<[u8; 20]>, String> {
    let Some(dispatcher) = transport.storage(dispatcher_address_key()).await? else {
        return Ok(None);
    };
    let dispatcher: [u8; 20] = dispatcher.try_into().map_err(|value: Vec<u8>| {
        format!("DotnsGateway.DispatcherAddress is {} bytes", value.len())
    })?;
    let output = transport
        .view(&dispatcher, call_no_args("protocolRegistry()"))
        .await
        .map_err(|err| format!("DotnsPopController.protocolRegistry(): {err}"))?;
    decode_address(&output)
        .map(Some)
        .map_err(|err| format!("DotnsPopController.protocolRegistry(): {err}"))
}

/// One component address out of the protocol registry's address book, so a
/// rotated implementation is picked up without a change here.
async fn protocol_component<T: DotnsTransport + ?Sized>(
    transport: &mut T,
    protocol_registry: &[u8; 20],
    name: &str,
) -> Result<[u8; 20], String> {
    let output = transport
        .view(
            protocol_registry,
            call_bytes32("get(bytes32)", &registry_key(name)),
        )
        .await
        .map_err(|err| format!("ProtocolRegistry.get({name}): {err}"))?;
    decode_address(&output).map_err(|err| format!("ProtocolRegistry.get({name}): {err}"))
}

/// ABI calldata for `text(bytes32 node, string key)`.
///
/// The key is a dynamic argument, so it is passed by offset with its length
/// ahead of the padded bytes.
fn call_text_record(node: &[u8; 32], key: &str) -> Vec<u8> {
    let mut input = crate::host_logic::dotns_gateway::selector("text(bytes32,string)").to_vec();
    input.extend_from_slice(node);
    let mut offset = [0u8; 32];
    offset[24..].copy_from_slice(&64u64.to_be_bytes());
    input.extend_from_slice(&offset);
    let mut length = [0u8; 32];
    length[24..].copy_from_slice(&(key.len() as u64).to_be_bytes());
    input.extend_from_slice(&length);
    let mut padded = key.as_bytes().to_vec();
    padded.resize(key.len().div_ceil(32) * 32, 0);
    input.extend_from_slice(&padded);
    input
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
        let call = call_text_record(&[0x11; 32], "manifest");
        // selector, node, offset, length, one padded word for an 8-byte key.
        assert_eq!(call.len(), 4 + 32 * 4);
        assert_eq!(&call[4..36], &[0x11; 32]);
        assert_eq!(call[67], 64, "key offset follows the node");
        assert_eq!(call[99], 8, "key length precedes its bytes");
        assert_eq!(&call[100..108], b"manifest");
    }
}
