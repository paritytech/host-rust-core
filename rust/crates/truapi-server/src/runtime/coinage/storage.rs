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
    RingIndex, RingLocation, Timestamp,
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

/// `Coinage::LockedCoins(account)` — `Twox64Concat` over `AccountId`.
///
/// Absence is the common case and means the coin is unlocked; a value means the
/// runtime refuses the coin as an origin until its expiry.
pub fn locked_coins_key(account: &CoinAccountId) -> Vec<u8> {
    [
        twox_128(b"Coinage").as_slice(),
        twox_128(b"LockedCoins").as_slice(),
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

/// `Coinage::RecyclerAliasStates((value, ring, alias))` — a three-key
/// `StorageNMap`, every key `Twox64Concat`, concatenated in declaration order.
///
/// Keyed by the contextual alias rather than the entry's member key: the alias
/// is what an unload reveals, and it is what the pallet locks after a failed
/// dispatch.
pub fn recycler_alias_state_key(
    exponent: DenominationExponent,
    ring: RingIndex,
    alias: &[u8; 32],
) -> Vec<u8> {
    [
        twox_128(b"Coinage").as_slice(),
        twox_128(b"RecyclerAliasStates").as_slice(),
        &twox_64_concat(&[exponent.get() as u8]),
        &twox_64_concat(&ring.0.to_le_bytes()),
        &twox_64_concat(alias),
    ]
    .concat()
}

/// `Members::Members(collection, member_key)` — the collection identifier is
/// used raw (`Identity`), the member key `Blake2_128Concat`.
///
/// This is the member-to-ring lookup: the coinage pallet's own
/// `RecyclersCoinToRecycler` only reports which *denomination* collection an
/// entry belongs to, never which ring inside it.
pub fn members_key(collection: &[u8; 32], member_key: &[u8; 32]) -> Vec<u8> {
    [
        twox_128(b"Members").as_slice(),
        twox_128(b"Members").as_slice(),
        collection.as_slice(),
        &blake2_128_concat(member_key),
    ]
    .concat()
}

/// `Members::Root(collection, ring_index)` — the collection identifier raw,
/// the ring index `Blake2_128Concat`.
///
/// Holds the ring commitment and its revision. A membership proof is only valid
/// against the revision it was built for, so an unload needs both halves of the
/// ring location.
pub fn ring_root_key(collection: &[u8; 32], ring: RingIndex) -> Vec<u8> {
    [
        twox_128(b"Members").as_slice(),
        twox_128(b"Root").as_slice(),
        collection.as_slice(),
        &blake2_128_concat(&ring.0.to_le_bytes()),
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

/// `Members::RingKeys((collection, ring_index, page))` — the collection
/// identifier raw, the ring index `Blake2_128Concat`, the page `Twox64Concat`.
///
/// A ring's members are paged, and proving membership needs all of them: the
/// prover reconstructs the ring commitment from the member list, so a missed page
/// produces a proof against a ring the chain does not have.
pub fn ring_keys_key(collection: &[u8; 32], ring: RingIndex, page: u32) -> Vec<u8> {
    [
        twox_128(b"Members").as_slice(),
        twox_128(b"RingKeys").as_slice(),
        collection.as_slice(),
        &blake2_128_concat(&ring.0.to_le_bytes()),
        &twox_64_concat(&page.to_le_bytes()),
    ]
    .concat()
}

/// `Members::Collections(collection)` — the collection identifier used raw.
///
/// Carries the ring size, which fixes the proof domain. A proof built for the
/// wrong domain does not verify.
pub fn collections_key(collection: &[u8; 32]) -> Vec<u8> {
    [
        twox_128(b"Members").as_slice(),
        twox_128(b"Collections").as_slice(),
        collection.as_slice(),
    ]
    .concat()
}

/// `Coinage::ConsumedFreeUnloadTokens((period, alias))` — both keys
/// `Twox64Concat`.
///
/// Presence means the slot is spent. A free unload token is one `(period,
/// counter)` slot, identified on chain by the alias the personhood key produces
/// in that slot's context.
pub fn consumed_free_unload_tokens_key(period: u32, alias: &[u8; 32]) -> Vec<u8> {
    [
        twox_128(b"Coinage").as_slice(),
        twox_128(b"ConsumedFreeUnloadTokens").as_slice(),
        &twox_64_concat(&period.to_le_bytes()),
        &twox_64_concat(alias),
    ]
    .concat()
}

/// `Coinage::PaidUnloadTokenMembers(member_key)` — `Twox64Concat` over the
/// member key.
///
/// Presence means this key has joined a paid unload-token ring.
pub fn paid_unload_token_members_key(member_key: &[u8; 32]) -> Vec<u8> {
    [
        twox_128(b"Coinage").as_slice(),
        twox_128(b"PaidUnloadTokenMembers").as_slice(),
        &twox_64_concat(member_key),
    ]
    .concat()
}

/// `System::Account(account)` — `Blake2_128Concat` over `AccountId`.
///
/// The fee account's native balance lives here, and it is what decides between
/// the two unload fee modes (§6.6).
pub fn system_account_key(account: &CoinAccountId) -> Vec<u8> {
    [
        twox_128(b"System").as_slice(),
        twox_128(b"Account").as_slice(),
        &blake2_128_concat(&account.0),
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

/// Why the chain is holding a coin.
///
/// A single-variant enum on chain today. Decoded as an enum rather than skipped
/// so a runtime that adds a reason fails to decode instead of being read as the
/// one reason this build knows.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Encode, Decode)]
pub enum ChainLockReason {
    /// A dispatch that used the coin as its origin failed.
    FailedDispatch {
        /// Consecutive failures so far; the lock doubles with each.
        retries: u8,
    },
}

/// The lock the pallet stores against a coin account.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Encode, Decode)]
pub struct ChainCoinLock {
    /// Why the coin is locked.
    pub reason: ChainLockReason,
    /// Unix timestamp, in seconds, at which the lock expires.
    pub until: u64,
}

/// What the pallet records against a recycler alias.
///
/// Absence means the alias is available. The two present states are not
/// interchangeable: `Locked` is temporary and the entry comes back, `Unloaded`
/// is terminal and it never will.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Encode, Decode)]
pub enum ChainAliasState {
    /// Temporarily locked after a failed dispatch.
    Locked(ChainCoinLock),
    /// Permanently consumed by a successful unload.
    Unloaded,
}

/// How full a ring is, as `Members` reports it.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Encode, Decode)]
pub struct RingKeysStatus {
    /// Keys submitted to the ring.
    pub total: u32,
    /// Keys included in its committed membership.
    pub included: u32,
    /// When the ring became immutable, in Unix seconds, once it is full.
    ///
    /// The clock the ring-expiration rescue sweep races: the chain destroys the
    /// backing value of any entry still in the ring `RecyclerExpirationTime`
    /// after this. Decoding the status without this field would silently drop
    /// the only signal that a purse is about to lose money.
    pub immutable_since: Option<u64>,
}

/// Where the `Members` pallet places one member key.
///
/// Only `Included` carries a ring index, and that is the point: an onboarding
/// or suspended member is in no ring, so an entry in either state cannot be
/// unloaded and must not be treated as merely "waiting for members".
#[derive(Debug, Clone, Copy, PartialEq, Eq, Encode, Decode)]
pub enum RingPosition {
    /// Queued, not yet in a ring.
    Onboarding {
        /// Page of the onboarding queue.
        queue_page: u32,
        /// When the member was queued, in Unix seconds.
        queued_at: u64,
    },
    /// Registered in a ring.
    Included {
        /// Ring holding the member.
        ring_index: u32,
        /// Page within the ring.
        ring_page: u32,
        /// Position within the page.
        ring_position: u32,
    },
    /// Suspended, and so in no ring at all.
    Suspended,
}

impl RingPosition {
    /// The ring holding this member, if it is in one.
    pub const fn ring_index(&self) -> Option<RingIndex> {
        match self {
            Self::Included { ring_index, .. } => Some(RingIndex(*ring_index)),
            Self::Onboarding { .. } | Self::Suspended => None,
        }
    }
}

/// One coin's chain state, ready to apply.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct ObservedCoin {
    /// Which local record this is about.
    pub index: CoinIndex,
    /// The coin the chain reports, or `None` if the account is empty.
    pub coin: Option<ChainCoin>,
    /// The chain's lock on the account, or `None` if it holds none.
    pub lock: Option<ChainCoinLock>,
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
    /// When that ring became immutable, if it has. Drives the rescue sweep.
    pub ring_immutable_since: Option<Timestamp>,
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

/// Decode a `LockedCoins` value, treating an absent entry as unlocked.
pub fn decode_coin_lock(bytes: Option<Vec<u8>>) -> Result<Option<ChainCoinLock>, CoinageError> {
    match bytes {
        None => Ok(None),
        Some(raw) => ChainCoinLock::decode(&mut &raw[..])
            .map(Some)
            .map_err(|error| {
                CoinageError::Internal(format!("decoding a coin lock failed: {error}"))
            }),
    }
}

/// Decode a `Members::Members` value; absence means the key is unknown to the
/// collection.
pub fn decode_ring_position(bytes: Option<Vec<u8>>) -> Result<Option<RingPosition>, CoinageError> {
    match bytes {
        None => Ok(None),
        Some(raw) => RingPosition::decode(&mut &raw[..])
            .map(Some)
            .map_err(|error| {
                CoinageError::Internal(format!("decoding a ring position failed: {error}"))
            }),
    }
}

/// Decode a `RecyclerAliasStates` value, treating an absent entry as available.
pub fn decode_alias_state(bytes: Option<Vec<u8>>) -> Result<Option<ChainAliasState>, CoinageError> {
    match bytes {
        None => Ok(None),
        Some(raw) => ChainAliasState::decode(&mut &raw[..])
            .map(Some)
            .map_err(|error| {
                CoinageError::Internal(format!("decoding an alias state failed: {error}"))
            }),
    }
}

/// Decode a `RingKeysStatus` value, treating an absent entry as an empty ring.
pub fn decode_ring_status(bytes: Option<Vec<u8>>) -> Result<RingKeysStatus, CoinageError> {
    match bytes {
        None => Ok(RingKeysStatus {
            total: 0,
            included: 0,
            immutable_since: None,
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
        // The lock is applied first and unconditionally: it is a fact about the
        // account whether or not the account currently holds a coin, and a
        // record whose lock has been dropped must stop reporting one.
        store.observe_coin_lock(
            purse,
            observed.index,
            observed
                .lock
                .map(|lock| Timestamp::from_unix_seconds(lock.until)),
        )?;

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
        store.observe_entry_ring_immutability(
            purse,
            observed.index,
            observed.ring_immutable_since,
        )?;

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
        ring_immutable_since: status.immutable_since.map(Timestamp::from_unix_seconds),
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

        let lock_key = locked_coins_key(&account);
        assert_eq!(&lock_key[..16], twox_128(b"Coinage").as_slice());
        assert_eq!(&lock_key[16..32], twox_128(b"LockedCoins").as_slice());
        assert_eq!(&lock_key[32..40], twox_64(&account.0).as_slice());
        assert_eq!(&lock_key[40..], &account.0);
        assert_ne!(
            lock_key, coin_key,
            "the lock and the coin are separate reads on the same account"
        );
    }

    #[test]
    fn an_absent_lock_means_unlocked_not_an_error() {
        assert_eq!(decode_coin_lock(None).expect("absent is fine"), None);
    }

    #[test]
    fn a_coin_lock_round_trips_through_the_pallet_layout() {
        let lock = ChainCoinLock {
            reason: ChainLockReason::FailedDispatch { retries: 2 },
            until: 1_700_000_000,
        };
        let encoded = lock.encode();

        assert_eq!(encoded.len(), 1 + 1 + 8, "variant, retries, then u64");
        assert_eq!(
            decode_coin_lock(Some(encoded)).expect("decodes"),
            Some(lock)
        );
    }

    #[test]
    fn an_unrecognized_lock_reason_fails_rather_than_being_read_as_the_known_one() {
        // Reason variant 9 does not exist. Reading it as `FailedDispatch` would
        // attach a wrong expiry to a real coin.
        let mut bytes = vec![9u8, 0];
        bytes.extend_from_slice(&1_700_000_000u64.to_le_bytes());

        assert!(decode_coin_lock(Some(bytes)).is_err());
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
                lock: None,
            }],
            &[ObservedEntry {
                index: entry,
                ring: Some(RingLocation::new(RingIndex(1), RevisionIndex(0))),
                included_members: 32,
                ring_immutable_since: None,
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

    /// A store holding one observed coin, ready to have locks applied to it.
    fn store_with_a_coin() -> (CoinageStore, CoinIndex) {
        let mut store = CoinageStore::new("Main".to_string());
        let coin = store
            .add_pending_coin(PurseId::MAIN, exponent(4))
            .expect("purse exists");
        (store, coin)
    }

    fn observe(
        store: &mut CoinageStore,
        index: CoinIndex,
        lock: Option<ChainCoinLock>,
    ) -> Result<(), CoinageError> {
        apply_observations(
            store,
            PurseId::MAIN,
            &[ObservedCoin {
                index,
                coin: Some(ChainCoin { value: 4, age: 0 }),
                lock,
            }],
            &[],
            &params(),
        )
    }

    #[test]
    fn a_chain_lock_is_read_as_seconds_and_stored_as_milliseconds() {
        // The pallet counts seconds and this layer counts milliseconds. Getting
        // this wrong makes a 60-second lock look 60 milliseconds long, so the
        // coin is reselected immediately and the retry is refused again.
        let (mut store, coin) = store_with_a_coin();

        observe(
            &mut store,
            coin,
            Some(ChainCoinLock {
                reason: ChainLockReason::FailedDispatch { retries: 0 },
                until: 1_700_000_060,
            }),
        )
        .expect("the coin is tracked");

        let record = store.coin(PurseId::MAIN, coin).expect("exists");
        assert_eq!(record.locked_until, Some(Timestamp(1_700_000_060_000)));
        assert!(!record.is_selectable(Timestamp(1_700_000_059_999)));
        assert!(record.is_selectable(Timestamp(1_700_000_060_000)));
    }

    #[test]
    fn observing_an_unlocked_account_releases_a_previous_lock() {
        // The chain drops the entry once the lock expires, so absence has to
        // clear the local record rather than being ignored as "no news".
        let (mut store, coin) = store_with_a_coin();
        observe(
            &mut store,
            coin,
            Some(ChainCoinLock {
                reason: ChainLockReason::FailedDispatch { retries: 0 },
                until: 1_700_000_060,
            }),
        )
        .expect("the coin is tracked");

        observe(&mut store, coin, None).expect("the coin is tracked");

        let record = store.coin(PurseId::MAIN, coin).expect("exists");
        assert_eq!(record.locked_until, None);
        assert!(record.is_selectable(Timestamp(0)));
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
                ring_immutable_since: None,
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
                ring_immutable_since: None,
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
                ring_immutable_since: None,
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
                lock: None,
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
                lock: None,
            }],
            &[],
            &params(),
        );

        assert!(matches!(stray, Err(CoinageError::Internal(_))));
    }

    #[test]
    fn the_alias_state_key_is_pinned() {
        // A three-key NMap: every key Twox64Concat, concatenated in the order
        // the pallet declares them. Getting the order wrong reads a different
        // alias entirely, which would look like "unlocked" and let selection
        // reoffer an entry the runtime refuses.
        let alias = [0xab; 32];
        let key = recycler_alias_state_key(exponent(4), RingIndex(7), &alias);

        assert_eq!(&key[..16], twox_128(b"Coinage").as_slice());
        assert_eq!(&key[16..32], twox_128(b"RecyclerAliasStates").as_slice());
        assert_eq!(&key[32..40], twox_64(&[4u8]).as_slice());
        assert_eq!(&key[40..41], &[4u8]);
        assert_eq!(&key[41..49], twox_64(&7u32.to_le_bytes()).as_slice());
        assert_eq!(&key[49..53], &7u32.to_le_bytes());
        assert_eq!(&key[53..61], twox_64(&alias).as_slice());
        assert_eq!(&key[61..], &alias);
    }

    #[test]
    fn the_ring_page_and_collection_keys_are_pinned() {
        // The three-key `RingKeys` map mixes all three hashers, so an order or
        // hasher slip returns an empty page — indistinguishable from a ring that
        // ends there, which would silently produce a proof against a truncated
        // ring.
        let collection = recycler_collection_id(exponent(4));
        let key = ring_keys_key(&collection, RingIndex(3), 2);

        assert_eq!(&key[..16], twox_128(b"Members").as_slice());
        assert_eq!(&key[16..32], twox_128(b"RingKeys").as_slice());
        assert_eq!(&key[32..64], &collection, "the collection is raw");
        assert_eq!(&key[64..80], blake2_128(&3u32.to_le_bytes()));
        assert_eq!(&key[80..84], &3u32.to_le_bytes());
        assert_eq!(&key[84..92], twox_64(&2u32.to_le_bytes()).as_slice());
        assert_eq!(&key[92..], &2u32.to_le_bytes());

        let collections = collections_key(&collection);
        assert_eq!(&collections[16..32], twox_128(b"Collections").as_slice());
        assert_eq!(&collections[32..], &collection);
        assert_eq!(collections.len(), 16 + 16 + 32);
    }

    #[test]
    fn the_unload_token_and_balance_keys_are_pinned() {
        let alias = [0x5c; 32];
        let consumed = consumed_free_unload_tokens_key(77, &alias);

        assert_eq!(&consumed[..16], twox_128(b"Coinage").as_slice());
        assert_eq!(
            &consumed[16..32],
            twox_128(b"ConsumedFreeUnloadTokens").as_slice()
        );
        assert_eq!(&consumed[32..40], twox_64(&77u32.to_le_bytes()).as_slice());
        assert_eq!(&consumed[40..44], &77u32.to_le_bytes());
        assert_eq!(&consumed[44..52], twox_64(&alias).as_slice());
        assert_eq!(&consumed[52..], &alias);

        // A different period must be a different slot, or one period's spend
        // would read as every period's.
        assert_ne!(consumed, consumed_free_unload_tokens_key(78, &alias));

        let member = [0x91; 32];
        let paid = paid_unload_token_members_key(&member);
        assert_eq!(
            &paid[16..32],
            twox_128(b"PaidUnloadTokenMembers").as_slice()
        );
        assert_eq!(&paid[32..40], twox_64(&member).as_slice());
        assert_eq!(&paid[40..], &member);

        let account = CoinAccountId([0x22; 32]);
        let balance = system_account_key(&account);
        assert_eq!(&balance[..16], twox_128(b"System").as_slice());
        assert_eq!(&balance[16..32], twox_128(b"Account").as_slice());
        assert_eq!(&balance[32..48], blake2_128(&account.0));
        assert_eq!(&balance[48..], &account.0);
    }

    #[test]
    fn an_alias_state_distinguishes_a_temporary_lock_from_a_permanent_one() {
        // The two are not interchangeable: locked comes back, unloaded never
        // does, and confusing them either strands value or reoffers a consumed
        // entry.
        let locked = ChainAliasState::Locked(ChainCoinLock {
            reason: ChainLockReason::FailedDispatch { retries: 1 },
            until: 1_700_000_120,
        });

        assert_eq!(
            decode_alias_state(Some(locked.encode())).expect("decodes"),
            Some(locked)
        );
        assert_eq!(
            decode_alias_state(Some(ChainAliasState::Unloaded.encode())).expect("decodes"),
            Some(ChainAliasState::Unloaded)
        );
        assert_eq!(
            decode_alias_state(None).expect("absent is fine"),
            None,
            "an absent entry means the alias is available"
        );
    }

    #[test]
    fn an_alias_lock_keeps_a_locally_available_entry_out_of_selection() {
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
                ring_immutable_since: None,
            }],
            &params(),
        )
        .expect("the entry is tracked");
        assert_eq!(
            store
                .balance(PurseId::MAIN, Timestamp(0))
                .expect("purse exists")
                .spendable,
            Amount::from_cents(16)
        );

        store
            .observe_entry_alias_lock(
                PurseId::MAIN,
                entry,
                Some(Timestamp::from_unix_seconds(1_700_000_120)),
            )
            .expect("the entry is tracked");

        let held = store
            .balance(PurseId::MAIN, Timestamp::from_unix_seconds(1_700_000_000))
            .expect("purse exists");
        assert_eq!(held.spendable, Amount::ZERO);
        assert_eq!(
            held.pending,
            Amount::from_cents(16),
            "the value is intact, just not yet usable"
        );
    }
}
