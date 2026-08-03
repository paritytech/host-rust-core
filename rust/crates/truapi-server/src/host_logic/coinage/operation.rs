//! Operation records, their status machine, and receipts.
//!
//! Every call to a long-running primitive starts a fresh operation with a
//! durable handle and a lock set no other operation may touch. The layer does
//! not deduplicate by argument equality; callers needing idempotency track
//! handles themselves.

use parity_scale_codec::{Decode, Encode};

use super::error::{CoinageError, InvalidTransition};
use super::types::{
    BlockHash, CoinAccountId, CoinIndex, EntryIndex, ExtrinsicHash, OperationHandle, OperationKind,
    PurseId, Timestamp,
};

const SUBJECT: &str = "operation";

/// Outcome of one submitted extrinsic.
#[derive(Debug, Clone, PartialEq, Eq, Encode, Decode)]
pub enum ExtrinsicOutcome {
    /// The extrinsic was included and its effects observed.
    Succeeded {
        /// Block that included the extrinsic.
        block_hash: BlockHash,
        /// Coin accounts the extrinsic consumed and created, together.
        affected_coins: Vec<CoinAccountId>,
    },
    /// The chain rejected the extrinsic.
    Rejected {
        /// Rejection reason reported by the chain.
        reason: String,
    },
}

impl ExtrinsicOutcome {
    /// Whether this extrinsic landed.
    pub const fn succeeded(&self) -> bool {
        matches!(self, Self::Succeeded { .. })
    }
}

/// One extrinsic an operation submitted, and how it resolved.
#[derive(Debug, Clone, PartialEq, Eq, Encode, Decode)]
pub struct ExtrinsicRecord {
    /// Hash of the submitted extrinsic.
    pub extrinsic_hash: ExtrinsicHash,
    /// How the chain resolved it.
    pub outcome: ExtrinsicOutcome,
}

/// Per-extrinsic summary attached to a successful operation.
///
/// A multi-extrinsic operation may mix successes and rejections: `Done` means
/// *at least one* extrinsic succeeded, and the caller introspects the records
/// to decide what that means for them.
#[derive(Debug, Clone, Default, PartialEq, Eq, Encode, Decode)]
pub struct OperationReceipt {
    /// Every extrinsic the operation submitted, in submission order.
    pub extrinsics: Vec<ExtrinsicRecord>,
}

impl OperationReceipt {
    /// Whether any submitted extrinsic succeeded.
    pub fn any_succeeded(&self) -> bool {
        self.extrinsics
            .iter()
            .any(|record| record.outcome.succeeded())
    }

    /// Whether some but not all submitted extrinsics succeeded.
    pub fn is_partial(&self) -> bool {
        self.any_succeeded()
            && self
                .extrinsics
                .iter()
                .any(|record| !record.outcome.succeeded())
    }
}

/// Terminal outcome of an operation.
#[derive(Debug, Clone, PartialEq, Eq, Encode, Decode)]
pub enum TerminalStatus {
    /// At least one submitted extrinsic was finalized successfully.
    Done(OperationReceipt),
    /// Nothing was submitted, everything submitted was rejected, or the
    /// operation was cancelled.
    Failed(CoinageError),
}

/// Where an operation is in its lifecycle.
#[derive(Debug, Clone, PartialEq, Eq, Encode, Decode)]
pub enum OperationStatus {
    /// Selecting, deriving, signing, building extrinsics, or re-planning
    /// between phases. Nothing in flight.
    Preparing,
    /// An extrinsic has been broadcast.
    Submitted,
    /// An extrinsic is in a non-finalized block.
    InBlock,
    /// An extrinsic has been finalized.
    Finalized,
    /// Blocked until the given instant, then back to `Preparing`.
    Waiting(Timestamp),
    /// Terminal success.
    Done(OperationReceipt),
    /// Terminal failure.
    Failed(CoinageError),
}

impl OperationStatus {
    /// A short label for diagnostics.
    pub const fn label(&self) -> &'static str {
        match self {
            Self::Preparing => "preparing",
            Self::Submitted => "submitted",
            Self::InBlock => "in-block",
            Self::Finalized => "finalized",
            Self::Waiting(_) => "waiting",
            Self::Done(_) => "done",
            Self::Failed(_) => "failed",
        }
    }

    /// Whether the operation has finished and its stream should close.
    pub const fn is_terminal(&self) -> bool {
        matches!(self, Self::Done(_) | Self::Failed(_))
    }

    /// Whether the caller may cancel right now.
    ///
    /// Cancellation is possible exactly while no extrinsic is in flight. A
    /// multi-phase operation becomes cancellable again each time it returns to
    /// `Preparing` or `Waiting`.
    pub const fn is_cancellable(&self) -> bool {
        matches!(self, Self::Preparing | Self::Waiting(_))
    }

    /// Whether an extrinsic is currently in flight.
    pub const fn has_extrinsic_in_flight(&self) -> bool {
        matches!(self, Self::Submitted | Self::InBlock)
    }

    /// The terminal outcome, if the operation has reached one.
    pub fn terminal(&self) -> Option<TerminalStatus> {
        match self {
            Self::Done(receipt) => Some(TerminalStatus::Done(receipt.clone())),
            Self::Failed(error) => Some(TerminalStatus::Failed(error.clone())),
            _ => None,
        }
    }
}

/// The set of records an operation holds exclusively until it terminates.
#[derive(Debug, Clone, Default, PartialEq, Eq, Encode, Decode)]
pub struct LockSet {
    /// Coins locked, by purse-scoped index.
    pub coins: Vec<(PurseId, CoinIndex)>,
    /// Recycler entries locked, by purse-scoped index.
    pub entries: Vec<(PurseId, EntryIndex)>,
}

impl LockSet {
    /// Whether the operation holds nothing.
    pub fn is_empty(&self) -> bool {
        self.coins.is_empty() && self.entries.is_empty()
    }

    /// Whether two lock sets overlap. Operations with disjoint lock sets may
    /// run concurrently.
    pub fn intersects(&self, other: &Self) -> bool {
        self.coins.iter().any(|coin| other.coins.contains(coin))
            || self
                .entries
                .iter()
                .any(|entry| other.entries.contains(entry))
    }
}

/// A durable operation record.
#[derive(Debug, Clone, PartialEq, Eq, Encode, Decode)]
pub struct Operation {
    /// Layer-issued handle.
    pub handle: OperationHandle,
    /// What the operation does.
    pub kind: OperationKind,
    /// Purse the operation acts on. Cross-purse operations name their source.
    pub purse: PurseId,
    /// Records held exclusively by this operation.
    pub locks: LockSet,
    /// Extrinsics submitted so far, appended before each broadcast.
    pub submitted: Vec<ExtrinsicHash>,
    /// Current status.
    pub status: OperationStatus,
}

impl Operation {
    /// Start an operation in `Preparing` with no locks and nothing submitted.
    pub fn start(handle: OperationHandle, kind: OperationKind, purse: PurseId) -> Self {
        Self {
            handle,
            kind,
            purse,
            locks: LockSet::default(),
            submitted: Vec::new(),
            status: OperationStatus::Preparing,
        }
    }

    /// Whether the operation has finished.
    pub fn is_terminal(&self) -> bool {
        self.status.is_terminal()
    }

    /// Whether the operation ever broadcast anything.
    pub fn has_submitted(&self) -> bool {
        !self.submitted.is_empty()
    }

    /// Record an extrinsic hash immediately before broadcasting it, and move to
    /// `Submitted`.
    ///
    /// The hash is appended before the broadcast so that a restart mid-flight
    /// can reconcile it against chain state rather than assume nothing happened.
    pub fn record_submission(
        &mut self,
        extrinsic_hash: ExtrinsicHash,
    ) -> Result<(), InvalidTransition> {
        if self.status.is_terminal() {
            return Err(InvalidTransition::new(
                SUBJECT,
                self.status.label(),
                "record a submission for",
            ));
        }

        self.submitted.push(extrinsic_hash);
        self.status = OperationStatus::Submitted;
        Ok(())
    }

    /// Advance to a non-terminal status.
    pub fn advance(&mut self, status: OperationStatus) -> Result<(), InvalidTransition> {
        if status.is_terminal() {
            return Err(InvalidTransition::new(
                SUBJECT,
                self.status.label(),
                "advance to a terminal status",
            ));
        }

        if self.status.is_terminal() {
            return Err(InvalidTransition::new(
                SUBJECT,
                self.status.label(),
                "advance",
            ));
        }

        self.status = status;
        Ok(())
    }

    /// Finish successfully with a receipt.
    pub fn finish(&mut self, receipt: OperationReceipt) -> Result<(), InvalidTransition> {
        if self.status.is_terminal() {
            return Err(InvalidTransition::new(
                SUBJECT,
                self.status.label(),
                "finish",
            ));
        }

        self.status = OperationStatus::Done(receipt);
        self.locks = LockSet::default();
        Ok(())
    }

    /// Finish unsuccessfully.
    pub fn fail(&mut self, error: CoinageError) -> Result<(), InvalidTransition> {
        if self.status.is_terminal() {
            return Err(InvalidTransition::new(SUBJECT, self.status.label(), "fail"));
        }

        self.status = OperationStatus::Failed(error);
        self.locks = LockSet::default();
        Ok(())
    }

    /// Cancel the operation, which is permitted only while nothing is in
    /// flight.
    pub fn cancel(&mut self) -> Result<(), InvalidTransition> {
        if !self.status.is_cancellable() {
            return Err(InvalidTransition::new(
                SUBJECT,
                self.status.label(),
                "cancel",
            ));
        }

        self.fail(CoinageError::Cancelled)
    }

    /// Resolve an operation found open after a restart.
    ///
    /// Pre-submission scratch state is not durable, so an operation that never
    /// broadcast is equivalent to a cancel. One that did must be reconciled
    /// against chain state by the caller, which is why this only reports what
    /// to do rather than deciding it.
    pub fn restart_disposition(&self) -> RestartDisposition {
        if self.is_terminal() {
            RestartDisposition::AlreadyTerminal
        } else if self.has_submitted() {
            RestartDisposition::Reconcile
        } else {
            RestartDisposition::FailInterrupted
        }
    }
}

/// What to do with an operation record recovered after a restart.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum RestartDisposition {
    /// The record is already finished; drop it.
    AlreadyTerminal,
    /// Nothing was broadcast, so fail it and release its locks.
    FailInterrupted,
    /// Extrinsics were broadcast; check them against chain state.
    Reconcile,
}

#[cfg(test)]
mod tests {
    use super::*;

    fn hash(byte: u8) -> ExtrinsicHash {
        ExtrinsicHash([byte; 32])
    }

    fn new_operation() -> Operation {
        Operation::start(OperationHandle(1), OperationKind::Transfer, PurseId::MAIN)
    }

    fn succeeded() -> ExtrinsicRecord {
        ExtrinsicRecord {
            extrinsic_hash: hash(1),
            outcome: ExtrinsicOutcome::Succeeded {
                block_hash: BlockHash([9; 32]),
                affected_coins: Vec::new(),
            },
        }
    }

    fn rejected() -> ExtrinsicRecord {
        ExtrinsicRecord {
            extrinsic_hash: hash(2),
            outcome: ExtrinsicOutcome::Rejected {
                reason: "bad origin".to_string(),
            },
        }
    }

    #[test]
    fn an_operation_starts_preparing_and_cancellable() {
        let operation = new_operation();

        assert_eq!(operation.status, OperationStatus::Preparing);
        assert!(operation.status.is_cancellable());
        assert!(!operation.has_submitted());
        assert!(operation.locks.is_empty());
    }

    #[test]
    fn cancellation_is_blocked_exactly_while_an_extrinsic_is_in_flight() {
        assert!(OperationStatus::Preparing.is_cancellable());
        assert!(OperationStatus::Waiting(Timestamp(1)).is_cancellable());
        assert!(!OperationStatus::Submitted.is_cancellable());
        assert!(!OperationStatus::InBlock.is_cancellable());
        assert!(!OperationStatus::Finalized.is_cancellable());
    }

    #[test]
    fn submission_is_recorded_before_the_status_moves() {
        let mut operation = new_operation();

        operation
            .record_submission(hash(3))
            .expect("submission is valid");

        assert_eq!(operation.submitted, vec![hash(3)]);
        assert_eq!(operation.status, OperationStatus::Submitted);
        assert!(operation.status.has_extrinsic_in_flight());
    }

    #[test]
    fn an_in_flight_operation_cannot_be_cancelled() {
        let mut operation = new_operation();
        operation
            .record_submission(hash(3))
            .expect("submission is valid");

        assert!(operation.cancel().is_err());
        assert_eq!(operation.status, OperationStatus::Submitted);
    }

    #[test]
    fn a_multi_phase_operation_becomes_cancellable_again_at_preparing() {
        let mut operation = new_operation();
        operation
            .record_submission(hash(3))
            .expect("submission is valid");
        operation
            .advance(OperationStatus::Finalized)
            .expect("advance is valid");
        operation
            .advance(OperationStatus::Preparing)
            .expect("re-plan is valid");

        assert!(operation.status.is_cancellable());
        operation.cancel().expect("cancel is valid");
        assert_eq!(
            operation.status,
            OperationStatus::Failed(CoinageError::Cancelled)
        );
    }

    #[test]
    fn advance_refuses_terminal_statuses() {
        let mut operation = new_operation();

        assert!(
            operation
                .advance(OperationStatus::Done(OperationReceipt::default()))
                .is_err()
        );
        assert!(
            operation
                .advance(OperationStatus::Failed(CoinageError::Cancelled))
                .is_err()
        );
    }

    #[test]
    fn terminating_releases_every_lock() {
        let mut operation = new_operation();
        operation.locks.coins.push((PurseId::MAIN, CoinIndex(0)));
        operation.locks.entries.push((PurseId::MAIN, EntryIndex(0)));

        operation
            .finish(OperationReceipt::default())
            .expect("finish is valid");

        assert!(operation.locks.is_empty());
    }

    #[test]
    fn a_terminal_operation_rejects_every_further_transition() {
        let mut operation = new_operation();
        operation.cancel().expect("cancel is valid");

        assert!(operation.record_submission(hash(4)).is_err());
        assert!(operation.advance(OperationStatus::Preparing).is_err());
        assert!(operation.finish(OperationReceipt::default()).is_err());
        assert!(operation.fail(CoinageError::Cancelled).is_err());
        assert!(operation.cancel().is_err());
    }

    #[test]
    fn a_receipt_reports_partial_success() {
        let all_good = OperationReceipt {
            extrinsics: vec![succeeded()],
        };
        let mixed = OperationReceipt {
            extrinsics: vec![succeeded(), rejected()],
        };
        let all_bad = OperationReceipt {
            extrinsics: vec![rejected()],
        };

        assert!(all_good.any_succeeded() && !all_good.is_partial());
        assert!(mixed.any_succeeded() && mixed.is_partial());
        assert!(!all_bad.any_succeeded() && !all_bad.is_partial());
    }

    #[test]
    fn restart_fails_operations_that_never_broadcast() {
        let operation = new_operation();

        assert_eq!(
            operation.restart_disposition(),
            RestartDisposition::FailInterrupted
        );
    }

    #[test]
    fn restart_reconciles_operations_that_broadcast() {
        let mut operation = new_operation();
        operation
            .record_submission(hash(5))
            .expect("submission is valid");

        assert_eq!(
            operation.restart_disposition(),
            RestartDisposition::Reconcile
        );
    }

    #[test]
    fn disjoint_lock_sets_do_not_intersect() {
        let first = LockSet {
            coins: vec![(PurseId::MAIN, CoinIndex(0))],
            entries: Vec::new(),
        };
        let second = LockSet {
            coins: vec![(PurseId::MAIN, CoinIndex(1))],
            entries: Vec::new(),
        };
        let overlapping = LockSet {
            coins: vec![(PurseId::MAIN, CoinIndex(0))],
            entries: Vec::new(),
        };

        assert!(!first.intersects(&second));
        assert!(first.intersects(&overlapping));
    }

    #[test]
    fn the_same_index_in_two_purses_is_a_different_lock() {
        let main = LockSet {
            coins: vec![(PurseId::MAIN, CoinIndex(0))],
            entries: Vec::new(),
        };
        let other = LockSet {
            coins: vec![(PurseId(1), CoinIndex(0))],
            entries: Vec::new(),
        };

        assert!(!main.intersects(&other));
    }
}
