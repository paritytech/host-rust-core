//! The layer's event stream.
//!
//! Events identify records by `(purse, denomination)` rather than by derivation
//! index: indices are internal to the layer and never cross its API. `Resynced`
//! is emitted exactly once after a restart, so a subscriber can tell
//! reconstruction of existing state from live changes that follow.

use super::entry::EntryOnChainState;
use super::operation::{OperationStatus, TerminalStatus};
use super::types::{
    Amount, CoinAge, DenominationExponent, OperationHandle, OperationKind, PurseId,
};

/// Something the layer observed or did.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum LayerEvent {
    /// Post-restart reconciliation is complete. Everything before this is
    /// reconstruction; everything after is a live change.
    Resynced,

    /// A purse was created.
    PurseCreated {
        /// The new purse.
        purse: PurseId,
        /// Its name.
        name: String,
    },
    /// A purse was renamed.
    PurseRenamed {
        /// The purse.
        purse: PurseId,
        /// Its new name.
        name: String,
    },
    /// A purse was drained and closed.
    PurseDeleted {
        /// The purse that was closed.
        purse: PurseId,
        /// Where its value went.
        drained_into: PurseId,
        /// How much moved.
        amount: Amount,
    },

    /// A coin became spendable.
    CoinAvailable {
        /// Owning purse.
        purse: PurseId,
        /// Denomination.
        exponent: DenominationExponent,
    },
    /// A coin was consumed.
    CoinSpent {
        /// Owning purse.
        purse: PurseId,
        /// Denomination.
        exponent: DenominationExponent,
    },
    /// A coin's observed age changed.
    CoinAged {
        /// Owning purse.
        purse: PurseId,
        /// Denomination.
        exponent: DenominationExponent,
        /// New age.
        age: CoinAge,
    },

    /// A recycler entry was created.
    EntryAllocated {
        /// Owning purse.
        purse: PurseId,
        /// Denomination the entry will realize.
        exponent: DenominationExponent,
    },
    /// A recycler entry's chain-side readiness changed.
    EntryReadinessChanged {
        /// Owning purse.
        purse: PurseId,
        /// Denomination.
        exponent: DenominationExponent,
        /// The new readiness.
        new_state: EntryOnChainState,
    },
    /// A recycler entry was unloaded.
    EntryConsumed {
        /// Owning purse.
        purse: PurseId,
        /// Denomination.
        exponent: DenominationExponent,
    },

    /// An operation started.
    OperationStarted {
        /// Its handle.
        handle: OperationHandle,
        /// What it does.
        kind: OperationKind,
        /// The purse it acts on.
        purse: PurseId,
    },
    /// An operation changed status without finishing.
    OperationProgress {
        /// Its handle.
        handle: OperationHandle,
        /// The new status.
        status: OperationStatus,
    },
    /// An operation finished.
    OperationCompleted {
        /// Its handle.
        handle: OperationHandle,
        /// How it ended.
        terminal: TerminalStatus,
    },

    /// A maintenance sweep began.
    MaintenanceSweepStarted {
        /// Purses the sweep will visit.
        purses: Vec<PurseId>,
    },
    /// A maintenance sweep finished.
    MaintenanceSweepCompleted {
        /// Coins recycled into entries.
        coins_recycled: u32,
        /// Entries rescued back into coins.
        entries_rescued: u32,
        /// Actions that failed.
        failed: u32,
    },
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn events_do_not_expose_derivation_indices() {
        // A compile-time-ish guard: the record-level events are keyed by purse
        // and denomination only, so a subscriber cannot correlate activity back
        // to a specific on-chain account through the event stream.
        let event = LayerEvent::CoinAvailable {
            purse: PurseId::MAIN,
            exponent: DenominationExponent::new(4).expect("exponent is in range"),
        };

        match event {
            LayerEvent::CoinAvailable { purse, exponent } => {
                assert_eq!(purse, PurseId::MAIN);
                assert_eq!(exponent.value(), Amount::from_cents(16));
            }
            other => panic!("unexpected event: {other:?}"),
        }
    }
}
