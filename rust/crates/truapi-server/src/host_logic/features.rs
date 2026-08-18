//! Feature-detection delegation.
//!
//! `feature_supported` and `supported_chains` are platform syscalls: each
//! host owns the set of chains it can service. This module is a thin shim
//! that forwards through to [`truapi_platform::Features`], plus the in-core
//! RFC-0026 resolution that answers `get_chain_info` from the host's chain
//! set so per-request semantics (ordering, `NotSupported`) stay core-owned,
//! and the RFC-0027 resolution that answers `Method` support queries from
//! the wire table. Only `Chain` queries reach the platform.

use truapi::latest::{
    ChainIdentifier, RemoteChainInfoError, RemoteChainInfoRequest, RemoteChainInfoResponse,
};
use truapi::v01::{GenericError, HostFeatureSupportedRequest, HostFeatureSupportedResponse};
use truapi_platform::{Features, HostChainSet};

/// Answer a feature-support query. `Chain` forwards to the platform;
/// `Method` (RFC 0027) is answered from the wire table, so no host learns
/// wire discriminants.
pub async fn feature_supported<P: Features + ?Sized>(
    platform: &P,
    request: HostFeatureSupportedRequest,
) -> Result<HostFeatureSupportedResponse, GenericError> {
    match request {
        HostFeatureSupportedRequest::Method { id } => Ok(HostFeatureSupportedResponse {
            supported: crate::frame::method_entry_registered(id),
        }),
        request @ HostFeatureSupportedRequest::Chain { .. } => {
            platform.feature_supported(request).await
        }
    }
}

/// Fetch the host's chain set from the platform implementation.
pub async fn supported_chains<P: Features + ?Sized>(
    platform: &P,
) -> Result<HostChainSet, GenericError> {
    platform.supported_chains().await
}

/// The genesis hash the host serves for `chain`, or `None` when it serves no
/// such chain.
///
/// Runtime code that needs to talk to a chain by role resolves it here rather
/// than carrying a configured hash, so a chain the host does not serve is a
/// missing entry instead of a connection to the wrong chain.
pub fn genesis_for(set: &HostChainSet, chain: ChainIdentifier) -> Option<[u8; 32]> {
    set.chains
        .iter()
        .find(|entry| entry.identifier == chain)
        .map(|entry| entry.genesis_hash)
}

/// Resolve a `get_chain_info` request against the host's chain set: the
/// requested identifier's genesis hash plus the host's network, echoing the
/// identifier, or `NotSupported` when the host does not serve it.
pub fn chain_info(
    set: &HostChainSet,
    request: &RemoteChainInfoRequest,
) -> Result<RemoteChainInfoResponse, RemoteChainInfoError> {
    genesis_for(set, request.chain)
        .map(|genesis_hash| RemoteChainInfoResponse {
            network: set.network.clone(),
            chain: request.chain,
            genesis_hash,
        })
        .ok_or(RemoteChainInfoError::NotSupported)
}

#[cfg(test)]
mod tests {
    use super::*;
    use truapi::latest::ChainIdentifier;
    use truapi_platform::HostChainEntry;

    fn paseo_set() -> HostChainSet {
        HostChainSet {
            network: "paseo".to_string(),
            chains: vec![
                HostChainEntry {
                    identifier: ChainIdentifier::AssetHub,
                    genesis_hash: [0xaa; 32],
                },
                HostChainEntry {
                    identifier: ChainIdentifier::People,
                    genesis_hash: [0xbb; 32],
                },
            ],
        }
    }

    struct AlwaysSupported;

    #[truapi_platform::async_trait]
    impl Features for AlwaysSupported {
        async fn feature_supported(
            &self,
            request: HostFeatureSupportedRequest,
        ) -> Result<HostFeatureSupportedResponse, GenericError> {
            assert!(matches!(request, HostFeatureSupportedRequest::Chain { .. }));
            Ok(HostFeatureSupportedResponse { supported: true })
        }

        async fn supported_chains(&self) -> Result<HostChainSet, GenericError> {
            Ok(paseo_set())
        }
    }

    struct AlwaysUnsupported;

    #[truapi_platform::async_trait]
    impl Features for AlwaysUnsupported {
        async fn feature_supported(
            &self,
            request: HostFeatureSupportedRequest,
        ) -> Result<HostFeatureSupportedResponse, GenericError> {
            assert!(matches!(request, HostFeatureSupportedRequest::Chain { .. }));
            Ok(HostFeatureSupportedResponse { supported: false })
        }

        async fn supported_chains(&self) -> Result<HostChainSet, GenericError> {
            Err(GenericError {
                reason: "no chains".to_string(),
            })
        }
    }

    fn req() -> HostFeatureSupportedRequest {
        HostFeatureSupportedRequest::Chain {
            genesis_hash: vec![0u8; 32],
        }
    }

    #[test]
    fn delegates_supported_to_platform() {
        let resp = futures::executor::block_on(feature_supported(&AlwaysSupported, req())).unwrap();
        assert!(resp.supported);
    }

    #[test]
    fn delegates_unsupported_to_platform() {
        let resp =
            futures::executor::block_on(feature_supported(&AlwaysUnsupported, req())).unwrap();
        assert!(!resp.supported);
    }

    #[test]
    fn delegates_supported_chains_to_platform() {
        let set = futures::executor::block_on(supported_chains(&AlwaysSupported)).unwrap();
        assert_eq!(set, paseo_set());
    }

    #[test]
    fn surfaces_supported_chains_platform_error() {
        let err = futures::executor::block_on(supported_chains(&AlwaysUnsupported)).unwrap_err();
        assert_eq!(err.reason, "no chains");
    }

    #[test]
    fn resolves_identifier_and_echoes_it() {
        let request = RemoteChainInfoRequest {
            chain: ChainIdentifier::People,
        };
        let response = chain_info(&paseo_set(), &request).unwrap();
        assert_eq!(response.network, "paseo");
        assert_eq!(response.chain, ChainIdentifier::People);
        assert_eq!(response.genesis_hash, [0xbb; 32]);
    }

    #[test]
    fn unserved_identifier_is_not_supported() {
        let request = RemoteChainInfoRequest {
            chain: ChainIdentifier::Bulletin,
        };
        let err = chain_info(&paseo_set(), &request).unwrap_err();
        assert_eq!(err, RemoteChainInfoError::NotSupported);
    }

    #[test]
    fn request_and_start_ids_answer_true() {
        let request_id = crate::frame::request_ids("system_feature_supported")
            .expect("known request method")
            .request_id;
        let start_id = crate::frame::subscription_ids("chain_follow_head_subscribe")
            .expect("known subscription method")
            .start_id;

        for id in [request_id, start_id] {
            let resp = futures::executor::block_on(feature_supported(
                &AlwaysUnsupported,
                HostFeatureSupportedRequest::Method { id },
            ))
            .unwrap();
            assert!(resp.supported, "id {id} opens a method");
        }
    }

    #[test]
    fn non_entry_and_unallocated_ids_answer_false() {
        use crate::generated::wire_table::CHAT_CUSTOM_MESSAGE_RENDER;

        let response_id = crate::frame::request_ids("system_feature_supported")
            .expect("known request method")
            .response_id;
        let sub_ids = crate::frame::subscription_ids("chain_follow_head_subscribe")
            .expect("known subscription method");

        for id in [
            response_id,
            sub_ids.stop_id,
            sub_ids.interrupt_id,
            sub_ids.receive_id,
            CHAT_CUSTOM_MESSAGE_RENDER.start_id,
            0xFA,
        ] {
            let resp = futures::executor::block_on(feature_supported(
                &AlwaysSupported,
                HostFeatureSupportedRequest::Method { id },
            ))
            .unwrap();
            assert!(!resp.supported, "id {id} does not open a method");
        }
    }
}

#[cfg(test)]
mod genesis_lookup_tests {
    use super::*;
    use truapi_platform::HostChainEntry;

    fn set() -> HostChainSet {
        HostChainSet {
            network: "paseo".to_string(),
            chains: vec![HostChainEntry {
                identifier: ChainIdentifier::AssetHub,
                genesis_hash: [0xab; 32],
            }],
        }
    }

    /// A chain the host does not serve is absent, not a different chain's hash.
    #[test]
    fn only_served_chains_resolve() {
        assert_eq!(
            genesis_for(&set(), ChainIdentifier::AssetHub),
            Some([0xab; 32])
        );
        assert_eq!(genesis_for(&set(), ChainIdentifier::Bulletin), None);
    }

    /// `chain_info` answers from the same lookup, so the product-facing method and
    /// in-core callers cannot disagree about what the host serves.
    #[test]
    fn chain_info_agrees_with_the_lookup() {
        let set = set();
        for chain in [ChainIdentifier::AssetHub, ChainIdentifier::People] {
            let request = RemoteChainInfoRequest { chain };
            assert_eq!(
                chain_info(&set, &request)
                    .ok()
                    .map(|info| info.genesis_hash),
                genesis_for(&set, chain),
            );
        }
    }
}
