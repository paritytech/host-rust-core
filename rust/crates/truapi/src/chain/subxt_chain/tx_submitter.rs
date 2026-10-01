//! [`TxSubmitter`] for [`SubxtChain`].

use futures::stream::{self, BoxStream, StreamExt};
use subxt::tx::TransactionStatus;
use subxt::utils::H256;

use super::{SubxtChain, failure};
use crate::chain::{EncodedExtrinsic, TxSubmitter, WatchEvent};
use crate::chain_runtime::RuntimeFailure;

#[async_trait::async_trait]
impl TxSubmitter for SubxtChain {
    async fn submit_and_watch(
        &self,
        genesis: H256,
        extrinsic: &EncodedExtrinsic,
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
