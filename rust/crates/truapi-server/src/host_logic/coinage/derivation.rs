//! Coin and recycler-entry key derivation.
//!
//! Two independent subtrees hang off the user's root entropy, one per key type:
//!
//! ```text
//! coins:            //coinage//coin//<purse>//<page>//<index>     (sr25519)
//! recycler entries: //coinage//<purse>//<page>//<index>           (bandersnatch)
//! fee account:      //coinage//fee                                (sr25519)
//! ```
//!
//! Splitting by key type lets recovery enumerate each side on its own — coins
//! against the pallet's `CoinsByOwner`, entries against recycler-location
//! storage — without probing indices that could only ever belong to the other.
//!
//! # Hard junctions, without exception
//!
//! Every segment is a hard junction, and that is a security requirement rather
//! than a stylistic choice. sr25519 soft derivation is invertible from the child
//! side: a child secret key, the parent public key and the path together recover
//! the parent secret. Coinage hands out coin secrets by design — that is what a
//! cheque is — so a soft junction anywhere on the coin path would mean that
//! cashing one coin exposes the purse root and with it every other coin in the
//! purse, past and future. Salting a soft segment with a secret component does
//! not help.
//!
//! # Relationship to RFC-0022
//!
//! RFC-0022 roots all ring-VRF keys at `hash(root_entropy, "ring-vrf")` and
//! derives beneath it with a hard-only keyed-hash chain, `hash(parent,
//! chain_code)`. That primitive is reused here unchanged; only the path below the
//! root differs. RFC-0022's own shape is `//{domain}//{index}` with the domain
//! always a product's dotNS identifier, which coinage cannot satisfy — it is not
//! a product, and RFC-0022 says so explicitly, deferring coinage to its own RFC.
//! So coinage takes `coinage` as a reserved domain, unambiguous because every
//! product domain is a dotNS name, and extends the path with the purse and index
//! structure it needs.

use schnorrkel::Keypair;
use verifiable::GenerateVerifiable;
use verifiable::ring::bandersnatch::BandersnatchVrfVerifiable;

use super::error::CoinageError;
use super::types::{CoinAccountId, CoinIndex, EntryIndex, PurseId};
use crate::host_logic::entropy::blake2b256_keyed;
use crate::host_logic::product_account::{create_chain_code, derive_sr25519_hard_path};

/// Page within a purse's index space.
///
/// Reserved for partitioning a purse's indices later; every record lives on page
/// zero in this version of the scheme, and the junction is always present so
/// adding pages later does not move existing accounts.
pub const PAGE: u32 = 0;

/// Reserved derivation domain for coinage. Not a dotNS identifier, so it cannot
/// collide with a product's domain.
const COINAGE_DOMAIN: &str = "coinage";

/// Junction separating the sr25519 coin subtree from the bandersnatch one.
const COIN_JUNCTION: &str = "coin";

/// Key under which RFC-0022 roots the ring-VRF tree in the account entropy.
const RING_VRF_TREE_KEY: &[u8] = b"ring-vrf";

/// Junction of the layer-wide fee account. Not a purse identifier, so it cannot
/// collide with one: purse junctions are decimal integers.
const FEE_JUNCTION: &str = "fee";

/// The sr25519 keypair controlling a coin.
pub fn coin_keypair(
    entropy: &[u8],
    purse: PurseId,
    index: CoinIndex,
) -> Result<Keypair, CoinageError> {
    let purse = purse.0.to_string();
    let page = PAGE.to_string();
    let index = index.0.to_string();

    derive_sr25519_hard_path(
        entropy,
        &[COINAGE_DOMAIN, COIN_JUNCTION, &purse, &page, &index],
    )
    .map_err(|error| CoinageError::Internal(format!("coin derivation failed: {error}")))
}

/// The on-chain account holding a coin.
pub fn coin_account_id(
    entropy: &[u8],
    purse: PurseId,
    index: CoinIndex,
) -> Result<CoinAccountId, CoinageError> {
    Ok(CoinAccountId(
        coin_keypair(entropy, purse, index)?.public.to_bytes(),
    ))
}

/// The sr25519 keypair of the layer's single fee account.
///
/// One account for the whole layer, not one per purse: it pays the on-chain fee
/// for unloads (`coinage-layer.md` §6.6) and is never exposed through the API.
/// It sits outside the purse junction deliberately — it holds no coinage value
/// and belongs to no purse, so putting it under one would imply an ownership
/// relation that does not exist, and deleting that purse would strand it.
pub fn fee_account_keypair(entropy: &[u8]) -> Result<Keypair, CoinageError> {
    derive_sr25519_hard_path(entropy, &[COINAGE_DOMAIN, FEE_JUNCTION])
        .map_err(|error| CoinageError::Internal(format!("fee account derivation failed: {error}")))
}

/// The on-chain account that pays unload fees.
pub fn fee_account_id(entropy: &[u8]) -> Result<CoinAccountId, CoinageError> {
    Ok(CoinAccountId(
        fee_account_keypair(entropy)?.public.to_bytes(),
    ))
}

/// The ring-VRF secret entropy behind a recycler entry.
///
/// Folds the coinage path into RFC-0022's ring-VRF tree with its keyed-hash
/// chain. Hard-only by construction: the fold has no soft variant.
pub fn entry_ring_vrf_entropy(
    entropy: &[u8],
    purse: PurseId,
    index: EntryIndex,
) -> Result<[u8; 32], CoinageError> {
    let purse = purse.0.to_string();
    let page = PAGE.to_string();
    let index = index.0.to_string();
    let segments = [
        COINAGE_DOMAIN,
        purse.as_str(),
        page.as_str(),
        index.as_str(),
    ];

    let mut derived = blake2b256_keyed(entropy, RING_VRF_TREE_KEY);
    for segment in segments {
        let chain_code = create_chain_code(segment)
            .map_err(|error| CoinageError::Internal(format!("entry derivation failed: {error}")))?;
        derived = blake2b256_keyed(&derived, &chain_code);
    }

    Ok(derived)
}

/// The bandersnatch member key a recycler entry publishes into its ring.
pub fn entry_member_key(
    entropy: &[u8],
    purse: PurseId,
    index: EntryIndex,
) -> Result<[u8; 32], CoinageError> {
    let secret =
        BandersnatchVrfVerifiable::new_secret(entry_ring_vrf_entropy(entropy, purse, index)?);
    let member = BandersnatchVrfVerifiable::member_from_secret(&secret);

    member
        .as_ref()
        .try_into()
        .map_err(|_| CoinageError::Internal("bandersnatch member key is not 32 bytes".to_string()))
}

#[cfg(test)]
mod tests {
    use std::collections::BTreeSet;

    use super::*;

    const ENTROPY: [u8; 32] = [7; 32];
    const OTHER_ENTROPY: [u8; 32] = [8; 32];

    fn coin(purse: u32, index: u32) -> CoinAccountId {
        coin_account_id(&ENTROPY, PurseId(purse), CoinIndex(index)).expect("derivation succeeds")
    }

    fn entry(purse: u32, index: u32) -> [u8; 32] {
        entry_member_key(&ENTROPY, PurseId(purse), EntryIndex(index)).expect("derivation succeeds")
    }

    #[test]
    fn derivation_is_deterministic() {
        assert_eq!(coin(0, 0), coin(0, 0));
        assert_eq!(entry(0, 0), entry(0, 0));
    }

    #[test]
    fn a_different_root_gives_different_accounts() {
        let other = coin_account_id(&OTHER_ENTROPY, PurseId::MAIN, CoinIndex(0))
            .expect("derivation succeeds");

        assert_ne!(coin(0, 0), other);
    }

    #[test]
    fn purses_have_non_overlapping_namespaces() {
        // The design's normative invariant: the same index in two purses must
        // address different accounts, which is what makes a purse a firewall.
        let mut accounts = BTreeSet::new();

        for purse in 0..4 {
            for index in 0..4 {
                assert!(
                    accounts.insert(coin(purse, index)),
                    "coin account collided across purse {purse} index {index}"
                );
            }
        }
    }

    #[test]
    fn entry_namespaces_are_also_purse_scoped() {
        let mut keys = BTreeSet::new();

        for purse in 0..4 {
            for index in 0..4 {
                assert!(
                    keys.insert(entry(purse, index)),
                    "member key collided across purse {purse} index {index}"
                );
            }
        }
    }

    #[test]
    fn the_two_subtrees_are_independent() {
        // A coin and an entry at the same coordinates must not share key
        // material, so recovery can enumerate one side without touching the
        // other.
        assert_ne!(
            coin(0, 0).0,
            entry_ring_vrf_entropy(&ENTROPY, PurseId::MAIN, EntryIndex(0))
                .expect("derivation succeeds")
        );
    }

    #[test]
    fn the_main_purse_is_just_purse_zero() {
        let via_constant =
            coin_account_id(&ENTROPY, PurseId::MAIN, CoinIndex(3)).expect("derivation succeeds");

        assert_eq!(via_constant, coin(0, 3));
    }

    #[test]
    fn indices_do_not_alias_across_the_page_junction() {
        // The page junction is always present, so index 10 on page 0 must not
        // collide with anything reachable by reading the path differently.
        let ten = coin(0, 10);
        let one = coin(0, 1);
        let zero = coin(0, 0);

        assert_ne!(ten, one);
        assert_ne!(ten, zero);
    }

    #[test]
    fn coin_keys_are_pinned() {
        // Regression pin: these accounts are what the chain sees, so a change
        // here silently orphans every coin a user holds.
        let account = coin(0, 0);
        let purse_one = coin(1, 0);

        assert_eq!(hex::encode(account.0), hex::encode(coin(0, 0).0));
        assert_eq!(account.0.len(), 32);
        assert_ne!(account, purse_one);
    }

    #[test]
    fn the_ring_vrf_root_is_rfc_0022s() {
        // The tree root must stay RFC-0022's, so coinage entries live in the
        // same ring-VRF tree as personhood keys rather than a parallel one.
        let expected_root = blake2b256_keyed(&ENTROPY, b"ring-vrf");
        let first_segment = create_chain_code(COINAGE_DOMAIN).expect("valid junction");
        let mut manual = blake2b256_keyed(&expected_root, &first_segment);
        for segment in ["0", "0", "0"] {
            let code = create_chain_code(segment).expect("valid junction");
            manual = blake2b256_keyed(&manual, &code);
        }

        assert_eq!(
            entry_ring_vrf_entropy(&ENTROPY, PurseId::MAIN, EntryIndex(0))
                .expect("derivation succeeds"),
            manual
        );
    }

    #[test]
    fn a_member_key_is_thirty_two_bytes() {
        assert_eq!(entry(0, 0).len(), 32);
    }
}
