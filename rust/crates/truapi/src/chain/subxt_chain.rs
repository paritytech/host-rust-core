//! [`SubxtChain`]: the chain capabilities over subxt clients.

use core::fmt::Display;
use core::future::ready;

use futures::stream::{self, BoxStream, StreamExt};
use sp_crypto_hashing::blake2_256;
use subxt::backend::Backend;
use subxt::config::Header;
use subxt::events::Phase;
use subxt::tx::{TransactionStatus, ValidationResult};
use subxt::utils::H256;

use super::{
    BlockBackend, ChainHeads, DispatchOutcome, Extrinsic, HashAndNumber, HeadEvent, Heads,
    TxSubmitter, TxValidator, WatchEvent,
};
use crate::chain_runtime::{ChainRuntime, LegacyConnection, RuntimeFailure};

/// The chain capabilities over [`ChainRuntime`]'s per-chain subxt clients:
/// the legacy client for reads, the shared chainHead client for validation
/// and submission.
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
}

#[async_trait::async_trait]
impl ChainHeads for SubxtChain {
    async fn heads(&self, genesis: H256) -> Result<Heads, RuntimeFailure> {
        const METHOD: &str = "chain_heads";
        let legacy = self.legacy(genesis).await?;
        let finalized = legacy
            .backend
            .latest_finalized_block_ref()
            .await
            .map_err(|error| failure(METHOD, error))?
            .hash();
        let best = legacy
            .methods
            .chain_get_block_hash(None)
            .await
            .map_err(|error| failure(METHOD, error))?
            .ok_or_else(|| RuntimeFailure::host_failure(METHOD, "node reported no best block"))?;
        Ok(Heads {
            finalized: Self::numbered(&legacy, finalized, METHOD).await?,
            best: Self::numbered(&legacy, best, METHOD).await?,
        })
    }

    async fn head_events(
        &self,
        genesis: H256,
    ) -> Result<BoxStream<'static, Result<HeadEvent, RuntimeFailure>>, RuntimeFailure> {
        const METHOD: &str = "chain_head_events";
        let legacy = self.legacy(genesis).await?;
        // Header streams hash each header with the chain's hasher, which comes
        // from metadata.
        let hasher = *legacy
            .client
            .at_current_block()
            .await
            .map_err(|error| failure(METHOD, error))?
            .hasher();
        let head = |kind: fn(HashAndNumber) -> HeadEvent| {
            move |item: Result<(<subxt::SubstrateConfig as subxt::Config>::Header, subxt::backend::BlockRef<H256>), subxt::error::BackendError>| {
                item.map(|(header, block)| {
                    kind(HashAndNumber {
                        hash: block.hash(),
                        number: header.number(),
                    })
                })
                .map_err(|error| failure(METHOD, error))
            }
        };
        let finalized = legacy
            .backend
            .stream_finalized_block_headers(hasher)
            .await
            .map_err(|error| failure(METHOD, error))?
            .map(head(HeadEvent::Finalized));
        let best = legacy
            .backend
            .stream_best_block_headers(hasher)
            .await
            .map_err(|error| failure(METHOD, error))?
            .map(head(HeadEvent::Best));
        Ok(stream::select(finalized, best).boxed())
    }
}

#[async_trait::async_trait]
impl BlockBackend for SubxtChain {
    async fn block_hash(&self, genesis: H256, number: u64) -> Result<Option<H256>, RuntimeFailure> {
        const METHOD: &str = "block_hash";
        let block = self
            .legacy(genesis)
            .await?
            .backend
            .block_number_to_hash(number)
            .await
            .map_err(|error| failure(METHOD, error))?;
        Ok(block.map(|block| block.hash()))
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
        let body = self
            .legacy(genesis)
            .await?
            .backend
            .block_body(at)
            .await
            .map_err(|error| failure(METHOD, error))?;
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
        let Some(body) = legacy
            .backend
            .block_body(at.hash)
            .await
            .map_err(|error| failure(METHOD, error))?
        else {
            return Ok(None);
        };
        let Some(index) = body
            .iter()
            .position(|candidate| H256(blake2_256(candidate)) == extrinsic)
        else {
            return Ok(None);
        };
        let phase = Phase::ApplyExtrinsic(
            u32::try_from(index).map_err(|error| failure(METHOD, error))?,
        );
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
            format!("no dispatch event for extrinsic {index} of block {:?}", at.hash),
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
        self.chains
            .online_client(genesis.as_bytes())
            .await?
            .tx()
            .await
            .map_err(|error| failure(METHOD, error))?
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
        let events = progress
            .filter_map(|status| {
                ready(match status {
                    Ok(TransactionStatus::Validated | TransactionStatus::Broadcasted) => None,
                    Ok(TransactionStatus::NoLongerInBestBlock) => {
                        Some(WatchEvent::NoLongerInBestBlock)
                    }
                    Ok(TransactionStatus::InBestBlock(block)) => {
                        Some(WatchEvent::InBestBlock(block.block_hash()))
                    }
                    Ok(TransactionStatus::InFinalizedBlock(block)) => {
                        Some(WatchEvent::InFinalizedBlock(block.block_hash()))
                    }
                    Ok(TransactionStatus::Invalid { message }) => Some(WatchEvent::Invalid(message)),
                    Ok(TransactionStatus::Dropped { message }) => Some(WatchEvent::Dropped(message)),
                    Ok(TransactionStatus::Error { message }) => Some(WatchEvent::Error(message)),
                    Err(error) => Some(WatchEvent::Error(error.to_string())),
                })
            })
            .scan(false, |ended, event| {
                if *ended {
                    return ready(None);
                }
                *ended = event.is_terminal();
                ready(Some(event))
            });
        Ok(events.boxed())
    }
}

fn failure(method: &'static str, error: impl Display) -> RuntimeFailure {
    RuntimeFailure::host_failure(method, error.to_string())
}
