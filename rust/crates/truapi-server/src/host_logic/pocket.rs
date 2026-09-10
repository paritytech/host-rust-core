//! NFT pocket key derivation: one sr25519 purse key per `pallet-scarcity`
//! item, all hard junctions, one purse per product.
//!
//! ```text
//! //pps//nft//<product_id>//<index>
//! ```
//!
//! Every junction is hard. RFC-0017's Appendix A used a soft item junction,
//! and sr25519 soft derivation is invertible from the child side: a child
//! secret together with the parent public key and the path recovers the
//! parent secret. A purse key that ever leaves the host, as the planned
//! off-chain key handover would let it, must therefore not be soft-derived
//! from anything the host wants to keep. The purse junction is the product id
//! itself, so recovery from seed needs only the product ids the host knows,
//! and the wallet's own purse is the reserved product [`WALLET_PURSE_PRODUCT_ID`].

use schnorrkel::Keypair;
use truapi_platform::normalize_product_identifier;

use super::product_account::{ProductAccountError, derive_sr25519_hard_path};

/// Reserved product id of the wallet's own purse, the RFC-0017 `MAIN_PURSE`
/// analogue. Governance reserves product ids of five characters or fewer, so
/// no product can claim it.
pub const WALLET_PURSE_PRODUCT_ID: &str = "nfts.dot";

/// Leading junctions shared by every purse key.
const POCKET_JUNCTIONS: [&str; 2] = ["pps", "nft"];

/// Error deriving a purse key.
#[derive(Debug, PartialEq, Eq, derive_more::Display)]
pub enum PocketDerivationError {
    /// The purse product id is not a valid product identifier.
    #[display("invalid purse product id {product_id:?}")]
    InvalidProductId {
        /// The rejected id.
        product_id: String,
    },
    /// The product id would be encoded as a numeric junction and collide with
    /// the index space; dotNS names never are.
    #[display("purse product id {product_id:?} is all digits")]
    NumericProductId {
        /// The rejected id.
        product_id: String,
    },
    /// The root or a junction failed to derive.
    #[display("{_0}")]
    Derivation(ProductAccountError),
}

/// The canonical purse product id: trimmed, NFC-normalized, lowercase.
pub fn normalize_purse_product_id(product_id: &str) -> Result<String, PocketDerivationError> {
    let normalized = normalize_product_identifier(product_id).map_err(|_| {
        PocketDerivationError::InvalidProductId {
            product_id: product_id.to_string(),
        }
    })?;
    if normalized.bytes().all(|byte| byte.is_ascii_digit()) {
        return Err(PocketDerivationError::NumericProductId {
            product_id: product_id.to_string(),
        });
    }
    Ok(normalized)
}

/// The purse key at `index` in `product_id`'s purse, derived from root entropy.
pub fn derive_purse_keypair(
    entropy: &[u8],
    product_id: &str,
    index: u32,
) -> Result<Keypair, PocketDerivationError> {
    let product_id = normalize_purse_product_id(product_id)?;
    let index = index.to_string();
    let junctions = [
        POCKET_JUNCTIONS[0],
        POCKET_JUNCTIONS[1],
        product_id.as_str(),
        index.as_str(),
    ];
    derive_sr25519_hard_path(entropy, &junctions).map_err(PocketDerivationError::Derivation)
}

/// The purse key's public bytes at `index` in `product_id`'s purse.
pub fn derive_purse_public_key(
    entropy: &[u8],
    product_id: &str,
    index: u32,
) -> Result<[u8; 32], PocketDerivationError> {
    Ok(derive_purse_keypair(entropy, product_id, index)?
        .public
        .to_bytes())
}

#[cfg(test)]
mod tests {
    use super::*;

    const ENTROPY: [u8; 16] = [0xAB; 16];

    #[test]
    fn purse_keys_are_isolated_by_product_and_index() {
        let a0 = derive_purse_public_key(&ENTROPY, "cardclash.dot", 0).unwrap();
        let a1 = derive_purse_public_key(&ENTROPY, "cardclash.dot", 1).unwrap();
        let b0 = derive_purse_public_key(&ENTROPY, "seity.dot", 0).unwrap();
        let w0 = derive_purse_public_key(&ENTROPY, WALLET_PURSE_PRODUCT_ID, 0).unwrap();
        assert_ne!(a0, a1);
        assert_ne!(a0, b0);
        assert_ne!(a0, w0);
        assert_eq!(
            a0,
            derive_purse_public_key(&ENTROPY, "CardClash.dot", 0).unwrap()
        );
    }

    #[test]
    fn purse_keys_are_not_product_accounts() {
        use crate::host_logic::product_account::{
            derive_product_keypair, derive_root_keypair_from_entropy, index_bytes,
        };
        let root = derive_root_keypair_from_entropy(&ENTROPY).unwrap();
        let account = derive_product_keypair(&root, "cardclash.dot", index_bytes(0)).unwrap();
        let purse = derive_purse_public_key(&ENTROPY, "cardclash.dot", 0).unwrap();
        assert_ne!(account.public.to_bytes(), purse);
    }

    #[test]
    fn invalid_purse_ids_are_rejected() {
        assert!(matches!(
            derive_purse_keypair(&ENTROPY, "not a product", 0),
            Err(PocketDerivationError::InvalidProductId { .. })
        ));
        assert!(matches!(
            derive_purse_keypair(&ENTROPY, "", 0),
            Err(PocketDerivationError::InvalidProductId { .. })
        ));
    }

    /// Pinned so the path can never move under minted items: any change here
    /// strands every key the shipped scheme has minted into.
    #[test]
    fn derivation_vectors_are_pinned() {
        let vectors = [
            (
                WALLET_PURSE_PRODUCT_ID,
                0u32,
                "d022c7eeecdd92349a606016389e94345d69899c0088c74c622a147a19847b54",
            ),
            (
                "cardclash.dot",
                0,
                "361dd047b3ce7a28c2097c1df219f229de79b962d828698ae6ad064ec770a83e",
            ),
            (
                "cardclash.dot",
                1,
                "d6a4ec484c295fc5be95c01fda5568f30558fd04b6447916a962e4a1ff6d8b13",
            ),
            (
                "seity.dot",
                0,
                "9a8b023f6801a37575b15b1051d031a3305fb7aab9f231505c2f433354cf8979",
            ),
        ];
        for (product_id, index, expected) in vectors {
            let actual = hex::encode(derive_purse_public_key(&ENTROPY, product_id, index).unwrap());
            assert_eq!(actual, expected, "{product_id}//{index}");
        }
    }
}
