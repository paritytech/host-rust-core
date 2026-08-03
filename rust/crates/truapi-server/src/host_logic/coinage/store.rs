//! The layer's record store.
//!
//! Individual records enforce their own lifecycles; this aggregate enforces the
//! invariants that span them — that a locked coin belongs to a live operation,
//! that two operations never hold the same record, that a derivation index is
//! never handed out twice, and that every purse referenced by a record exists.
//!
//! The store is pure and serializable. It performs no I/O: the caller persists
//! it, hands it chain observations, and drains the events it produces. Keeping
//! persistence outside means the whole state machine is exercisable in a unit
//! test with no host and no chain.
//!
//! # Ordering of event delivery against persistence
//!
//! Events must be drained and published **before** the store is persisted.
//!
//! A terminal operation drops its record as soon as its status is emitted, so
//! persisting first and publishing second loses the receipt and the record
//! together if the process dies in between — the operation would simply have
//! never happened, as far as any later reader is concerned. Publishing first is
//! safe in the other direction: a crash leaves the operation still open in the
//! persisted store, and [`CoinageStore::reconcile_after_restart`] resolves it on
//! the next start. The worst case becomes a duplicate event rather than a lost
//! one, which subscribers can absorb and a lost receipt cannot.

use std::collections::BTreeMap;

use parity_scale_codec::{Decode, Encode};

use super::chain_constants::CoinageChainConstants;
use super::coin::Coin;
use super::entry::{EntryLocalState, RecyclerEntry};
use super::error::CoinageError;
use super::event::LayerEvent;
use super::operation::{
    LockSet, Operation, OperationReceipt, OperationStatus, RestartDisposition, TerminalStatus,
};
use super::params::CoinageParameters;
use super::purse::{Purse, PurseBalance, PurseInfo, compute_balance};
use super::selection::{SelectionPlan, SelectionRequest, select};
use super::types::{
    CoinAge, CoinIndex, DenominationExponent, EntryIndex, ExtrinsicHash, OperationHandle,
    OperationHandleAllocator, OperationKind, PurseId, RingLocation, Timestamp,
};

use core::time::Duration;

/// Every record the layer owns, plus the counters that keep derivation indices
/// unique.
#[derive(Debug, Clone, Encode, Decode)]
pub struct CoinageStore {
    purses: BTreeMap<PurseId, Purse>,
    coins: BTreeMap<(PurseId, CoinIndex), Coin>,
    entries: BTreeMap<(PurseId, EntryIndex), RecyclerEntry>,
    operations: BTreeMap<OperationHandle, Operation>,
    handles: OperationHandleAllocator,
    /// Monotonic purse-id counter. Never reclaims an identifier, even after a
    /// purse is closed: a purse id names a derivation namespace, so reusing one
    /// would let a new purse's accounts be correlated with the closed purse's
    /// on-chain history.
    next_purse_id: u32,
    /// Events awaiting delivery. Transient, so they are not persisted with the
    /// rest of the store.
    #[codec(skip)]
    events: Vec<LayerEvent>,
}

impl CoinageStore {
    /// Create a store holding only the main purse, which exists by
    /// construction.
    pub fn new(main_purse_name: String) -> Self {
        let mut purses = BTreeMap::new();
        purses.insert(PurseId::MAIN, Purse::new(PurseId::MAIN, main_purse_name));

        Self {
            purses,
            coins: BTreeMap::new(),
            entries: BTreeMap::new(),
            operations: BTreeMap::new(),
            handles: OperationHandleAllocator::default(),
            next_purse_id: PurseId::MAIN.0 + 1,
            events: Vec::new(),
        }
    }

    /// Take everything observed since the last drain.
    ///
    /// Publish these before persisting the store; see the module documentation
    /// for why that order is the safe one.
    pub fn take_events(&mut self) -> Vec<LayerEvent> {
        core::mem::take(&mut self.events)
    }

    // -- purses ------------------------------------------------------------

    /// A purse, if it exists.
    pub fn purse(&self, purse: PurseId) -> Option<&Purse> {
        self.purses.get(&purse)
    }

    /// Every purse, in identifier order.
    pub fn purses(&self) -> impl Iterator<Item = &Purse> {
        self.purses.values()
    }

    /// Open a new purse with a fresh identifier.
    pub fn create_purse(&mut self, name: String) -> PurseId {
        let id = PurseId(self.next_purse_id);
        self.next_purse_id += 1;
        self.purses.insert(id, Purse::new(id, name.clone()));
        self.events
            .push(LayerEvent::PurseCreated { purse: id, name });
        id
    }

    /// Change a purse's name.
    pub fn rename_purse(&mut self, purse: PurseId, name: String) -> Result<(), CoinageError> {
        let record = self
            .purses
            .get_mut(&purse)
            .ok_or(CoinageError::PurseNotFound(purse))?;
        record.name = name.clone();
        self.events.push(LayerEvent::PurseRenamed { purse, name });
        Ok(())
    }

    /// Close a purse once its value has been drained elsewhere.
    ///
    /// Dropping the purse record also drops its index counters, which is only
    /// safe because purse identifiers are never reused: no future purse can
    /// derive into the closed namespace.
    pub fn close_purse(
        &mut self,
        purse: PurseId,
        drained_into: PurseId,
        amount: super::types::Amount,
    ) -> Result<(), CoinageError> {
        if purse.is_main() {
            return Err(CoinageError::CannotDeleteMainPurse);
        }
        if !self.purses.contains_key(&purse) {
            return Err(CoinageError::PurseNotFound(purse));
        }
        if !self.purses.contains_key(&drained_into) {
            return Err(CoinageError::PurseNotFound(drained_into));
        }
        if self.has_in_flight_operations(purse) {
            return Err(CoinageError::PurseHasInFlightOperations);
        }

        self.purses.remove(&purse);
        self.coins.retain(|(owner, _), _| *owner != purse);
        self.entries.retain(|(owner, _), _| *owner != purse);
        self.events.push(LayerEvent::PurseDeleted {
            purse,
            drained_into,
            amount,
        });
        Ok(())
    }

    /// Whether any operation still holds records in this purse or acts on it.
    pub fn has_in_flight_operations(&self, purse: PurseId) -> bool {
        self.operations.values().any(|operation| {
            operation.purse == purse
                || operation
                    .locks
                    .coins
                    .iter()
                    .any(|(owner, _)| *owner == purse)
                || operation
                    .locks
                    .entries
                    .iter()
                    .any(|(owner, _)| *owner == purse)
        })
    }

    /// The purse's three-value balance.
    pub fn balance(&self, purse: PurseId, now: Timestamp) -> Result<PurseBalance, CoinageError> {
        if !self.purses.contains_key(&purse) {
            return Err(CoinageError::PurseNotFound(purse));
        }

        Ok(compute_balance(
            self.coin_records(purse),
            self.entry_records(purse),
            now,
        ))
    }

    /// The purse's identity together with its balance.
    pub fn purse_info(&self, purse: PurseId, now: Timestamp) -> Result<PurseInfo, CoinageError> {
        let record = self
            .purses
            .get(&purse)
            .ok_or(CoinageError::PurseNotFound(purse))?;
        Ok(PurseInfo::new(record, self.balance(purse, now)?))
    }

    // -- records -----------------------------------------------------------

    /// Register a coin an in-flight operation is expected to produce, taking
    /// the next free index in the purse.
    pub fn add_pending_coin(
        &mut self,
        purse: PurseId,
        exponent: DenominationExponent,
    ) -> Result<CoinIndex, CoinageError> {
        let record = self
            .purses
            .get_mut(&purse)
            .ok_or(CoinageError::PurseNotFound(purse))?;
        let index = record.allocate_coin_index();
        self.coins
            .insert((purse, index), Coin::pending(purse, index, exponent));
        Ok(index)
    }

    /// Register a freshly created recycler entry, taking the next free index.
    ///
    /// `jitter` is the caller's draw from `[0, jitter_upper_bound]`; the store
    /// holds no randomness source.
    pub fn allocate_entry(
        &mut self,
        purse: PurseId,
        exponent: DenominationExponent,
        now: Timestamp,
        jitter: Duration,
    ) -> Result<EntryIndex, CoinageError> {
        let record = self
            .purses
            .get_mut(&purse)
            .ok_or(CoinageError::PurseNotFound(purse))?;
        let index = record.allocate_entry_index();
        self.entries.insert(
            (purse, index),
            RecyclerEntry::allocated(purse, index, exponent, now, jitter),
        );
        self.events
            .push(LayerEvent::EntryAllocated { purse, exponent });
        Ok(index)
    }

    /// A coin record.
    pub fn coin(&self, purse: PurseId, index: CoinIndex) -> Option<&Coin> {
        self.coins.get(&(purse, index))
    }

    /// A recycler-entry record.
    pub fn entry(&self, purse: PurseId, index: EntryIndex) -> Option<&RecyclerEntry> {
        self.entries.get(&(purse, index))
    }

    /// Every coin in a purse, in index order.
    pub fn coins_in(&self, purse: PurseId) -> Vec<Coin> {
        self.coin_records(purse).copied().collect()
    }

    /// Every recycler entry in a purse, in index order.
    pub fn entries_in(&self, purse: PurseId) -> Vec<RecyclerEntry> {
        self.entry_records(purse).copied().collect()
    }

    /// Coins the age sweep should recycle before the chain's cap makes them
    /// unusable.
    pub fn coins_needing_recycling(
        &self,
        purse: PurseId,
        recycle_at_age: CoinAge,
    ) -> Vec<CoinIndex> {
        self.coin_records(purse)
            .filter(|coin| coin.needs_recycling(recycle_at_age))
            .map(|coin| coin.index)
            .collect()
    }

    /// Record that the chain reports a coin account populated at a given age.
    pub fn observe_coin(
        &mut self,
        purse: PurseId,
        index: CoinIndex,
        age: CoinAge,
    ) -> Result<(), CoinageError> {
        let coin = self
            .coins
            .get_mut(&(purse, index))
            .ok_or_else(|| unknown_record("coin", purse))?;

        let was_pending = !coin.is_selectable();
        let previous_age = coin.age;
        let exponent = coin.exponent;
        coin.observe_populated(age)?;

        if was_pending {
            self.events
                .push(LayerEvent::CoinAvailable { purse, exponent });
        } else if previous_age != age {
            self.events.push(LayerEvent::CoinAged {
                purse,
                exponent,
                age,
            });
        }

        Ok(())
    }

    /// Record what the chain says about a recycler entry's ring.
    pub fn observe_entry_ring(
        &mut self,
        purse: PurseId,
        index: EntryIndex,
        ring: RingLocation,
        member_count: u32,
        params: &CoinageParameters,
    ) -> Result<(), CoinageError> {
        let entry = self
            .entries
            .get_mut(&(purse, index))
            .ok_or_else(|| unknown_record("recycler entry", purse))?;

        let previous = entry.on_chain;
        entry.observe_ring(ring, member_count, params);

        if entry.on_chain != previous {
            self.events.push(LayerEvent::EntryReadinessChanged {
                purse,
                exponent: entry.exponent,
                new_state: entry.on_chain,
            });
        }

        Ok(())
    }

    // -- operations --------------------------------------------------------

    /// Select records for a request and lock them under one new operation.
    ///
    /// Selecting and locking together is what makes the "two concurrent
    /// selections never disagree about availability" guarantee structural: no
    /// other caller can observe the window between choosing a record and
    /// holding it.
    pub fn begin_operation(
        &mut self,
        purse: PurseId,
        kind: OperationKind,
        request: &SelectionRequest,
        constants: &CoinageChainConstants,
        now: Timestamp,
    ) -> Result<(OperationHandle, SelectionPlan), CoinageError> {
        if !self.purses.contains_key(&purse) {
            return Err(CoinageError::PurseNotFound(purse));
        }

        let coins = self.coins_in(purse);
        let entries = self.entries_in(purse);
        let plan = select(request, &coins, &entries, constants, now)?;
        let locks = plan.lock_set(purse);

        let handle = self.handles.allocate();
        let mut operation = Operation::start(handle, kind, purse);
        operation.locks = locks.clone();

        self.apply_locks(handle, &locks)?;
        self.operations.insert(handle, operation);
        self.events.push(LayerEvent::OperationStarted {
            handle,
            kind,
            purse,
        });

        Ok((handle, plan))
    }

    /// Start an operation that holds no records, such as a sweep or a recovery
    /// scan.
    pub fn start_operation(
        &mut self,
        purse: PurseId,
        kind: OperationKind,
    ) -> Result<OperationHandle, CoinageError> {
        if !self.purses.contains_key(&purse) {
            return Err(CoinageError::PurseNotFound(purse));
        }

        let handle = self.handles.allocate();
        self.operations
            .insert(handle, Operation::start(handle, kind, purse));
        self.events.push(LayerEvent::OperationStarted {
            handle,
            kind,
            purse,
        });
        Ok(handle)
    }

    /// An open operation.
    pub fn operation(&self, handle: OperationHandle) -> Option<&Operation> {
        self.operations.get(&handle)
    }

    /// Every operation that has not reached a terminal state.
    pub fn open_operations(&self) -> impl Iterator<Item = &Operation> {
        self.operations.values()
    }

    /// Move an operation to a non-terminal status.
    pub fn advance_operation(
        &mut self,
        handle: OperationHandle,
        status: OperationStatus,
    ) -> Result<(), CoinageError> {
        let operation = self
            .operations
            .get_mut(&handle)
            .ok_or(CoinageError::OperationNotFound(handle))?;
        operation.advance(status.clone())?;
        self.events
            .push(LayerEvent::OperationProgress { handle, status });
        Ok(())
    }

    /// Note an extrinsic hash immediately before it is broadcast.
    pub fn record_submission(
        &mut self,
        handle: OperationHandle,
        extrinsic_hash: ExtrinsicHash,
    ) -> Result<(), CoinageError> {
        let operation = self
            .operations
            .get_mut(&handle)
            .ok_or(CoinageError::OperationNotFound(handle))?;
        operation.record_submission(extrinsic_hash)?;
        self.events.push(LayerEvent::OperationProgress {
            handle,
            status: OperationStatus::Submitted,
        });
        Ok(())
    }

    /// Finish an operation successfully.
    ///
    /// `consumed` names the subset of the operation's locks the chain actually
    /// spent; those records retire, and everything else the operation held goes
    /// back to the selectable pool.
    pub fn finish_operation(
        &mut self,
        handle: OperationHandle,
        receipt: OperationReceipt,
        consumed: &LockSet,
    ) -> Result<(), CoinageError> {
        let operation = self
            .operations
            .get(&handle)
            .ok_or(CoinageError::OperationNotFound(handle))?;
        let locks = operation.locks.clone();

        for key in &consumed.coins {
            if !locks.coins.contains(key) {
                return Err(CoinageError::Internal(format!(
                    "{handle} cannot consume a coin it does not hold"
                )));
            }
        }
        for key in &consumed.entries {
            if !locks.entries.contains(key) {
                return Err(CoinageError::Internal(format!(
                    "{handle} cannot consume an entry it does not hold"
                )));
            }
        }

        for key in &locks.coins {
            let Some(coin) = self.coins.get_mut(key) else {
                continue;
            };
            if consumed.coins.contains(key) {
                coin.mark_spent(handle)?;
                self.events.push(LayerEvent::CoinSpent {
                    purse: key.0,
                    exponent: coin.exponent,
                });
            } else {
                coin.release(handle)?;
            }
        }

        for key in &locks.entries {
            let Some(entry) = self.entries.get_mut(key) else {
                continue;
            };
            if consumed.entries.contains(key) {
                entry.mark_consumed(handle)?;
                self.events.push(LayerEvent::EntryConsumed {
                    purse: key.0,
                    exponent: entry.exponent,
                });
            } else {
                entry.release(handle)?;
            }
        }

        self.retire(handle, TerminalStatus::Done(receipt))
    }

    /// Finish an operation unsuccessfully, returning everything it held.
    pub fn fail_operation(
        &mut self,
        handle: OperationHandle,
        error: CoinageError,
    ) -> Result<(), CoinageError> {
        if !self.operations.contains_key(&handle) {
            return Err(CoinageError::OperationNotFound(handle));
        }

        self.release_locks(handle);
        self.retire(handle, TerminalStatus::Failed(error))
    }

    /// Cancel an operation, which is permitted only while nothing is in flight.
    pub fn cancel_operation(&mut self, handle: OperationHandle) -> Result<(), CoinageError> {
        let operation = self
            .operations
            .get(&handle)
            .ok_or(CoinageError::OperationNotFound(handle))?;

        if !operation.status.is_cancellable() {
            return Err(super::error::InvalidTransition::new(
                "operation",
                operation.status.label(),
                "cancel",
            )
            .into());
        }

        self.fail_operation(handle, CoinageError::Cancelled)
    }

    /// Resolve operations left open by a restart.
    ///
    /// Operations that never broadcast are failed and their locks released:
    /// pre-submission scratch state is not durable, so a restart while
    /// preparing is indistinguishable from a cancel. Operations that did
    /// broadcast are returned for the caller to check against chain state.
    /// `Resynced` is emitted last, so a subscriber can tell reconstruction from
    /// the live changes that follow.
    pub fn reconcile_after_restart(&mut self) -> Vec<OperationHandle> {
        let mut needs_reconciliation = Vec::new();
        let mut interrupted = Vec::new();

        for operation in self.operations.values() {
            match operation.restart_disposition() {
                RestartDisposition::Reconcile => needs_reconciliation.push(operation.handle),
                RestartDisposition::FailInterrupted | RestartDisposition::AlreadyTerminal => {
                    interrupted.push(operation.handle);
                }
            }
        }

        for handle in interrupted {
            let _ = self.fail_operation(handle, CoinageError::InterruptedPreSubmission);
        }

        self.events.push(LayerEvent::Resynced);
        needs_reconciliation
    }

    // -- internals ---------------------------------------------------------

    fn coin_records(&self, purse: PurseId) -> impl Iterator<Item = &Coin> {
        self.coins
            .range((purse, CoinIndex(0))..=(purse, CoinIndex(u32::MAX)))
            .map(|(_, coin)| coin)
    }

    fn entry_records(&self, purse: PurseId) -> impl Iterator<Item = &RecyclerEntry> {
        self.entries
            .range((purse, EntryIndex(0))..=(purse, EntryIndex(u32::MAX)))
            .map(|(_, entry)| entry)
    }

    /// Lock every record in the set, or none of them.
    ///
    /// Checked in full before anything mutates, so a conflict cannot leave the
    /// store half-locked with no operation owning the difference.
    fn apply_locks(
        &mut self,
        handle: OperationHandle,
        locks: &LockSet,
    ) -> Result<(), CoinageError> {
        for key in &locks.coins {
            let coin = self
                .coins
                .get(key)
                .ok_or_else(|| unknown_record("coin", key.0))?;
            if !coin.is_selectable() {
                return Err(CoinageError::Internal(format!(
                    "coin {:?} in {} is not lockable",
                    key.1, key.0
                )));
            }
        }
        for key in &locks.entries {
            let entry = self
                .entries
                .get(key)
                .ok_or_else(|| unknown_record("recycler entry", key.0))?;
            if entry.local != EntryLocalState::Available {
                return Err(CoinageError::Internal(format!(
                    "recycler entry {:?} in {} is not lockable",
                    key.1, key.0
                )));
            }
        }

        for key in &locks.coins {
            if let Some(coin) = self.coins.get_mut(key) {
                coin.lock_for(handle)?;
            }
        }
        for key in &locks.entries {
            if let Some(entry) = self.entries.get_mut(key) {
                entry.lock_for(handle)?;
            }
        }

        Ok(())
    }

    fn release_locks(&mut self, handle: OperationHandle) {
        let Some(operation) = self.operations.get(&handle) else {
            return;
        };
        let locks = operation.locks.clone();

        for key in &locks.coins {
            if let Some(coin) = self.coins.get_mut(key) {
                let _ = coin.release(handle);
            }
        }
        for key in &locks.entries {
            if let Some(entry) = self.entries.get_mut(key) {
                let _ = entry.release(handle);
            }
        }
    }

    /// Emit the terminal status and drop the record.
    ///
    /// The layer keeps no operation history: a caller that needs the receipt
    /// takes it from the event, and a later lookup on the stale handle reports
    /// `OperationNotFound`. Retaining records instead would grow the durable
    /// store without bound and keep a permanent trail of extrinsic hashes
    /// linking the user's coins to on-chain activity — the correlation the
    /// recycler exists to break.
    ///
    /// Because the record is gone once this returns, the emitted event is the
    /// only remaining copy of the receipt until the caller publishes it. See
    /// the module documentation on ordering.
    fn retire(
        &mut self,
        handle: OperationHandle,
        terminal: TerminalStatus,
    ) -> Result<(), CoinageError> {
        self.operations.remove(&handle);
        self.events
            .push(LayerEvent::OperationCompleted { handle, terminal });
        Ok(())
    }
}

fn unknown_record(kind: &str, purse: PurseId) -> CoinageError {
    CoinageError::Internal(format!("unknown {kind} in {purse}"))
}

#[cfg(test)]
mod tests {
    use super::super::coin::CoinState;
    use super::super::selection::OutputRequirement;
    use super::super::types::Amount;
    use super::*;

    const NOW: Timestamp = Timestamp(1_000_000);

    fn exponent(value: i8) -> DenominationExponent {
        DenominationExponent::new(value).expect("exponent is in range")
    }

    fn ring(index: u32) -> RingLocation {
        RingLocation::new(
            super::super::types::RingIndex(index),
            super::super::types::RevisionIndex(0),
        )
    }

    fn store() -> CoinageStore {
        CoinageStore::new("Main".to_string())
    }

    /// Add a coin already confirmed on chain.
    fn fund(store: &mut CoinageStore, purse: PurseId, exponent_value: i8) -> CoinIndex {
        let index = store
            .add_pending_coin(purse, exponent(exponent_value))
            .expect("purse exists");
        store
            .observe_coin(purse, index, CoinAge(0))
            .expect("coin exists");
        index
    }

    fn request(cents: u64) -> SelectionRequest {
        SelectionRequest {
            amount: Amount::from_cents(cents),
            outputs: OutputRequirement::AnyDenominations,
            allow_degraded: true,
        }
    }

    fn begin(
        store: &mut CoinageStore,
        purse: PurseId,
        cents: u64,
    ) -> Result<(OperationHandle, SelectionPlan), CoinageError> {
        store.begin_operation(
            purse,
            OperationKind::Transfer,
            &request(cents),
            &super::super::chain_constants::next_people_paseo(),
            NOW,
        )
    }

    #[test]
    fn a_new_store_holds_only_the_main_purse() {
        let store = store();

        assert_eq!(store.purses().count(), 1);
        assert!(store.purse(PurseId::MAIN).is_some());
    }

    #[test]
    fn purse_identifiers_are_never_reused_after_a_close() {
        let mut store = store();
        let first = store.create_purse("Groceries".to_string());

        store
            .close_purse(first, PurseId::MAIN, Amount::ZERO)
            .expect("close is valid");
        let second = store.create_purse("Rent".to_string());

        // Reuse would let the new purse derive into the closed purse's
        // namespace and inherit its on-chain history.
        assert_ne!(first, second);
        assert_eq!(second, PurseId(first.0 + 1));
    }

    #[test]
    fn the_main_purse_cannot_be_closed() {
        let mut store = store();

        assert_eq!(
            store.close_purse(PurseId::MAIN, PurseId::MAIN, Amount::ZERO),
            Err(CoinageError::CannotDeleteMainPurse)
        );
    }

    #[test]
    fn a_purse_with_in_flight_operations_cannot_be_closed() {
        let mut store = store();
        let purse = store.create_purse("Groceries".to_string());
        fund(&mut store, purse, 3);
        begin(&mut store, purse, 8).expect("8 cents are available");

        assert_eq!(
            store.close_purse(purse, PurseId::MAIN, Amount::ZERO),
            Err(CoinageError::PurseHasInFlightOperations)
        );
    }

    #[test]
    fn operations_on_an_unknown_purse_are_rejected() {
        let mut store = store();
        let ghost = PurseId(99);

        assert_eq!(
            store.balance(ghost, NOW),
            Err(CoinageError::PurseNotFound(ghost))
        );
        assert_eq!(
            store.add_pending_coin(ghost, exponent(2)),
            Err(CoinageError::PurseNotFound(ghost))
        );
        assert!(matches!(
            begin(&mut store, ghost, 4),
            Err(CoinageError::PurseNotFound(_))
        ));
    }

    #[test]
    fn indices_are_never_reused_within_a_purse() {
        let mut store = store();
        let first = fund(&mut store, PurseId::MAIN, 3);
        let second = fund(&mut store, PurseId::MAIN, 3);

        assert_ne!(first, second);
        assert_eq!(
            store
                .purse(PurseId::MAIN)
                .expect("main purse exists")
                .next_coin_index,
            CoinIndex(2)
        );
    }

    #[test]
    fn the_same_index_in_two_purses_is_a_different_record() {
        let mut store = store();
        let other = store.create_purse("Groceries".to_string());
        let main_coin = fund(&mut store, PurseId::MAIN, 3);
        let other_coin = fund(&mut store, other, 5);

        assert_eq!(main_coin, other_coin);
        assert_eq!(
            store
                .coin(PurseId::MAIN, main_coin)
                .expect("exists")
                .exponent,
            exponent(3)
        );
        assert_eq!(
            store.coin(other, other_coin).expect("exists").exponent,
            exponent(5)
        );
    }

    #[test]
    fn observing_a_pending_coin_announces_it_and_moves_the_balance() {
        let mut store = store();
        let index = store
            .add_pending_coin(PurseId::MAIN, exponent(4))
            .expect("purse exists");

        let pending = store.balance(PurseId::MAIN, NOW).expect("purse exists");
        assert_eq!(pending.spendable, Amount::ZERO);
        assert_eq!(pending.pending, Amount::from_cents(16));

        store
            .observe_coin(PurseId::MAIN, index, CoinAge(0))
            .expect("coin exists");

        let settled = store.balance(PurseId::MAIN, NOW).expect("purse exists");
        assert_eq!(settled.spendable, Amount::from_cents(16));
        assert_eq!(settled.pending, Amount::ZERO);
        assert!(store.take_events().contains(&LayerEvent::CoinAvailable {
            purse: PurseId::MAIN,
            exponent: exponent(4),
        }));
    }

    #[test]
    fn re_observing_at_the_same_age_announces_nothing() {
        let mut store = store();
        let index = fund(&mut store, PurseId::MAIN, 4);
        store.take_events();

        store
            .observe_coin(PurseId::MAIN, index, CoinAge(0))
            .expect("coin exists");

        assert!(store.take_events().is_empty());
    }

    #[test]
    fn a_changed_age_is_announced() {
        let mut store = store();
        let index = fund(&mut store, PurseId::MAIN, 4);
        store.take_events();

        store
            .observe_coin(PurseId::MAIN, index, CoinAge(7))
            .expect("coin exists");

        assert_eq!(
            store.take_events(),
            vec![LayerEvent::CoinAged {
                purse: PurseId::MAIN,
                exponent: exponent(4),
                age: CoinAge(7),
            }]
        );
    }

    #[test]
    fn beginning_an_operation_locks_what_it_selected() {
        let mut store = store();
        let index = fund(&mut store, PurseId::MAIN, 3);

        let (handle, plan) = begin(&mut store, PurseId::MAIN, 8).expect("8 cents are available");

        assert_eq!(plan.target_value(), Amount::from_cents(8));
        assert_eq!(
            store.coin(PurseId::MAIN, index).expect("exists").state,
            CoinState::LockedFor(handle)
        );
        assert_eq!(
            store
                .balance(PurseId::MAIN, NOW)
                .expect("purse exists")
                .spendable,
            Amount::ZERO
        );
    }

    #[test]
    fn a_locked_record_is_invisible_to_the_next_selection() {
        let mut store = store();
        fund(&mut store, PurseId::MAIN, 3);
        begin(&mut store, PurseId::MAIN, 8).expect("8 cents are available");

        // The only coin is held, so the second request sees an empty purse.
        assert!(matches!(
            begin(&mut store, PurseId::MAIN, 8),
            Err(CoinageError::InsufficientFunds { .. })
        ));
    }

    #[test]
    fn two_operations_can_hold_disjoint_records() {
        let mut store = store();
        fund(&mut store, PurseId::MAIN, 3);
        fund(&mut store, PurseId::MAIN, 3);

        let (first, _) = begin(&mut store, PurseId::MAIN, 8).expect("first coin");
        let (second, _) = begin(&mut store, PurseId::MAIN, 8).expect("second coin");

        assert_ne!(first, second);
        let first_locks = store.operation(first).expect("open").locks.clone();
        let second_locks = store.operation(second).expect("open").locks.clone();
        assert!(!first_locks.intersects(&second_locks));
    }

    #[test]
    fn failing_an_operation_returns_everything_it_held() {
        let mut store = store();
        let index = fund(&mut store, PurseId::MAIN, 3);
        let (handle, _) = begin(&mut store, PurseId::MAIN, 8).expect("8 cents are available");

        store
            .fail_operation(handle, CoinageError::Cancelled)
            .expect("operation is open");

        assert_eq!(
            store.coin(PurseId::MAIN, index).expect("exists").state,
            CoinState::Available
        );
        assert_eq!(
            store
                .balance(PurseId::MAIN, NOW)
                .expect("purse exists")
                .spendable,
            Amount::from_cents(8)
        );
    }

    #[test]
    fn finishing_retires_consumed_records_and_frees_the_rest() {
        let mut store = store();
        let spent = fund(&mut store, PurseId::MAIN, 3);
        let kept = fund(&mut store, PurseId::MAIN, 3);
        let (handle, _) = begin(&mut store, PurseId::MAIN, 16).expect("both coins");

        let consumed = LockSet {
            coins: vec![(PurseId::MAIN, spent)],
            entries: Vec::new(),
        };
        store
            .finish_operation(handle, OperationReceipt::default(), &consumed)
            .expect("operation is open");

        assert_eq!(
            store.coin(PurseId::MAIN, spent).expect("exists").state,
            CoinState::Spent
        );
        assert_eq!(
            store.coin(PurseId::MAIN, kept).expect("exists").state,
            CoinState::Available
        );
    }

    #[test]
    fn an_operation_cannot_consume_what_it_never_held() {
        let mut store = store();
        fund(&mut store, PurseId::MAIN, 3);
        let outsider = fund(&mut store, PurseId::MAIN, 5);
        let (handle, _) = begin(&mut store, PurseId::MAIN, 8).expect("the 8-cent coin");

        let consumed = LockSet {
            coins: vec![(PurseId::MAIN, outsider)],
            entries: Vec::new(),
        };

        assert!(matches!(
            store.finish_operation(handle, OperationReceipt::default(), &consumed),
            Err(CoinageError::Internal(_))
        ));
    }

    #[test]
    fn a_terminal_operation_is_dropped_and_its_handle_goes_stale() {
        let mut store = store();
        fund(&mut store, PurseId::MAIN, 3);
        let (handle, _) = begin(&mut store, PurseId::MAIN, 8).expect("8 cents are available");

        store
            .fail_operation(handle, CoinageError::Cancelled)
            .expect("operation is open");

        assert!(store.operation(handle).is_none());
        assert_eq!(
            store.fail_operation(handle, CoinageError::Cancelled),
            Err(CoinageError::OperationNotFound(handle))
        );
    }

    #[test]
    fn the_terminal_event_carries_the_receipt() {
        let mut store = store();
        fund(&mut store, PurseId::MAIN, 3);
        let (handle, _) = begin(&mut store, PurseId::MAIN, 8).expect("8 cents are available");
        store.take_events();

        let receipt = OperationReceipt::default();
        store
            .finish_operation(handle, receipt.clone(), &LockSet::default())
            .expect("operation is open");

        assert!(
            store
                .take_events()
                .contains(&LayerEvent::OperationCompleted {
                    handle,
                    terminal: TerminalStatus::Done(receipt),
                })
        );
    }

    #[test]
    fn an_in_flight_operation_cannot_be_cancelled() {
        let mut store = store();
        fund(&mut store, PurseId::MAIN, 3);
        let (handle, _) = begin(&mut store, PurseId::MAIN, 8).expect("8 cents are available");
        store
            .record_submission(handle, ExtrinsicHash([1; 32]))
            .expect("operation is open");

        assert!(store.cancel_operation(handle).is_err());
        assert!(store.operation(handle).is_some());
    }

    #[test]
    fn restart_fails_operations_that_never_broadcast() {
        let mut store = store();
        let index = fund(&mut store, PurseId::MAIN, 3);
        let (handle, _) = begin(&mut store, PurseId::MAIN, 8).expect("8 cents are available");

        let pending = store.reconcile_after_restart();

        assert!(pending.is_empty());
        assert!(store.operation(handle).is_none());
        assert_eq!(
            store.coin(PurseId::MAIN, index).expect("exists").state,
            CoinState::Available
        );
    }

    #[test]
    fn restart_keeps_operations_that_broadcast_for_reconciliation() {
        let mut store = store();
        fund(&mut store, PurseId::MAIN, 3);
        let (handle, _) = begin(&mut store, PurseId::MAIN, 8).expect("8 cents are available");
        store
            .record_submission(handle, ExtrinsicHash([2; 32]))
            .expect("operation is open");

        let pending = store.reconcile_after_restart();

        assert_eq!(pending, vec![handle]);
        assert!(store.operation(handle).is_some());
    }

    #[test]
    fn resynced_is_the_last_event_of_a_restart() {
        let mut store = store();
        fund(&mut store, PurseId::MAIN, 3);
        begin(&mut store, PurseId::MAIN, 8).expect("8 cents are available");
        store.take_events();

        store.reconcile_after_restart();
        let events = store.take_events();

        assert_eq!(events.last(), Some(&LayerEvent::Resynced));
    }

    #[test]
    fn a_store_survives_a_round_trip_through_its_encoding() {
        let mut original = store();
        let purse = original.create_purse("Groceries".to_string());
        fund(&mut original, purse, 4);
        let (handle, _) = begin(&mut original, purse, 16).expect("16 cents are available");
        original
            .record_submission(handle, ExtrinsicHash([3; 32]))
            .expect("operation is open");

        let encoded = original.encode();
        let restored =
            CoinageStore::decode(&mut &encoded[..]).expect("the store round-trips through SCALE");

        assert_eq!(
            restored.balance(purse, NOW).expect("purse exists"),
            original.balance(purse, NOW).expect("purse exists")
        );
        assert_eq!(
            restored.operation(handle).expect("still open").submitted,
            vec![ExtrinsicHash([3; 32])]
        );
        assert_eq!(restored.purses().count(), 2);
    }

    #[test]
    fn recycling_candidates_are_reported_oldest_first_in_index_order() {
        let mut store = store();
        let young = fund(&mut store, PurseId::MAIN, 3);
        let old = fund(&mut store, PurseId::MAIN, 3);
        store
            .observe_coin(PurseId::MAIN, old, CoinAge(14))
            .expect("coin exists");

        let due = store.coins_needing_recycling(PurseId::MAIN, CoinAge(14));

        assert_eq!(due, vec![old]);
        assert!(!due.contains(&young));
    }

    #[test]
    fn entry_readiness_changes_are_announced_once() {
        let mut store = store();
        let params = CoinageParameters::default();
        let index = store
            .allocate_entry(PurseId::MAIN, exponent(4), NOW, Duration::ZERO)
            .expect("purse exists");
        store.take_events();

        store
            .observe_entry_ring(PurseId::MAIN, index, ring(1), 32, &params)
            .expect("entry exists");
        let first = store.take_events();

        store
            .observe_entry_ring(PurseId::MAIN, index, ring(1), 33, &params)
            .expect("entry exists");
        let second = store.take_events();

        assert_eq!(first.len(), 1);
        assert!(second.is_empty());
    }
}
