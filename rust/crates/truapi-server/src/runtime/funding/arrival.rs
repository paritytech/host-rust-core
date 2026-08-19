//! Chain-side half of the funding arrival watch.
//!
//! Reads the destination balance through [`ChainRuntime`] and drives
//! [`ArrivalProbe`] until the deposit lands, then settles the session with
//! `observe_arrival`. This is what makes `Delivered` the core's own claim: no
//! provider report reaches it, and a provider that lies about having sent funds
//! moves the session no further than `Bridging`.
//!
//! The read mirrors `runtime::identity`'s People-chain lookup — follow a fresh
//! head, issue one storage operation, await its value — because the key is
//! built locally and so needs no chain metadata.

use std::sync::Arc;
use std::sync::atomic::{AtomicU64, Ordering};
#[cfg(not(target_arch = "wasm32"))]
use std::time::Duration;
#[cfg(target_arch = "wasm32")]
use web_time::Duration;

use futures::{FutureExt, pin_mut};
use tracing::{debug, instrument, warn};
use truapi::latest::{
    OperationStartedResult, RemoteChainHeadFollowRequest, RemoteChainHeadStorageRequest,
    StorageQueryItem, StorageQueryType,
};
use truapi_platform::{FundingAddress, Platform};

use super::FundingRegistry;
use crate::chain_runtime::{
    ChainHeadStorageValue, ChainHeadStorageValueLookup, ChainRuntime,
    wait_for_chain_head_best_hash, wait_for_chain_head_storage_value,
};
use crate::host_logic::funding::current_unix_millis;
use crate::host_logic::funding::watch::{
    ArrivalProbe, assets_account_storage_key, decode_asset_balance, decode_system_free_balance,
    system_account_storage_key,
};

/// Budget for one balance read.
const READ_TIMEOUT: Duration = Duration::from_secs(10);
const BEST_BLOCK_TIMEOUT: Duration = Duration::from_secs(2);
/// Gap between balance reads while waiting. Two Polkadot blocks: fast enough
/// that the pending row does not feel stale, slow enough not to hammer an RPC
/// endpoint for the length of a bank transfer.
const POLL_INTERVAL: Duration = Duration::from_secs(12);

/// Monotonic salt for follow ids, so concurrent watches never collide.
static WATCH_COUNTER: AtomicU64 = AtomicU64::new(1);

/// Which storage map holds the destination balance.
///
/// Chosen from [`FundingAddress::asset_id`] rather than guessed, because the
/// two maps have different keys and different value layouts, and reading the
/// wrong one would report a permanent zero.
#[derive(Debug, Clone, PartialEq, Eq)]
struct BalanceSource {
    genesis_hash: Vec<u8>,
    key: Vec<u8>,
    asset_backed: bool,
}

impl BalanceSource {
    fn for_address(address: &FundingAddress) -> Self {
        match address.asset_id {
            Some(asset_id) => Self {
                genesis_hash: address.genesis_hash.to_vec(),
                key: assets_account_storage_key(asset_id, &address.account),
                asset_backed: true,
            },
            None => Self {
                genesis_hash: address.genesis_hash.to_vec(),
                key: system_account_storage_key(&address.account),
                asset_backed: false,
            },
        }
    }

    fn decode(&self, value: &[u8]) -> Result<u128, String> {
        if self.asset_backed {
            decode_asset_balance(value)
        } else {
            decode_system_free_balance(value)
        }
    }
}

/// Watch a destination until the deposit arrives, the session settles
/// elsewhere, or its deadline passes.
///
/// Spawned per inbound session and owns no state of its own: the session in the
/// registry is the single source of truth, so this loop re-reads it every pass
/// and stops the moment it is no longer waiting.
#[instrument(skip_all, fields(runtime.method = "funding.watch_arrival", intent = %intent))]
pub(crate) async fn watch_for_arrival(
    chain: ChainRuntime,
    registry: Arc<FundingRegistry>,
    storage: Arc<dyn Platform>,
    intent: String,
    address: FundingAddress,
) {
    let source = BalanceSource::for_address(&address);
    let Some(session) = registry.get(&intent) else {
        return;
    };
    let expected = session.amount;

    // Anything already in the account predates this session and is not the
    // deposit. A failed baseline read is treated as zero rather than aborting:
    // over-reporting an arrival is impossible from a zero baseline, whereas
    // giving up would strand the session on the expiry path.
    let baseline = match read_balance(&chain, &source).await {
        Ok(balance) => balance,
        Err(reason) => {
            warn!(%reason, "funding baseline read failed; watching from zero");
            0
        }
    };
    let probe = ArrivalProbe::new(baseline, expected);
    debug!(baseline, expected, "funding arrival watch started");

    loop {
        let delay = futures_timer::Delay::new(POLL_INTERVAL).fuse();
        pin_mut!(delay);
        delay.await;

        // The session may have settled or expired while we slept — through a
        // provider failure report, or a sweep — in which case stop.
        match registry.get(&intent) {
            Some(session) if !session.stage.is_terminal() => {
                if session.deadline_ms <= current_unix_millis() {
                    debug!("funding arrival watch stopping: session past its deadline");
                    return;
                }
            }
            _ => {
                debug!("funding arrival watch stopping: session no longer waiting");
                return;
            }
        }

        let current = match read_balance(&chain, &source).await {
            Ok(balance) => balance,
            Err(reason) => {
                // Transient RPC trouble must not fail the session: the deposit
                // is either on chain or it is not, and the next pass re-reads.
                warn!(%reason, "funding balance read failed; retrying");
                continue;
            }
        };
        let Some(credited) = probe.credited(current) else {
            continue;
        };

        match registry
            .mutate(storage.as_ref(), &intent, |session| {
                session.observe_arrival(credited)
            })
            .await
        {
            Ok(_) => debug!(credited, "funding arrival observed on chain"),
            Err(reason) => warn!(%reason, "funding arrival could not be recorded"),
        }
        return;
    }
}

/// Read the destination balance at a fresh head. A missing storage entry is
/// zero, which is what an account that does not exist yet holds.
async fn read_balance(chain: &ChainRuntime, source: &BalanceSource) -> Result<u128, String> {
    let watch_id = WATCH_COUNTER.fetch_add(1, Ordering::Relaxed);
    let follow_id = format!("truapi:funding:{watch_id}");
    let mut follow = chain.remote_chain_head_follow(
        follow_id.clone(),
        RemoteChainHeadFollowRequest {
            genesis_hash: source.genesis_hash.clone(),
            with_runtime: false,
        },
    );

    let hash =
        wait_for_chain_head_best_hash(&mut follow, "funding", READ_TIMEOUT, BEST_BLOCK_TIMEOUT)
            .await?;
    let response = chain
        .remote_chain_head_storage(RemoteChainHeadStorageRequest {
            genesis_hash: source.genesis_hash.clone(),
            follow_subscription_id: follow_id.clone(),
            hash,
            items: vec![StorageQueryItem {
                key: source.key.clone(),
                query_type: StorageQueryType::Value,
            }],
            child_trie: None,
        })
        .await
        .map_err(|failure| failure.reason())?;
    let operation_id = match response.operation {
        OperationStartedResult::Started { operation_id } => operation_id,
        OperationStartedResult::LimitReached => {
            return Err("funding storage read limit reached".to_string());
        }
    };
    let value = wait_for_chain_head_storage_value(
        &mut follow,
        ChainHeadStorageValueLookup {
            chain,
            genesis_hash: &source.genesis_hash,
            follow_subscription_id: &follow_id,
            operation_id: &operation_id,
            key: &source.key,
            label: "funding",
            timeout: READ_TIMEOUT,
        },
    )
    .await?;
    match value {
        ChainHeadStorageValue::Found(value) => source.decode(&value),
        ChainHeadStorageValue::Missing => Ok(0),
        ChainHeadStorageValue::Inaccessible => {
            Err("funding destination storage was inaccessible".to_string())
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use parity_scale_codec::Encode;

    const ACCOUNT: [u8; 32] = [0x11; 32];
    const GENESIS: [u8; 32] = [0x22; 32];

    fn address(asset_id: Option<u32>) -> FundingAddress {
        FundingAddress {
            account: ACCOUNT,
            genesis_hash: GENESIS,
            asset_id,
        }
    }

    #[test]
    fn a_native_destination_reads_the_system_map() {
        let source = BalanceSource::for_address(&address(None));

        assert!(!source.asset_backed);
        assert_eq!(source.key, system_account_storage_key(&ACCOUNT));
    }

    #[test]
    fn an_asset_destination_reads_the_assets_map() {
        let source = BalanceSource::for_address(&address(Some(1984)));

        assert!(source.asset_backed);
        assert_eq!(source.key, assets_account_storage_key(1984, &ACCOUNT));
    }

    #[test]
    fn each_source_decodes_with_its_own_layout() {
        // A System record's balance sits past four u32 counters; an asset
        // record's is leading. Decoding one as the other must not silently
        // produce a plausible number.
        let system_blob = (7u32, 1u32, 2u32, 0u32, 9_000u128).encode();
        let asset_blob = 9_000u128.encode();

        assert_eq!(
            BalanceSource::for_address(&address(None)).decode(&system_blob),
            Ok(9_000)
        );
        assert_eq!(
            BalanceSource::for_address(&address(Some(1))).decode(&asset_blob),
            Ok(9_000)
        );
        assert_ne!(
            BalanceSource::for_address(&address(Some(1))).decode(&system_blob),
            Ok(9_000),
            "an asset decode of a System record must not agree by accident"
        );
    }

    #[test]
    fn the_genesis_hash_travels_with_the_source() {
        let source = BalanceSource::for_address(&address(None));

        assert_eq!(source.genesis_hash, GENESIS.to_vec());
    }
}
