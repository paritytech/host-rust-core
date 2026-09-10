//! Durable NFT-pocket records for one wallet: each purse's index counter and
//! the receive keys handed out but not yet seen holding an item.
//!
//! The chain is the authority on what a purse holds; this store only has to
//! remember what the host allocated, so the next key is never a reused one and
//! a retried allocation answers with the same key. One slot per wallet root,
//! written whole, cache-fronted, and cleared rather than trusted when it fails
//! to decode.

use std::collections::HashMap;
use std::sync::{Arc, Mutex};

use parity_scale_codec::{Decode, Encode};
use truapi_platform::{CoreStorageKey, Platform};

/// A receive key allocated for a caller and not yet observed holding an item.
#[derive(Clone, Debug, PartialEq, Eq, Encode, Decode)]
pub(crate) struct ReservedKey {
    /// Derivation index within the purse.
    pub index: u32,
    /// Caller-chosen replay key; the same key returns the same index.
    pub idempotency_key: String,
    /// Product that asked for the key.
    pub requested_by: String,
}

/// One product's purse.
#[derive(Clone, Debug, PartialEq, Eq, Encode, Decode)]
pub(crate) struct PurseRecord {
    /// Product the purse belongs to; the derivation junction.
    pub product_id: String,
    /// Next never-allocated index. Only ever grows.
    pub next_index: u32,
    /// Keys handed out and not yet seen occupied.
    pub reserved: Vec<ReservedKey>,
}

/// Every purse the host knows for one wallet root.
#[derive(Clone, Debug, Default, PartialEq, Eq, Encode, Decode)]
pub(crate) struct PocketSnapshot {
    /// Purses in creation order.
    pub purses: Vec<PurseRecord>,
}

/// Failure reading or writing the pocket slot.
#[derive(Debug, derive_more::Display)]
pub(crate) enum PocketStoreError {
    /// The platform's core storage failed.
    #[display("pocket storage: {_0}")]
    Storage(String),
    /// The persisted blob did not decode; it was cleared.
    #[display("pocket storage corrupt: {_0}")]
    Corrupt(String),
}

/// Cache-fronted, guard-serialized pocket store.
pub(crate) struct PocketStore {
    platform: Arc<dyn Platform>,
    cache: Mutex<HashMap<[u8; 32], PocketSnapshot>>,
    storage_guard: futures::lock::Mutex<()>,
}

impl PocketStore {
    /// Build a store over the platform's core storage.
    pub(crate) fn new(platform: Arc<dyn Platform>) -> Arc<Self> {
        Arc::new(Self {
            platform,
            cache: Mutex::new(HashMap::new()),
            storage_guard: futures::lock::Mutex::new(()),
        })
    }

    /// Every purse the host has allocated for `root_public_key`.
    pub(crate) async fn snapshot(
        &self,
        root_public_key: [u8; 32],
    ) -> Result<PocketSnapshot, PocketStoreError> {
        if let Some(snapshot) = self.cached(root_public_key) {
            return Ok(snapshot);
        }
        let _guard = self.storage_guard.lock().await;
        self.load_under_guard(root_public_key).await
    }

    /// The purse record for `product_id`, if any key was ever allocated in it.
    pub(crate) async fn purse(
        &self,
        root_public_key: [u8; 32],
        product_id: &str,
    ) -> Result<Option<PurseRecord>, PocketStoreError> {
        Ok(self
            .snapshot(root_public_key)
            .await?
            .purses
            .into_iter()
            .find(|purse| purse.product_id == product_id))
    }

    /// Allocate the next key in `product_id`'s purse for `requested_by`, or
    /// answer a repeated `idempotency_key` from the same caller with the index
    /// it already got. Creates the purse record on first use.
    pub(crate) async fn allocate(
        &self,
        root_public_key: [u8; 32],
        product_id: &str,
        requested_by: &str,
        idempotency_key: &str,
    ) -> Result<u32, PocketStoreError> {
        let _guard = self.storage_guard.lock().await;
        let mut snapshot = self.load_under_guard(root_public_key).await?;
        let purse = purse_mut(&mut snapshot, product_id);
        if let Some(existing) = purse
            .reserved
            .iter()
            .find(|key| key.requested_by == requested_by && key.idempotency_key == idempotency_key)
        {
            return Ok(existing.index);
        }
        let index = purse.next_index;
        purse.next_index = index
            .checked_add(1)
            .ok_or_else(|| PocketStoreError::Storage("purse index space exhausted".into()))?;
        purse.reserved.push(ReservedKey {
            index,
            idempotency_key: idempotency_key.to_string(),
            requested_by: requested_by.to_string(),
        });
        self.persist_under_guard(root_public_key, snapshot).await?;
        Ok(index)
    }

    /// Record that a scan saw items up to `highest_occupied` in `product_id`'s
    /// purse, so allocation resumes above them after a restore from seed, and
    /// drop reservations for keys now seen occupied.
    pub(crate) async fn observe_occupied(
        &self,
        root_public_key: [u8; 32],
        product_id: &str,
        occupied: &[u32],
    ) -> Result<(), PocketStoreError> {
        let Some(highest) = occupied.iter().copied().max() else {
            return Ok(());
        };
        let _guard = self.storage_guard.lock().await;
        let mut snapshot = self.load_under_guard(root_public_key).await?;
        let purse = purse_mut(&mut snapshot, product_id);
        let before = (purse.next_index, purse.reserved.len());
        purse.next_index = purse.next_index.max(highest.saturating_add(1));
        purse.reserved.retain(|key| !occupied.contains(&key.index));
        if before == (purse.next_index, purse.reserved.len()) {
            return Ok(());
        }
        self.persist_under_guard(root_public_key, snapshot).await
    }

    fn cached(&self, root_public_key: [u8; 32]) -> Option<PocketSnapshot> {
        self.cache
            .lock()
            .expect("pocket store cache mutex poisoned")
            .get(&root_public_key)
            .cloned()
    }

    async fn load_under_guard(
        &self,
        root_public_key: [u8; 32],
    ) -> Result<PocketSnapshot, PocketStoreError> {
        if let Some(snapshot) = self.cached(root_public_key) {
            return Ok(snapshot);
        }
        let key = CoreStorageKey::ScarcityPocket { root_public_key };
        let snapshot = match self
            .platform
            .read_core_storage(key.clone())
            .await
            .map_err(|err| PocketStoreError::Storage(err.reason))?
        {
            Some(blob) => match decode_snapshot(&blob) {
                Ok(snapshot) => snapshot,
                Err(error) => {
                    let _ = self.platform.clear_core_storage(key).await;
                    return Err(error);
                }
            },
            None => PocketSnapshot::default(),
        };
        self.cache
            .lock()
            .expect("pocket store cache mutex poisoned")
            .insert(root_public_key, snapshot.clone());
        Ok(snapshot)
    }

    async fn persist_under_guard(
        &self,
        root_public_key: [u8; 32],
        snapshot: PocketSnapshot,
    ) -> Result<(), PocketStoreError> {
        self.platform
            .write_core_storage(
                CoreStorageKey::ScarcityPocket { root_public_key },
                snapshot.encode(),
            )
            .await
            .map_err(|err| PocketStoreError::Storage(err.reason))?;
        self.cache
            .lock()
            .expect("pocket store cache mutex poisoned")
            .insert(root_public_key, snapshot);
        Ok(())
    }
}

fn purse_mut<'a>(snapshot: &'a mut PocketSnapshot, product_id: &str) -> &'a mut PurseRecord {
    if let Some(position) = snapshot
        .purses
        .iter()
        .position(|purse| purse.product_id == product_id)
    {
        return &mut snapshot.purses[position];
    }
    snapshot.purses.push(PurseRecord {
        product_id: product_id.to_string(),
        next_index: 0,
        reserved: Vec::new(),
    });
    snapshot.purses.last_mut().expect("a purse was just pushed")
}

fn decode_snapshot(blob: &[u8]) -> Result<PocketSnapshot, PocketStoreError> {
    let mut input = blob;
    let snapshot = PocketSnapshot::decode(&mut input)
        .map_err(|error| PocketStoreError::Corrupt(error.to_string()))?;
    if !input.is_empty() {
        return Err(PocketStoreError::Corrupt("trailing bytes".into()));
    }
    Ok(snapshot)
}

#[cfg(test)]
mod tests {
    use truapi_platform::CoreStorage;

    use super::*;
    use crate::test_support::StubPlatform;

    const ROOT: [u8; 32] = [0x77; 32];

    #[test]
    fn allocation_is_monotonic_and_replays_by_caller_and_key() {
        futures::executor::block_on(async {
            let store = PocketStore::new(Arc::new(StubPlatform::default()));
            let a = store
                .allocate(ROOT, "cardclash.dot", "console.dot", "mint-1")
                .await
                .unwrap();
            let b = store
                .allocate(ROOT, "cardclash.dot", "console.dot", "mint-2")
                .await
                .unwrap();
            let again = store
                .allocate(ROOT, "cardclash.dot", "console.dot", "mint-1")
                .await
                .unwrap();
            // Another caller's identical key is its own allocation.
            let other = store
                .allocate(ROOT, "cardclash.dot", "seity.dot", "mint-1")
                .await
                .unwrap();
            assert_eq!((a, b, again, other), (0, 1, 0, 2));
            // A different purse has its own index space.
            assert_eq!(
                store
                    .allocate(ROOT, "nfts.dot", "console.dot", "mint-1")
                    .await
                    .unwrap(),
                0
            );
            let purses = store.snapshot(ROOT).await.unwrap().purses;
            assert_eq!(purses.len(), 2);
            assert_eq!(purses[0].next_index, 3);
            assert_eq!(purses[0].reserved.len(), 3);
        });
    }

    #[test]
    fn observing_occupied_keys_raises_the_counter_and_frees_reservations() {
        futures::executor::block_on(async {
            let store = PocketStore::new(Arc::new(StubPlatform::default()));
            store
                .allocate(ROOT, "cardclash.dot", "console.dot", "k")
                .await
                .unwrap();
            // A restore from seed finds items the counter never allocated.
            store
                .observe_occupied(ROOT, "cardclash.dot", &[0, 5])
                .await
                .unwrap();
            let purse = store.purse(ROOT, "cardclash.dot").await.unwrap().unwrap();
            assert_eq!(purse.next_index, 6);
            assert!(purse.reserved.is_empty(), "index 0 was seen occupied");
            assert_eq!(
                store
                    .allocate(ROOT, "cardclash.dot", "console.dot", "k2")
                    .await
                    .unwrap(),
                6
            );
            // Nothing to observe changes nothing.
            store
                .observe_occupied(ROOT, "cardclash.dot", &[])
                .await
                .unwrap();
            assert_eq!(
                store
                    .purse(ROOT, "cardclash.dot")
                    .await
                    .unwrap()
                    .unwrap()
                    .next_index,
                7
            );
        });
    }

    #[test]
    fn a_corrupt_slot_is_cleared_rather_than_trusted() {
        futures::executor::block_on(async {
            let platform = Arc::new(StubPlatform::default());
            let key = CoreStorageKey::ScarcityPocket {
                root_public_key: ROOT,
            };
            platform
                .write_core_storage(key.clone(), vec![0xff, 0xff, 0xff])
                .await
                .unwrap();
            let store = PocketStore::new(platform.clone());
            assert!(matches!(
                store.snapshot(ROOT).await,
                Err(PocketStoreError::Corrupt(_))
            ));
            assert!(platform.read_core_storage(key).await.unwrap().is_none());
            // The next read starts from an empty pocket.
            assert!(store.snapshot(ROOT).await.unwrap().purses.is_empty());
        });
    }

    #[test]
    fn snapshots_survive_a_fresh_store_over_the_same_platform() {
        futures::executor::block_on(async {
            let platform = Arc::new(StubPlatform::default());
            let first = PocketStore::new(platform.clone());
            first
                .allocate(ROOT, "seity.dot", "seity.dot", "pin")
                .await
                .unwrap();
            let second = PocketStore::new(platform);
            let purse = second.purse(ROOT, "seity.dot").await.unwrap().unwrap();
            assert_eq!(purse.next_index, 1);
            assert_eq!(purse.reserved[0].idempotency_key, "pin");
        });
    }
}
