//! Rebuilding a wallet's records from the chain (`coinage-layer.md` §8.10,
//! Appendix C).
//!
//! Distinct from the operation recovery of §7.7, which resolves transactions that
//! were in flight when a process died. This is the other kind: durable state is
//! gone entirely, and everything the layer knows has to be re-derived from the root
//! entropy and looked up on chain.
//!
//! The scan walks a purse's derivation indices in batches, asking the chain about
//! each account, and stops after `gap_limit` consecutive batches find nothing. That
//! bound is what makes the scan terminate at all — there is no upper index to walk
//! to — and it is also the scan's one blind spot: a wallet with a long stretch of
//! unused indices followed by a used one stops short of it. §8.10's `extend_scan`
//! exists for exactly that, which is why this module takes its starting cursors as
//! arguments rather than always beginning at zero.
//!
//! # What a scan cannot bring back
//!
//! Two things, and both matter:
//!
//! - **The operation log.** Any transaction in flight when durable state was lost
//!   is unrecoverable as a transaction; the scan sees only whatever the chain
//!   ended up with.
//! - **Purse identifiers.** The chain has no notion of a purse, so a purse is only
//!   found if the caller supplies its identifier from a backup. The main purse is
//!   always scanned, because its identifier is fixed by construction.

use crate::host_logic::coinage::derivation;
use crate::host_logic::coinage::error::CoinageError;
use crate::host_logic::coinage::params::CoinageParameters;
use crate::host_logic::coinage::store::CoinageStore;
use crate::host_logic::coinage::types::{
    CoinIndex, DenominationExponent, EntryIndex, PurseId, Timestamp,
};
use crate::runtime::coinage::storage;
use crate::runtime::statement_allowance::rpc::RpcClient;

/// Where a scan of one purse should start, and what it found.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Default)]
pub struct ScanOutcome {
    /// Coin records restored.
    pub coins_found: u32,
    /// Recycler-entry records restored.
    pub entries_found: u32,
    /// First coin index the scan did not examine.
    pub next_coin_index: CoinIndex,
    /// First entry index the scan did not examine.
    pub next_entry_index: EntryIndex,
}

impl ScanOutcome {
    /// Whether the scan found anything at all.
    pub fn is_empty(&self) -> bool {
        self.coins_found == 0 && self.entries_found == 0
    }
}

/// Scan one purse's two derivation sub-trees, restoring what the chain holds.
///
/// The coin and entry sub-trees are walked independently, each with its own cursor
/// and its own gap counter: they are separate key types over separate storage, and
/// a purse can easily hold entries at high indices and no coins at all.
#[allow(clippy::too_many_arguments)]
pub async fn scan_purse(
    rpc: &RpcClient,
    store: &mut CoinageStore,
    entropy: &[u8],
    purse: PurseId,
    params: &CoinageParameters,
    from_coin: CoinIndex,
    from_entry: EntryIndex,
    now: Timestamp,
    at: &str,
) -> Result<ScanOutcome, CoinageError> {
    let coins = scan_coins(rpc, store, entropy, purse, params, from_coin, at).await?;
    let entries = scan_entries(rpc, store, entropy, purse, params, from_entry, now, at).await?;

    Ok(ScanOutcome {
        coins_found: coins.0,
        entries_found: entries.0,
        next_coin_index: coins.1,
        next_entry_index: entries.1,
    })
}

/// Walk the coin sub-tree until `gap_limit` consecutive batches are empty.
///
/// One round trip per batch, not per index: a scan with the recommended parameters
/// asks about hundreds of accounts, and doing that one at a time turns a recovery
/// into minutes of sequential requests against a live node.
async fn scan_coins(
    rpc: &RpcClient,
    store: &mut CoinageStore,
    entropy: &[u8],
    purse: PurseId,
    params: &CoinageParameters,
    from: CoinIndex,
    at: &str,
) -> Result<(u32, CoinIndex), CoinageError> {
    let mut cursor = from.0;
    let mut empty_batches = 0;
    let mut found = 0;

    while empty_batches < params.recovery_gap_limit {
        let indices = batch_indices(cursor, params.recovery_batch_size);
        if indices.is_empty() {
            // The index space is exhausted, which is not an error: there is simply
            // nothing further to ask about.
            return Ok((found, CoinIndex(u32::MAX)));
        }

        let mut keys = Vec::with_capacity(indices.len());
        for index in &indices {
            let account = derivation::coin_account_id(entropy, purse, CoinIndex(*index))?;
            keys.push(storage::coins_by_owner_key(&account));
        }
        let values = read_many(rpc, &keys, at).await?;

        let mut batch_found = false;
        for (index, raw) in indices.iter().zip(values) {
            let Some(coin) = storage::decode_coin(raw)? else {
                continue;
            };
            let exponent = DenominationExponent::new(coin.value).ok_or_else(|| {
                CoinageError::RecoveryFailed(format!(
                    "the chain reports denomination {} at coin index {index}, which this layer \
                     cannot represent",
                    coin.value
                ))
            })?;
            store.restore_coin(
                purse,
                CoinIndex(*index),
                exponent,
                crate::host_logic::coinage::types::CoinAge(coin.age),
            )?;
            found += 1;
            batch_found = true;
        }

        cursor = cursor.saturating_add(params.recovery_batch_size);
        empty_batches = if batch_found { 0 } else { empty_batches + 1 };
    }

    Ok((found, CoinIndex(cursor)))
}

/// Walk the recycler-entry sub-tree the same way.
///
/// An entry is found through the pallet's own `RecyclersCoinToRecycler`, which
/// answers with the denomination collection the member key belongs to — enough to
/// restore the record. Where the entry sits inside that collection is left to
/// ordinary observation, which runs over the restored records afterwards.
#[allow(clippy::too_many_arguments)]
async fn scan_entries(
    rpc: &RpcClient,
    store: &mut CoinageStore,
    entropy: &[u8],
    purse: PurseId,
    params: &CoinageParameters,
    from: EntryIndex,
    now: Timestamp,
    at: &str,
) -> Result<(u32, EntryIndex), CoinageError> {
    let mut cursor = from.0;
    let mut empty_batches = 0;
    let mut found = 0;

    while empty_batches < params.recovery_gap_limit {
        let indices = batch_indices(cursor, params.recovery_batch_size);
        if indices.is_empty() {
            return Ok((found, EntryIndex(u32::MAX)));
        }

        let mut keys = Vec::with_capacity(indices.len());
        for index in &indices {
            let member_key = derivation::entry_member_key(entropy, purse, EntryIndex(*index))?;
            keys.push(storage::recyclers_coin_to_recycler_key(&member_key));
        }
        let values = read_many(rpc, &keys, at).await?;

        let mut batch_found = false;
        for (index, raw) in indices.iter().zip(values) {
            let Some(bytes) = raw else {
                continue;
            };
            let value = decode_denomination(&bytes, *index)?;
            store.restore_entry(purse, EntryIndex(*index), value, now)?;
            found += 1;
            batch_found = true;
        }

        cursor = cursor.saturating_add(params.recovery_batch_size);
        empty_batches = if batch_found { 0 } else { empty_batches + 1 };
    }

    Ok((found, EntryIndex(cursor)))
}

/// The indices one batch covers, stopping at the end of the index space.
fn batch_indices(cursor: u32, size: u32) -> Vec<u32> {
    (0..size)
        .map_while(|offset| cursor.checked_add(offset))
        .collect()
}

/// The denomination `RecyclersCoinToRecycler` reports for a member key.
fn decode_denomination(bytes: &[u8], index: u32) -> Result<DenominationExponent, CoinageError> {
    let value = bytes.first().map(|byte| *byte as i8).ok_or_else(|| {
        CoinageError::RecoveryFailed(format!("entry {index} has an empty collection record"))
    })?;

    DenominationExponent::new(value).ok_or_else(|| {
        CoinageError::RecoveryFailed(format!(
            "the chain reports denomination {value} at entry index {index}, which this layer \
             cannot represent"
        ))
    })
}

/// Read many keys at one block, in one round trip.
///
/// Returns one entry per key, in the order given, so a caller can zip the answers
/// back onto the indices that produced them. A key the chain has nothing for comes
/// back as `None` — which, for a scan, is the ordinary case.
async fn read_many(
    rpc: &RpcClient,
    keys: &[Vec<u8>],
    at: &str,
) -> Result<Vec<Option<Vec<u8>>>, CoinageError> {
    use std::collections::HashMap;

    let hex_keys: Vec<String> = keys
        .iter()
        .map(|key| format!("0x{}", hex::encode(key)))
        .collect();
    let response = rpc
        .call(
            "state_queryStorageAt",
            serde_json::json!([hex_keys.clone(), at]),
        )
        .await
        .map_err(|error| CoinageError::SubscriptionError(error.to_string()))?;

    // `state_queryStorageAt` answers with one change set per block, each holding
    // `[key, value]` pairs for the keys that have a value.
    let mut present: HashMap<String, Vec<u8>> = HashMap::new();
    for change_set in response.as_array().into_iter().flatten() {
        for change in change_set
            .get("changes")
            .and_then(serde_json::Value::as_array)
            .into_iter()
            .flatten()
        {
            let Some(pair) = change.as_array() else {
                continue;
            };
            let (Some(key), Some(value)) = (
                pair.first().and_then(serde_json::Value::as_str),
                pair.get(1).and_then(serde_json::Value::as_str),
            ) else {
                continue;
            };
            let bytes =
                hex::decode(value.strip_prefix("0x").unwrap_or(value)).map_err(|error| {
                    CoinageError::RecoveryFailed(format!(
                        "decoding a scanned storage value: {error}"
                    ))
                })?;
            present.insert(key.to_string(), bytes);
        }
    }

    Ok(hex_keys
        .into_iter()
        .map(|key| present.get(&key).cloned())
        .collect())
}

#[cfg(test)]
mod tests {
    use parity_scale_codec::Encode;

    use crate::host_logic::coinage::types::CoinAge;
    use crate::runtime::coinage::testing::FakeChain;

    use super::*;

    const ENTROPY: [u8; 32] = [7; 32];
    const NOW: Timestamp = Timestamp(1_700_000_000_000);

    fn block_on<F: core::future::Future>(future: F) -> F::Output {
        futures::executor::block_on(future)
    }

    fn exponent(value: i8) -> DenominationExponent {
        DenominationExponent::new(value).expect("exponent is in range")
    }

    /// A scan that looks at a handful of indices and gives up after two empty
    /// batches, so a test stays readable.
    fn params() -> CoinageParameters {
        CoinageParameters {
            recovery_batch_size: 4,
            recovery_gap_limit: 2,
            ..CoinageParameters::default()
        }
    }

    fn store() -> CoinageStore {
        CoinageStore::new("Main".to_string())
    }

    /// Put a coin on chain at one of our derived accounts.
    fn place_coin(chain: &FakeChain, purse: PurseId, index: u32, exponent_value: i8, age: u16) {
        let account =
            derivation::coin_account_id(&ENTROPY, purse, CoinIndex(index)).expect("derives");
        chain.set_storage(
            &storage::coins_by_owner_key(&account),
            storage::ChainCoin {
                value: exponent_value,
                age,
            }
            .encode(),
        );
    }

    /// Put a recycler entry on chain at one of our derived member keys.
    fn place_entry(chain: &FakeChain, purse: PurseId, index: u32, exponent_value: i8) {
        let member_key =
            derivation::entry_member_key(&ENTROPY, purse, EntryIndex(index)).expect("derives");
        chain.set_storage(
            &storage::recyclers_coin_to_recycler_key(&member_key),
            exponent_value.encode(),
        );
    }

    fn scan(chain: &FakeChain, store: &mut CoinageStore) -> ScanOutcome {
        block_on(scan_purse(
            &chain.rpc(),
            store,
            &ENTROPY,
            PurseId::MAIN,
            &params(),
            CoinIndex(0),
            EntryIndex(0),
            NOW,
            "0xfeed",
        ))
        .expect("scans")
    }

    #[test]
    fn a_scan_restores_coins_at_the_indices_they_were_derived_under() {
        let chain = FakeChain::default();
        let mut store = store();
        place_coin(&chain, PurseId::MAIN, 0, 4, 3);
        place_coin(&chain, PurseId::MAIN, 2, 3, 0);

        let outcome = scan(&chain, &mut store);

        assert_eq!(outcome.coins_found, 2);
        let restored = store.coins_in(PurseId::MAIN);
        assert_eq!(restored.len(), 2);
        assert_eq!(restored[0].index, CoinIndex(0));
        assert_eq!(restored[0].exponent, exponent(4));
        assert_eq!(restored[0].age, CoinAge(3), "the age came from the chain");
        assert_eq!(restored[1].index, CoinIndex(2));
        assert_eq!(restored[1].exponent, exponent(3));
        // Restored coins are spendable: the chain says the accounts hold them.
        assert_eq!(
            store
                .balance(PurseId::MAIN, NOW)
                .expect("purse exists")
                .spendable,
            crate::host_logic::coinage::types::Amount::from_cents(24)
        );
    }

    #[test]
    fn a_scan_leaves_the_index_counter_past_everything_it_found() {
        // §4.3's invariant survives a recovery: the next allocation must not
        // re-derive an account the scan just restored.
        let chain = FakeChain::default();
        let mut store = store();
        place_coin(&chain, PurseId::MAIN, 5, 4, 0);

        scan(&chain, &mut store);

        let next = store
            .add_pending_coin(PurseId::MAIN, exponent(2))
            .expect("purse exists");
        assert!(
            next.0 > 5,
            "the counter moved past the restored index, not to it: {next:?}"
        );
    }

    #[test]
    fn a_scan_restores_entries_with_the_denomination_the_chain_reports() {
        let chain = FakeChain::default();
        let mut store = store();
        place_entry(&chain, PurseId::MAIN, 0, 4);
        place_entry(&chain, PurseId::MAIN, 1, 2);

        let outcome = scan(&chain, &mut store);

        assert_eq!(outcome.entries_found, 2);
        let restored = store.entries_in(PurseId::MAIN);
        assert_eq!(restored[0].exponent, exponent(4));
        assert_eq!(restored[1].exponent, exponent(2));
        // Readiness cannot be restored — the local jitter draw is gone — so a
        // recovered entry is selectable at once.
        assert!(restored[0].ready_at <= NOW);
    }

    #[test]
    fn a_scan_stops_after_the_gap_limit_and_says_where_it_stopped() {
        let chain = FakeChain::default();
        let mut store = store();
        place_coin(&chain, PurseId::MAIN, 0, 4, 0);

        let outcome = scan(&chain, &mut store);

        // One batch found something, then two empty ones ended it: 4 + 4 + 4.
        assert_eq!(outcome.next_coin_index, CoinIndex(12));
        assert_eq!(outcome.coins_found, 1);
    }

    #[test]
    fn a_coin_beyond_the_gap_is_missed_and_the_cursor_says_where_to_resume() {
        // The scan's blind spot, and the reason §8.10 has `extend_scan`: a long
        // unused stretch ends the walk before a later index is reached.
        let chain = FakeChain::default();
        let mut store = store();
        place_coin(&chain, PurseId::MAIN, 40, 4, 0);

        let outcome = scan(&chain, &mut store);
        assert_eq!(outcome.coins_found, 0, "the gap swallowed it");

        // Resuming from the reported cursor, with the same limits, walks further.
        let extended = block_on(scan_purse(
            &chain.rpc(),
            &mut store,
            &ENTROPY,
            PurseId::MAIN,
            &CoinageParameters {
                recovery_batch_size: 4,
                recovery_gap_limit: 12,
                ..CoinageParameters::default()
            },
            outcome.next_coin_index,
            outcome.next_entry_index,
            NOW,
            "0xfeed",
        ))
        .expect("scans");

        assert_eq!(extended.coins_found, 1, "a wider gap limit reaches it");
        assert_eq!(store.coins_in(PurseId::MAIN)[0].index, CoinIndex(40));
    }

    #[test]
    fn a_denomination_this_layer_cannot_represent_fails_the_scan() {
        // Silently skipping it would leave value on chain that the wallet does not
        // know it has, which is the exact failure recovery exists to fix.
        let chain = FakeChain::default();
        let mut store = store();
        place_coin(&chain, PurseId::MAIN, 0, -1, 0);

        let refused = block_on(scan_purse(
            &chain.rpc(),
            &mut store,
            &ENTROPY,
            PurseId::MAIN,
            &params(),
            CoinIndex(0),
            EntryIndex(0),
            NOW,
            "0xfeed",
        ))
        .expect_err("a sub-cent denomination has no representation here");

        assert!(matches!(refused, CoinageError::RecoveryFailed(_)));
    }

    #[test]
    fn a_scan_of_an_empty_wallet_finds_nothing_and_says_so() {
        let chain = FakeChain::default();
        let mut store = store();

        let outcome = scan(&chain, &mut store);

        assert!(outcome.is_empty());
        assert!(store.coins_in(PurseId::MAIN).is_empty());
    }

    #[test]
    fn every_read_is_pinned_to_one_block() {
        // A scan spanning blocks could see a coin move mid-walk and record it in
        // two places, or in neither.
        let chain = FakeChain::default();
        let mut store = store();
        place_coin(&chain, PurseId::MAIN, 1, 4, 0);

        scan(&chain, &mut store);

        for (method, params) in chain.calls() {
            assert_eq!(
                method, "state_queryStorageAt",
                "a scan reads in bulk, one round trip per batch"
            );
            assert!(params.contains("0xfeed"), "unpinned read: {params}");
        }
        // Two batches of coins and two of entries, not one request per index.
        assert!(chain.calls().len() <= 8, "{} requests", chain.calls().len());
    }
}
