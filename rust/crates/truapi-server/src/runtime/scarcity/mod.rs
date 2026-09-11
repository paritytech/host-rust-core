//! The NFT pocket: per-product `pallet-scarcity` purses over the wallet's
//! root, served by whichever host the product runs on.
//!
//! Custody is context. Each product has one purse, derived at
//! `//pps//nft//<product_id>//<index>`; the wallet's own is the reserved
//! `nfts.dot`. The chain is the authority on what a purse holds; the engine
//! scans `NftsByOwner`, hands out never-reused receive keys, moves items, and
//! remembers only what it allocated and what it broadcast. Keys come from a
//! [`keys::PurseKeys`] source: the signing host derives them from root entropy,
//! a pairing host asks the paired signing host. Products reach the pocket
//! through the `Scarcity` service; the wallet reaches it directly.

pub(crate) mod chain;
pub(crate) mod keys;
pub(crate) mod store;
pub(crate) mod transfer;

use std::collections::HashMap;
use std::sync::Arc;

use truapi::latest::{ChainIdentifier, ScarcityItem, ScarcityTransferability};

use crate::host_logic::features::{genesis_for, supported_chains};
use crate::host_logic::pocket::{PocketDerivationError, normalize_purse_product_id};
use crate::runtime::authority::{AuthorityError, AuthoritySession};
use crate::runtime::services::RuntimeServices;
use crate::runtime::statement_allowance::rpc::RpcClient;
use crate::runtime::statement_allowance::{ChainClient, ChainContext, StatementAllowanceError};
use chain::{Nft, ScarcityChainError, Transferability};
use keys::{PURSE_KEYS_MAX_COUNT, PurseKeys};
use store::{PocketStore, PocketStoreError};

/// Keys read per scan round trip; matches the Stash's browser-side scan.
const SCAN_BATCH: u32 = 10;
/// Hard ceiling on indices a scan will walk past the last occupied key.
pub(crate) const SCAN_MAX: u32 = 1_000;

/// Failure inside the pocket engine.
#[derive(Debug, derive_more::Display)]
pub(crate) enum PocketError {
    /// The host serves no Asset Hub, so there is no Scarcity pallet to read.
    #[display("the host serves no Asset Hub")]
    ChainNotServed,
    /// The target purse's product id is not one this host can allocate for.
    #[display("{_0}")]
    Derivation(PocketDerivationError),
    /// The pocket slot in core storage failed.
    #[display("{_0}")]
    Store(PocketStoreError),
    /// A chain read failed.
    #[display("{_0}")]
    Chain(ScarcityChainError),
    /// Metadata or runtime version could not be resolved.
    #[display("{_0}")]
    Context(StatementAllowanceError),
    /// The key source, local session or paired signing host, could not
    /// serve the call.
    #[display("{_0}")]
    Authority(AuthorityError),
    /// Catch-all.
    #[display("{reason}")]
    Unknown {
        /// Reason.
        reason: String,
    },
}

impl From<PocketDerivationError> for PocketError {
    fn from(err: PocketDerivationError) -> Self {
        Self::Derivation(err)
    }
}
impl From<PocketStoreError> for PocketError {
    fn from(err: PocketStoreError) -> Self {
        Self::Store(err)
    }
}
impl From<ScarcityChainError> for PocketError {
    fn from(err: ScarcityChainError) -> Self {
        Self::Chain(err)
    }
}
impl From<StatementAllowanceError> for PocketError {
    fn from(err: StatementAllowanceError) -> Self {
        Self::Context(err)
    }
}
impl From<AuthorityError> for PocketError {
    fn from(err: AuthorityError) -> Self {
        Self::Authority(err)
    }
}

/// A pocket call's failure as the account authority reports it: either the
/// authority could not serve the caller at all, or the engine failed.
#[derive(Debug, derive_more::Display)]
pub(crate) enum PocketAuthorityError {
    /// Session or capability failure.
    #[display("{_0}")]
    Authority(AuthorityError),
    /// Engine failure.
    #[display("{_0}")]
    Pocket(PocketError),
}

impl From<AuthorityError> for PocketAuthorityError {
    fn from(err: AuthorityError) -> Self {
        Self::Authority(err)
    }
}
impl From<PocketError> for PocketAuthorityError {
    fn from(err: PocketError) -> Self {
        // A key source's authority failure is the authority's failure to the
        // caller too, so the service maps it to `NotConnected`/`Rejected`
        // rather than an opaque reason.
        match err {
            PocketError::Authority(err) => Self::Authority(err),
            other => Self::Pocket(other),
        }
    }
}

/// One item found in a purse, with the index it sits at.
#[derive(Debug, Clone, PartialEq, Eq)]
pub(crate) struct HeldItem {
    /// Derivation index of the holding key.
    pub index: u32,
    /// The holding key.
    pub address: [u8; 32],
    /// The item.
    pub nft: Nft,
}

/// An Asset Hub connection with its metadata and signed-extension state.
pub(crate) struct AssetHub {
    /// Raw RPC client.
    pub rpc: RpcClient,
    /// Metadata and chain state.
    pub context: ChainContext,
}

/// The pocket engine shared by every product runtime of one host.
pub(crate) struct ScarcityPocket {
    services: Arc<RuntimeServices>,
    store: Arc<PocketStore>,
}

impl ScarcityPocket {
    /// Build the engine over the host's shared runtime services.
    pub(crate) fn new(services: Arc<RuntimeServices>) -> Self {
        let store = PocketStore::new(services.platform.clone());
        Self { services, store }
    }

    /// The durable allocation and transfer records.
    pub(crate) fn store(&self) -> &PocketStore {
        &self.store
    }

    /// The Asset Hub the host serves, resolved by role rather than by a
    /// configured hash, with its metadata revalidated.
    pub(crate) async fn asset_hub(&self) -> Result<AssetHub, PocketError> {
        let chains = supported_chains(self.services.platform.as_ref())
            .await
            .map_err(|err| PocketError::Unknown {
                reason: format!("supportedChains: {}", err.reason),
            })?;
        let genesis =
            genesis_for(&chains, ChainIdentifier::AssetHub).ok_or(PocketError::ChainNotServed)?;
        let host_rpc = self
            .services
            .chain
            .rpc_client("scarcity pocket", &genesis)
            .await
            .map_err(|err| PocketError::Unknown {
                reason: format!("Asset Hub connection: {err}"),
            })?;
        let rpc = RpcClient::new(subxt_rpcs::RpcClient::new(host_rpc));
        let client = ChainClient::new(rpc.clone(), genesis);
        let context = self.services.chain_context.get(&client).await?;
        Ok(AssetHub { rpc, context })
    }

    /// The items `product_id`'s purse holds, in derivation order, read from the
    /// chain. Allocation bookkeeping catches up with anything the scan finds,
    /// so a wallet restored from seed rebuilds its purses by listing them.
    pub(crate) async fn scan_purse(
        &self,
        keys: &dyn PurseKeys,
        session: &AuthoritySession,
        product_id: &str,
    ) -> Result<Vec<HeldItem>, PocketError> {
        let hub = self.asset_hub().await?;
        transfer::recover(self, &hub, session.public_key)
            .await
            .map_err(|err| PocketError::Unknown {
                reason: format!("transfer log recovery: {err}"),
            })?;
        self.scan_purse_with(&hub, keys, session, product_id).await
    }

    /// [`Self::scan_purse`] against an already resolved Asset Hub.
    pub(crate) async fn scan_purse_with(
        &self,
        hub: &AssetHub,
        keys: &dyn PurseKeys,
        session: &AuthoritySession,
        product_id: &str,
    ) -> Result<Vec<HeldItem>, PocketError> {
        let product_id = normalize_purse_product_id(product_id)?;
        let root = session.public_key;
        let known = self
            .store
            .purse(root, &product_id)
            .await?
            .map_or(0, |purse| purse.next_index);
        let mut held = Vec::new();
        let mut occupied = Vec::new();
        // Everything the host allocated, then a gap-limit window beyond it.
        let mut from = 0u32;
        let mut trailing_empty = 0u32;
        while from < SCAN_MAX {
            let to = (from + SCAN_BATCH).min(SCAN_MAX);
            let batch = keys
                .public_keys(session, &product_id, from, to - from)
                .await?;
            if batch.len() != (to - from) as usize {
                return Err(PocketError::Unknown {
                    reason: format!(
                        "the key source returned {} keys for {} indices",
                        batch.len(),
                        to - from
                    ),
                });
            }
            let found = chain::read_nfts(&hub.rpc, &hub.context.metadata, &batch).await?;
            let mut any = false;
            for ((index, address), nft) in (from..to).zip(batch).zip(found) {
                if let Some(nft) = nft {
                    any = true;
                    occupied.push(index);
                    held.push(HeldItem {
                        index,
                        address,
                        nft,
                    });
                }
            }
            from = to;
            if from >= known {
                trailing_empty = if any { 0 } else { trailing_empty + 1 };
                if trailing_empty >= 1 {
                    break;
                }
            }
        }
        self.store
            .observe_occupied(root, &product_id, &occupied)
            .await?;
        Ok(held)
    }

    /// The `Scarcity` service view of `product_id`'s purse, optionally
    /// filtered to `collections`, with each item's transferability read from
    /// its definition.
    pub(crate) async fn list(
        &self,
        keys: &dyn PurseKeys,
        session: &AuthoritySession,
        product_id: &str,
        collections: Option<&[u32]>,
    ) -> Result<Vec<ScarcityItem>, PocketError> {
        let held = self.scan_purse(keys, session, product_id).await?;
        let held: Vec<HeldItem> = held
            .into_iter()
            .filter(|item| {
                collections.is_none_or(|collections| collections.contains(&item.nft.collection))
            })
            .collect();
        if held.is_empty() {
            return Ok(Vec::new());
        }
        let hub = self.asset_hub().await?;
        let mut transferability: HashMap<(u32, u32), ScarcityTransferability> = HashMap::new();
        let mut items = Vec::with_capacity(held.len());
        for item in held {
            let key = (item.nft.collection, item.nft.item);
            let kind = match transferability.get(&key) {
                Some(kind) => *kind,
                None => {
                    let kind = match chain::read_transferability(
                        &hub.rpc,
                        &hub.context.metadata,
                        key.0,
                        key.1,
                    )
                    .await?
                    {
                        Some(Transferability::Soulbound) => ScarcityTransferability::Soulbound,
                        // A missing definition is broken state the pallet itself
                        // refuses to transfer; report it as bound rather than
                        // inviting a move that cannot succeed.
                        None => ScarcityTransferability::Soulbound,
                        Some(Transferability::Transferable) => {
                            ScarcityTransferability::Transferable
                        }
                    };
                    transferability.insert(key, kind);
                    kind
                }
            };
            items.push(ScarcityItem {
                instance: item.nft.instance,
                collection: item.nft.collection,
                item: item.nft.item,
                address: item.address,
                state_nonce: item.nft.state_nonce,
                minted_at: item.nft.minted_at,
                last_moved: item.nft.last_moved,
                transferability: kind,
            });
        }
        Ok(items)
    }

    /// A fresh, empty key in `target_product_id`'s purse for `requested_by`,
    /// or the same key again for a repeated `idempotency_key`. The key source
    /// owns the allocation, so only one host ever hands out an index.
    pub(crate) async fn request_receive_address(
        &self,
        keys: &dyn PurseKeys,
        session: &AuthoritySession,
        target_product_id: &str,
        requested_by: &str,
        idempotency_key: &str,
    ) -> Result<[u8; 32], PocketError> {
        let target = normalize_purse_product_id(target_product_id)?;
        keys.allocate_receive_key(session, &target, requested_by, idempotency_key)
            .await
            .map(|(_, key)| key)
    }

    /// Move `instance` out of `from_product_id`'s purse to `to`, reporting
    /// progress, and return the including block hash once ownership is
    /// verified there.
    pub(crate) async fn transfer(
        &self,
        keys: &dyn PurseKeys,
        session: &AuthoritySession,
        from_product_id: &str,
        instance: u64,
        to: [u8; 32],
        progress: &(dyn Fn(truapi::latest::ScarcityTransferStatus) + Send + Sync),
    ) -> Result<[u8; 32], transfer::TransferError> {
        let hub = self.asset_hub().await?;
        transfer::recover(self, &hub, session.public_key).await?;
        transfer::execute(
            self,
            &hub,
            keys,
            session,
            transfer::TransferSpec {
                from_product_id,
                instance,
                to,
            },
            progress,
        )
        .await
    }

    /// The purse a key belongs to, if the host allocated it: searched over
    /// every key allocated so far in every known purse.
    pub(crate) async fn purse_of(
        &self,
        keys: &dyn PurseKeys,
        session: &AuthoritySession,
        address: &[u8; 32],
    ) -> Result<Option<String>, PocketError> {
        for purse in self.store.snapshot(session.public_key).await?.purses {
            let mut start = 0u32;
            while start < purse.next_index {
                let count = (purse.next_index - start).min(PURSE_KEYS_MAX_COUNT);
                let batch = keys
                    .public_keys(session, &purse.product_id, start, count)
                    .await?;
                if batch.contains(address) {
                    return Ok(Some(purse.product_id));
                }
                start = start.saturating_add(count);
            }
        }
        Ok(None)
    }

    /// Product ids of every purse the host has allocated in, for the wallet's
    /// own view.
    pub(crate) async fn known_purses(
        &self,
        root_public_key: [u8; 32],
    ) -> Result<Vec<String>, PocketError> {
        Ok(self
            .store
            .snapshot(root_public_key)
            .await?
            .purses
            .into_iter()
            .map(|purse| purse.product_id)
            .collect())
    }
}

#[cfg(test)]
pub(crate) mod tests {
    use std::sync::Arc;

    use parity_scale_codec::Encode;
    use serde_json::json;
    use zeroize::Zeroizing;

    use super::keys::LocalPurseKeys;
    use super::*;
    use crate::host_logic::pocket::derive_purse_public_key;
    use crate::runtime::statement_allowance::extension::{ChainState, Era, Metadata};
    use crate::runtime::statement_allowance::rpc::testing::ScriptedRpc;
    use crate::test_support::StubPlatform;

    pub(crate) const ENTROPY: [u8; 16] = [0xAB; 16];
    pub(crate) const ROOT: [u8; 32] = [0x77; 32];
    const PRODUCT: &str = "cardclash.dot";

    pub(crate) fn pocket(platform: Arc<StubPlatform>) -> ScarcityPocket {
        let services = RuntimeServices::new(
            platform,
            truapi_platform::HostInfo {
                name: "test".to_string(),
                icon: None,
                version: None,
                platform: truapi::latest::HostPlatform::Unknown,
            },
            [0; 32],
            [0xbb; 32],
            crate::test_support::test_spawner(),
        );
        ScarcityPocket::new(services)
    }

    /// A session snapshot over the test root; the engine reads only its key.
    pub(crate) fn session() -> AuthoritySession {
        AuthoritySession {
            public_key: ROOT,
            identity_account_id: None,
            lite_username: None,
            full_username: None,
            validation_id: Vec::new(),
        }
    }

    fn local_keys(engine: &ScarcityPocket) -> LocalPurseKeys<'_> {
        LocalPurseKeys::new(engine, Zeroizing::new(ENTROPY.to_vec()))
    }

    fn hub(rpc: ScriptedRpc) -> AssetHub {
        let metadata = Metadata::decode(include_bytes!(
            "../../../tests/fixtures/paseo-next-asset-hub-metadata.scale"
        ))
        .unwrap();
        AssetHub {
            rpc: RpcClient::new(subxt_rpcs::RpcClient::new(rpc)),
            context: ChainContext {
                metadata: Arc::new(metadata),
                state: ChainState {
                    spec_version: 1,
                    transaction_version: 1,
                    genesis_hash: [0; 32],
                    nonce: 0,
                    restrict_origins: false,
                    era: Era::Immortal,
                },
            },
        }
    }

    fn nft_hex(instance: u64, collection: u32, item: u32, nonce: u64) -> String {
        let mut bytes = Vec::new();
        bytes.extend(instance.encode());
        bytes.extend(collection.encode());
        bytes.extend(item.encode());
        bytes.extend(1_000u64.encode());
        bytes.extend(2_000u64.encode());
        bytes.extend(nonce.encode());
        format!("0x{}", hex::encode(bytes))
    }

    /// The first batch holds items at indices 1 and 3, the second is empty,
    /// so the scan stops after two round trips, reports the two items in
    /// derivation order, and moves the allocation counter above them.
    #[test]
    fn scan_walks_batches_until_an_empty_trailing_batch() {
        futures::executor::block_on(async {
            let platform = Arc::new(StubPlatform::default());
            let engine = pocket(platform);
            let keys = local_keys(&engine);
            let metadata = hub(ScriptedRpc::default()).context.metadata;
            let key = |index: u32| {
                let owner = derive_purse_public_key(&ENTROPY, PRODUCT, index).unwrap();
                format!(
                    "0x{}",
                    hex::encode(chain::nfts_by_owner_key(&metadata, &owner).unwrap())
                )
            };
            let first = json!([{ "block": "0x01", "changes": [
                [key(1), nft_hex(34, 7, 2, 0)],
                [key(3), nft_hex(35, 7, 5, 4)],
                [key(0), null],
            ]}]);
            let second = json!([{ "block": "0x01", "changes": [] }]);
            let rpc = ScriptedRpc::new([first.to_string().as_str(), second.to_string().as_str()]);
            let hub = hub(rpc.clone());

            let held = engine
                .scan_purse_with(&hub, &keys, &session(), PRODUCT)
                .await
                .unwrap();
            assert_eq!(
                held.iter()
                    .map(|item| (item.index, item.nft.instance))
                    .collect::<Vec<_>>(),
                vec![(1, 34), (3, 35)]
            );
            assert_eq!(held[1].nft.state_nonce, 4);
            assert_eq!(
                held[0].address,
                derive_purse_public_key(&ENTROPY, PRODUCT, 1).unwrap()
            );
            let calls = rpc.calls();
            assert_eq!(
                calls.len(),
                2,
                "one batch with items, one empty trailing batch"
            );
            assert!(
                calls
                    .iter()
                    .all(|(method, _)| method == "state_queryStorageAt")
            );
            let purse = engine.store().purse(ROOT, PRODUCT).await.unwrap().unwrap();
            assert_eq!(
                purse.next_index, 4,
                "allocation resumes above the highest occupied key"
            );
        });
    }

    /// A purse the host already allocated deep into reads all of it before the
    /// gap-limit window applies, so an early empty batch does not end the scan.
    #[test]
    fn scan_reads_every_allocated_key_before_applying_the_gap_limit() {
        futures::executor::block_on(async {
            let platform = Arc::new(StubPlatform::default());
            let engine = pocket(platform);
            let keys = local_keys(&engine);
            for i in 0..25 {
                engine
                    .store()
                    .allocate(ROOT, PRODUCT, "console.dot", &format!("k{i}"))
                    .await
                    .unwrap();
            }
            let metadata = hub(ScriptedRpc::default()).context.metadata;
            let owner = derive_purse_public_key(&ENTROPY, PRODUCT, 22).unwrap();
            let key22 = format!(
                "0x{}",
                hex::encode(chain::nfts_by_owner_key(&metadata, &owner).unwrap())
            );
            let empty = json!([{ "block": "0x01", "changes": [] }]).to_string();
            let with_item =
                json!([{ "block": "0x01", "changes": [[key22, nft_hex(9, 1, 1, 0)]] }]).to_string();
            // 0..10 empty, 10..20 empty, 20..30 has index 22 (past `known` = 25,
            // so it counts as the window), 30..40 empty ends it.
            let rpc = ScriptedRpc::new([
                empty.as_str(),
                empty.as_str(),
                with_item.as_str(),
                empty.as_str(),
            ]);
            let hub = hub(rpc.clone());
            let held = engine
                .scan_purse_with(&hub, &keys, &session(), PRODUCT)
                .await
                .unwrap();
            assert_eq!(held.len(), 1);
            assert_eq!(held[0].index, 22);
            assert_eq!(rpc.calls().len(), 4);
            let purse = engine.store().purse(ROOT, PRODUCT).await.unwrap().unwrap();
            assert_eq!(purse.next_index, 25, "the counter never moves backwards");
            assert_eq!(
                purse.reserved.len(),
                24,
                "the occupied reservation was released"
            );
        });
    }

    /// The purse lookup asks the key source for each purse's allocated range
    /// and finds a key by its index, with no chain access.
    #[test]
    fn purse_of_searches_allocated_keys_through_the_key_source() {
        futures::executor::block_on(async {
            let platform = Arc::new(StubPlatform::default());
            let engine = pocket(platform);
            let keys = local_keys(&engine);
            for i in 0..3 {
                engine
                    .store()
                    .allocate(ROOT, PRODUCT, "console.dot", &format!("k{i}"))
                    .await
                    .unwrap();
            }
            let second = derive_purse_public_key(&ENTROPY, PRODUCT, 2).unwrap();
            assert_eq!(
                engine.purse_of(&keys, &session(), &second).await.unwrap(),
                Some(PRODUCT.to_string())
            );
            let unallocated = derive_purse_public_key(&ENTROPY, PRODUCT, 3).unwrap();
            assert_eq!(
                engine
                    .purse_of(&keys, &session(), &unallocated)
                    .await
                    .unwrap(),
                None
            );
        });
    }
}
