//! Chain capabilities shared by host services: heads, block data, and
//! transaction validation and submission.
//!
//! Each capability is its own trait, and a consumer takes only the ones it
//! uses as `Arc<dyn …>`. Every method names the chain by its genesis hash, so
//! one implementation serves every chain. [`SubxtChain`] implements all four
//! over [`crate::chain_runtime::ChainRuntime`]: reads and validation go
//! through the legacy JSON-RPC methods, which reach any block the node still
//! keeps, and submission goes through the shared chainHead client.
//!
//! `Ok(None)` means the node knows the block, or the extrinsic in it, does
//! not exist. A read the node cannot serve, such as the body or events of a
//! block it has pruned, or any read over a closed connection, is an `Err`.
//! Extrinsics are hashed with Blake2-256, the hasher of every chain the core
//! talks to.

use futures::stream::BoxStream;
use sp_crypto_hashing::blake2_256;
use subxt::tx::ValidationResult;
use subxt::utils::H256;

use crate::chain_runtime::RuntimeFailure;

mod subxt_chain;

pub use subxt_chain::SubxtChain;

#[cfg(all(test, not(target_arch = "wasm32")))]
mod tests;

/// An encoded extrinsic, ready to submit, with its Blake2-256 hash as the
/// chain reports it.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct Extrinsic {
    bytes: Vec<u8>,
    hash: H256,
}

impl Extrinsic {
    /// Wrap a fully encoded extrinsic, including its compact length prefix.
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
    /// The node stopped watching it. Terminal, but the extrinsic may still
    /// be included.
    Dropped(String),
    /// Watching failed, on the node or in the client, which gives up after
    /// four minutes without finality. Terminal, but the extrinsic may still
    /// be included.
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

    /// A fresh stream of the finalized and best blocks the node announces,
    /// starting with the current ones. Finalized blocks it skips are not
    /// filled in. The stream ends after its first error.
    async fn head_events(
        &self,
        genesis: H256,
    ) -> Result<BoxStream<'static, Result<HeadEvent, RuntimeFailure>>, RuntimeFailure>;
}

/// Block data at any block the node still keeps.
#[async_trait::async_trait]
pub trait BlockBackend: Send + Sync {
    /// Hash of the block at `number`: canonical up to the finalized height,
    /// on the current best chain above it, where a reorg can replace it.
    async fn block_hash(&self, genesis: H256, number: u64) -> Result<Option<H256>, RuntimeFailure>;

    /// Number of the block with `hash`.
    async fn block_number(&self, genesis: H256, hash: H256) -> Result<Option<u64>, RuntimeFailure>;

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
    /// Validate `extrinsic` against the best block, as the transaction pool
    /// does.
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
    /// invalid extrinsic is reported and left to the caller. An `Err` does not
    /// prove the node never received it.
    async fn submit_and_watch(
        &self,
        genesis: H256,
        extrinsic: &Extrinsic,
    ) -> Result<BoxStream<'static, WatchEvent>, RuntimeFailure>;
}
