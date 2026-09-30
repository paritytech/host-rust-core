//! [`SubxtChain`]: the chain capabilities over subxt clients.

use core::error::Error;
use core::future::ready;

use futures::stream::{self, BoxStream, StreamExt};
use sp_crypto_hashing::blake2_256;
use subxt::backend::Backend;
use subxt::config::{Hasher, Header};
use subxt::events::Phase;
use subxt::tx::{TransactionStatus, ValidationResult};
use subxt::utils::H256;
use subxt_rpcs::Error as RpcError;

use super::{
    BlockBackend, ChainHeads, DispatchOutcome, Extrinsic, HashAndNumber, HeadEvent, Heads,
    TxSubmitter, TxValidator, WatchEvent,
};
use crate::chain_runtime::{ChainRuntime, LegacyConnection, RuntimeFailure};

/// The chain capabilities over [`ChainRuntime`]'s per-chain subxt clients:
/// the legacy client for reads and validation, the shared chainHead client
/// for submission.
#[derive(Clone)]
pub struct SubxtChain {
    chains: ChainRuntime,
}

impl SubxtChain {
    /// Capabilities over the connections `chains` manages.
    pub fn new(chains: ChainRuntime) -> Self {
        Self { chains }
    }

    async fn legacy(&self, genesis: H256) -> Result<LegacyConnection, RuntimeFailure> {
        self.chains.legacy_connection(genesis.as_bytes()).await
    }
}

/// Number of the block with `hash`, which the node must know.
async fn numbered(
    legacy: &LegacyConnection,
    hash: H256,
    method: &'static str,
) -> Result<HashAndNumber, RuntimeFailure> {
    let header = legacy
        .backend
        .block_header(hash)
        .await
        .map_err(|error| failure(method, error))?
        .ok_or_else(|| RuntimeFailure::host_failure(method, format!("unknown block {hash:?}")))?;
    Ok(HashAndNumber {
        hash,
        number: header.number(),
    })
}

/// The best block, as the node sees it now.
async fn best_block(
    legacy: &LegacyConnection,
    method: &'static str,
) -> Result<HashAndNumber, RuntimeFailure> {
    let best = legacy
        .methods
        .chain_get_block_hash(None)
        .await
        .map_err(|error| failure(method, error))?
        .ok_or_else(|| RuntimeFailure::host_failure(method, "node reported no best block"))?;
    numbered(legacy, best, method).await
}

/// The latest finalized block.
async fn finalized_block(
    legacy: &LegacyConnection,
    method: &'static str,
) -> Result<HashAndNumber, RuntimeFailure> {
    let finalized = legacy
        .backend
        .latest_finalized_block_ref()
        .await
        .map_err(|error| failure(method, error))?
        .hash();
    numbered(legacy, finalized, method).await
}

/// The body of block `at`, or `None` when the node does not know the block.
/// A node that knows the header but not the body cannot prove what the block
/// contains, so that is an error.
async fn body(
    legacy: &LegacyConnection,
    at: H256,
    method: &'static str,
) -> Result<Option<Vec<Vec<u8>>>, RuntimeFailure> {
    if let Some(body) = legacy
        .backend
        .block_body(at)
        .await
        .map_err(|error| failure(method, error))?
    {
        return Ok(Some(body));
    }
    let known = legacy
        .backend
        .block_header(at)
        .await
        .map_err(|error| failure(method, error))?
        .is_some();
    if known {
        return Err(RuntimeFailure::host_failure(
            method,
            format!("node cannot serve the body of block {at:?}"),
        ));
    }
    Ok(None)
}

#[async_trait::async_trait]
impl ChainHeads for SubxtChain {
    async fn heads(&self, genesis: H256) -> Result<Heads, RuntimeFailure> {
        const METHOD: &str = "chain_heads";
        let legacy = self.legacy(genesis).await?;
        Ok(Heads {
            finalized: finalized_block(&legacy, METHOD).await?,
            best: best_block(&legacy, METHOD).await?,
        })
    }

    async fn head_events(
        &self,
        genesis: H256,
    ) -> Result<BoxStream<'static, Result<HeadEvent, RuntimeFailure>>, RuntimeFailure> {
        const METHOD: &str = "chain_head_events";
        let legacy = self.legacy(genesis).await?;
        // Blocks are hashed with the chain's hasher, which comes from metadata.
        let hasher = *legacy
            .client
            .at_current_block()
            .await
            .map_err(|error| failure(METHOD, error))?
            .hasher();
        // The raw subscriptions report only what the node announces. Filling
        // gaps by height would ask for hashes a light client cannot give.
        let finalized = legacy
            .methods
            .chain_subscribe_finalized_heads()
            .await
            .map_err(|error| failure(METHOD, error))?
            .map(move |header| {
                header
                    .map(|header| HeadEvent::Finalized(hashed(hasher, &header)))
                    .map_err(|error| failure(METHOD, error))
            });
        let best = legacy
            .methods
            .chain_subscribe_new_heads()
            .await
            .map_err(|error| failure(METHOD, error))?
            .map(move |header| {
                header
                    .map(|header| HeadEvent::Best(hashed(hasher, &header)))
                    .map_err(|error| failure(METHOD, error))
            });
        let events = stream::select(finalized, best).scan(false, |failed, event| {
            if *failed {
                return ready(None);
            }
            *failed = event.is_err();
            ready(Some(event))
        });
        Ok(events.boxed())
    }
}

fn hashed(hasher: impl Hasher<Hash = H256>, header: &impl Header) -> HashAndNumber {
    HashAndNumber {
        hash: hasher.hash(&header.encode()),
        number: header.number(),
    }
}

#[async_trait::async_trait]
impl BlockBackend for SubxtChain {
    async fn block_hash(&self, genesis: H256, number: u64) -> Result<Option<H256>, RuntimeFailure> {
        const METHOD: &str = "block_hash";
        let legacy = self.legacy(genesis).await?;
        if let Some(block) = legacy
            .backend
            .block_number_to_hash(number)
            .await
            .map_err(|error| failure(METHOD, error))?
        {
            return Ok(Some(block.hash()));
        }
        // Every height up to the finalized one has a block, so a missing hash
        // there is one the node cannot serve, not one that does not exist.
        if number <= finalized_block(&legacy, METHOD).await?.number {
            return Err(RuntimeFailure::host_failure(
                METHOD,
                format!("node cannot serve the hash of finalized block {number}"),
            ));
        }
        Ok(None)
    }

    async fn block_number(&self, genesis: H256, hash: H256) -> Result<Option<u64>, RuntimeFailure> {
        const METHOD: &str = "block_number";
        let header = self
            .legacy(genesis)
            .await?
            .backend
            .block_header(hash)
            .await
            .map_err(|error| failure(METHOD, error))?;
        Ok(header.map(|header| header.number()))
    }

    async fn extrinsic_hashes(
        &self,
        genesis: H256,
        at: H256,
    ) -> Result<Option<Vec<H256>>, RuntimeFailure> {
        const METHOD: &str = "extrinsic_hashes";
        let body = body(&self.legacy(genesis).await?, at, METHOD).await?;
        Ok(body.map(|extrinsics| {
            extrinsics
                .iter()
                .map(|extrinsic| H256(blake2_256(extrinsic)))
                .collect()
        }))
    }

    async fn dispatch_outcome(
        &self,
        genesis: H256,
        at: HashAndNumber,
        extrinsic: H256,
    ) -> Result<Option<DispatchOutcome>, RuntimeFailure> {
        const METHOD: &str = "dispatch_outcome";
        let legacy = self.legacy(genesis).await?;
        let Some(body) = body(&legacy, at.hash, METHOD).await? else {
            return Ok(None);
        };
        let Some(index) = body
            .iter()
            .position(|candidate| H256(blake2_256(candidate)) == extrinsic)
        else {
            return Ok(None);
        };
        let phase =
            Phase::ApplyExtrinsic(u32::try_from(index).map_err(|error| failure(METHOD, error))?);
        let at_block = legacy
            .client
            .at_block_hash_and_number(at.hash, at.number)
            .await
            .map_err(|error| failure(METHOD, error))?;
        let events = at_block
            .events()
            .fetch()
            .await
            .map_err(|error| failure(METHOD, error))?;
        for event in events.iter() {
            let event = event.map_err(|error| failure(METHOD, error))?;
            if event.phase() != phase || event.pallet_name() != "System" {
                continue;
            }
            match event.event_name() {
                "ExtrinsicSuccess" => return Ok(Some(DispatchOutcome::Succeeded)),
                "ExtrinsicFailed" => return Ok(Some(DispatchOutcome::Failed)),
                _ => {}
            }
        }
        Err(RuntimeFailure::host_failure(
            METHOD,
            format!(
                "no dispatch event for extrinsic {index} of block {:?}",
                at.hash
            ),
        ))
    }
}

#[async_trait::async_trait]
impl TxValidator for SubxtChain {
    async fn validate(
        &self,
        genesis: H256,
        extrinsic: &Extrinsic,
    ) -> Result<ValidationResult, RuntimeFailure> {
        const METHOD: &str = "validate";
        let legacy = self.legacy(genesis).await?;
        let best = best_block(&legacy, METHOD).await?;
        legacy
            .client
            .at_block_hash_and_number(best.hash, best.number)
            .await
            .map_err(|error| failure(METHOD, error))?
            .tx()
            .from_bytes(extrinsic.bytes().to_vec())
            .validate()
            .await
            .map_err(|error| failure(METHOD, error))
    }
}

#[async_trait::async_trait]
impl TxSubmitter for SubxtChain {
    async fn submit_and_watch(
        &self,
        genesis: H256,
        extrinsic: &Extrinsic,
    ) -> Result<BoxStream<'static, WatchEvent>, RuntimeFailure> {
        const METHOD: &str = "submit_and_watch";
        let progress = self
            .chains
            .online_client(genesis.as_bytes())
            .await?
            .tx()
            .await
            .map_err(|error| failure(METHOD, error))?
            .from_bytes(extrinsic.bytes().to_vec())
            .submit_and_watch()
            .await
            .map_err(|error| failure(METHOD, error))?;
        // The watch is dropped with its terminal event, so the subscription
        // does not outlive it.
        let events = stream::unfold(Some(progress), |progress| async move {
            let mut progress = progress?;
            loop {
                let event = match progress.next().await? {
                    Ok(TransactionStatus::Validated | TransactionStatus::Broadcasted) => continue,
                    Ok(TransactionStatus::NoLongerInBestBlock) => WatchEvent::NoLongerInBestBlock,
                    Ok(TransactionStatus::InBestBlock(block)) => {
                        WatchEvent::InBestBlock(block.block_hash())
                    }
                    Ok(TransactionStatus::InFinalizedBlock(block)) => {
                        WatchEvent::InFinalizedBlock(block.block_hash())
                    }
                    Ok(TransactionStatus::Invalid { message }) => WatchEvent::Invalid(message),
                    Ok(TransactionStatus::Dropped { message }) => WatchEvent::Dropped(message),
                    Ok(TransactionStatus::Error { message }) => WatchEvent::Error(message),
                    Err(error) => WatchEvent::Error(error.to_string()),
                };
                let next = (!event.is_terminal()).then_some(progress);
                return Some((event, next));
            }
        });
        Ok(events.boxed())
    }
}

/// A transport that failed or closed means the chain is unavailable for now;
/// anything else is a failure of the node or of decoding its answer.
fn failure(method: &'static str, error: impl Error + 'static) -> RuntimeFailure {
    let mut source: Option<&(dyn Error + 'static)> = Some(&error);
    while let Some(cause) = source {
        if let Some(RpcError::Client(_) | RpcError::DisconnectedWillReconnect(_)) =
            cause.downcast_ref()
        {
            return RuntimeFailure::unavailable_with_reason(method, error.to_string());
        }
        source = cause.source();
    }
    RuntimeFailure::host_failure(method, error.to_string())
}
