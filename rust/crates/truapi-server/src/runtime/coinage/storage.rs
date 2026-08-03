//! Storage keys and decoding for the chain state coinage observes.
//!
//! The layer's local records are a projection of chain state, so observation is
//! the half of the chain layer that keeps them true. This module builds the keys
//! and decodes the values; issuing the reads and driving the loop belong to the
//! caller, which keeps every byte-layout decision here and unit-testable.
//!
//! Storage keys are pinned by golden tests. A hasher silently changed is a query
//! that returns nothing rather than an error, which would read as "the user has
//! no coins" — the most dangerous possible failure for a wallet.

use parity_scale_codec::{Decode, Encode};
use sp_crypto_hashing::{blake2_128, twox_64, twox_128};

use crate::host_logic::coinage::error::CoinageError;
use crate::host_logic::coinage::params::CoinageParameters;
use crate::host_logic::coinage::store::CoinageStore;
use crate::host_logic::coinage::types::{
    CoinAccountId, CoinAge, CoinIndex, DenominationExponent, EntryIndex, PurseId, RevisionIndex,
    RingIndex, RingLocation,
};

/// Prefix of a recycler ring's 32-byte collection identifier.
///
/// Rings are segregated by denomination, so the exponent goes in the byte right
/// after this prefix and the rest is zero.
const RECYCLER_COLLECTION_PREFIX: &[u8] = b"coinage/recycler";

/// Byte holding the denomination inside a recycler collection identifier.
const RECYCLER_COLLECTION_EXPONENT_OFFSET: usize = 16;

/// `Blake2_128Concat(x)` = `blake2_128(x) ‖ x`.
fn blake2_128_concat(x: &[u8]) -> Vec<u8> {
    [blake2_128(x).as_slice(), x].concat()
}

/// `Twox64Concat(x)` = `twox_64(x) ‖ x`.
fn twox_64_concat(x: &[u8]) -> Vec<u8> {
    [twox_64(x).as_slice(), x].concat()
}

/// The membership collection holding recycler rings of one denomination.
pub fn recycler_collection_id(exponent: DenominationExponent) -> [u8; 32] {
    let mut id = [0u8; 32];
    id[..RECYCLER_COLLECTION_PREFIX.len()].copy_from_slice(RECYCLER_COLLECTION_PREFIX);
    id[RECYCLER_COLLECTION_EXPONENT_OFFSET] = exponent.get() as u8;
    id
}

/// `Coinage::CoinsByOwner(account)` — `Twox64Concat` over `AccountId`.
pub fn coins_by_owner_key(account: &CoinAccountId) -> Vec<u8> {
    [
        twox_128(b"Coinage").as_slice(),
        twox_128(b"CoinsByOwner").as_slice(),
        &twox_64_concat(&account.0),
    ]
    .concat()
}

/// `Coinage::RecyclersCoinToRecycler(member_key)` — `Twox64Concat` over the
/// bandersnatch member key. Presence means the entry is loaded, and the value is
/// the denomination of the ring holding it.
pub fn recyclers_coin_to_recycler_key(member_key: &[u8; 32]) -> Vec<u8> {
    [
        twox_128(b"Coinage").as_slice(),
        twox_128(b"RecyclersCoinToRecycler").as_slice(),
        &twox_64_concat(member_key),
    ]
    .concat()
}

/// `Members::RingKeysStatus((collection, ring_index))` — the collection
/// identifier is used raw, the ring index `Blake2_128Concat`.
pub fn ring_keys_status_key(collection: &[u8; 32], ring: RingIndex) -> Vec<u8> {
    [
        twox_128(b"Members").as_slice(),
        twox_128(b"RingKeysStatus").as_slice(),
        collection.as_slice(),
        &blake2_128_concat(&ring.0.to_le_bytes()),
    ]
    .concat()
}

/// The coin record the pallet stores per account.
///
/// `Encode` is derived so tests can build the exact bytes the chain returns.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Encode, Decode)]
pub struct ChainCoin {
    /// Denomination exponent.
    pub value: i8,
    /// Transfers and splits so far.
    pub age: u16,
}

/// How full a ring is, as `Members` reports it.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Encode, Decode)]
pub struct RingKeysStatus {
    /// Keys submitted to the ring.
    pub total: u32,
    /// Keys included in its committed membership.
    pub included: u32,
}

/// One coin's chain state, ready to apply.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct ObservedCoin {
    /// Which local record this is about.
    pub index: CoinIndex,
    /// The coin the chain reports, or `None` if the account is empty.
    pub coin: Option<ChainCoin>,
}

/// One recycler entry's chain state, ready to apply.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct ObservedEntry {
    /// Which local record this is about.
    pub index: EntryIndex,
    /// Where the entry sits, if the chain reports a location for it.
    pub ring: Option<RingLocation>,
    /// Committed member count of that ring, which decides the anonymity
    /// classification.
    pub included_members: u32,
}

/// Decode a `CoinsByOwner` value, treating an absent entry as an empty account.
pub fn decode_coin(bytes: Option<Vec<u8>>) -> Result<Option<ChainCoin>, CoinageError> {
    match bytes {
        None => Ok(None),
        Some(raw) => ChainCoin::decode(&mut &raw[..])
            .map(Some)
            .map_err(|error| CoinageError::Internal(format!("decoding a coin failed: {error}"))),
    }
}

/// Decode a `RingKeysStatus` value, treating an absent entry as an empty ring.
pub fn decode_ring_status(bytes: Option<Vec<u8>>) -> Result<RingKeysStatus, CoinageError> {
    match bytes {
        None => Ok(RingKeysStatus {
            total: 0,
            included: 0,
        }),
        Some(raw) => RingKeysStatus::decode(&mut &raw[..]).map_err(|error| {
            CoinageError::Internal(format!("decoding a ring status failed: {error}"))
        }),
    }
}

/// Apply a batch of observations to the store.
///
/// A coin the chain no longer holds is left alone rather than retired here: only
/// its owning operation knows whether an empty account means spent or means the
/// extrinsic has not landed yet, and guessing would race it.
pub fn apply_observations(
    store: &mut CoinageStore,
    purse: PurseId,
    coins: &[ObservedCoin],
    entries: &[ObservedEntry],
    params: &CoinageParameters,
) -> Result<(), CoinageError> {
    for observed in coins {
        if let Some(coin) = observed.coin {
            let exponent = DenominationExponent::new(coin.value).ok_or_else(|| {
                CoinageError::Internal(format!(
                    "chain reports coin {:?} at unsupported denomination {}",
                    observed.index, coin.value
                ))
            })?;
            let known = store
                .coin(purse, observed.index)
                .ok_or_else(|| untracked("coin", purse))?;
            if known.exponent != exponent {
                return Err(CoinageError::Internal(format!(
                    "chain reports coin {:?} as {exponent}, local record says {}",
                    observed.index, known.exponent
                )));
            }

            store.observe_coin(purse, observed.index, CoinAge(coin.age))?;
        }
    }

    for observed in entries {
        match observed.ring {
            Some(ring) => {
                store.observe_entry_ring(
                    purse,
                    observed.index,
                    ring,
                    observed.included_members,
                    params,
                )?;
            }
            None => store.observe_entry_missing(purse, observed.index)?,
        }
    }

    Ok(())
}

/// Build the observation for one entry from the two reads it needs.
///
/// The chain reports an entry's denomination and ring index separately from the
/// ring's fill level, so this pairs them up and keeps the revision the caller
/// pinned its reads at.
pub fn observe_entry(
    index: EntryIndex,
    recycler_denomination: Option<i8>,
    ring: RingIndex,
    revision: RevisionIndex,
    status: RingKeysStatus,
) -> ObservedEntry {
    ObservedEntry {
        index,
        ring: recycler_denomination.map(|_| RingLocation::new(ring, revision)),
        included_members: status.included,
    }
}

fn untracked(kind: &str, purse: PurseId) -> CoinageError {
    CoinageError::Internal(format!(
        "chain reports a {kind} in {purse} that the layer does not track"
    ))
}

#[cfg(test)]
mod tests {
    use core::time::Duration;

    use crate::host_logic::coinage::entry::{EntryLocalState, EntryOnChainState};
    use crate::host_logic::coinage::types::{Amount, Timestamp};

    use super::*;

    fn exponent(value: i8) -> DenominationExponent {
        DenominationExponent::new(value).expect("exponent is in range")
    }

    fn params() -> CoinageParameters {
        CoinageParameters::default()
    }

    #[test]
    fn a_recycler_collection_is_segregated_by_denomination() {
        let four = recycler_collection_id(exponent(4));
        let five = recycler_collection_id(exponent(5));

        assert_eq!(&four[..16], b"coinage/recycler");
        assert_eq!(four[16], 4);
        assert_eq!(&four[17..], &[0u8; 15]);
        assert_ne!(four, five, "each denomination has its own ring collection");
    }

    #[test]
    fn storage_keys_are_pinned() {
        // A hasher quietly changed makes a query return nothing rather than
        // fail, which a wallet would render as "you have no coins".
        let account = CoinAccountId([3; 32]);
        let coin_key = coins_by_owner_key(&account);

        assert_eq!(&coin_key[..16], twox_128(b"Coinage").as_slice());
        assert_eq!(&coin_key[16..32], twox_128(b"CoinsByOwner").as_slice());
        assert_eq!(&coin_key[32..40], twox_64(&account.0).as_slice());
        assert_eq!(&coin_key[40..], &account.0);
        assert_eq!(coin_key.len(), 16 + 16 + 8 + 32);

        let member = [7u8; 32];
        let entry_key = recyclers_coin_to_recycler_key(&member);
        assert_eq!(
            &entry_key[16..32],
            twox_128(b"RecyclersCoinToRecycler").as_slice()
        );
        assert_eq!(&entry_key[40..], &member);

        let collection = recycler_collection_id(exponent(4));
        let status_key = ring_keys_status_key(&collection, RingIndex(9));
        assert_eq!(&status_key[16..32], twox_128(b"RingKeysStatus").as_slice());
        // The collection identifier is used raw; only the ring index is hashed.
        assert_eq!(&status_key[32..64], &collection);
        assert_eq!(&status_key[64..80], blake2_128(&9u32.to_le_bytes()));
        assert_eq!(&status_key[80..], &9u32.to_le_bytes());
    }

    #[test]
    fn an_absent_coin_is_an_empty_account_not_an_error() {
        assert_eq!(decode_coin(None).expect("absent is fine"), None);
    }

    #[test]
    fn a_coin_round_trips_through_the_pallet_layout() {
        let encoded = ChainCoin { value: 4, age: 3 }.encode();

        assert_eq!(encoded.len(), 1 + 2, "i8 then u16");
        assert_eq!(
            decode_coin(Some(encoded)).expect("decodes"),
            Some(ChainCoin { value: 4, age: 3 })
        );
    }

    #[test]
    fn an_absent_ring_status_reads_as_empty() {
        let status = decode_ring_status(None).expect("absent is fine");

        assert_eq!(status.included, 0);
        assert_eq!(status.total, 0);
    }

    #[test]
    fn observations_move_records_into_their_chain_state() {
        let mut store = CoinageStore::new("Main".to_string());
        let coin = store
            .add_pending_coin(PurseId::MAIN, exponent(4))
            .expect("purse exists");
        let entry = store
            .allocate_entry(PurseId::MAIN, exponent(4), Timestamp(0), Duration::ZERO)
            .expect("purse exists");

        apply_observations(
            &mut store,
            PurseId::MAIN,
            &[ObservedCoin {
                index: coin,
                coin: Some(ChainCoin { value: 4, age: 2 }),
            }],
            &[ObservedEntry {
                index: entry,
                ring: Some(RingLocation::new(RingIndex(1), RevisionIndex(0))),
                included_members: 32,
            }],
            &params(),
        )
        .expect("both records are tracked");

        assert_eq!(
            store.coin(PurseId::MAIN, coin).expect("exists").age,
            CoinAge(2)
        );
        assert_eq!(
            store.entry(PurseId::MAIN, entry).expect("exists").on_chain,
            EntryOnChainState::Ready
        );
        assert_eq!(
            store
                .balance(PurseId::MAIN, Timestamp(0))
                .expect("purse exists")
                .spendable,
            Amount::from_cents(32)
        );
    }

    #[test]
    fn a_thin_ring_is_classified_as_degraded() {
        let mut store = CoinageStore::new("Main".to_string());
        let entry = store
            .allocate_entry(PurseId::MAIN, exponent(4), Timestamp(0), Duration::ZERO)
            .expect("purse exists");

        apply_observations(
            &mut store,
            PurseId::MAIN,
            &[],
            &[ObservedEntry {
                index: entry,
                ring: Some(RingLocation::new(RingIndex(1), RevisionIndex(0))),
                included_members: 3,
            }],
            &params(),
        )
        .expect("the entry is tracked");

        assert_eq!(
            store.entry(PurseId::MAIN, entry).expect("exists").on_chain,
            EntryOnChainState::Degraded(3)
        );
    }

    #[test]
    fn an_entry_the_chain_no_longer_locates_reads_as_missing() {
        let mut store = CoinageStore::new("Main".to_string());
        let entry = store
            .allocate_entry(PurseId::MAIN, exponent(4), Timestamp(0), Duration::ZERO)
            .expect("purse exists");
        apply_observations(
            &mut store,
            PurseId::MAIN,
            &[],
            &[ObservedEntry {
                index: entry,
                ring: Some(RingLocation::new(RingIndex(1), RevisionIndex(0))),
                included_members: 32,
            }],
            &params(),
        )
        .expect("tracked");

        apply_observations(
            &mut store,
            PurseId::MAIN,
            &[],
            &[ObservedEntry {
                index: entry,
                ring: None,
                included_members: 0,
            }],
            &params(),
        )
        .expect("tracked");

        let record = store.entry(PurseId::MAIN, entry).expect("exists");
        assert_eq!(record.on_chain, EntryOnChainState::Missing);
        assert_eq!(
            record.local,
            EntryLocalState::Available,
            "losing a location does not retire the record"
        );
    }

    #[test]
    fn a_denomination_disagreement_is_refused_rather_than_absorbed() {
        // If the chain says a coin is a different size than the local record,
        // something is wrong with derivation or the record. Overwriting would
        // silently corrupt the balance.
        let mut store = CoinageStore::new("Main".to_string());
        let coin = store
            .add_pending_coin(PurseId::MAIN, exponent(4))
            .expect("purse exists");

        let mismatch = apply_observations(
            &mut store,
            PurseId::MAIN,
            &[ObservedCoin {
                index: coin,
                coin: Some(ChainCoin { value: 5, age: 0 }),
            }],
            &[],
            &params(),
        );

        assert!(matches!(mismatch, Err(CoinageError::Internal(_))));
    }

    #[test]
    fn an_untracked_record_is_refused() {
        let mut store = CoinageStore::new("Main".to_string());

        let stray = apply_observations(
            &mut store,
            PurseId::MAIN,
            &[ObservedCoin {
                index: CoinIndex(42),
                coin: Some(ChainCoin { value: 4, age: 0 }),
            }],
            &[],
            &params(),
        );

        assert!(matches!(stray, Err(CoinageError::Internal(_))));
    }
}
