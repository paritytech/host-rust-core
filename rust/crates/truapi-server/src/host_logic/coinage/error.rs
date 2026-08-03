//! Error taxonomy for the coinage layer.
//!
//! Errors returned synchronously describe failure to *start* an operation.
//! Errors carried in a terminal `Failed` status describe failure of a started
//! operation.

use core::fmt;

use parity_scale_codec::{Decode, Encode};
use thiserror::Error;

use super::types::{Amount, ExtrinsicHash, OperationHandle, PurseId};

/// A failure in the coinage layer.
#[derive(Debug, Clone, PartialEq, Eq, Error, Encode, Decode)]
pub enum CoinageError {
    /// No purse with this identifier exists.
    #[error("{0} does not exist")]
    PurseNotFound(PurseId),
    /// No operation with this handle is open. Terminal operations are dropped
    /// once their status has been emitted, so a stale handle lands here.
    #[error("{0} is not open")]
    OperationNotFound(OperationHandle),
    /// The main purse cannot be deleted.
    #[error("the main purse cannot be deleted")]
    CannotDeleteMainPurse,
    /// The purse still has operations that have not reached a terminal state.
    #[error("purse has in-flight operations")]
    PurseHasInFlightOperations,
    /// The requested recipient outputs do not sum to the requested amount.
    #[error("recipient outputs do not sum to the requested amount")]
    OutputsDoNotSumToAmount,
    /// The purse cannot cover the requested amount.
    #[error("insufficient funds: requested {requested}, available {available}")]
    InsufficientFunds {
        /// Amount the caller asked for.
        requested: Amount,
        /// Amount the purse can currently produce.
        available: Amount,
    },
    /// The fee account cannot cover an externally funded step.
    #[error("insufficient external funds")]
    InsufficientExternalFunds,
    /// The purse holds enough value, but too much of it sits in recycler
    /// entries that are not yet selectable. Distinguishes "wait" from
    /// "insufficient funds".
    #[error("no ready entries: requested {requested}, available when ready {available_when_ready}")]
    NoReadyEntries {
        /// Amount the caller asked for.
        requested: Amount,
        /// Amount that would be available once pending entries become ready.
        available_when_ready: Amount,
    },
    /// The purse holds enough selectable value, and waiting would not add any,
    /// but it cannot be arranged into the requested denominations.
    ///
    /// Coinage can divide a coin but never merge two, so a request for one
    /// 16-cent output cannot be met by two 8-cent coins. Per-extrinsic caps can
    /// have the same effect: a named denomination has to be minted whole by a
    /// single group, and no group may be large enough.
    #[error(
        "holdings cannot be arranged into the requested outputs: requested {requested}, available {available}"
    )]
    UnsatisfiableOutputs {
        /// Amount the caller asked for.
        requested: Amount,
        /// Selectable value the purse holds.
        available: Amount,
    },
    /// Neither a free nor a paid unload token could be obtained.
    #[error("no unload token available")]
    NoUnloadToken,
    /// An imported coin secret is malformed or does not control the coin.
    #[error("bad coin secret")]
    BadCoinSecret,
    /// A coin was spent by someone else between selection and submission.
    #[error("coin was sniped before submission")]
    SnipedCoin,
    /// The chain rejected a submitted extrinsic.
    #[error("chain rejected extrinsic {extrinsic_hash:?}: {reason}")]
    ChainRejected {
        /// Hash of the rejected extrinsic.
        extrinsic_hash: ExtrinsicHash,
        /// Rejection reason reported by the chain.
        reason: String,
    },
    /// The caller cancelled the operation before any extrinsic was in flight.
    #[error("operation cancelled")]
    Cancelled,
    /// The layer restarted while the operation was preparing, before it had
    /// submitted anything.
    #[error("operation interrupted before submission")]
    InterruptedPreSubmission,
    /// The durable store could not be read or written.
    #[error("storage error: {0}")]
    StorageError(String),
    /// A chain subscription failed.
    #[error("subscription error: {0}")]
    SubscriptionError(String),
    /// Recovery from root entropy could not complete.
    #[error("recovery failed: {0}")]
    RecoveryFailed(String),
    /// An invariant of the layer was violated.
    #[error("internal error: {0}")]
    Internal(String),
}

/// A lifecycle transition the state model does not permit.
///
/// Records reject transitions rather than silently absorbing them, so a
/// mis-sequenced caller surfaces immediately instead of corrupting the model.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Error)]
pub struct InvalidTransition {
    /// What kind of record was being transitioned, e.g. `"coin"`.
    pub subject: &'static str,
    /// The state the record was in.
    pub from: &'static str,
    /// The transition that was attempted.
    pub attempted: &'static str,
}

impl InvalidTransition {
    /// Construct a rejection for `attempted` applied to a record in `from`.
    pub const fn new(subject: &'static str, from: &'static str, attempted: &'static str) -> Self {
        Self {
            subject,
            from,
            attempted,
        }
    }
}

impl fmt::Display for InvalidTransition {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(
            f,
            "cannot {} a {} in state {}",
            self.attempted, self.subject, self.from
        )
    }
}

impl From<InvalidTransition> for CoinageError {
    fn from(transition: InvalidTransition) -> Self {
        Self::Internal(transition.to_string())
    }
}
