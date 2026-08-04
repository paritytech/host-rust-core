//! The durable operation log.
//!
//! `coinage-layer.md` §7.4. One entry per **on-chain transaction**, not per
//! logical operation: an operation that unloads two recycler groups and then
//! transfers the resulting coins has three entries.
//!
//! An entry is written before its transaction is broadcast and carries
//! everything needed to decide the transaction's fate later without having seen
//! any of it happen — which inputs it consumes, which outputs it should create,
//! and the era it was anchored in. That last part is what makes an unresolved
//! entry decidable at all: past `checkpoint + mortality` the transaction can
//! never be included, so its inputs can be released. An immortal transaction
//! has no such point, which is why `runtime::coinage::extrinsic` refuses to
//! assemble one.
//!
//! The log records purse-scoped indices rather than account identifiers.
//! Indices are the layer's own identity for a record (§4.1) and the accounts
//! are derivable from them, so this keeps the durable store from spelling out
//! the input-to-output linkage that the recycler anonymity set exists to break
//! (§12.3).

use parity_scale_codec::{Decode, Encode};

use super::error::CoinageError;
use super::operation::{ExtrinsicOutcome, ExtrinsicRecord, LockSet, OperationReceipt};
use super::types::{BlockHash, ExtrinsicHash};

/// The era a transaction was anchored in.
///
/// Mirrors the anchor the extrinsic was actually built with. If the two ever
/// disagree, the expiry test below is answering a question about a different
/// transaction.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Encode, Decode)]
pub struct Checkpoint {
    /// Height of the era anchor block.
    pub number: u64,
    /// Hash of the era anchor block.
    pub hash: BlockHash,
    /// Era length in blocks.
    pub mortality: u64,
}

impl Checkpoint {
    /// Last height at which the transaction can still be included.
    pub const fn last_valid_block(&self) -> u64 {
        self.number.saturating_add(self.mortality)
    }

    /// Whether a finalized chain at this height proves the transaction dead.
    ///
    /// Strictly greater: at exactly `last_valid_block` the transaction is still
    /// includable, and releasing its inputs a block early would let them be
    /// respent under a transaction that can still land.
    pub const fn has_expired(&self, finalized_height: u64) -> bool {
        finalized_height > self.last_valid_block()
    }
}

/// How a logged transaction resolved.
#[derive(Debug, Clone, PartialEq, Eq, Encode, Decode)]
pub enum LogEntryState {
    /// Still in flight, or never broadcast and not yet given up on.
    Pending,
    /// Definitely took effect, observed at a finalized block.
    Succeeded {
        /// The finalized block the effect was observed at.
        block_hash: BlockHash,
    },
    /// Definitely did not and can never take effect.
    Rejected {
        /// Why.
        reason: String,
    },
    /// Never submitted, because a transaction it depends on did not succeed.
    Abandoned {
        /// Why.
        reason: String,
    },
}

impl LogEntryState {
    /// A short label for diagnostics.
    pub const fn label(&self) -> &'static str {
        match self {
            Self::Pending => "pending",
            Self::Succeeded { .. } => "succeeded",
            Self::Rejected { .. } => "rejected",
            Self::Abandoned { .. } => "abandoned",
        }
    }

    /// Whether the entry still needs resolving.
    pub const fn is_pending(&self) -> bool {
        matches!(self, Self::Pending)
    }

    /// Whether the transaction took effect.
    pub const fn succeeded(&self) -> bool {
        matches!(self, Self::Succeeded { .. })
    }
}

/// One transaction's worth of write-ahead log.
#[derive(Debug, Clone, PartialEq, Eq, Encode, Decode)]
pub struct LogEntry {
    /// Position within the owning operation. Unique per operation, assigned in
    /// planning order.
    pub sequence: u32,
    /// Sequences within the same operation whose outputs this entry consumes.
    ///
    /// Intra-operation by construction: an operation never spends another
    /// operation's in-flight outputs, because selection can only choose records
    /// no other operation holds.
    pub depends_on: Vec<u32>,
    /// Records the transaction consumes.
    pub inputs: LockSet,
    /// Records the transaction is expected to create.
    pub outputs: LockSet,
    /// Hash of the assembled extrinsic; `None` until one is built.
    pub extrinsic_hash: Option<ExtrinsicHash>,
    /// The era the extrinsic was anchored in.
    pub checkpoint: Checkpoint,
    /// How it resolved.
    pub state: LogEntryState,
}

impl LogEntry {
    /// Plan a transaction, before an extrinsic exists for it.
    pub fn planned(
        sequence: u32,
        inputs: LockSet,
        outputs: LockSet,
        checkpoint: Checkpoint,
    ) -> Self {
        Self {
            sequence,
            depends_on: Vec::new(),
            inputs,
            outputs,
            extrinsic_hash: None,
            checkpoint,
            state: LogEntryState::Pending,
        }
    }

    /// Declare that this transaction consumes another's outputs.
    pub fn after(mut self, sequences: impl IntoIterator<Item = u32>) -> Self {
        self.depends_on.extend(sequences);
        self.depends_on.sort_unstable();
        self.depends_on.dedup();
        self
    }

    /// Attach the hash of the extrinsic about to be broadcast.
    pub fn set_extrinsic_hash(&mut self, hash: ExtrinsicHash) {
        self.extrinsic_hash = Some(hash);
    }

    /// Whether an extrinsic was ever built and broadcast for this entry.
    pub const fn was_broadcast(&self) -> bool {
        self.extrinsic_hash.is_some()
    }

    /// Resolve the entry, refusing to overwrite an outcome already reached.
    ///
    /// A definite outcome is final. Re-resolving would mean two different
    /// answers about whether the same records were consumed, and whichever ran
    /// second would win — so this rejects instead.
    pub fn resolve(&mut self, state: LogEntryState) -> Result<(), CoinageError> {
        if !self.state.is_pending() {
            return Err(CoinageError::Internal(format!(
                "log entry {} is already {}; cannot resolve it as {}",
                self.sequence,
                self.state.label(),
                state.label()
            )));
        }
        self.state = state;
        Ok(())
    }
}

/// Every transaction one operation has planned, in sequence order.
#[derive(Debug, Clone, Default, PartialEq, Eq, Encode, Decode)]
pub struct OperationLog {
    entries: Vec<LogEntry>,
}

impl OperationLog {
    /// Append a planned transaction, rejecting a duplicate or dangling
    /// dependency.
    pub fn push(&mut self, entry: LogEntry) -> Result<(), CoinageError> {
        if self.entry(entry.sequence).is_some() {
            return Err(CoinageError::Internal(format!(
                "log already holds sequence {}",
                entry.sequence
            )));
        }
        for dependency in &entry.depends_on {
            if *dependency == entry.sequence {
                return Err(CoinageError::Internal(format!(
                    "log entry {} depends on itself",
                    entry.sequence
                )));
            }
            if self.entry(*dependency).is_none() {
                return Err(CoinageError::Internal(format!(
                    "log entry {} depends on unknown sequence {dependency}",
                    entry.sequence
                )));
            }
        }

        self.entries.push(entry);
        Ok(())
    }

    /// The next unused sequence number.
    pub fn next_sequence(&self) -> u32 {
        self.entries
            .iter()
            .map(|entry| entry.sequence + 1)
            .max()
            .unwrap_or(0)
    }

    /// Every entry, in the order they were planned.
    pub fn entries(&self) -> &[LogEntry] {
        &self.entries
    }

    /// One entry by sequence.
    pub fn entry(&self, sequence: u32) -> Option<&LogEntry> {
        self.entries.iter().find(|entry| entry.sequence == sequence)
    }

    /// One entry by sequence, mutably.
    pub fn entry_mut(&mut self, sequence: u32) -> Option<&mut LogEntry> {
        self.entries
            .iter_mut()
            .find(|entry| entry.sequence == sequence)
    }

    /// Whether the log is empty.
    pub fn is_empty(&self) -> bool {
        self.entries.is_empty()
    }

    /// Whether any entry ever reached the network.
    pub fn any_broadcast(&self) -> bool {
        self.entries.iter().any(LogEntry::was_broadcast)
    }

    /// Whether any entry still needs resolving.
    pub fn has_pending(&self) -> bool {
        self.entries.iter().any(|entry| entry.state.is_pending())
    }

    /// Whether at least one transaction definitely took effect.
    pub fn any_succeeded(&self) -> bool {
        self.entries.iter().any(|entry| entry.state.succeeded())
    }

    /// Extrinsic hashes in submission order, for the operation record.
    pub fn submitted_hashes(&self) -> Vec<ExtrinsicHash> {
        self.entries
            .iter()
            .filter_map(|entry| entry.extrinsic_hash)
            .collect()
    }

    /// Whether every transaction this entry depends on has definitely
    /// succeeded, so it may be broadcast.
    ///
    /// `coinage-layer.md` §7.5, submission order. Optimistic in-block inclusion
    /// of a dependency is deliberately not enough: a reorg that invalidated the
    /// predecessor would leave this transaction spending outputs that never
    /// existed, and it would then be the chain, not the layer, deciding which
    /// of the two survived.
    pub fn is_submittable(&self, sequence: u32) -> bool {
        self.entry(sequence).is_some_and(|entry| {
            entry.depends_on.iter().all(|dependency| {
                self.entry(*dependency)
                    .is_some_and(|dependency| dependency.state.succeeded())
            })
        })
    }

    /// Pending entries whose dependencies are all resolved, in dependency
    /// order.
    ///
    /// §7.5, resolution order. Resolving out of order gives wrong answers: if
    /// an unload mints a coin that a later transfer spends, finding that coin
    /// absent means either "the unload never landed" or "the unload landed and
    /// the transfer consumed it", and only the unload's own verdict
    /// distinguishes them.
    pub fn resolvable(&self) -> Vec<u32> {
        self.entries
            .iter()
            .filter(|entry| entry.state.is_pending())
            .filter(|entry| {
                entry.depends_on.iter().all(|dependency| {
                    self.entry(*dependency)
                        .is_some_and(|dependency| !dependency.state.is_pending())
                })
            })
            .map(|entry| entry.sequence)
            .collect()
    }

    /// Abandon every pending entry that can no longer take effect because a
    /// transaction it depends on did not succeed.
    ///
    /// Repeats until nothing changes, so a failure at the head of a chain
    /// propagates all the way down it. Abandoning reverts nothing: the entry's
    /// inputs were its predecessor's outputs, which never came into existence,
    /// and the operation's original inputs are returned exactly once by the
    /// predecessor's own reversion.
    pub fn cascade_abandoned(&mut self) -> Vec<u32> {
        let mut abandoned = Vec::new();
        loop {
            let doomed: Vec<(u32, String)> =
                self.entries
                    .iter()
                    .filter(|entry| entry.state.is_pending())
                    .filter_map(|entry| {
                        entry.depends_on.iter().find_map(|dependency| {
                            let blocker = self.entry(*dependency)?;
                            match &blocker.state {
                                LogEntryState::Rejected { .. }
                                | LogEntryState::Abandoned { .. } => Some((
                                    entry.sequence,
                                    format!(
                                        "transaction {dependency} it depends on {}",
                                        blocker.state.label()
                                    ),
                                )),
                                _ => None,
                            }
                        })
                    })
                    .collect();

            if doomed.is_empty() {
                return abandoned;
            }
            for (sequence, reason) in doomed {
                if let Some(entry) = self.entry_mut(sequence) {
                    // Infallible: only pending entries were collected.
                    let _ = entry.resolve(LogEntryState::Abandoned { reason });
                    abandoned.push(sequence);
                }
            }
        }
    }

    /// Project the log into the receipt the operation reports on termination.
    ///
    /// A receipt is a view of the log, never an independently maintained
    /// summary: two structures recording the same outcomes could disagree, and
    /// the one the caller sees would be the one that is wrong. Entries still
    /// `Pending` are omitted — an operation must not terminate while any
    /// transaction's fate is unresolved.
    pub fn receipt(&self) -> OperationReceipt {
        OperationReceipt {
            extrinsics: self
                .entries
                .iter()
                .filter_map(|entry| {
                    let outcome = match &entry.state {
                        LogEntryState::Pending => return None,
                        LogEntryState::Succeeded { block_hash } => ExtrinsicOutcome::Succeeded {
                            block_hash: *block_hash,
                            affected_coins: Vec::new(),
                        },
                        LogEntryState::Rejected { reason } => ExtrinsicOutcome::Rejected {
                            reason: reason.clone(),
                        },
                        LogEntryState::Abandoned { reason } => ExtrinsicOutcome::Abandoned {
                            reason: reason.clone(),
                        },
                    };
                    Some(ExtrinsicRecord {
                        extrinsic_hash: entry.extrinsic_hash,
                        outcome,
                    })
                })
                .collect(),
        }
    }
}

#[cfg(test)]
mod tests {
    use super::super::types::{CoinIndex, EntryIndex, PurseId};
    use super::*;

    fn checkpoint(number: u64) -> Checkpoint {
        Checkpoint {
            number,
            hash: BlockHash([number as u8; 32]),
            mortality: 256,
        }
    }

    fn coins(indices: &[u32]) -> LockSet {
        LockSet {
            coins: indices
                .iter()
                .map(|index| (PurseId::MAIN, CoinIndex(*index)))
                .collect(),
            entries: Vec::new(),
        }
    }

    fn entries(indices: &[u32]) -> LockSet {
        LockSet {
            coins: Vec::new(),
            entries: indices
                .iter()
                .map(|index| (PurseId::MAIN, EntryIndex(*index)))
                .collect(),
        }
    }

    #[test]
    fn expiry_is_exclusive_at_the_last_valid_block() {
        // Releasing inputs one block early would let them be respent under a
        // transaction the chain would still accept.
        let checkpoint = checkpoint(1_000);

        assert_eq!(checkpoint.last_valid_block(), 1_256);
        assert!(!checkpoint.has_expired(1_256), "still includable");
        assert!(checkpoint.has_expired(1_257));
    }

    #[test]
    fn a_planned_entry_starts_pending_and_unbroadcast() {
        let entry = LogEntry::planned(0, coins(&[1]), coins(&[2, 3]), checkpoint(10));

        assert!(entry.state.is_pending());
        assert!(!entry.was_broadcast());
        assert!(entry.depends_on.is_empty());
    }

    #[test]
    fn dependencies_are_deduplicated_and_ordered() {
        let entry = LogEntry::planned(2, coins(&[1]), coins(&[2]), checkpoint(10)).after([1, 0, 1]);

        assert_eq!(entry.depends_on, vec![0, 1]);
    }

    #[test]
    fn a_resolved_entry_cannot_be_resolved_again() {
        // Two answers about whether the same records were consumed would let
        // the later one silently overwrite the earlier.
        let mut entry = LogEntry::planned(0, coins(&[1]), coins(&[2]), checkpoint(10));
        entry
            .resolve(LogEntryState::Succeeded {
                block_hash: BlockHash([9; 32]),
            })
            .expect("first resolution");

        let refused = entry.resolve(LogEntryState::Rejected {
            reason: "expired".to_string(),
        });

        assert!(refused.is_err());
        assert!(entry.state.succeeded(), "the first answer stands");
    }

    #[test]
    fn a_log_rejects_a_duplicate_sequence() {
        let mut log = OperationLog::default();
        log.push(LogEntry::planned(
            0,
            coins(&[1]),
            coins(&[2]),
            checkpoint(10),
        ))
        .expect("first");

        assert!(
            log.push(LogEntry::planned(
                0,
                coins(&[3]),
                coins(&[4]),
                checkpoint(10)
            ))
            .is_err()
        );
    }

    #[test]
    fn a_log_rejects_a_dangling_or_self_dependency() {
        let mut log = OperationLog::default();

        assert!(
            log.push(LogEntry::planned(0, coins(&[1]), coins(&[2]), checkpoint(10)).after([7]))
                .is_err(),
            "a dependency that does not exist"
        );
        assert!(
            log.push(LogEntry::planned(0, coins(&[1]), coins(&[2]), checkpoint(10)).after([0]))
                .is_err(),
            "a dependency on itself"
        );
    }

    #[test]
    fn sequences_continue_past_the_highest_used() {
        let mut log = OperationLog::default();
        assert_eq!(log.next_sequence(), 0);

        log.push(LogEntry::planned(
            0,
            entries(&[1]),
            coins(&[0]),
            checkpoint(10),
        ))
        .expect("push");
        assert_eq!(log.next_sequence(), 1);

        log.push(LogEntry::planned(1, coins(&[0]), coins(&[1]), checkpoint(10)).after([0]))
            .expect("push");
        assert_eq!(log.next_sequence(), 2);
    }

    #[test]
    fn a_log_summarizes_what_the_operation_did() {
        let mut log = OperationLog::default();
        log.push(LogEntry::planned(
            0,
            entries(&[1]),
            coins(&[0]),
            checkpoint(10),
        ))
        .expect("push");
        log.push(LogEntry::planned(1, coins(&[0]), coins(&[1]), checkpoint(10)).after([0]))
            .expect("push");

        assert!(log.has_pending());
        assert!(!log.any_broadcast());
        assert!(!log.any_succeeded());
        assert!(log.submitted_hashes().is_empty());

        log.entry_mut(0)
            .expect("exists")
            .set_extrinsic_hash(ExtrinsicHash([1; 32]));
        log.entry_mut(0)
            .expect("exists")
            .resolve(LogEntryState::Succeeded {
                block_hash: BlockHash([2; 32]),
            })
            .expect("resolves");
        log.entry_mut(1)
            .expect("exists")
            .resolve(LogEntryState::Abandoned {
                reason: "predecessor rejected".to_string(),
            })
            .expect("resolves");

        assert!(!log.has_pending());
        assert!(log.any_broadcast());
        assert!(log.any_succeeded());
        assert_eq!(log.submitted_hashes(), vec![ExtrinsicHash([1; 32])]);
    }

    #[test]
    fn a_log_round_trips_through_scale() {
        let mut log = OperationLog::default();
        log.push(LogEntry::planned(
            0,
            entries(&[4]),
            coins(&[9]),
            checkpoint(1_234),
        ))
        .expect("push");
        log.entry_mut(0)
            .expect("exists")
            .set_extrinsic_hash(ExtrinsicHash([3; 32]));

        let encoded = log.encode();
        let decoded = OperationLog::decode(&mut &encoded[..]).expect("decodes");

        assert_eq!(decoded, log, "the log survives persistence");
    }

    #[test]
    fn an_entry_names_its_records_by_index_not_by_account() {
        // The durable log must not spell out the input-to-output linkage in
        // account identifiers; that is exactly what the recycler anonymity set
        // exists to break (§12.3). Indices are meaningless without the entropy.
        let entry = LogEntry::planned(0, entries(&[4]), coins(&[9]), checkpoint(10));

        let encoded = entry.encode();
        assert!(!encoded.is_empty());
        assert_eq!(entry.inputs.entries.len(), 1);
        assert_eq!(entry.outputs.coins.len(), 1);
    }

    #[test]
    fn a_receipt_projects_every_resolved_entry() {
        let mut log = OperationLog::default();
        log.push(LogEntry::planned(
            0,
            entries(&[1]),
            coins(&[0]),
            checkpoint(10),
        ))
        .expect("push");
        log.push(LogEntry::planned(1, coins(&[0]), coins(&[1]), checkpoint(10)).after([0]))
            .expect("push");
        log.push(LogEntry::planned(
            2,
            coins(&[2]),
            coins(&[3]),
            checkpoint(10),
        ))
        .expect("push");

        log.entry_mut(0)
            .expect("exists")
            .set_extrinsic_hash(ExtrinsicHash([1; 32]));
        log.entry_mut(0)
            .expect("exists")
            .resolve(LogEntryState::Succeeded {
                block_hash: BlockHash([2; 32]),
            })
            .expect("resolves");
        log.entry_mut(1)
            .expect("exists")
            .resolve(LogEntryState::Abandoned {
                reason: "predecessor rejected".to_string(),
            })
            .expect("resolves");

        let receipt = log.receipt();

        // Entry 2 is still pending, so it is not in the receipt at all.
        assert_eq!(receipt.extrinsics.len(), 2);
        assert!(receipt.any_succeeded());
        assert!(receipt.is_partial(), "one succeeded, one did not");
        assert_eq!(
            receipt.extrinsics[0].extrinsic_hash,
            Some(ExtrinsicHash([1; 32]))
        );
        assert_eq!(
            receipt.extrinsics[1].extrinsic_hash, None,
            "an abandoned transaction was never broadcast"
        );
        assert!(matches!(
            receipt.extrinsics[1].outcome,
            ExtrinsicOutcome::Abandoned { .. }
        ));
    }

    /// A two-step operation: entry 0 unloads a recycler entry into coin 0,
    /// entry 1 then transfers that coin. The shape §7.5 is written for.
    fn chained() -> OperationLog {
        let mut log = OperationLog::default();
        log.push(LogEntry::planned(
            0,
            entries(&[1]),
            coins(&[0]),
            checkpoint(10),
        ))
        .expect("push");
        log.push(LogEntry::planned(1, coins(&[0]), coins(&[9]), checkpoint(10)).after([0]))
            .expect("push");
        log
    }

    #[test]
    fn a_dependent_transaction_is_unsubmittable_until_its_predecessor_succeeds() {
        let mut log = chained();

        assert!(log.is_submittable(0), "nothing blocks the head");
        assert!(!log.is_submittable(1), "its inputs do not exist yet");

        // Optimistic inclusion is deliberately not enough; only a resolved
        // success unblocks the dependent transaction.
        log.entry_mut(0)
            .expect("exists")
            .set_extrinsic_hash(ExtrinsicHash([1; 32]));
        assert!(!log.is_submittable(1), "broadcast is not success");

        log.entry_mut(0)
            .expect("exists")
            .resolve(LogEntryState::Succeeded {
                block_hash: BlockHash([2; 32]),
            })
            .expect("resolves");
        assert!(log.is_submittable(1));
    }

    #[test]
    fn a_failed_predecessor_never_unblocks_its_dependent() {
        let mut log = chained();
        log.entry_mut(0)
            .expect("exists")
            .resolve(LogEntryState::Rejected {
                reason: "expired".to_string(),
            })
            .expect("resolves");

        assert!(!log.is_submittable(1));
    }

    #[test]
    fn only_entries_whose_dependencies_are_resolved_are_resolvable() {
        let mut log = chained();

        assert_eq!(
            log.resolvable(),
            vec![0],
            "entry 1 cannot be interpreted yet"
        );

        log.entry_mut(0)
            .expect("exists")
            .resolve(LogEntryState::Succeeded {
                block_hash: BlockHash([2; 32]),
            })
            .expect("resolves");

        assert_eq!(log.resolvable(), vec![1]);
    }

    #[test]
    fn a_rejected_head_cascades_down_the_whole_chain() {
        let mut log = chained();
        log.push(LogEntry::planned(2, coins(&[9]), coins(&[7]), checkpoint(10)).after([1]))
            .expect("push");
        log.entry_mut(0)
            .expect("exists")
            .resolve(LogEntryState::Rejected {
                reason: "expired".to_string(),
            })
            .expect("resolves");

        let abandoned = log.cascade_abandoned();

        assert_eq!(abandoned, vec![1, 2], "the failure propagates transitively");
        assert!(!log.has_pending());
        for sequence in [1, 2] {
            assert!(matches!(
                log.entry(sequence).expect("exists").state,
                LogEntryState::Abandoned { .. }
            ));
        }
    }

    #[test]
    fn a_cascade_leaves_independent_transactions_alone() {
        let mut log = chained();
        // An unrelated transaction in the same operation, e.g. a second unload
        // group that feeds nothing.
        log.push(LogEntry::planned(
            2,
            entries(&[5]),
            coins(&[6]),
            checkpoint(10),
        ))
        .expect("push");
        log.entry_mut(0)
            .expect("exists")
            .resolve(LogEntryState::Rejected {
                reason: "expired".to_string(),
            })
            .expect("resolves");

        assert_eq!(log.cascade_abandoned(), vec![1]);
        assert!(
            log.entry(2).expect("exists").state.is_pending(),
            "an independent transaction is unaffected"
        );
    }

    #[test]
    fn a_succeeding_chain_cascades_nothing() {
        let mut log = chained();
        log.entry_mut(0)
            .expect("exists")
            .resolve(LogEntryState::Succeeded {
                block_hash: BlockHash([2; 32]),
            })
            .expect("resolves");

        assert!(log.cascade_abandoned().is_empty());
        assert!(log.entry(1).expect("exists").state.is_pending());
    }
}
