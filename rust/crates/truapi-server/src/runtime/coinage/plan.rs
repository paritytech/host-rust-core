//! Turning a selection plan into the transactions that carry it out.
//!
//! Selection says *which records* to spend (`coinage-layer.md` §6.3). This module
//! says *which extrinsics* that becomes: one per whole coin transferred, one for
//! a split, one per unload group. It allocates the coin records the layer expects
//! to receive, and records for each produced coin where it should land.
//!
//! Planning performs no I/O and touches no chain. It mutates only the store, and
//! only to take derivation indices for the outputs — which must happen before
//! anything is broadcast, because an index handed out twice would derive an
//! account that is already on chain (§4.3).
//!
//! # Why these transactions are independent
//!
//! Both `Coinage::split` and `Coinage::unload_recycler_into_coins` name a
//! destination account per produced coin. A payment therefore mints its outputs
//! *straight into the recipient's accounts*, and never needs the two-step "mint
//! to myself, then transfer" that would make the second transaction depend on the
//! first. So a plan of this shape carries no `depends_on` edges: every transaction
//! stands alone, each is one atomic chain-side effect, and a failure of one does
//! not orphan another.
//!
//! Dependencies are still modelled, because §7.5 is about the general case and
//! external offload (§8.6) does chain transactions: entries produced by its
//! recycle phase are inputs to its offboard phase.

use crate::host_logic::coinage::error::CoinageError;
use crate::host_logic::coinage::operation::LockSet;
use crate::host_logic::coinage::selection::SelectionPlan;
use crate::host_logic::coinage::store::CoinageStore;
use crate::host_logic::coinage::types::{
    CoinAccountId, CoinIndex, DenominationExponent, EntryIndex, PurseId, RingLocation,
};
use crate::runtime::coinage::call::CoinOutput;

/// Where a produced coin should land.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Destination {
    /// An account this layer does not control: a transfer recipient.
    ///
    /// The layer keeps no record for it and cannot observe it, which is why a
    /// transaction whose every output is external is resolved by asking whether
    /// its *inputs* were consumed (§7.7).
    External(CoinAccountId),
    /// A fresh coin record in one of the layer's purses.
    Local {
        /// Purse the record belongs to.
        purse: PurseId,
        /// Index allocated for it.
        index: CoinIndex,
    },
}

/// One coin a transaction will create.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct PlannedOutput {
    /// Denomination to mint.
    pub exponent: DenominationExponent,
    /// Where it goes.
    pub destination: Destination,
}

/// What one planned transaction asks the chain to do.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum TransactionKind {
    /// `Coinage::transfer`: move one coin, whole, to a single account.
    Transfer {
        /// Coin that authorizes the call and is consumed by it.
        source: (PurseId, CoinIndex),
        /// Where it lands. A whole-coin transfer preserves the denomination, so
        /// the output's exponent is the source coin's.
        to: PlannedOutput,
    },
    /// `Coinage::split`: divide one coin into the named destinations.
    Split {
        /// Coin that authorizes the call and is consumed by it.
        source: (PurseId, CoinIndex),
        /// Its denomination, which the outputs must sum to exactly.
        source_exponent: DenominationExponent,
        /// Coins to create.
        outputs: Vec<PlannedOutput>,
    },
    /// `Coinage::transfer` from a coin the caller supplied the secret for, into
    /// one of our purses (§8.5).
    ///
    /// The origin is not one of our records, so the layer signs with the supplied
    /// secret rather than a derived key, and the log entry has no inputs to
    /// revert: a failed import leaves the coin where it was, still under whatever
    /// secret the caller holds.
    ImportTransfer {
        /// Position of the secret in the operation's supplied list.
        ///
        /// A position rather than the secret itself: a plan is compared, printed
        /// and held in memory, and none of those should ever touch key material.
        secret: usize,
        /// Account the coin sits in now.
        from: CoinAccountId,
        /// Where it is going, in one of our purses.
        to: PlannedOutput,
    },
    /// `Coinage::load_recycler_with_coin`: turn one coin into a fresh recycler
    /// entry (§6.4).
    ///
    /// The coin is the origin and is consumed; the entry is the output. No unload
    /// token is involved — tokens are spent going the other way.
    Recycle {
        /// Coin that authorizes the call and is consumed by it.
        source: (PurseId, CoinIndex),
        /// Entry record allocated for what the coin becomes.
        entry: (PurseId, EntryIndex),
    },
    /// `Coinage::load_recycler_with_external_asset_unpaid_batch`: turn an
    /// externally held asset into recycler entries (§8.2).
    ///
    /// One extrinsic for the whole top-up, signed by the account holding the
    /// external asset rather than by anything of ours.
    TopUpLoad {
        /// Purse the entries land in.
        purse: PurseId,
        /// Entries to create, with the records allocated for them.
        entries: Vec<(DenominationExponent, EntryIndex)>,
    },
    /// `Coinage::unload_recycler_into_external_asset_and_vouchers`: send one
    /// group's value out of coinage (§8.6).
    ///
    /// Whatever the group carries beyond `payout` is reloaded into the `vouchers`
    /// by the same extrinsic. Letting surplus land as a coin would tie the
    /// entry-side anonymity set to a fresh account.
    Offboard {
        /// Purse holding the entries.
        purse: PurseId,
        /// Ring the entries sit in.
        ring: RingLocation,
        /// Denomination shared by the group.
        exponent: DenominationExponent,
        /// Entries to consume.
        entries: Vec<EntryIndex>,
        /// Account outside coinage receiving the value.
        destination: CoinAccountId,
        /// How much of the group goes to the destination.
        payout: crate::host_logic::coinage::types::Amount,
        /// Fresh entries for the remainder, with the records allocated for them.
        vouchers: Vec<(DenominationExponent, EntryIndex)>,
    },
    /// `Coinage::unload_recycler_into_coins`: turn one group of entries into
    /// coins, consuming an unload token.
    Unload {
        /// Purse holding the entries.
        purse: PurseId,
        /// Ring the entries sit in, at the revision proofs are built against.
        ring: RingLocation,
        /// Denomination shared by the group.
        exponent: DenominationExponent,
        /// Entries to consume.
        entries: Vec<EntryIndex>,
        /// Coins to create.
        outputs: Vec<PlannedOutput>,
    },
}

impl TransactionKind {
    /// A short label for diagnostics.
    pub const fn label(&self) -> &'static str {
        match self {
            Self::Transfer { .. } => "transfer",
            Self::ImportTransfer { .. } => "import",
            Self::Recycle { .. } => "recycle",
            Self::Offboard { .. } => "offboard",
            Self::TopUpLoad { .. } => "top-up",
            Self::Split { .. } => "split",
            Self::Unload { .. } => "unload",
        }
    }

    /// The coins this transaction will create, in call order.
    pub fn outputs(&self) -> Vec<PlannedOutput> {
        match self {
            Self::Transfer { to, .. } | Self::ImportTransfer { to, .. } => vec![*to],
            // These produce entries, not coins.
            Self::Recycle { .. } | Self::Offboard { .. } | Self::TopUpLoad { .. } => Vec::new(),
            Self::Split { outputs, .. } | Self::Unload { outputs, .. } => outputs.clone(),
        }
    }
}

/// One transaction, with everything the write-ahead log needs to describe it.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct PlannedTransaction {
    /// What the chain is being asked to do.
    pub kind: TransactionKind,
    /// Records the transaction consumes.
    pub inputs: LockSet,
    /// Records the layer expects it to create. Only the layer's own records
    /// appear: an external recipient's coin is not ours to observe.
    pub outputs: LockSet,
    /// Sequences whose outputs this transaction spends (§7.5).
    pub depends_on: Vec<u32>,
    /// Coins this transaction materializes that are to be exported once it has
    /// **definitely** succeeded (§8.4).
    ///
    /// Emitting a secret on optimistic inclusion would hand out control of a coin
    /// a reorg could remove, so the list is kept here rather than acted on when
    /// the transaction is built.
    pub exports: Vec<(PurseId, CoinIndex)>,
}

/// The transactions one operation will submit, in submission order.
#[derive(Debug, Clone, Default, PartialEq, Eq)]
pub struct OperationProgram {
    /// Transactions, in the order they are submitted.
    pub transactions: Vec<PlannedTransaction>,
    /// Coins already on chain in the right shape, to be exported as they are.
    ///
    /// No transaction materializes these, so nothing has to settle before their
    /// secrets can be handed out.
    pub exports_in_place: Vec<(PurseId, CoinIndex)>,
}

impl OperationProgram {
    /// How many transactions the operation will submit.
    pub fn len(&self) -> usize {
        self.transactions.len()
    }

    /// Whether the operation has nothing to submit.
    pub fn is_empty(&self) -> bool {
        self.transactions.is_empty()
    }

    /// How many unload tokens the program consumes.
    pub fn unload_tokens_required(&self) -> usize {
        self.transactions
            .iter()
            .filter(|transaction| matches!(transaction.kind, TransactionKind::Unload { .. }))
            .count()
    }
}

/// Where the value an operation produces is meant to end up.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum TargetDestinations {
    /// Named accounts outside the layer, one coin per entry.
    ///
    /// Used by transfer: each output is destined for a separately named recipient,
    /// so the produced denominations must match these exactly.
    Recipients(Vec<CoinOutput>),
    /// Fresh records in one of the layer's purses.
    ///
    /// Used by rebalance, where the coins stay with the layer, so their shape is
    /// free.
    IntoPurse(PurseId),
    /// Coins to be handed out under their own secrets, staying in `purse`.
    ///
    /// Export uses this. A coin already in the right shape needs *no transaction
    /// at all*: handing over its secret transfers control of it without touching
    /// the chain. Only value that has to be reshaped — a split, an unload — costs
    /// an extrinsic.
    Export(PurseId),
}

/// Plan the transactions that carry out `selection` from `purse`.
///
/// Change always returns to `purse`, whatever the targets do: it is value that
/// never left, and routing it elsewhere would move funds the caller did not ask
/// to move.
pub fn plan_operation(
    store: &mut CoinageStore,
    purse: PurseId,
    selection: &SelectionPlan,
    targets: &TargetDestinations,
) -> Result<OperationProgram, CoinageError> {
    let mut assignment = TargetAssignment::new(targets);
    let mut transactions = Vec::new();
    let mut exports_in_place = Vec::new();

    // Whole coins move as they are, one transfer each. A coin bound for one of
    // our own purses still moves on chain: its destination account is derived in
    // that purse's namespace, which is what keeps two purses uncorrelated.
    //
    // An export is the exception: the coin is already the right shape and already
    // ours, so control of it changes hands with the secret and nothing is
    // submitted.
    for coin in &selection.whole_coins {
        if matches!(targets, TargetDestinations::Export(_)) {
            exports_in_place.push((purse, coin.index));
            continue;
        }

        let to = PlannedOutput {
            exponent: coin.exponent,
            destination: assignment.take(store, coin.exponent)?,
        };

        transactions.push(PlannedTransaction {
            kind: TransactionKind::Transfer {
                source: (purse, coin.index),
                to,
            },
            inputs: LockSet {
                coins: vec![(purse, coin.index)],
                entries: Vec::new(),
            },
            outputs: local_locks(&[to]),
            depends_on: Vec::new(),
            exports: Vec::new(),
        });
    }

    // A split delivers its share of the targets and returns its change.
    if let Some(step) = &selection.split {
        let mut outputs = Vec::new();
        for exponent in &step.target_outputs {
            outputs.push(PlannedOutput {
                exponent: *exponent,
                destination: assignment.take(store, *exponent)?,
            });
        }
        for exponent in &step.change_outputs {
            outputs.push(change_output(store, purse, *exponent)?);
        }

        transactions.push(PlannedTransaction {
            kind: TransactionKind::Split {
                source: (purse, step.coin.index),
                source_exponent: step.coin.exponent,
                outputs: outputs.clone(),
            },
            inputs: LockSet {
                coins: vec![(purse, step.coin.index)],
                entries: Vec::new(),
            },
            outputs: local_locks(&outputs),
            depends_on: Vec::new(),
            exports: exported(targets, &outputs, &step.target_outputs),
        });
    }

    // Each unload group is one atomic extrinsic carrying one token.
    for group in &selection.unloads {
        let mut outputs = Vec::new();
        for exponent in &group.target_outputs {
            outputs.push(PlannedOutput {
                exponent: *exponent,
                destination: assignment.take(store, *exponent)?,
            });
        }
        for exponent in &group.change_outputs {
            outputs.push(change_output(store, purse, *exponent)?);
        }

        transactions.push(PlannedTransaction {
            kind: TransactionKind::Unload {
                purse,
                ring: group.ring,
                exponent: group.exponent,
                entries: group.entries.clone(),
                outputs: outputs.clone(),
            },
            inputs: LockSet {
                coins: Vec::new(),
                entries: group.entries.iter().map(|index| (purse, *index)).collect(),
            },
            outputs: local_locks(&outputs),
            depends_on: Vec::new(),
            exports: exported(targets, &outputs, &group.target_outputs),
        });
    }

    assignment.finish()?;
    Ok(OperationProgram {
        transactions,
        exports_in_place,
    })
}

/// Plan the transactions that bring externally held coins into `into` (§8.5).
///
/// One transaction per coin, each independent: a bad secret or a sniped coin costs
/// that coin and no other, which is what makes partial success the normal outcome
/// rather than a failure mode.
///
/// `coins` pairs each coin's account with the denomination the chain reports for
/// it. Nothing is selected and nothing is locked — the inputs belong to whoever
/// holds the secret, not to this layer.
pub fn plan_import(
    store: &mut CoinageStore,
    into: PurseId,
    coins: &[(CoinAccountId, DenominationExponent)],
) -> Result<OperationProgram, CoinageError> {
    let mut transactions = Vec::new();

    for (position, (from, exponent)) in coins.iter().enumerate() {
        let index = store.add_pending_coin(into, *exponent)?;
        let to = PlannedOutput {
            exponent: *exponent,
            destination: Destination::Local { purse: into, index },
        };

        transactions.push(PlannedTransaction {
            kind: TransactionKind::ImportTransfer {
                secret: position,
                from: *from,
                to,
            },
            inputs: LockSet::default(),
            outputs: local_locks(&[to]),
            depends_on: Vec::new(),
            exports: Vec::new(),
        });
    }

    Ok(OperationProgram {
        transactions,
        exports_in_place: Vec::new(),
    })
}

/// One purse's share of a maintenance sweep, already chosen by the caller.
///
/// The caller picks the records because picking needs the clock and the chain
/// constants; this module turns the choice into transactions.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct SweepWork {
    /// Purse the work belongs to.
    pub purse: PurseId,
    /// Coins old enough to recycle, oldest first.
    pub aging_coins: Vec<(CoinIndex, DenominationExponent)>,
    /// Entries whose ring is close to expiry, grouped as they will be unloaded.
    pub rescues: Vec<RescueGroup>,
}

/// Entries of one denomination in one ring, to be rescued together.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct RescueGroup {
    /// Where the entries sit on chain.
    pub ring: RingLocation,
    /// Denomination shared by the group.
    pub exponent: DenominationExponent,
    /// Entries to unload.
    pub entries: Vec<EntryIndex>,
}

/// Plan both sweeps for the given purses (§6.4, §8.7).
///
/// The two directions are planned together and in this order — coin to entry
/// first, entry to coin second — because that is the order in which they free
/// something up: a rescue mints coins, and a coin minted now is not old enough to
/// recycle, so nothing planned here can undo anything else planned here.
///
/// `jitter` supplies each new entry's readiness delay, one draw per aging coin, in
/// order. The store holds no randomness source and this module reads no clock, so
/// both arrive from the caller.
pub fn plan_maintenance(
    store: &mut CoinageStore,
    work: &[SweepWork],
    now: crate::host_logic::coinage::types::Timestamp,
    jitter: &[core::time::Duration],
) -> Result<OperationProgram, CoinageError> {
    let mut transactions = Vec::new();
    let mut draws = jitter.iter().copied();

    for purse_work in work {
        let purse = purse_work.purse;

        for (coin, exponent) in &purse_work.aging_coins {
            let delay = draws.next().ok_or_else(|| {
                CoinageError::Internal(
                    "a maintenance sweep needs one jitter draw per recycled coin".to_string(),
                )
            })?;
            let entry = store.allocate_entry(purse, *exponent, now, delay)?;

            transactions.push(PlannedTransaction {
                kind: TransactionKind::Recycle {
                    source: (purse, *coin),
                    entry: (purse, entry),
                },
                inputs: LockSet {
                    coins: vec![(purse, *coin)],
                    entries: Vec::new(),
                },
                outputs: LockSet {
                    coins: Vec::new(),
                    entries: vec![(purse, entry)],
                },
                depends_on: Vec::new(),
                exports: Vec::new(),
            });
        }

        for group in &purse_work.rescues {
            // A rescue returns the value to the same purse as coins, so every
            // output is one of ours and the group's value is conserved.
            let mut outputs = Vec::new();
            let total = group.entries.len();
            for _ in 0..total {
                outputs.push(change_output(store, purse, group.exponent)?);
            }

            transactions.push(PlannedTransaction {
                kind: TransactionKind::Unload {
                    purse,
                    ring: group.ring,
                    exponent: group.exponent,
                    entries: group.entries.clone(),
                    outputs: outputs.clone(),
                },
                inputs: LockSet {
                    coins: Vec::new(),
                    entries: group.entries.iter().map(|index| (purse, *index)).collect(),
                },
                outputs: local_locks(&outputs),
                depends_on: Vec::new(),
                exports: Vec::new(),
            });
        }
    }

    Ok(OperationProgram {
        transactions,
        exports_in_place: Vec::new(),
    })
}

/// The records among `outputs` that an export hands out, being the ones that went
/// toward the request rather than back as change.
///
/// Change is never exported: it is value the caller did not ask to move, so it
/// stays under the layer's control.
fn exported(
    targets: &TargetDestinations,
    outputs: &[PlannedOutput],
    target_outputs: &[DenominationExponent],
) -> Vec<(PurseId, CoinIndex)> {
    if !matches!(targets, TargetDestinations::Export(_)) {
        return Vec::new();
    }

    outputs
        .iter()
        .take(target_outputs.len())
        .filter_map(|output| match output.destination {
            Destination::Local { purse, index } => Some((purse, index)),
            Destination::External(_) => None,
        })
        .collect()
}

/// Allocate a record for change coming back to `purse`.
fn change_output(
    store: &mut CoinageStore,
    purse: PurseId,
    exponent: DenominationExponent,
) -> Result<PlannedOutput, CoinageError> {
    let index = store.add_pending_coin(purse, exponent)?;
    Ok(PlannedOutput {
        exponent,
        destination: Destination::Local { purse, index },
    })
}

/// The subset of outputs the layer keeps records for.
fn local_locks(outputs: &[PlannedOutput]) -> LockSet {
    LockSet {
        coins: outputs
            .iter()
            .filter_map(|output| match output.destination {
                Destination::Local { purse, index } => Some((purse, index)),
                Destination::External(_) => None,
            })
            .collect(),
        entries: Vec::new(),
    }
}

/// Hands out one destination per produced target denomination.
///
/// Under named recipients the assignment is by denomination and each recipient is
/// used exactly once, so a plan that produced the wrong shape is caught here
/// rather than by the runtime after a coin has been consumed.
struct TargetAssignment<'a> {
    targets: &'a TargetDestinations,
    unclaimed: Vec<CoinOutput>,
}

impl<'a> TargetAssignment<'a> {
    fn new(targets: &'a TargetDestinations) -> Self {
        let unclaimed = match targets {
            TargetDestinations::Recipients(outputs) => outputs.clone(),
            TargetDestinations::IntoPurse(_) | TargetDestinations::Export(_) => Vec::new(),
        };
        Self { targets, unclaimed }
    }

    /// The destination for one produced coin of `exponent`.
    fn take(
        &mut self,
        store: &mut CoinageStore,
        exponent: DenominationExponent,
    ) -> Result<Destination, CoinageError> {
        match self.targets {
            TargetDestinations::Recipients(_) => {
                let position = self
                    .unclaimed
                    .iter()
                    .position(|output| output.exponent == exponent)
                    .ok_or(CoinageError::OutputsDoNotSumToAmount)?;
                Ok(Destination::External(
                    self.unclaimed.remove(position).account,
                ))
            }
            TargetDestinations::IntoPurse(purse) | TargetDestinations::Export(purse) => {
                let index = store.add_pending_coin(*purse, exponent)?;
                Ok(Destination::Local {
                    purse: *purse,
                    index,
                })
            }
        }
    }

    /// Every named recipient must have been served.
    fn finish(self) -> Result<(), CoinageError> {
        if self.unclaimed.is_empty() {
            Ok(())
        } else {
            Err(CoinageError::OutputsDoNotSumToAmount)
        }
    }
}

#[cfg(test)]
mod tests {
    use core::time::Duration;

    use crate::host_logic::coinage::chain_constants::next_people_paseo;
    use crate::host_logic::coinage::params::CoinageParameters;
    use crate::host_logic::coinage::selection::{OutputRequirement, SelectionRequest, select};
    use crate::host_logic::coinage::types::{Amount, CoinAge, RevisionIndex, RingIndex, Timestamp};

    use super::*;

    const NOW: Timestamp = Timestamp(1_000_000);

    fn exponent(value: i8) -> DenominationExponent {
        DenominationExponent::new(value).expect("exponent is in range")
    }

    fn store() -> CoinageStore {
        CoinageStore::new("Main".to_string())
    }

    /// A coin the chain already reports populated.
    fn fund(store: &mut CoinageStore, purse: PurseId, exponent_value: i8) -> CoinIndex {
        let index = store
            .add_pending_coin(purse, exponent(exponent_value))
            .expect("purse exists");
        store
            .observe_coin(purse, index, CoinAge(0))
            .expect("coin exists");
        index
    }

    /// A selectable entry in a well-populated ring.
    fn load_entry(store: &mut CoinageStore, purse: PurseId, exponent_value: i8, ring: u32) {
        let index = store
            .allocate_entry(purse, exponent(exponent_value), NOW, Duration::ZERO)
            .expect("purse exists");
        store
            .observe_entry_ring(
                purse,
                index,
                RingLocation::new(RingIndex(ring), RevisionIndex(0)),
                64,
                &CoinageParameters::default(),
            )
            .expect("entry exists");
    }

    fn recipient(exponent_value: i8, byte: u8) -> CoinOutput {
        CoinOutput {
            exponent: exponent(exponent_value),
            account: CoinAccountId([byte; 32]),
        }
    }

    /// Select for a named-recipient request, the way a transfer does.
    fn select_exact(
        store: &CoinageStore,
        purse: PurseId,
        recipients: &[CoinOutput],
    ) -> SelectionPlan {
        let amount = recipients
            .iter()
            .map(|output| output.exponent.value())
            .fold(Amount::ZERO, |total, value| {
                total.checked_add(value).expect("no overflow")
            });
        select(
            &SelectionRequest {
                amount,
                outputs: OutputRequirement::Exact(
                    recipients.iter().map(|output| output.exponent).collect(),
                ),
                allow_degraded: true,
            },
            &store.coins_in(purse),
            &store.entries_in(purse),
            &next_people_paseo(),
            NOW,
        )
        .expect("selection succeeds")
    }

    #[test]
    fn an_exact_match_becomes_one_transfer_per_coin() {
        let mut store = store();
        let first = fund(&mut store, PurseId::MAIN, 4);
        let second = fund(&mut store, PurseId::MAIN, 4);
        let recipients = vec![recipient(4, 0xaa), recipient(4, 0xbb)];
        let selection = select_exact(&store, PurseId::MAIN, &recipients);

        let program = plan_operation(
            &mut store,
            PurseId::MAIN,
            &selection,
            &TargetDestinations::Recipients(recipients),
        )
        .expect("plans");

        assert_eq!(program.len(), 2);
        assert_eq!(program.unload_tokens_required(), 0);
        for transaction in &program.transactions {
            assert!(matches!(transaction.kind, TransactionKind::Transfer { .. }));
            // Nothing depends on anything: each coin moves on its own.
            assert!(transaction.depends_on.is_empty());
            // The recipient's coin is not ours, so the log expects no output.
            assert!(transaction.outputs.coins.is_empty());
            assert!(matches!(
                transaction.kind.outputs()[0].destination,
                Destination::External(_)
            ));
            assert_eq!(transaction.inputs.coins.len(), 1);
        }
        let sources: Vec<CoinIndex> = program
            .transactions
            .iter()
            .map(|transaction| match transaction.kind {
                TransactionKind::Transfer { source, .. } => source.1,
                ref other => panic!("unexpected {other:?}"),
            })
            .collect();
        assert_eq!(sources, vec![first, second]);
    }

    #[test]
    fn a_split_delivers_to_the_recipient_and_keeps_its_change() {
        // One 16-cent coin paying an 8-cent recipient: the split mints the
        // recipient's coin directly and returns 8 cents of change to us.
        let mut store = store();
        let source = fund(&mut store, PurseId::MAIN, 4);
        let recipients = vec![recipient(3, 0xcc)];
        let selection = select_exact(&store, PurseId::MAIN, &recipients);

        let program = plan_operation(
            &mut store,
            PurseId::MAIN,
            &selection,
            &TargetDestinations::Recipients(recipients),
        )
        .expect("plans");

        assert_eq!(program.len(), 1);
        let transaction = &program.transactions[0];
        let TransactionKind::Split {
            source: split_source,
            source_exponent,
            outputs,
        } = &transaction.kind
        else {
            panic!("expected a split, got {:?}", transaction.kind);
        };
        assert_eq!(*split_source, (PurseId::MAIN, source));
        assert_eq!(*source_exponent, exponent(4));

        // Value is conserved across the split, which the pallet requires.
        let produced: Amount = outputs
            .iter()
            .map(|output| output.exponent.value())
            .fold(Amount::ZERO, |total, value| {
                total.checked_add(value).expect("no overflow")
            });
        assert_eq!(produced, exponent(4).value());

        // One output leaves, one comes back as a record of ours.
        assert_eq!(
            outputs
                .iter()
                .filter(|output| matches!(output.destination, Destination::External(_)))
                .count(),
            1
        );
        assert_eq!(transaction.outputs.coins.len(), 1);
        let (purse, index) = transaction.outputs.coins[0];
        assert_eq!(purse, PurseId::MAIN);
        assert_eq!(
            store.coin(purse, index).expect("record exists").exponent,
            exponent(3),
            "the change record is minted as pending before anything is broadcast"
        );
    }

    #[test]
    fn an_unload_group_becomes_one_transaction_carrying_one_token() {
        let mut store = store();
        load_entry(&mut store, PurseId::MAIN, 4, 3);
        load_entry(&mut store, PurseId::MAIN, 4, 3);
        let recipients = vec![recipient(4, 0xdd)];
        let selection = select_exact(&store, PurseId::MAIN, &recipients);

        let program = plan_operation(
            &mut store,
            PurseId::MAIN,
            &selection,
            &TargetDestinations::Recipients(recipients),
        )
        .expect("plans");

        assert_eq!(program.len(), 1);
        assert_eq!(
            program.unload_tokens_required(),
            1,
            "one group, one token, whatever the group's size"
        );
        let transaction = &program.transactions[0];
        let TransactionKind::Unload {
            entries, outputs, ..
        } = &transaction.kind
        else {
            panic!("expected an unload, got {:?}", transaction.kind);
        };
        assert_eq!(
            entries.len(),
            1,
            "one 16-cent entry covers a 16-cent target"
        );
        assert_eq!(transaction.inputs.entries.len(), entries.len());
        assert_eq!(outputs.len(), 1, "no change: the group is exactly spent");
        assert!(matches!(outputs[0].destination, Destination::External(_)));
    }

    #[test]
    fn a_rebalance_routes_every_target_into_the_destination_purse() {
        let mut store = store();
        let savings = store.create_purse("Savings".to_string());
        fund(&mut store, PurseId::MAIN, 4);
        let selection = select(
            &SelectionRequest {
                amount: Amount::from_cents(16),
                outputs: OutputRequirement::AnyDenominations,
                allow_degraded: true,
            },
            &store.coins_in(PurseId::MAIN),
            &store.entries_in(PurseId::MAIN),
            &next_people_paseo(),
            NOW,
        )
        .expect("selection succeeds");

        let program = plan_operation(
            &mut store,
            PurseId::MAIN,
            &selection,
            &TargetDestinations::IntoPurse(savings),
        )
        .expect("plans");

        assert_eq!(program.len(), 1);
        let transaction = &program.transactions[0];
        match transaction.kind {
            TransactionKind::Transfer { source, to } => {
                assert_eq!(source, (PurseId::MAIN, CoinIndex(0)));
                // The destination record is allocated in the *target* purse's
                // namespace, which is what keeps the two purses uncorrelated.
                assert_eq!(
                    to.destination,
                    Destination::Local {
                        purse: savings,
                        index: CoinIndex(0)
                    }
                );
                assert_eq!(to.exponent, exponent(4));
            }
            ref other => panic!("unexpected {other:?}"),
        }
        // And it *is* one of our records, so the log expects it.
        assert_eq!(transaction.outputs.coins, vec![(savings, CoinIndex(0))]);
        assert_eq!(
            store
                .coin(savings, CoinIndex(0))
                .expect("record exists")
                .exponent,
            exponent(4)
        );
    }

    #[test]
    fn a_recipient_the_plan_cannot_serve_is_refused_before_anything_moves() {
        // Planning is the last point at which a shape mismatch is free. After
        // this the coin is consumed by the extension whatever the pallet decides.
        let mut store = store();
        fund(&mut store, PurseId::MAIN, 4);
        let recipients = vec![recipient(4, 0xaa)];
        let selection = select_exact(&store, PurseId::MAIN, &recipients);

        let refused = plan_operation(
            &mut store,
            PurseId::MAIN,
            &selection,
            // A recipient wanting a denomination the plan never produces.
            &TargetDestinations::Recipients(vec![recipient(2, 0xaa)]),
        )
        .expect_err("the assignment does not balance");

        assert_eq!(refused, CoinageError::OutputsDoNotSumToAmount);
    }

    #[test]
    fn an_unserved_recipient_is_refused() {
        let mut store = store();
        fund(&mut store, PurseId::MAIN, 4);
        let recipients = vec![recipient(4, 0xaa)];
        let selection = select_exact(&store, PurseId::MAIN, &recipients);

        let refused = plan_operation(
            &mut store,
            PurseId::MAIN,
            &selection,
            &TargetDestinations::Recipients(vec![recipient(4, 0xaa), recipient(4, 0xbb)]),
        )
        .expect_err("one recipient would go unpaid");

        assert_eq!(refused, CoinageError::OutputsDoNotSumToAmount);
    }

    #[test]
    fn planning_allocates_output_indices_before_anything_is_broadcast() {
        // §7.4 step 1: local state moves first. An index handed out after a
        // broadcast could be handed out twice.
        let mut store = store();
        fund(&mut store, PurseId::MAIN, 4);
        let recipients = vec![recipient(3, 0xcc)];
        let selection = select_exact(&store, PurseId::MAIN, &recipients);
        let before = store.purse(PurseId::MAIN).expect("exists").next_coin_index;

        plan_operation(
            &mut store,
            PurseId::MAIN,
            &selection,
            &TargetDestinations::Recipients(recipients),
        )
        .expect("plans");

        let after = store.purse(PurseId::MAIN).expect("exists").next_coin_index;
        assert!(after.0 > before.0, "the change index is spent");
    }

    #[test]
    fn an_empty_selection_plans_nothing() {
        let mut store = store();
        let selection = select(
            &SelectionRequest {
                amount: Amount::ZERO,
                outputs: OutputRequirement::AnyDenominations,
                allow_degraded: true,
            },
            &[],
            &[],
            &next_people_paseo(),
            NOW,
        )
        .expect("zero is selectable");

        let program = plan_operation(
            &mut store,
            PurseId::MAIN,
            &selection,
            &TargetDestinations::IntoPurse(PurseId::MAIN),
        )
        .expect("plans");

        assert!(program.is_empty());
    }
}
