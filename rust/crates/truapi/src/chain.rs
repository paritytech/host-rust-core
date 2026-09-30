//! Chain capabilities shared by host services: heads, block data, and
//! transaction validation and submission.
//!
//! Each capability is its own trait, and a consumer takes only the ones it
//! uses as `Arc<dyn …>`. Every method names the chain by its genesis hash, so
//! one implementation serves every chain. [`SubxtChain`] implements all four
//! over [`crate::chain_runtime::ChainRuntime`]: reads go through the legacy
//! JSON-RPC methods, which reach any block the node still keeps, and
//! validation and submission go through the shared chainHead client.
//!
//! `Ok(None)` means the block, or the extrinsic in it, is unknown to the node.
//! A read the node cannot serve, for example events of a block whose state it
//! has pruned, is an `Err`.

use futures::stream::BoxStream;
use sp_crypto_hashing::blake2_256;
use subxt::tx::ValidationResult;
use subxt::utils::H256;

use crate::chain_runtime::RuntimeFailure;

mod subxt_chain;

pub use subxt_chain::SubxtChain;

#[cfg(all(test, not(target_arch = "wasm32")))]
mod tests;

/// An encoded extrinsic, ready to submit, with its hash as the chain computes
/// it.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct Extrinsic {
    bytes: Vec<u8>,
    hash: H256,
}

impl Extrinsic {
    /// Wrap a fully encoded extrinsic, including its length prefix.
    pub fn new(bytes: Vec<u8>) -> Self {
        let hash = H256(blake2_256(&bytes));
        Self { bytes, hash }
    }

    /// The encoded extrinsic.
    pub fn bytes(&self) -> &[u8] {
        &self.bytes
    }

    /// The extrinsic hash, as reported in blocks and transaction pools.
    pub fn hash(&self) -> H256 {
        self.hash
    }
}

/// A block identified by both its hash and its number.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct HashAndNumber {
    /// Block hash.
    pub hash: H256,
    /// Block number.
    pub number: u64,
}

/// The finalized and best blocks, read together.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct Heads {
    /// Latest finalized block.
    pub finalized: HashAndNumber,
    /// Current best block.
    pub best: HashAndNumber,
}

/// A new head reported by the node.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum HeadEvent {
    /// A block was finalized.
    Finalized(HashAndNumber),
    /// A block became the best block.
    Best(HashAndNumber),
}

/// Whether an included extrinsic dispatched successfully.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum DispatchOutcome {
    /// `System.ExtrinsicSuccess` was emitted for it.
    Succeeded,
    /// `System.ExtrinsicFailed` was emitted for it.
    Failed,
}

/// Progress of a submitted extrinsic. The stream ends after a terminal event.
#[derive(Clone, Debug, PartialEq, Eq)]
pub enum WatchEvent {
    /// Included in the block that is currently best.
    InBestBlock(H256),
    /// The best block that included it was retracted.
    NoLongerInBestBlock,
    /// Included in a finalized block. Terminal.
    InFinalizedBlock(H256),
    /// Rejected as invalid. Terminal.
    Invalid(String),
    /// Dropped from the pool. Terminal.
    Dropped(String),
    /// The node failed to track it. Terminal.
    Error(String),
}

impl WatchEvent {
    /// Whether no further event follows this one.
    pub fn is_terminal(&self) -> bool {
        !matches!(self, Self::InBestBlock(_) | Self::NoLongerInBestBlock)
    }
}

/// Finalized and best heads of a chain.
#[async_trait::async_trait]
pub trait ChainHeads: Send + Sync {
    /// The current finalized and best blocks.
    async fn heads(&self, genesis: H256) -> Result<Heads, RuntimeFailure>;

    /// A fresh stream of new finalized and best blocks. It ends when the
    /// node's subscriptions end.
    async fn head_events(
        &self,
        genesis: H256,
    ) -> Result<BoxStream<'static, Result<HeadEvent, RuntimeFailure>>, RuntimeFailure>;
}

/// Block data at any block the node still keeps.
#[async_trait::async_trait]
pub trait BlockBackend: Send + Sync {
    /// Hash of the canonical block at `number`.
    async fn block_hash(&self, genesis: H256, number: u64) -> Result<Option<H256>, RuntimeFailure>;

    /// Number of the block with `hash`.
    async fn block_number(&self, genesis: H256, hash: H256)
    -> Result<Option<u64>, RuntimeFailure>;

    /// Hashes of the extrinsics in the block with hash `at`, in block order.
    async fn extrinsic_hashes(
        &self,
        genesis: H256,
        at: H256,
    ) -> Result<Option<Vec<H256>>, RuntimeFailure>;

    /// How the extrinsic with hash `extrinsic` dispatched in block `at`, or
    /// `None` when the block does not contain it.
    async fn dispatch_outcome(
        &self,
        genesis: H256,
        at: HashAndNumber,
        extrinsic: H256,
    ) -> Result<Option<DispatchOutcome>, RuntimeFailure>;
}

/// Checks an extrinsic against the chain's transaction pool rules.
#[async_trait::async_trait]
pub trait TxValidator: Send + Sync {
    /// Validate `extrinsic` at the latest finalized block.
    async fn validate(
        &self,
        genesis: H256,
        extrinsic: &Extrinsic,
    ) -> Result<ValidationResult, RuntimeFailure>;
}

/// Submits extrinsics and reports their progress.
#[async_trait::async_trait]
pub trait TxSubmitter: Send + Sync {
    /// Send `extrinsic` once and watch it. Nothing resubmits it: a dropped or
    /// invalid extrinsic is reported and left to the caller.
    async fn submit_and_watch(
        &self,
        genesis: H256,
        extrinsic: &Extrinsic,
    ) -> Result<BoxStream<'static, WatchEvent>, RuntimeFailure>;
}
