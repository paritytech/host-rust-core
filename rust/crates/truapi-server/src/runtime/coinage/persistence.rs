//! Durable persistence for the coinage record store.
//!
//! The whole store lives in one `CoreStorageKey::CoinageState` slot rather than
//! a slot per record: a write is then atomic from the host's point of view, and
//! the host needs no key enumeration to hand the layer its state back. The cost
//! is that every mutation re-encodes everything, which is fine at testnet purse
//! sizes and will need revisiting before a purse holds thousands of records.
//!
//! # Why publishing is bundled with persisting
//!
//! `coinage-layer.md` §7.9 requires events to be drained and published *before*
//! the store is persisted. A terminal operation drops its record as soon as its
//! status is emitted, so persisting first and publishing second loses the
//! receipt and the record together if the process dies in between — the
//! operation would simply never have happened as far as any later reader is
//! concerned. Publishing first degrades to a duplicate event after a crash,
//! which subscribers absorb and recovery resolves.
//!
//! That ordering is a rule no type can enforce on its own, so this module does
//! not expose a bare `persist`. [`publish_and_persist`] is the only way to write
//! the store, and it takes the publisher as an argument, which makes the safe
//! order the only reachable one.

use parity_scale_codec::{Decode, Encode};
use truapi_platform::{CoreStorage, CoreStorageKey};

use crate::host_logic::coinage::error::CoinageError;
use crate::host_logic::coinage::event::LayerEvent;
use crate::host_logic::coinage::store::CoinageStore;

/// Read the store back, or build a fresh one if the slot is empty.
///
/// An empty slot is first run, not an error: the main purse exists by
/// construction once entropy is present (`coinage-layer.md` §13).
pub async fn load<S: CoreStorage + ?Sized>(
    storage: &S,
    main_purse_name: &str,
) -> Result<CoinageStore, CoinageError> {
    let raw = storage
        .read_core_storage(CoreStorageKey::CoinageState)
        .await
        .map_err(|error| {
            CoinageError::StorageError(format!("reading coinage state: {}", error.reason))
        })?;

    match raw {
        None => Ok(CoinageStore::new(main_purse_name.to_string())),
        Some(bytes) => CoinageStore::decode(&mut &bytes[..]).map_err(|error| {
            // Deliberately fatal rather than falling back to an empty store: a
            // fresh store would re-derive from index zero and hand out account
            // identifiers that are already on chain, breaking the no-reuse
            // invariant of §4.3. Losing the records is recoverable by scanning;
            // reusing an index is not.
            CoinageError::StorageError(format!("decoding coinage state: {error}"))
        }),
    }
}

/// Publish everything the store has observed, then persist it.
///
/// `publish` receives the drained events in order, together with the store they
/// came from: a balance is a projection of every record in a purse rather than
/// anything an event can carry, so the publisher needs the store to reproject
/// the derived subscription streams. It runs before the write, so a crash
/// between the two costs a duplicate event rather than a lost receipt. A failed
/// write leaves the in-memory store ahead of the durable one; the caller should
/// treat that as fatal for the operation in flight and let recovery reconcile on
/// the next start.
pub async fn publish_and_persist<S, P>(
    storage: &S,
    store: &mut CoinageStore,
    publish: P,
) -> Result<(), CoinageError>
where
    S: CoreStorage + ?Sized,
    P: FnOnce(Vec<LayerEvent>, &CoinageStore),
{
    let events = store.take_events();
    publish(events, store);

    storage
        .write_core_storage(CoreStorageKey::CoinageState, store.encode())
        .await
        .map_err(|error| {
            CoinageError::StorageError(format!("writing coinage state: {}", error.reason))
        })
}

/// Drop the persisted store.
///
/// Only for a host discarding its identity: the records are the only local
/// witness to coins whose accounts are already on chain, so clearing this slot
/// without also discarding the entropy strands them until a wallet recovery
/// scan (§8.10) finds them again.
pub async fn clear<S: CoreStorage + ?Sized>(storage: &S) -> Result<(), CoinageError> {
    storage
        .clear_core_storage(CoreStorageKey::CoinageState)
        .await
        .map_err(|error| {
            CoinageError::StorageError(format!("clearing coinage state: {}", error.reason))
        })
}

#[cfg(test)]
mod tests {
    use std::collections::HashMap;
    use std::sync::Mutex;

    use truapi::v01;

    use crate::host_logic::coinage::types::{CoinAge, DenominationExponent, PurseId};

    use super::*;

    #[derive(Default)]
    struct MemStorage {
        inner: Mutex<HashMap<Vec<u8>, Vec<u8>>>,
        fail_writes: bool,
    }

    impl MemStorage {
        fn failing() -> Self {
            Self {
                fail_writes: true,
                ..Self::default()
            }
        }

        fn slot(&self) -> Option<Vec<u8>> {
            self.inner
                .lock()
                .unwrap()
                .get(&CoreStorageKey::CoinageState.encode())
                .cloned()
        }
    }

    #[truapi_platform::async_trait]
    impl CoreStorage for MemStorage {
        async fn read_core_storage(
            &self,
            key: CoreStorageKey,
        ) -> Result<Option<Vec<u8>>, v01::GenericError> {
            Ok(self.inner.lock().unwrap().get(&key.encode()).cloned())
        }

        async fn write_core_storage(
            &self,
            key: CoreStorageKey,
            value: Vec<u8>,
        ) -> Result<(), v01::GenericError> {
            if self.fail_writes {
                return Err(v01::GenericError {
                    reason: "disk full".to_string(),
                });
            }
            self.inner.lock().unwrap().insert(key.encode(), value);
            Ok(())
        }

        async fn clear_core_storage(&self, key: CoreStorageKey) -> Result<(), v01::GenericError> {
            self.inner.lock().unwrap().remove(&key.encode());
            Ok(())
        }
    }

    fn exponent(value: i8) -> DenominationExponent {
        DenominationExponent::new(value).expect("exponent is in range")
    }

    fn block_on<F: core::future::Future>(future: F) -> F::Output {
        futures::executor::block_on(future)
    }

    #[test]
    fn an_empty_slot_yields_a_store_holding_only_the_main_purse() {
        let storage = MemStorage::default();

        let store = block_on(load(&storage, "Main")).expect("first run is not an error");

        assert_eq!(store.purses().count(), 1);
        assert_eq!(store.purse(PurseId::MAIN).expect("exists").name, "Main");
    }

    #[test]
    fn records_and_index_counters_survive_a_round_trip() {
        let storage = MemStorage::default();
        let mut store = block_on(load(&storage, "Main")).expect("loads");
        let savings = store.create_purse("Savings".to_string());
        let coin = store
            .add_pending_coin(savings, exponent(4))
            .expect("purse exists");
        store
            .observe_coin(savings, coin, CoinAge(3))
            .expect("coin exists");

        block_on(publish_and_persist(&storage, &mut store, |_, _| {})).expect("persists");
        let reloaded = block_on(load(&storage, "Main")).expect("loads");

        assert_eq!(reloaded.purse(savings).expect("exists").name, "Savings");
        assert_eq!(
            reloaded.coin(savings, coin).expect("exists").age,
            CoinAge(3)
        );
        // The counter matters more than the record: a reloaded store that
        // restarted its indices would re-derive accounts already on chain.
        let mut reloaded = reloaded;
        let next = reloaded
            .add_pending_coin(savings, exponent(4))
            .expect("purse exists");
        assert_ne!(next, coin, "the index counter survived");
    }

    #[test]
    fn events_are_published_before_the_store_is_written() {
        // The ordering §7.9 requires. Asserted by observing that the slot is
        // still empty at the moment the publisher runs.
        let storage = MemStorage::default();
        let mut store = block_on(load(&storage, "Main")).expect("loads");
        store.create_purse("Savings".to_string());
        let mut slot_when_published = Some(vec![0xff]);

        block_on(publish_and_persist(&storage, &mut store, |events, _| {
            slot_when_published = storage.slot();
            assert!(
                events
                    .iter()
                    .any(|event| matches!(event, LayerEvent::PurseCreated { .. })),
                "the publisher sees the drained events"
            );
        }))
        .expect("persists");

        assert_eq!(slot_when_published, None, "published before the write");
        assert!(storage.slot().is_some(), "and written afterwards");
    }

    #[test]
    fn events_are_drained_exactly_once() {
        let storage = MemStorage::default();
        let mut store = block_on(load(&storage, "Main")).expect("loads");
        store.create_purse("Savings".to_string());

        let mut first = Vec::new();
        block_on(publish_and_persist(&storage, &mut store, |events, _| {
            first = events;
        }))
        .expect("persists");
        let mut second = Vec::new();
        block_on(publish_and_persist(&storage, &mut store, |events, _| {
            second = events;
        }))
        .expect("persists");

        assert_eq!(first.len(), 1);
        assert!(second.is_empty(), "a second write republishes nothing");
    }

    #[test]
    fn a_corrupt_slot_fails_rather_than_resetting_the_index_counters() {
        // Falling back to a fresh store would re-derive from index zero and
        // hand out account identifiers that already hold coins on chain.
        let storage = MemStorage::default();
        storage
            .inner
            .lock()
            .unwrap()
            .insert(CoreStorageKey::CoinageState.encode(), vec![0xff; 8]);

        let error = block_on(load(&storage, "Main")).expect_err("refuses to guess");

        assert!(matches!(error, CoinageError::StorageError(_)));
    }

    #[test]
    fn a_failed_write_is_reported() {
        let storage = MemStorage::failing();
        let mut store = CoinageStore::new("Main".to_string());

        let error = block_on(publish_and_persist(&storage, &mut store, |_, _| {}))
            .expect_err("write fails");

        assert!(matches!(error, CoinageError::StorageError(_)));
    }

    #[test]
    fn clearing_removes_the_slot() {
        let storage = MemStorage::default();
        let mut store = CoinageStore::new("Main".to_string());
        block_on(publish_and_persist(&storage, &mut store, |_, _| {})).expect("persists");

        block_on(clear(&storage)).expect("clears");

        assert_eq!(storage.slot(), None);
    }
}
