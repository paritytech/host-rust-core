//! Pinned-block dotNS transport shared by the core's dotNS readers.
//!
//! Every dotNS read runs over one `chainHead_v1` follow pinned to a best block,
//! so a sequence of storage reads and contract views sees one consistent state.
//! No chain metadata is needed.

use core::sync::atomic::{AtomicU64, Ordering};
#[cfg(not(target_arch = "wasm32"))]
use std::time::Duration;
#[cfg(target_arch = "wasm32")]
use web_time::Duration;

use futures::stream::BoxStream;
use truapi::latest::{
    OperationStartedResult, RemoteChainHeadCallRequest, RemoteChainHeadFollowItem,
    RemoteChainHeadFollowRequest, RemoteChainHeadStorageRequest, StorageQueryItem,
    StorageQueryType,
};

use crate::chain_runtime::{
    ChainHeadStorageValue, ChainHeadStorageValueLookup, ChainRuntime,
    wait_for_chain_head_best_hash, wait_for_chain_head_call_output,
    wait_for_chain_head_storage_value,
};
use crate::host_logic::dotns_gateway::{
    DotnsTransport, DotnsViewError, VIEW_CALL_ORIGIN, encode_revive_call, view_output,
};

/// Budget for one step of a lookup: opening the follow, one storage read, one
/// contract view. A step that stalls this long is not going to answer.
pub(crate) const OPERATION_TIMEOUT: Duration = Duration::from_secs(10);
/// Budget for the best-block hash the follow opens on.
pub(crate) const BEST_BLOCK_TIMEOUT: Duration = Duration::from_secs(2);

/// Monotonic salt for follow ids, so concurrent lookups do not collide.
static DOTNS_LOOKUP_COUNTER: AtomicU64 = AtomicU64::new(1);

/// One pinned-block context for a sequence of dotNS reads. It owns the
/// `chainHead_v1` follow every read and view runs over.
pub(crate) struct DotnsLookup<'a> {
    chain: &'a ChainRuntime,
    follow: BoxStream<'static, RemoteChainHeadFollowItem>,
    genesis_hash: Vec<u8>,
    follow_id: String,
    hash: Vec<u8>,
}

impl<'a> DotnsLookup<'a> {
    /// Opens a follow on Asset Hub and pins it to the current best block.
    ///
    /// `label` distinguishes this lookup's follow id from concurrent ones and
    /// appears in chain logs, so it should name what is being resolved.
    pub(crate) async fn pinned_to_best_block(
        chain: &'a ChainRuntime,
        asset_hub_chain_genesis_hash: [u8; 32],
        label: &str,
    ) -> Result<Self, String> {
        let genesis_hash = asset_hub_chain_genesis_hash.to_vec();
        let lookup_id = DOTNS_LOOKUP_COUNTER.fetch_add(1, Ordering::Relaxed);
        let follow_id = format!("truapi:dotns:{lookup_id}:{label}");
        let mut follow = chain.remote_chain_head_follow(
            follow_id.clone(),
            RemoteChainHeadFollowRequest {
                genesis_hash: genesis_hash.clone(),
                with_runtime: true,
            },
        );
        let hash = wait_for_chain_head_best_hash(
            &mut follow,
            "Asset Hub",
            OPERATION_TIMEOUT,
            BEST_BLOCK_TIMEOUT,
        )
        .await?;
        Ok(Self {
            chain,
            follow,
            genesis_hash,
            follow_id,
            hash,
        })
    }
}

#[truapi_platform::async_trait]
impl DotnsTransport for DotnsLookup<'_> {
    /// Reads one storage value at the pinned block. `Ok(None)` when absent.
    async fn storage(&mut self, key: Vec<u8>) -> Result<Option<Vec<u8>>, String> {
        let response = self
            .chain
            .remote_chain_head_storage(RemoteChainHeadStorageRequest {
                genesis_hash: self.genesis_hash.clone(),
                follow_subscription_id: self.follow_id.clone(),
                hash: self.hash.clone(),
                items: vec![StorageQueryItem {
                    key: key.clone(),
                    query_type: StorageQueryType::Value,
                }],
                child_trie: None,
            })
            .await
            .map_err(|failure| failure.reason())?;
        let operation_id = started_operation_id(response.operation)?;
        let value = wait_for_chain_head_storage_value(
            &mut self.follow,
            ChainHeadStorageValueLookup {
                chain: self.chain,
                genesis_hash: &self.genesis_hash,
                follow_subscription_id: &self.follow_id,
                operation_id: &operation_id,
                key: &key,
                label: "Asset Hub",
                timeout: OPERATION_TIMEOUT,
            },
        )
        .await?;
        match value {
            ChainHeadStorageValue::Found(value) => Ok(Some(value)),
            ChainHeadStorageValue::Missing => Ok(None),
            ChainHeadStorageValue::Inaccessible => {
                Err("Asset Hub storage was inaccessible".to_string())
            }
        }
    }

    /// Dry-runs a contract view via `ReviveApi_call` at the pinned block and
    /// returns its data.
    ///
    /// Views originate from the synthetic always-mapped account. They work
    /// regardless of the queried account's revive mapping.
    async fn view(&mut self, dest: &[u8; 20], input: Vec<u8>) -> Result<Vec<u8>, DotnsViewError> {
        let response = self
            .chain
            .remote_chain_head_call(RemoteChainHeadCallRequest {
                genesis_hash: self.genesis_hash.clone(),
                follow_subscription_id: self.follow_id.clone(),
                hash: self.hash.clone(),
                function: "ReviveApi_call".to_string(),
                call_parameters: encode_revive_call(&VIEW_CALL_ORIGIN, dest, &input),
            })
            .await
            .map_err(|failure| DotnsViewError::Failed(failure.reason()))?;
        let operation_id =
            started_operation_id(response.operation).map_err(DotnsViewError::Failed)?;
        let output = wait_for_chain_head_call_output(
            &mut self.follow,
            &operation_id,
            "Asset Hub",
            OPERATION_TIMEOUT,
        )
        .await
        .map_err(DotnsViewError::Failed)?;
        view_output(&output)
    }
}

/// Unwraps a started operation id. `LimitReached` maps to an error.
fn started_operation_id(operation: OperationStartedResult) -> Result<String, String> {
    match operation {
        OperationStartedResult::Started { operation_id } => Ok(operation_id),
        OperationStartedResult::LimitReached => {
            Err("Asset Hub operation limit reached".to_string())
        }
    }
}
