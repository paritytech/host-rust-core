//! Resolving in-flight transactions against finalized chain state.
//!
//! `coinage-layer.md` §7.7. This is the slow, guaranteed path: it decides what
//! became of a logged transaction from **finalized** state alone, needing
//! neither the transaction's hash nor its events, so it works after a crash in
//! which the layer never saw either.
//!
//! Distinct from wallet recovery (§8.10), which rebuilds a whole wallet from
//! root entropy. This one resolves work that was already in flight.
//!
//! The decision is pure and lives here; issuing the chain reads belongs to
//! `runtime::coinage::recover`. Keeping them apart means every branch of the
//! procedure — including the ones a live chain would take days to produce — is
//! exercisable in a unit test.

use super::log::{Checkpoint, LogEntry, LogEntryState};

/// What a finalized block says about one logged transaction's records.
///
/// Both questions are asked because either can answer affirmatively on its own:
/// a transfer's outputs belong to the *recipient*, so the layer will never see
/// them, and only the disappearance of its inputs shows that it landed.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct RecordObservation {
    /// Every record the transaction was expected to create exists on chain.
    pub outputs_present: bool,
    /// Every record the transaction consumes is gone from chain.
    pub inputs_consumed: bool,
}

/// The verdict for one entry at one finalized block.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum Resolution {
    /// The transaction definitely took effect.
    Succeeded {
        /// Which observation proved it, for the log's reason string.
        evidence: SuccessEvidence,
    },
    /// The transaction can never take effect.
    Rejected {
        /// Why.
        reason: String,
    },
    /// Nothing is decided yet; ask again at the next finalized block.
    StillPending,
}

/// How a success was established.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum SuccessEvidence {
    /// The transaction's own outputs are on chain.
    OutputsPresent,
    /// The outputs are not visible, but the inputs are gone, so something
    /// consumed them — for a transfer, the recipient has already claimed.
    InputsConsumed,
}

/// Decide one entry's fate from a finalized observation.
///
/// The caller must have resolved every entry this one depends on first, and
/// must have run the abandonment cascade; this function assumes both and
/// answers only the chain-state question. See §7.5 for why the order matters:
/// an absent output is consistent with "the predecessor never landed" and with
/// "the predecessor landed and this transaction consumed it", and only the
/// predecessor's own verdict separates them.
pub fn resolve(
    entry: &LogEntry,
    observation: RecordObservation,
    finalized_height: u64,
) -> Resolution {
    if observation.outputs_present {
        return Resolution::Succeeded {
            evidence: SuccessEvidence::OutputsPresent,
        };
    }
    if observation.inputs_consumed {
        return Resolution::Succeeded {
            evidence: SuccessEvidence::InputsConsumed,
        };
    }
    if entry.checkpoint.has_expired(finalized_height) {
        return Resolution::Rejected {
            reason: expiry_reason(&entry.checkpoint, finalized_height),
        };
    }
    Resolution::StillPending
}

/// Human-readable expiry, naming the heights so a support log can be checked
/// against the chain.
fn expiry_reason(checkpoint: &Checkpoint, finalized_height: u64) -> String {
    format!(
        "expired unincluded: era anchored at {} for {} blocks, finalized height {finalized_height}",
        checkpoint.number, checkpoint.mortality
    )
}

/// Turn a resolution into the log state to record.
pub fn log_state(
    resolution: &Resolution,
    block_hash: super::types::BlockHash,
) -> Option<LogEntryState> {
    match resolution {
        Resolution::Succeeded { .. } => Some(LogEntryState::Succeeded { block_hash }),
        Resolution::Rejected { reason } => Some(LogEntryState::Rejected {
            reason: reason.clone(),
        }),
        Resolution::StillPending => None,
    }
}

#[cfg(test)]
mod tests {
    use super::super::operation::LockSet;
    use super::super::types::{BlockHash, CoinIndex, PurseId};
    use super::*;

    fn checkpoint() -> Checkpoint {
        Checkpoint {
            number: 1_000,
            hash: BlockHash([1; 32]),
            mortality: 256,
        }
    }

    fn entry() -> LogEntry {
        LogEntry::planned(
            0,
            LockSet {
                coins: vec![(PurseId::MAIN, CoinIndex(1))],
                entries: Vec::new(),
            },
            LockSet {
                coins: vec![(PurseId::MAIN, CoinIndex(2))],
                entries: Vec::new(),
            },
            checkpoint(),
        )
    }

    fn observation(outputs_present: bool, inputs_consumed: bool) -> RecordObservation {
        RecordObservation {
            outputs_present,
            inputs_consumed,
        }
    }

    #[test]
    fn visible_outputs_prove_success() {
        assert_eq!(
            resolve(&entry(), observation(true, true), 1_100),
            Resolution::Succeeded {
                evidence: SuccessEvidence::OutputsPresent
            }
        );
    }

    #[test]
    fn consumed_inputs_prove_success_even_when_outputs_are_invisible() {
        // A transfer's outputs belong to the recipient. The layer can never see
        // them, so the only evidence it will ever get is that its own inputs
        // are gone.
        assert_eq!(
            resolve(&entry(), observation(false, true), 1_100),
            Resolution::Succeeded {
                evidence: SuccessEvidence::InputsConsumed
            }
        );
    }

    #[test]
    fn nothing_observed_and_still_in_the_era_stays_pending() {
        assert_eq!(
            resolve(&entry(), observation(false, false), 1_100),
            Resolution::StillPending
        );
    }

    #[test]
    fn nothing_observed_past_the_era_is_definitely_dead() {
        let resolution = resolve(&entry(), observation(false, false), 1_257);

        let Resolution::Rejected { reason } = resolution else {
            unreachable!("past the era, inclusion is impossible");
        };
        assert!(reason.contains("1000"), "names the anchor: {reason}");
        assert!(reason.contains("256"), "names the period: {reason}");
        assert!(reason.contains("1257"), "names the height: {reason}");
    }

    #[test]
    fn expiry_never_overrides_observed_success() {
        // The order matters: a transaction can land inside its era and only be
        // observed afterwards. Checking expiry first would declare a landed
        // transaction dead and release inputs the chain has already consumed.
        assert!(matches!(
            resolve(&entry(), observation(true, false), 99_999),
            Resolution::Succeeded { .. }
        ));
        assert!(matches!(
            resolve(&entry(), observation(false, true), 99_999),
            Resolution::Succeeded { .. }
        ));
    }

    #[test]
    fn the_era_boundary_is_not_yet_expired() {
        assert_eq!(
            resolve(&entry(), observation(false, false), 1_256),
            Resolution::StillPending,
            "still includable at exactly the last valid block"
        );
    }

    #[test]
    fn only_a_decided_resolution_yields_a_log_state() {
        let block = BlockHash([7; 32]);

        assert_eq!(
            log_state(
                &Resolution::Succeeded {
                    evidence: SuccessEvidence::OutputsPresent
                },
                block
            ),
            Some(LogEntryState::Succeeded { block_hash: block })
        );
        assert!(matches!(
            log_state(
                &Resolution::Rejected {
                    reason: "expired".to_string()
                },
                block
            ),
            Some(LogEntryState::Rejected { .. })
        ));
        assert_eq!(log_state(&Resolution::StillPending, block), None);
    }
}
