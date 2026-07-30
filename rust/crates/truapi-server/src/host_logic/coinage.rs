//! Coinage key derivation shared by wallet-local hosts.
//!
//! These paths mirror the Polkadot app's `CoinKeypairFactory` and
//! `VoucherKeypairFactory`. Coin keys use Substrate sr25519 hard derivation at
//! `//pps//coin//<index>`. Voucher keys apply keyed BLAKE2b at each hard
//! junction in `//pps//ring-vrf//<index>` before deriving the Bandersnatch
//! member key and recycler alias.

use thiserror::Error;
use verifiable::GenerateVerifiable;
use verifiable::ring::bandersnatch::BandersnatchVrfVerifiable;

use super::product_account::{ProductAccountError, create_chain_code, derive_sr25519_hard_path};

const RECYCLER_ALIAS_CONTEXT: &[u8] = b"pop:polkadot.network/coinrecyclr";

/// Public material needed to locate one voucher on chain.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct VoucherKeys {
    /// Bandersnatch member key stored by Coinage and Members.
    pub member: [u8; 32],
    /// Ring-VRF alias used by `Coinage.RecyclersUnloaded`.
    pub recycler_alias: [u8; 32],
}

/// Public material submitted when an external asset holder loads a voucher.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct VoucherLoad {
    /// Bandersnatch member key that becomes the voucher owner.
    pub member: [u8; 32],
    /// Plain Bandersnatch signature proving the external asset holder approved
    /// this voucher member key.
    pub proof_of_ownership: [u8; 64],
}

/// Failure while deriving Coinage keys from wallet entropy.
#[derive(Debug, Error)]
pub enum CoinageKeyError {
    /// The sr25519 derivation path or root entropy was invalid.
    #[error(transparent)]
    Sr25519(#[from] ProductAccountError),
    /// Bandersnatch could not derive the recycler alias.
    #[error("derive Coinage recycler alias: {0:?}")]
    RecyclerAlias(verifiable::Error),
    /// Bandersnatch could not sign the external asset holder's account id.
    #[error("sign Coinage voucher ownership: {0:?}")]
    ProofOfOwnership(verifiable::Error),
}

/// Derive the sr25519 public key for `//pps//coin//<index>`.
pub fn derive_coin_public_key(
    root_entropy: &[u8],
    index: u32,
) -> Result<[u8; 32], CoinageKeyError> {
    let index = index.to_string();
    Ok(
        derive_sr25519_hard_path(root_entropy, &["pps", "coin", &index])?
            .public
            .to_bytes(),
    )
}

/// Derive the member key and recycler alias for
/// `//pps//ring-vrf//<index>`.
pub fn derive_voucher_keys(
    root_entropy: &[u8],
    index: u32,
) -> Result<VoucherKeys, CoinageKeyError> {
    let entropy = derive_voucher_entropy(root_entropy, index)?;
    let secret = BandersnatchVrfVerifiable::new_secret(entropy);
    let member = BandersnatchVrfVerifiable::member_from_secret(&secret);
    let recycler_alias =
        BandersnatchVrfVerifiable::alias_in_context(&secret, RECYCLER_ALIAS_CONTEXT)
            .map_err(CoinageKeyError::RecyclerAlias)?;

    Ok(VoucherKeys {
        member,
        recycler_alias,
    })
}

/// Derive one voucher member key and sign ownership by `external_asset_holder`.
///
/// The signature layout matches the iOS Cash top-up flow: the voucher's
/// Bandersnatch secret signs the temporary sr25519 deposit account id.
pub fn derive_voucher_load(
    root_entropy: &[u8],
    index: u32,
    external_asset_holder: &[u8; 32],
) -> Result<VoucherLoad, CoinageKeyError> {
    let entropy = derive_voucher_entropy(root_entropy, index)?;
    let secret = BandersnatchVrfVerifiable::new_secret(entropy);
    let member = BandersnatchVrfVerifiable::member_from_secret(&secret);
    let proof_of_ownership = BandersnatchVrfVerifiable::sign(&secret, external_asset_holder)
        .map_err(CoinageKeyError::ProofOfOwnership)?;
    Ok(VoucherLoad {
        member,
        proof_of_ownership,
    })
}

fn derive_voucher_entropy(
    root_entropy: &[u8],
    index: u32,
) -> Result<[u8; 32], ProductAccountError> {
    let index = index.to_string();
    let mut entropy = root_entropy.to_vec();
    for junction in ["pps", "ring-vrf", &index] {
        let chain_code = create_chain_code(junction)?;
        let mut params = blake2b_simd::Params::new();
        params.hash_length(32).key(&chain_code);
        entropy = params.hash(&entropy).as_bytes().to_vec();
    }
    entropy.try_into().map_err(|entropy: Vec<u8>| {
        ProductAccountError::InvalidEntropy(format!(
            "Coinage voucher entropy is {} bytes",
            entropy.len()
        ))
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    const ENTROPY: [u8; 32] = [0xabu8; 32];

    #[test]
    fn coin_keys_are_stable_and_indexed() {
        let first = derive_coin_public_key(&ENTROPY, 0).unwrap();
        let repeated = derive_coin_public_key(&ENTROPY, 0).unwrap();
        let second = derive_coin_public_key(&ENTROPY, 1).unwrap();

        assert_eq!(first, repeated);
        assert_ne!(first, second);
    }

    #[test]
    fn voucher_keys_are_stable_and_indexed() {
        let first = derive_voucher_keys(&ENTROPY, 0).unwrap();
        let repeated = derive_voucher_keys(&ENTROPY, 0).unwrap();
        let second = derive_voucher_keys(&ENTROPY, 1).unwrap();

        assert_eq!(first, repeated);
        assert_ne!(first, second);
        assert_ne!(first.member, first.recycler_alias);
    }

    #[test]
    fn voucher_load_proves_the_external_asset_holder() {
        let owner = [0x42; 32];
        let load = derive_voucher_load(&ENTROPY, 7, &owner).unwrap();

        assert!(BandersnatchVrfVerifiable::verify_signature(
            &load.proof_of_ownership,
            &owner,
            &load.member,
        ));
        assert!(!BandersnatchVrfVerifiable::verify_signature(
            &load.proof_of_ownership,
            &[0x24; 32],
            &load.member,
        ));
        assert_eq!(
            load.member,
            derive_voucher_keys(&ENTROPY, 7).unwrap().member
        );
    }
}
