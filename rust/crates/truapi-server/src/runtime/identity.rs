//! dotNS identity lookup used to resolve usernames for a paired session.
//!
//! Usernames live in the dotNS contracts on Asset Hub. The gateway pallet
//! storage anchors the `DotnsPopController`. The protocol registry locates the
//! `StoreFactory`. The account's labels come from its `LabelStore` on the warm
//! path. On the cold path they come from its pending claim on the controller,
//! covering gateway-minted names before the user settles their store.
//!
//! All reads run over one `chainHead_v1` follow via `ReviveApi_call` dry-runs.
//! No chain metadata is needed.

use std::sync::atomic::{AtomicU64, Ordering};
#[cfg(not(target_arch = "wasm32"))]
use std::time::Duration;
#[cfg(target_arch = "wasm32")]
use web_time::Duration;

use crate::chain_runtime::{
    ChainHeadStorageValue, ChainHeadStorageValueLookup, ChainRuntime,
    wait_for_chain_head_best_hash, wait_for_chain_head_call_output,
    wait_for_chain_head_storage_value,
};
use crate::host_logic::dotns_gateway::{
    DotnsIdentity, DotnsTransport, VIEW_CALL_ORIGIN, classify_labels, decode_revive_call_output,
    discover_pop_controller, encode_revive_call, resolve_labels,
};
use crate::host_logic::session::SessionInfo;

use futures::stream::BoxStream;
use futures::{FutureExt, pin_mut};
use tracing::{debug, instrument, warn};
use truapi::latest::{
    OperationStartedResult, RemoteChainHeadCallRequest, RemoteChainHeadFollowItem,
    RemoteChainHeadFollowRequest, RemoteChainHeadStorageRequest, StorageQueryItem,
    StorageQueryType,
};

/// Budget for the whole Asset Hub lookup: best block, storage, contract views.
const LOOKUP_TIMEOUT: Duration = Duration::from_secs(10);
const BEST_BLOCK_TIMEOUT: Duration = Duration::from_secs(2);

/// Monotonic salt for local identity lookup follow ids. It keeps concurrent
/// dotNS identity lookups from colliding.
static IDENTITY_LOOKUP_COUNTER: AtomicU64 = AtomicU64::new(1);

/// Fills in missing usernames by querying the dotNS contracts on Asset Hub.
/// Returns the session unchanged when it already carries a username. Also
/// returns it unchanged when no Asset Hub is configured.
#[instrument(skip_all, fields(runtime.method = "session.identity.resolve_with_chain"))]
pub(super) async fn resolve_session_identity_with_chain(
    chain: &ChainRuntime,
    asset_hub_chain_genesis_hash: [u8; 32],
    mut session: SessionInfo,
) -> SessionInfo {
    if session.has_username() || asset_hub_chain_genesis_hash == [0; 32] {
        return session;
    }

    let preferred_account = session.identity_account_id.unwrap_or(session.public_key);
    if lookup_and_apply(
        chain,
        asset_hub_chain_genesis_hash,
        preferred_account,
        &mut session,
        "identity",
    )
    .await
        == LookupOutcome::NoRecord
        && preferred_account != session.public_key
    {
        let public_key = session.public_key;
        lookup_and_apply(
            chain,
            asset_hub_chain_genesis_hash,
            public_key,
            &mut session,
            "root identity",
        )
        .await;
    }

    session
}

/// Maximum lookup attempts per account on transient failure. The first attempt
/// warms the Asset Hub connection, cached per genesis. A retry after a cold-start
/// timeout therefore usually resolves immediately.
const IDENTITY_LOOKUP_MAX_ATTEMPTS: usize = 3;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum LookupOutcome {
    /// A username record was found and applied.
    Applied,
    /// The account has no dotNS labels. Definitive, not worth a retry.
    NoRecord,
    /// The lookup failed transiently after exhausting retries.
    Failed,
}

/// Looks up `account`'s dotNS identity and applies any usernames to `session`.
/// Transient failures are retried against the warmed connection.
async fn lookup_and_apply(
    chain: &ChainRuntime,
    asset_hub_chain_genesis_hash: [u8; 32],
    account: [u8; 32],
    session: &mut SessionInfo,
    label: &str,
) -> LookupOutcome {
    for attempt in 1..=IDENTITY_LOOKUP_MAX_ATTEMPTS {
        match lookup_dotns_identity(chain, asset_hub_chain_genesis_hash, account).await {
            Ok(Some(identity)) => {
                debug!(
                    account = %hex::encode(account),
                    lite_username = identity.lite_username.as_deref().unwrap_or(""),
                    full_username = identity.full_username.as_deref().unwrap_or(""),
                    "dotNS {label} lookup found username"
                );
                session.apply_usernames(identity.lite_username, identity.full_username);
                return LookupOutcome::Applied;
            }
            Ok(None) => {
                debug!(
                    account = %hex::encode(account),
                    "dotNS {label} lookup found no labels"
                );
                return LookupOutcome::NoRecord;
            }
            Err(reason) => {
                warn!(
                    account = %hex::encode(account),
                    attempt,
                    %reason,
                    "dotNS {label} lookup failed"
                );
            }
        }
    }
    LookupOutcome::Failed
}

/// Resolves `account_id`'s usernames from the dotNS contracts at a fresh Asset
/// Hub head, under one overall time budget. Returns `None` when the gateway is not
/// deployed. Also returns `None` when the account holds no labels.
#[instrument(skip_all, fields(runtime.method = "session.identity.lookup"))]
async fn lookup_dotns_identity(
    chain: &ChainRuntime,
    asset_hub_chain_genesis_hash: [u8; 32],
    account_id: [u8; 32],
) -> Result<Option<DotnsIdentity>, String> {
    let timeout = futures_timer::Delay::new(LOOKUP_TIMEOUT).fuse();
    pin_mut!(timeout);
    let lookup = async {
        let mut lookup =
            DotnsLookup::pinned_to_best_block(chain, asset_hub_chain_genesis_hash, account_id)
                .await?;
        let Some(controller) = discover_pop_controller(&mut lookup).await? else {
            return Ok(None);
        };
        let labels = resolve_labels(&mut lookup, &controller, &account_id).await?;
        if labels.is_empty() {
            return Ok(None);
        }
        Ok(Some(classify_labels(labels)))
    }
    .fuse();
    pin_mut!(lookup);
    futures::select! {
        value = lookup => value,
        () = timeout => Err("dotNS identity lookup timed out".to_string()),
    }
}

/// One pinned-block context for the dotNS lookup steps. It owns the
/// `chainHead_v1` follow every read and view runs over.
struct DotnsLookup<'a> {
    chain: &'a ChainRuntime,
    follow: BoxStream<'static, RemoteChainHeadFollowItem>,
    genesis_hash: Vec<u8>,
    follow_id: String,
    hash: Vec<u8>,
}

impl<'a> DotnsLookup<'a> {
    /// Opens a follow on Asset Hub and pins it to the current best block.
    async fn pinned_to_best_block(
        chain: &'a ChainRuntime,
        asset_hub_chain_genesis_hash: [u8; 32],
        account_id: [u8; 32],
    ) -> Result<Self, String> {
        let genesis_hash = asset_hub_chain_genesis_hash.to_vec();
        let lookup_id = IDENTITY_LOOKUP_COUNTER.fetch_add(1, Ordering::Relaxed);
        let follow_id = format!("truapi:identity:{lookup_id}:{}", hex::encode(account_id));
        let mut follow = chain.remote_chain_head_follow(
            follow_id.clone(),
            RemoteChainHeadFollowRequest {
                genesis_hash: genesis_hash.clone(),
                with_runtime: false,
            },
        );
        let hash = wait_for_chain_head_best_hash(
            &mut follow,
            "Asset Hub",
            LOOKUP_TIMEOUT,
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
                timeout: LOOKUP_TIMEOUT,
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
    async fn view(&mut self, dest: &[u8; 20], input: Vec<u8>) -> Result<Vec<u8>, String> {
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
            .map_err(|failure| failure.reason())?;
        let operation_id = started_operation_id(response.operation)?;
        let output = wait_for_chain_head_call_output(
            &mut self.follow,
            &operation_id,
            "Asset Hub",
            LOOKUP_TIMEOUT,
        )
        .await?;
        decode_revive_call_output(&output).map_err(|err| err.to_string())
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
