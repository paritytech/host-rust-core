//! Ring-VRF prover parameters, installed on demand.
//!
//! The proving stack needs one parameter set per ring domain, and the largest
//! is several MiB of incompressible data. Hosts that compile them in install
//! nothing here. Hosts that serve them do so once per domain, on the first
//! local proof that needs one, so a session that never proves never pays for
//! them.

use std::sync::Arc;

use sp_crypto_hashing::blake2_256;
use tracing::warn;
use truapi_platform::{RingProverDomain, RingProverParams};
use verifiable::ring::RingDomainSize;

/// Why a ring domain has no usable parameters.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub(crate) enum ParamsUnavailable {
    /// This host serves no parameters. Proving has to happen elsewhere.
    Unsupported,
    /// The host answered, but the bytes are not the pinned parameters.
    HashMismatch,
    /// The host failed to answer, or the bytes were not usable parameters.
    Failed,
}

/// Blake2b-256 of each domain's parameter blob, emitted by `truapi-srs-gen`.
///
/// Compiled-in parameters inherit the integrity of the core artifact; fetched
/// ones do not. A substituted SRS attacks the soundness and the anonymity of
/// every proof made with it, so bytes that do not match are refused. The
/// native test suite recomputes these from the compiled-in SRS, so drift is a
/// test failure rather than a browser that cannot prove.
const DOMAIN11_HASH: &str = "7a73571d3bbc32e972f4b47eceec633b1d897fa262f90181b594b3be8d26f527";
const DOMAIN12_HASH: &str = "cfaef391085a41b618337d6cd4d2cbfc3555cfe3faa1fb90a1cee10701c837d2";
const DOMAIN16_HASH: &str = "3a9b3ced347d5c56bdbb9042f9fff2acd9c8b61c27fe43a68b6d8b119027ff16";

/// Installs host-supplied parameters, once per ring domain.
pub(crate) struct RingProverParamsCache {
    host: Option<Arc<dyn RingProverParams>>,
    /// Domains already installed, guarded by an async lock so two proofs for
    /// the same domain wait on one request rather than racing two.
    installed: futures::lock::Mutex<[bool; RING_DOMAIN_COUNT]>,
}

/// Number of ring domains the protocol defines.
const RING_DOMAIN_COUNT: usize = 3;

impl RingProverParamsCache {
    /// Build a cache over the host's parameter source, if it has one.
    pub(crate) fn new(host: Option<Arc<dyn RingProverParams>>) -> Self {
        Self {
            host,
            installed: futures::lock::Mutex::new([false; RING_DOMAIN_COUNT]),
        }
    }

    /// Make sure `domain` has parameters installed.
    ///
    /// Returns immediately for a domain installed earlier in this session.
    pub(crate) async fn ensure(&self, domain: RingDomainSize) -> Result<(), ParamsUnavailable> {
        let Some(host) = self.host.as_ref() else {
            return Err(ParamsUnavailable::Unsupported);
        };

        let slot = domain_index(domain);
        let mut installed = self.installed.lock().await;
        if installed[slot] {
            return Ok(());
        }

        let bytes = host
            .load_ring_prover_params(platform_domain(domain))
            .await
            .map_err(|error| {
                warn!(
                    ?error,
                    ?domain,
                    "the host failed to serve ring prover parameters"
                );
                ParamsUnavailable::Failed
            })?
            .ok_or(ParamsUnavailable::Unsupported)?;

        if hex::encode(blake2_256(&bytes)) != expected_hash(domain) {
            warn!(
                ?domain,
                "ring prover parameters did not match the pinned hash"
            );
            return Err(ParamsUnavailable::HashMismatch);
        }

        verifiable::ring::bandersnatch::install_ring_setup(domain, &bytes).map_err(|error| {
            warn!(?error, ?domain, "ring prover parameters did not install");
            ParamsUnavailable::Failed
        })?;

        installed[slot] = true;
        Ok(())
    }
}

/// Position of a domain in the per-domain arrays.
fn domain_index(domain: RingDomainSize) -> usize {
    match domain {
        RingDomainSize::Domain11 => 0,
        RingDomainSize::Domain12 => 1,
        RingDomainSize::Domain16 => 2,
    }
}

/// The platform-facing spelling of a ring domain. The two enums meet here and
/// nowhere else, which is what keeps `truapi-platform` free of `verifiable`.
fn platform_domain(domain: RingDomainSize) -> RingProverDomain {
    match domain {
        RingDomainSize::Domain11 => RingProverDomain::Domain11,
        RingDomainSize::Domain12 => RingProverDomain::Domain12,
        RingDomainSize::Domain16 => RingProverDomain::Domain16,
    }
}

/// The parameter hash this build accepts for `domain`, lowercase hex.
fn expected_hash(domain: RingDomainSize) -> &'static str {
    match domain {
        RingDomainSize::Domain11 => DOMAIN11_HASH,
        RingDomainSize::Domain12 => DOMAIN12_HASH,
        RingDomainSize::Domain16 => DOMAIN16_HASH,
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use async_trait::async_trait;
    use futures::executor::block_on;
    use std::sync::atomic::{AtomicUsize, Ordering};
    use truapi::latest::GenericError;

    /// Host that serves whatever bytes it was built with, counting calls.
    struct ScriptedParams {
        bytes: Option<Vec<u8>>,
        calls: AtomicUsize,
    }

    impl ScriptedParams {
        fn serving(bytes: Vec<u8>) -> Arc<Self> {
            Arc::new(Self {
                bytes: Some(bytes),
                calls: AtomicUsize::new(0),
            })
        }

        fn serving_nothing() -> Arc<Self> {
            Arc::new(Self {
                bytes: None,
                calls: AtomicUsize::new(0),
            })
        }
    }

    #[async_trait]
    impl RingProverParams for ScriptedParams {
        async fn load_ring_prover_params(
            &self,
            _domain: RingProverDomain,
        ) -> Result<Option<Vec<u8>>, GenericError> {
            self.calls.fetch_add(1, Ordering::SeqCst);
            Ok(self.bytes.clone())
        }
    }

    #[test]
    fn a_host_without_the_capability_is_never_asked() {
        let cache = RingProverParamsCache::new(None);
        assert_eq!(
            block_on(cache.ensure(RingDomainSize::Domain11)),
            Err(ParamsUnavailable::Unsupported)
        );
    }

    #[test]
    fn parameters_that_miss_the_pinned_hash_are_refused() {
        let host = ScriptedParams::serving(vec![9u8; 64]);
        let cache = RingProverParamsCache::new(Some(host.clone()));

        assert_eq!(
            block_on(cache.ensure(RingDomainSize::Domain11)),
            Err(ParamsUnavailable::HashMismatch)
        );
        assert_eq!(
            host.calls.load(Ordering::SeqCst),
            1,
            "the host is asked once, and the answer is not installed"
        );
    }

    #[test]
    fn a_host_serving_no_bytes_for_the_domain_is_unsupported() {
        let host = ScriptedParams::serving_nothing();
        let cache = RingProverParamsCache::new(Some(host));
        assert_eq!(
            block_on(cache.ensure(RingDomainSize::Domain11)),
            Err(ParamsUnavailable::Unsupported)
        );
    }

    /// Native only: it cuts the parameters from the compiled-in SRS, which a
    /// wasm build does not have. That is the point of the pinning.
    ///
    /// Doubles as the check that the pinned hashes are the ones
    /// `truapi-srs-gen` emits: these parameters are cut from the compiled-in
    /// SRS the same way, so a mismatch fails here rather than in a browser.
    #[test]
    #[cfg(not(target_arch = "wasm32"))]
    fn genuine_parameters_install_once_and_are_not_fetched_again() {
        let host = ScriptedParams::serving(domain11_params());
        let cache = RingProverParamsCache::new(Some(host.clone()));

        assert_eq!(block_on(cache.ensure(RingDomainSize::Domain11)), Ok(()));
        assert_eq!(block_on(cache.ensure(RingDomainSize::Domain11)), Ok(()));
        assert_eq!(
            host.calls.load(Ordering::SeqCst),
            1,
            "a domain installed once is not fetched again"
        );
    }

    /// Domain11 parameters, built the way `truapi-srs-gen` builds them.
    #[cfg(not(target_arch = "wasm32"))]
    fn domain11_params() -> Vec<u8> {
        use verifiable::ring::RingCurveParams;
        use verifiable::ring::ark_vrf::reexports::ark_serialize::CanonicalSerialize;
        use verifiable::ring::ark_vrf::suites::bandersnatch::BandersnatchSha512Ell2;

        let srs = verifiable::ring::Bls12_381Params::srs_raw();
        let setup = verifiable::ring::ring_setup_from_srs::<BandersnatchSha512Ell2>(
            RingDomainSize::Domain11,
            srs,
        )
        .expect("the compiled-in SRS loads");
        let mut bytes = Vec::new();
        setup
            .pcs_params
            .serialize_uncompressed(&mut bytes)
            .expect("parameters serialize");
        bytes
    }
}
