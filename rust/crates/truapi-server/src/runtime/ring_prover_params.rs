//! Ring-VRF prover parameters, read on the first proof that needs them.
//!
//! A prover needs one set of powers of tau per ring domain, and the largest
//! runs to several MiB of incompressible data: more than the rest of the
//! browser core put together, for a capability most sessions never reach.
//! Targets that can afford them compile them in and never do anything here.
//! The browser cannot, so each domain's parameters are published beside the
//! core's own WASM and read from there when a product first asks this host to
//! prove.
//!
//! Nothing outside this module takes part. The parameters are the core's own
//! asset, addressed by a hash this build pins, so no host implements a
//! capability for them and no artifact carries a manifest describing them.

/// This host cannot prove for a ring domain: it has no parameters for that
/// domain and could not obtain any. A role with a paired signer delegates the
/// proof; a role without one reports it.
#[derive(Debug)]
#[cfg_attr(not(target_arch = "wasm32"), allow(dead_code))]
pub(in crate::runtime) struct Unavailable;

/// Make sure `domain` has prover parameters installed.
///
/// A build that compiles them in has nothing to do, so the answer is always
/// `Ok`.
#[cfg(not(target_arch = "wasm32"))]
pub(in crate::runtime) async fn ensure(
    _domain: verifiable::ring::RingDomainSize,
) -> Result<(), Unavailable> {
    Ok(())
}

#[cfg(target_arch = "wasm32")]
pub(in crate::runtime) use browser::ensure;

/// Blake2b-256 of each domain's parameter file, as `truapi-srs-gen` emits it.
///
/// This is both halves of the contract: the first eight characters name the
/// file to read, and the whole hash is what its bytes must come to. Compiled-in
/// parameters inherit the integrity of the core artifact and fetched ones do
/// not, and a substituted SRS attacks the soundness and the anonymity of every
/// proof made under it, so bytes that hash to anything else are refused.
///
/// Present natively only for the test that recomputes them from the
/// compiled-in SRS, so a generator that drifts fails the test suite rather
/// than the browser.
#[cfg(any(target_arch = "wasm32", test))]
mod pinned {
    use verifiable::ring::RingDomainSize;

    const DOMAIN11: &str = "7a73571d3bbc32e972f4b47eceec633b1d897fa262f90181b594b3be8d26f527";
    const DOMAIN12: &str = "cfaef391085a41b618337d6cd4d2cbfc3555cfe3faa1fb90a1cee10701c837d2";
    const DOMAIN16: &str = "3a9b3ced347d5c56bdbb9042f9fff2acd9c8b61c27fe43a68b6d8b119027ff16";

    /// The parameter hash this build accepts for `domain`, lowercase hex.
    pub(super) fn hash(domain: RingDomainSize) -> &'static str {
        match domain {
            RingDomainSize::Domain11 => DOMAIN11,
            RingDomainSize::Domain12 => DOMAIN12,
            RingDomainSize::Domain16 => DOMAIN16,
        }
    }

    /// Name of the file carrying `domain`'s parameters, which is the hash the
    /// bytes have to come to.
    pub(super) fn file(domain: RingDomainSize) -> String {
        format!("srs-domain{}-{}.bin", domain.as_power(), &hash(domain)[..8])
    }
}

#[cfg(target_arch = "wasm32")]
mod browser {
    use super::{Unavailable, pinned};

    use futures::lock::Mutex;
    use js_sys::Uint8Array;
    use send_wrapper::SendWrapper;
    use sp_crypto_hashing::blake2_256;
    use std::sync::OnceLock;
    use tracing::warn;
    use verifiable::ring::RingDomainSize;
    use wasm_bindgen::JsCast;
    use wasm_bindgen::prelude::*;

    // Resolved against this snippet's own URL, which wasm-bindgen emits two
    // directories below the core's WASM. `make wasm` fails the build if that
    // stops being true.
    #[wasm_bindgen(inline_js = r#"
export async function readCoreAsset(file) {
  const url = new URL("../../" + file, import.meta.url);
  // The files are named by content, so a cached one can never be stale and
  // the HTTP cache makes this one read per browser rather than per session.
  const response = await fetch(url, { cache: "force-cache" });
  if (!response.ok) throw new Error(`${url}: ${response.status} ${response.statusText}`);
  return new Uint8Array(await response.arrayBuffer());
}
"#)]
    extern "C" {
        #[wasm_bindgen(js_name = readCoreAsset)]
        fn read_core_asset(file: &str) -> js_sys::Promise;
    }

    /// Domains installed so far, behind an async lock so two proofs for one
    /// domain wait on a single read rather than racing two.
    ///
    /// Installing is process-wide, as the prover's own setup cells are, so
    /// every runtime in the worker shares this.
    static INSTALLED: OnceLock<Mutex<[bool; RingDomainSize::VARIANTS.len()]>> = OnceLock::new();

    /// Make sure `domain` has prover parameters installed.
    ///
    /// Returns immediately for a domain installed earlier in this worker.
    pub(in crate::runtime) async fn ensure(domain: RingDomainSize) -> Result<(), Unavailable> {
        let slot = domain as usize;
        let mut installed = INSTALLED
            .get_or_init(|| Mutex::new([false; RingDomainSize::VARIANTS.len()]))
            .lock()
            .await;
        if installed[slot] {
            return Ok(());
        }

        let file = pinned::file(domain);
        let bytes = read(&file).await?;

        if hex::encode(blake2_256(&bytes)) != pinned::hash(domain) {
            warn!(
                ?domain,
                file, "ring prover parameters missed the pinned hash"
            );
            return Err(Unavailable);
        }

        verifiable::ring::bandersnatch::install_ring_setup(domain, &bytes).map_err(|error| {
            warn!(?error, ?domain, "ring prover parameters did not install");
            Unavailable
        })?;

        installed[slot] = true;
        Ok(())
    }

    /// Read one file published beside the core's WASM.
    async fn read(file: &str) -> Result<Vec<u8>, Unavailable> {
        let file = file.to_owned();
        let value = SendWrapper::new(async move {
            wasm_bindgen_futures::JsFuture::from(read_core_asset(&file)).await
        })
        .await
        .map_err(|error| {
            warn!(?error, "a core asset could not be read");
            Unavailable
        })?;
        Ok(value.unchecked_into::<Uint8Array>().to_vec())
    }
}

/// Native only: the pinned hashes have to be the ones `truapi-srs-gen` emits,
/// or the browser reads a file that is not published and cannot prove. Both
/// sides cut their parameters from the SRS `verifiable` ships, so recomputing
/// them here is the whole check.
#[cfg(all(test, not(target_arch = "wasm32")))]
mod tests {
    use super::*;
    use sp_crypto_hashing::blake2_256;
    use verifiable::ring::RingDomainSize;
    use verifiable::ring::ark_vrf::reexports::ark_serialize::CanonicalSerialize;
    use verifiable::ring::ark_vrf::suites::bandersnatch::BandersnatchSha512Ell2;
    use verifiable::ring::{Bls12_381Params, RingCurveParams, ring_setup_from_srs};

    #[test]
    fn every_pinned_hash_is_the_one_the_generator_emits() {
        for domain in RingDomainSize::VARIANTS {
            let setup =
                ring_setup_from_srs::<BandersnatchSha512Ell2>(domain, Bls12_381Params::srs_raw())
                    .expect("the compiled-in SRS covers every domain");
            let mut bytes = Vec::new();
            setup
                .pcs_params
                .serialize_uncompressed(&mut bytes)
                .expect("parameters serialize");

            assert_eq!(
                hex::encode(blake2_256(&bytes)),
                pinned::hash(domain),
                "{domain:?} parameters no longer hash to the pinned value",
            );
        }
    }

    #[test]
    fn a_domain_reads_the_file_its_hash_names() {
        assert_eq!(
            pinned::file(RingDomainSize::Domain16),
            format!(
                "srs-domain16-{}.bin",
                &pinned::hash(RingDomainSize::Domain16)[..8]
            ),
        );
    }
}
