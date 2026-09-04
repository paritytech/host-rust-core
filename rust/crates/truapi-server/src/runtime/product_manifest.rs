//! Root manifest resolution over dotNS.
//!
//! Resolves a product id to the JSON its base name publishes at the `manifest`
//! text record, following [RFC — Product Manifest Format][manifest]: derive the
//! node, find the resolver through the registry, read the record. Parsing that
//! JSON is [`crate::host_logic::product_manifest`]'s job.
//!
//! [manifest]: ../../../../docs/rfcs/product-manifest.md

use tracing::instrument;

use crate::chain_runtime::ChainRuntime;
use crate::host_logic::dotns_gateway::{
    DotnsTransport, DotnsViewError, call_bytes32, call_no_args, decode_address, decode_string,
    dispatcher_address_key, namehash_under, registry_key,
};
use crate::runtime::dotns_lookup::DotnsLookup;

/// Text record a base name publishes its root manifest at.
const MANIFEST_RECORD_KEY: &str = "manifest";

/// Reads `product_id`'s root manifest JSON.
///
/// `Ok(None)` means the product does not exist as far as dotNS is concerned:
/// either the node has no resolver, or its resolver holds no manifest record.
/// The two are one answer because a caller cannot act on the difference.
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

    let Some(registry) = dotns_registry(&mut lookup).await? else {
        return Ok(None);
    };

    let node = product_node(product_id);
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

/// Finds the dotNS name registry through the gateway's dispatcher and the
/// protocol registry it points at. `Ok(None)` when the gateway is not deployed.
async fn dotns_registry<T: DotnsTransport + ?Sized>(
    transport: &mut T,
) -> Result<Option<[u8; 20]>, String> {
    let Some(dispatcher) = transport.storage(dispatcher_address_key()).await? else {
        return Ok(None);
    };
    let dispatcher: [u8; 20] = dispatcher.try_into().map_err(|value: Vec<u8>| {
        format!("DotnsGateway.DispatcherAddress is {} bytes", value.len())
    })?;
    let protocol_output = transport
        .view(&dispatcher, call_no_args("protocolRegistry()"))
        .await
        .map_err(|err| format!("DotnsPopController.protocolRegistry(): {err}"))?;
    let protocol_registry = decode_address(&protocol_output)
        .map_err(|err| format!("DotnsPopController.protocolRegistry(): {err}"))?;
    let registry_output = transport
        .view(
            &protocol_registry,
            call_bytes32("get(bytes32)", &registry_key("registry")),
        )
        .await
        .map_err(|err| format!("ProtocolRegistry.get(registry): {err}"))?;
    decode_address(&registry_output)
        .map(Some)
        .map_err(|err| format!("ProtocolRegistry.get(registry): {err}"))
}

/// ENS-style node of a dotted product identifier, folded right to left from the
/// zero root so `dim2.dot` hashes as `dot` then `dim2` under it.
fn product_node(product_id: &str) -> [u8; 32] {
    product_id
        .rsplit('.')
        .fold([0u8; 32], |parent, label| namehash_under(&parent, label))
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

    #[test]
    fn a_product_node_matches_the_reference_derivation() {
        // Same fold the gateway's own namehash test pins, applied to a dotted
        // product id rather than a username label.
        let tld = namehash_under(&[0u8; 32], "paseo");
        assert_eq!(product_node("paseo"), tld);
        assert_eq!(
            product_node("alicebc.paseo"),
            namehash_under(&tld, "alicebc")
        );
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
