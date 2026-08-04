//! Reading coinage chain state.
//!
//! [`super::storage`] owns the byte layouts — keys and value decoding — and is
//! testable offline. This module issues the reads, deriving the accounts to ask
//! about from the layer's own record indices.
//!
//! Every read takes an explicit block hash. Recovery depends on that: a
//! decision it makes must not be undoable, so its reads are pinned to a
//! finalized block rather than taken at whatever the best block happens to be.

use subxt::ext::scale_value::scale::decode_as_type;
use subxt::ext::scale_value::{Composite, Value, ValueDef};

use crate::host_logic::coinage::derivation;
use crate::host_logic::coinage::error::CoinageError;
use crate::host_logic::coinage::params::CoinageParameters;
use crate::host_logic::coinage::store::CoinageStore;
use crate::host_logic::coinage::types::{
    BlockHash, CoinIndex, EntryIndex, PurseId, RevisionIndex, RingIndex, RingLocation, Timestamp,
};
use crate::runtime::coinage::storage;
use crate::runtime::statement_allowance::extension::Metadata;
use crate::runtime::statement_allowance::rpc::RpcClient;

/// Decode a `0x`-prefixed 32-byte block hash.
pub fn decode_block_hash(hash: &str) -> Result<BlockHash, CoinageError> {
    let bytes = hex::decode(hash.strip_prefix("0x").unwrap_or(hash))
        .map_err(|error| CoinageError::SubscriptionError(format!("block hash hex: {error}")))?;
    let length = bytes.len();
    bytes
        .try_into()
        .map(BlockHash)
        .map_err(|_| CoinageError::SubscriptionError(format!("block hash is {length} bytes")))
}

/// Height of the block at `hash`.
pub async fn block_number(rpc: &RpcClient, hash: &str) -> Result<u64, CoinageError> {
    let header = rpc
        .call("chain_getHeader", serde_json::json!([hash]))
        .await
        .map_err(|error| CoinageError::SubscriptionError(error.to_string()))?;
    let number = header
        .get("number")
        .and_then(serde_json::Value::as_str)
        .ok_or_else(|| {
            CoinageError::SubscriptionError(format!("chain_getHeader({hash}) carried no number"))
        })?;

    u64::from_str_radix(number.strip_prefix("0x").unwrap_or(number), 16)
        .map_err(|error| CoinageError::SubscriptionError(format!("header number: {error}")))
}

/// Whether the chain holds a coin at this record's account, as of `at`.
pub async fn coin_present(
    rpc: &RpcClient,
    entropy: &[u8],
    purse: PurseId,
    index: CoinIndex,
    at: &str,
) -> Result<bool, CoinageError> {
    let account = derivation::coin_account_id(entropy, purse, index)?;
    let raw = rpc
        .get_storage_at(&storage::coins_by_owner_key(&account), at)
        .await
        .map_err(|error| CoinageError::SubscriptionError(error.to_string()))?;

    // Decoded rather than merely tested for presence: a value that will not
    // decode means the layout assumption is wrong, and reading that as "the
    // coin is there" would build a success verdict on bytes nobody understood.
    Ok(storage::decode_coin(raw)?.is_some())
}

/// Whether the chain still places this recycler entry in a ring, as of `at`.
pub async fn entry_present(
    rpc: &RpcClient,
    entropy: &[u8],
    purse: PurseId,
    index: EntryIndex,
    at: &str,
) -> Result<bool, CoinageError> {
    let member_key = derivation::entry_member_key(entropy, purse, index)?;
    let raw = rpc
        .get_storage_at(&storage::recyclers_coin_to_recycler_key(&member_key), at)
        .await
        .map_err(|error| CoinageError::SubscriptionError(error.to_string()))?;

    Ok(raw.is_some())
}

/// The chain's lock on a coin account, as of `at`.
pub async fn coin_lock(
    rpc: &RpcClient,
    entropy: &[u8],
    purse: PurseId,
    index: CoinIndex,
    at: &str,
) -> Result<Option<storage::ChainCoinLock>, CoinageError> {
    let account = derivation::coin_account_id(entropy, purse, index)?;
    let raw = rpc
        .get_storage_at(&storage::locked_coins_key(&account), at)
        .await
        .map_err(|error| CoinageError::SubscriptionError(error.to_string()))?;

    storage::decode_coin_lock(raw)
}

/// Read every chain fact backing one purse's records and apply it.
///
/// `coinage-layer.md` §6.1. Six storage sets are consulted; the pallet's own
/// `RecyclersCoinToRecycler` only says which *denomination* collection an entry
/// belongs to, so the ring index comes from the `Members` pallet and the
/// revision from that ring's root.
///
/// Pinned to one block for the whole purse: a refresh that read half its
/// records before a new block and half after would produce a view that never
/// existed, and selection would then plan against it.
pub async fn refresh_purse(
    rpc: &RpcClient,
    metadata: &Metadata,
    store: &mut CoinageStore,
    entropy: &[u8],
    purse: PurseId,
    params: &CoinageParameters,
    at: &str,
) -> Result<(), CoinageError> {
    let mut coins = Vec::new();
    for coin in store.coins_in(purse) {
        let account = derivation::coin_account_id(entropy, purse, coin.index)?;
        coins.push(storage::ObservedCoin {
            index: coin.index,
            coin: storage::decode_coin(
                read(rpc, &storage::coins_by_owner_key(&account), at).await?,
            )?,
            lock: storage::decode_coin_lock(
                read(rpc, &storage::locked_coins_key(&account), at).await?,
            )?,
        });
    }

    let mut entries = Vec::new();
    let mut alias_locks = Vec::new();
    for entry in store.entries_in(purse) {
        let member_key = derivation::entry_member_key(entropy, purse, entry.index)?;
        let collection = storage::recycler_collection_id(entry.exponent);

        let loaded = read(
            rpc,
            &storage::recyclers_coin_to_recycler_key(&member_key),
            at,
        )
        .await?
        .is_some();
        if !loaded {
            entries.push(storage::ObservedEntry {
                index: entry.index,
                ring: None,
                included_members: 0,
                ring_immutable_since: None,
            });
            continue;
        }

        let position = storage::decode_ring_position(
            read(rpc, &storage::members_key(&collection, &member_key), at).await?,
        )?;
        let Some(ring) = position
            .as_ref()
            .and_then(storage::RingPosition::ring_index)
        else {
            // Loaded into the collection but not yet placed in a ring, or
            // suspended. Either way there is nothing to unload from.
            entries.push(storage::ObservedEntry {
                index: entry.index,
                ring: None,
                included_members: 0,
                ring_immutable_since: None,
            });
            continue;
        };

        let status = storage::decode_ring_status(
            read(rpc, &storage::ring_keys_status_key(&collection, ring), at).await?,
        )?;
        let revision = ring_revision(rpc, metadata, &collection, ring, at).await?;

        entries.push(storage::ObservedEntry {
            index: entry.index,
            ring: revision.map(|revision| RingLocation::new(ring, revision)),
            included_members: status.included,
            ring_immutable_since: status.immutable_since.map(Timestamp::from_unix_seconds),
        });
        alias_locks.push((entry.index, entry.exponent, ring));
    }

    storage::apply_observations(store, purse, &coins, &entries, params)?;

    for (index, exponent, ring) in alias_locks {
        let alias = super::proof::recycler_alias(entropy, purse, index)?;
        let locked_until = match storage::decode_alias_state(
            read(
                rpc,
                &storage::recycler_alias_state_key(exponent, ring, &alias),
                at,
            )
            .await?,
        )? {
            Some(storage::ChainAliasState::Locked(lock)) => {
                Some(Timestamp::from_unix_seconds(lock.until))
            }
            // `Unloaded` is terminal, not a lock: the entry is gone rather than
            // temporarily refused, and the operation that unloaded it owns that
            // transition.
            Some(storage::ChainAliasState::Unloaded) | None => None,
        };
        store.observe_entry_alias_lock(purse, index, locked_until)?;
    }

    Ok(())
}

/// Read one storage value pinned to `at`.
async fn read(rpc: &RpcClient, key: &[u8], at: &str) -> Result<Option<Vec<u8>>, CoinageError> {
    rpc.get_storage_at(key, at)
        .await
        .map_err(|error| CoinageError::SubscriptionError(error.to_string()))
}

/// The revision of a ring's current root.
///
/// Decoded through the metadata registry rather than by byte offset: the root
/// is a bandersnatch ring commitment whose size is a property of the curve, and
/// a hard-coded offset would read a neighbouring field the day it changes.
async fn ring_revision(
    rpc: &RpcClient,
    metadata: &Metadata,
    collection: &[u8; 32],
    ring: RingIndex,
    at: &str,
) -> Result<Option<RevisionIndex>, CoinageError> {
    let Some(raw) = read(rpc, &storage::ring_root_key(collection, ring), at).await? else {
        return Ok(None);
    };
    let type_id = metadata
        .storage_value_type("Members", "Root")
        .ok_or_else(|| {
            CoinageError::Internal("Members.Root is absent from metadata".to_string())
        })?;
    let value = decode_as_type(&mut &raw[..], type_id, metadata.registry())
        .map_err(|error| CoinageError::Internal(format!("decoding a ring root failed: {error}")))?;

    revision_field(&value)
        .map(Some)
        .ok_or_else(|| CoinageError::Internal("a ring root carried no revision field".to_string()))
}

/// Pull the `revision` field out of a decoded ring root.
fn revision_field(value: &Value<u32>) -> Option<RevisionIndex> {
    let ValueDef::Composite(Composite::Named(fields)) = &value.value else {
        return None;
    };
    fields
        .iter()
        .find(|(name, _)| name == "revision")
        .and_then(|(_, value)| value.as_u128())
        .and_then(|revision| u32::try_from(revision).ok())
        .map(RevisionIndex)
}

#[cfg(test)]
mod tests {
    use subxt_rpcs::RpcClient as HostRpcClient;

    use crate::runtime::statement_allowance::rpc::testing::ScriptedRpc;

    use super::*;

    const ENTROPY: [u8; 32] = [7; 32];
    const AT: &str = "0x0707070707070707070707070707070707070707070707070707070707070707";

    fn scripted(responses: &[String]) -> (ScriptedRpc, RpcClient) {
        let scripted = ScriptedRpc::new(responses.iter().map(String::as_str));
        let rpc = RpcClient::new(HostRpcClient::new(scripted.clone()));
        (scripted, rpc)
    }

    fn block_on<F: core::future::Future>(future: F) -> F::Output {
        futures::executor::block_on(future)
    }

    #[test]
    fn a_block_hash_round_trips() {
        assert_eq!(decode_block_hash(AT).expect("decodes"), BlockHash([7; 32]));
        assert!(decode_block_hash("0xnothex").is_err());
        assert!(decode_block_hash("0x00").is_err(), "wrong length");
    }

    #[test]
    fn a_header_number_is_read_as_hex() {
        let (_scripted, rpc) = scripted(&[r#"{"number":"0x3e8"}"#.to_string()]);

        assert_eq!(block_on(block_number(&rpc, AT)).expect("reads"), 1_000);
    }

    #[test]
    fn a_header_without_a_number_is_an_error() {
        let (_scripted, rpc) = scripted(&[r#"{"parentHash":"0x00"}"#.to_string()]);

        assert!(block_on(block_number(&rpc, AT)).is_err());
    }

    #[test]
    fn an_absent_coin_reads_as_absent_and_a_present_one_as_present() {
        use parity_scale_codec::Encode;

        let (_scripted, rpc) = scripted(&["null".to_string()]);
        assert!(
            !block_on(coin_present(
                &rpc,
                &ENTROPY,
                PurseId::MAIN,
                CoinIndex(0),
                AT
            ))
            .expect("reads")
        );

        let coin = storage::ChainCoin { value: 4, age: 1 }.encode();
        let (_scripted, rpc) = scripted(&[format!("\"0x{}\"", hex::encode(coin))]);
        assert!(
            block_on(coin_present(
                &rpc,
                &ENTROPY,
                PurseId::MAIN,
                CoinIndex(0),
                AT
            ))
            .expect("reads")
        );
    }

    #[test]
    fn an_undecodable_coin_is_an_error_not_a_presence() {
        // Reading garbage as "the coin is there" would let recovery declare a
        // transaction successful on the strength of bytes nobody understood.
        let (_scripted, rpc) = scripted(&["\"0x\"".to_string()]);

        assert!(
            block_on(coin_present(
                &rpc,
                &ENTROPY,
                PurseId::MAIN,
                CoinIndex(0),
                AT
            ))
            .is_err()
        );
    }

    #[test]
    fn the_read_is_pinned_to_the_requested_block() {
        // Recovery's whole guarantee rests on this: a decision taken at the
        // best block could describe a fork that is about to vanish.
        let (scripted, rpc) = scripted(&["null".to_string()]);

        block_on(coin_present(
            &rpc,
            &ENTROPY,
            PurseId::MAIN,
            CoinIndex(0),
            AT,
        ))
        .expect("reads");

        let (method, params) = scripted.calls().into_iter().next().expect("one call");
        assert_eq!(method, "state_getStorage");
        assert!(params.contains(AT), "the block hash is passed: {params}");
    }

    #[test]
    fn a_ring_status_without_immutability_still_decodes() {
        use parity_scale_codec::Encode;

        let status = storage::RingKeysStatus {
            total: 32,
            included: 32,
            immutable_since: Some(1_700_000_000),
        };

        assert_eq!(
            storage::decode_ring_status(Some(status.encode())).expect("decodes"),
            status,
            "immutable_since is the rescue sweep's only warning"
        );
    }

    #[test]
    fn refreshing_a_purse_assembles_coin_and_entry_state() {
        use parity_scale_codec::Encode;

        use crate::host_logic::coinage::store::CoinageStore;
        use crate::host_logic::coinage::types::DenominationExponent;

        let exponent = DenominationExponent::new(4).expect("in range");
        let mut store = CoinageStore::new("Main".to_string());
        let coin = store
            .add_pending_coin(PurseId::MAIN, exponent)
            .expect("purse exists");
        let entry = store
            .allocate_entry(
                PurseId::MAIN,
                exponent,
                Timestamp(0),
                core::time::Duration::ZERO,
            )
            .expect("purse exists");

        // The reads, in the order refresh_purse makes them.
        let responses = vec![
            // coin: CoinsByOwner, then LockedCoins
            format!(
                "\"0x{}\"",
                hex::encode(storage::ChainCoin { value: 4, age: 2 }.encode())
            ),
            "null".to_string(),
            // entry: RecyclersCoinToRecycler (loaded), Members (ring 1)
            "\"0x04\"".to_string(),
            format!(
                "\"0x{}\"",
                hex::encode(
                    storage::RingPosition::Included {
                        ring_index: 1,
                        ring_page: 0,
                        ring_position: 3,
                    }
                    .encode()
                )
            ),
            // RingKeysStatus
            format!(
                "\"0x{}\"",
                hex::encode(
                    storage::RingKeysStatus {
                        total: 32,
                        included: 32,
                        immutable_since: Some(1_700_000_000),
                    }
                    .encode()
                )
            ),
            // Members::Root — absent, so no revision and therefore no usable
            // ring location.
            "null".to_string(),
            // RecyclerAliasStates
            "null".to_string(),
        ];
        let (_scripted, rpc) = scripted(&responses);
        let metadata = Metadata::decode(include_bytes!(
            "../../../tests/fixtures/paseo-next-v2-metadata.scale"
        ))
        .expect("the fixture decodes");

        block_on(refresh_purse(
            &rpc,
            &metadata,
            &mut store,
            &ENTROPY,
            PurseId::MAIN,
            &CoinageParameters::default(),
            AT,
        ))
        .expect("refreshes");

        let coin = store.coin(PurseId::MAIN, coin).expect("exists");
        assert_eq!(coin.age.0, 2);
        assert_eq!(coin.locked_until, None);
        let entry = store.entry(PurseId::MAIN, entry).expect("exists");
        assert_eq!(
            entry.ring, None,
            "a ring whose root has no revision cannot be proven against"
        );
        // The rescue sweep's deadline must survive the whole pipeline: decoded
        // from RingStatus, carried through ObservedEntry, stored on the record.
        // Losing it anywhere along the way is how entries expire unnoticed.
        assert_eq!(
            entry.ring_immutable_since,
            Some(Timestamp::from_unix_seconds(1_700_000_000)),
            "the rescue deadline reached the record"
        );
        // Recorded even though this entry is not currently rescuable: without
        // a committed root there is nothing to prove membership against, so
        // `needs_rescue` declines. Immutability is a fact about the ring and is
        // stored unconditionally, so the sweep can act the moment the ring
        // becomes usable rather than needing a second observation pass.
        assert!(
            !entry.needs_rescue(
                Timestamp::from_unix_seconds(1_700_000_000)
                    .saturating_add(core::time::Duration::from_secs(80 * 24 * 60 * 60)),
                core::time::Duration::from_secs(90 * 24 * 60 * 60),
                core::time::Duration::from_secs(22 * 24 * 60 * 60),
            )
        );
    }

    #[test]
    fn an_entry_still_onboarding_is_not_placed_in_a_ring() {
        use parity_scale_codec::Encode;

        use crate::host_logic::coinage::store::CoinageStore;
        use crate::host_logic::coinage::types::DenominationExponent;

        let exponent = DenominationExponent::new(4).expect("in range");
        let mut store = CoinageStore::new("Main".to_string());
        let entry = store
            .allocate_entry(
                PurseId::MAIN,
                exponent,
                Timestamp(0),
                core::time::Duration::ZERO,
            )
            .expect("purse exists");

        let (_scripted, rpc) = scripted(&[
            "\"0x04\"".to_string(),
            format!(
                "\"0x{}\"",
                hex::encode(
                    storage::RingPosition::Onboarding {
                        queue_page: 0,
                        queued_at: 1_700_000_000,
                    }
                    .encode()
                )
            ),
        ]);
        let metadata = Metadata::decode(include_bytes!(
            "../../../tests/fixtures/paseo-next-v2-metadata.scale"
        ))
        .expect("the fixture decodes");

        block_on(refresh_purse(
            &rpc,
            &metadata,
            &mut store,
            &ENTROPY,
            PurseId::MAIN,
            &CoinageParameters::default(),
            AT,
        ))
        .expect("refreshes");

        // No ring means nothing to unload from, so the value stays pending
        // rather than being offered to selection.
        assert!(
            !store
                .entry(PurseId::MAIN, entry)
                .expect("exists")
                .is_selectable(Timestamp(0), true)
        );
    }
}
