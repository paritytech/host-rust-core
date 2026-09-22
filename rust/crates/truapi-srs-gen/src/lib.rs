//! Per-domain ring-VRF prover parameters, cut from the SRS `verifiable` ships.
//!
//! A prover needs `3 * piop_domain_size + 1` powers of tau, so the parameters
//! for a 255-member ring are a thirty-second of those for a 16127-member one.
//! A core that reads its parameters at runtime reads only the domain in hand,
//! so each one is published as its own file.
//!
//! The file name carries a prefix of the content hash, which is also what the
//! core pins: it addresses a file by the hash it expects, so a file this tool
//! emits under a different name is one the core never asks for.

use std::fs;
use std::io;
use std::path::Path;

use sp_crypto_hashing::blake2_256;
use verifiable::ring::ark_vrf::reexports::ark_serialize::CanonicalSerialize;
use verifiable::ring::ark_vrf::suites::bandersnatch::BandersnatchSha512Ell2;
use verifiable::ring::{Bls12_381Params, RingCurveParams, RingDomainSize, ring_setup_from_srs};

/// What went wrong while emitting the parameters.
#[derive(Debug, derive_more::Display, derive_more::Error, derive_more::From)]
pub enum EmitError {
    /// The output directory could not be written.
    Io(io::Error),
    /// The shipped SRS could not be read or cut down to a domain.
    #[display("the shipped SRS is unusable for {domain:?}")]
    Srs {
        /// Domain whose parameters could not be produced.
        domain: RingDomainSize,
    },
}

/// One emitted parameter file.
pub struct Emitted {
    /// File name, carrying a prefix of the content hash.
    pub file: String,
    /// Blake2b-256 of the file's bytes, lowercase hex.
    pub hash: String,
    /// Length in bytes.
    pub bytes: usize,
}

/// Write one parameter file per ring domain into `out_dir`, returning what was
/// written in domain order.
pub fn emit(out_dir: &Path) -> Result<Vec<Emitted>, EmitError> {
    fs::create_dir_all(out_dir)?;
    let srs = Bls12_381Params::srs_raw();

    RingDomainSize::VARIANTS
        .into_iter()
        .map(|domain| {
            let setup = ring_setup_from_srs::<BandersnatchSha512Ell2>(domain, srs)
                .map_err(|_| EmitError::Srs { domain })?;
            let mut bytes = Vec::new();
            setup
                .pcs_params
                .serialize_uncompressed(&mut bytes)
                .map_err(|_| EmitError::Srs { domain })?;

            let hash = hex::encode(blake2_256(&bytes));
            let file = format!("srs-domain{}-{}.bin", domain.as_power(), &hash[..8]);
            fs::write(out_dir.join(&file), &bytes)?;
            Ok(Emitted {
                file,
                hash,
                bytes: bytes.len(),
            })
        })
        .collect()
}
