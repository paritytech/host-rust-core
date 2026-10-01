//! [`ChainHeads`] for [`SubxtChain`].

use futures::Stream;
use futures::stream::{self, BoxStream, StreamExt};
use subxt::config::substrate::DynamicHasher256;
use subxt::config::{Hasher, Header};
use subxt::utils::H256;
use subxt_rpcs::Error as RpcError;

use super::{SubxtChain, best_block, failure, finalized_block};
use crate::chain::{ChainHeads, HashAndNumber, HeadEvent, Heads};
use crate::chain_runtime::{LegacyConnection, RuntimeFailure};

const HEADS: &str = "chain_heads";
const HEAD_EVENTS: &str = "chain_head_events";

type HeadEvents = BoxStream<'static, Result<HeadEvent, RuntimeFailure>>;

#[async_trait::async_trait]
impl ChainHeads for SubxtChain {
    async fn heads(&self, genesis: H256) -> Result<Heads, RuntimeFailure> {
        let legacy = self.legacy(genesis).await?;
        Ok(Heads {
            finalized: finalized_block(&legacy, HEADS).await?,
            best: best_block(&legacy, HEADS).await?,
        })
    }

    async fn head_events(&self, genesis: H256) -> Result<HeadEvents, RuntimeFailure> {
        let legacy = self.legacy(genesis).await?;
        let hasher = chain_hasher(&legacy).await?;
        let finalized = finalized_heads(&legacy, hasher).await?;
        let best = best_heads(&legacy, hasher).await?;
        Ok(stream::select(finalized, best).boxed())
    }
}

/// Blocks are hashed with the chain's hasher, which comes from metadata.
async fn chain_hasher(legacy: &LegacyConnection) -> Result<DynamicHasher256, RuntimeFailure> {
    let at = legacy
        .client
        .at_current_block()
        .await
        .map_err(|error| failure(HEAD_EVENTS, error))?;
    Ok(*at.hasher())
}

/// Finalized heads exactly as the node announces them. Filling gaps by height
/// would ask for hashes a light client cannot give.
async fn finalized_heads(
    legacy: &LegacyConnection,
    hasher: DynamicHasher256,
) -> Result<HeadEvents, RuntimeFailure> {
    let headers = legacy
        .methods
        .chain_subscribe_finalized_heads()
        .await
        .map_err(|error| failure(HEAD_EVENTS, error))?;
    Ok(announced(headers, hasher, HeadEvent::Finalized))
}

/// Best heads as the node announces them.
async fn best_heads(
    legacy: &LegacyConnection,
    hasher: DynamicHasher256,
) -> Result<HeadEvents, RuntimeFailure> {
    let headers = legacy
        .methods
        .chain_subscribe_new_heads()
        .await
        .map_err(|error| failure(HEAD_EVENTS, error))?;
    Ok(announced(headers, hasher, HeadEvent::Best))
}

fn announced<Headers, H>(
    headers: Headers,
    hasher: DynamicHasher256,
    event: fn(HashAndNumber) -> HeadEvent,
) -> HeadEvents
where
    Headers: Stream<Item = Result<H, RpcError>> + Send + 'static,
    H: Header,
{
    headers
        .map(move |header| {
            let header = header.map_err(|error| failure(HEAD_EVENTS, error))?;
            Ok(event(HashAndNumber {
                hash: hasher.hash(&header.encode()),
                number: header.number(),
            }))
        })
        .boxed()
}
