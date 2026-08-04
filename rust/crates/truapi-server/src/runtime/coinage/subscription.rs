//! The layer's three subscription surfaces.
//!
//! `coinage-layer.md` §8.9 and §7.2. Three streams, one fan-out point:
//!
//! - **Events** — every [`LayerEvent`] the store produced, in order. An event is
//!   a change rather than a value, so this stream has nothing to emit at
//!   subscribe time and starts live.
//! - **Purse balance** — the three-value balance, current value first and a new
//!   item on every change.
//! - **Operation status** — the state machine of §5.5, current status first,
//!   terminal item exactly once, then the stream closes.
//!
//! # Why balances are recomputed rather than published
//!
//! A balance is a projection of the whole purse, and several of its inputs are
//! time-dependent: an entry inside its jitter delay, a coin the chain locked
//! after a failed dispatch. Events cannot carry a balance because the value
//! moves without any event — the clock alone changes it. So this hub holds the
//! last value it emitted per subscriber and recomputes against the store,
//! emitting only on a real change. [`CoinageSubscriptions::publish`] does that
//! after a mutation; [`CoinageSubscriptions::refresh`] does it on a clock tick,
//! where there are no events at all.
//!
//! # Why operation status comes from the events
//!
//! A terminal operation's record is dropped as soon as its status is emitted
//! (§7.8), so by the time a status change is published the store may no longer
//! hold the operation. `OperationCompleted` carries the terminal status and its
//! receipt, which makes the event the only complete source. Progress is taken
//! from the events too, so a subscriber sees every intermediate status rather
//! than only whichever one the store happened to settle on.
//!
//! Subscribing reads the store directly, which assumes the store has no
//! undrained events — the invariant every mutating path already maintains by
//! calling [`crate::runtime::coinage::persistence::publish_and_persist`] before
//! yielding to a caller.

use std::sync::{Arc, Mutex};

use futures::channel::mpsc;
use futures::stream::{self, BoxStream, StreamExt};

use crate::host_logic::coinage::error::CoinageError;
use crate::host_logic::coinage::event::LayerEvent;
use crate::host_logic::coinage::operation::OperationStatus;
use crate::host_logic::coinage::purse::PurseBalance;
use crate::host_logic::coinage::store::CoinageStore;
use crate::host_logic::coinage::types::{OperationHandle, PurseId, Timestamp};

/// Message for a poisoned subscription mutex. The hub holds no invariant a
/// panicking subscriber could break, but a poisoned lock is still a bug worth
/// naming.
const POISONED: &str = "coinage subscription mutex poisoned";

/// One balance subscriber and the value it last saw.
struct BalanceSubscriber {
    purse: PurseId,
    last: PurseBalance,
    sender: mpsc::UnboundedSender<PurseBalance>,
}

/// One operation-status subscriber and the status it last saw.
struct StatusSubscriber {
    handle: OperationHandle,
    last: OperationStatus,
    sender: mpsc::UnboundedSender<OperationStatus>,
}

/// Fan-out for the layer's subscriptions.
///
/// Shared behind an [`Arc`]: the driver publishes into it while callers hold
/// streams out of it. Dropping a stream is always safe — the sender is pruned at
/// the next publish and nothing about the operation changes.
#[derive(Default)]
pub struct CoinageSubscriptions {
    events: Mutex<Vec<mpsc::UnboundedSender<LayerEvent>>>,
    balances: Mutex<Vec<BalanceSubscriber>>,
    statuses: Mutex<Vec<StatusSubscriber>>,
}

impl CoinageSubscriptions {
    /// Create a hub with no subscribers.
    pub fn new() -> Arc<Self> {
        Arc::new(Self::default())
    }

    /// Subscribe to every event the layer publishes from now on.
    pub fn subscribe_events(&self) -> BoxStream<'static, LayerEvent> {
        let (sender, receiver) = mpsc::unbounded();
        self.events.lock().expect(POISONED).push(sender);
        Box::pin(receiver)
    }

    /// Subscribe to a purse's balance, current value first.
    pub fn subscribe_purse_balance(
        &self,
        store: &CoinageStore,
        purse: PurseId,
        now: Timestamp,
    ) -> Result<BoxStream<'static, PurseBalance>, CoinageError> {
        let current = store.balance(purse, now)?;
        let (sender, receiver) = mpsc::unbounded();
        self.balances
            .lock()
            .expect(POISONED)
            .push(BalanceSubscriber {
                purse,
                last: current,
                sender,
            });

        Ok(Box::pin(
            stream::once(async move { current }).chain(receiver),
        ))
    }

    /// Subscribe to an operation's status, current status first and the terminal
    /// status last.
    ///
    /// Fails with `OperationNotFound` for a handle the store does not hold,
    /// which includes an operation that has already terminated: its record is
    /// gone and its terminal status was published to whoever was subscribed at
    /// the time.
    pub fn subscribe_operation_status(
        &self,
        store: &CoinageStore,
        handle: OperationHandle,
    ) -> Result<BoxStream<'static, OperationStatus>, CoinageError> {
        let current = store
            .operation(handle)
            .ok_or(CoinageError::OperationNotFound(handle))?
            .status
            .clone();
        let (sender, receiver) = mpsc::unbounded();

        // A terminal status registers no subscriber: dropping the sender closes
        // the stream right after the item the caller is owed.
        if !current.is_terminal() {
            self.statuses
                .lock()
                .expect(POISONED)
                .push(StatusSubscriber {
                    handle,
                    last: current.clone(),
                    sender,
                });
        }

        Ok(Box::pin(
            stream::once(async move { current }).chain(receiver),
        ))
    }

    /// Deliver a batch of drained events and reproject the derived streams.
    ///
    /// Called with the store as it stands after the mutation that produced
    /// `events` and before it is persisted, so a subscriber learns of a terminal
    /// operation no later than the durable store does (§7.9).
    pub fn publish(&self, events: &[LayerEvent], store: &CoinageStore, now: Timestamp) {
        self.publish_events(events);
        self.advance_statuses(events);
        self.refresh_balances(store, now);
    }

    /// Reproject balances with no events to deliver.
    ///
    /// For the driver's clock tick: an entry leaving its jitter delay or a chain
    /// lock expiring changes a balance without changing a record.
    pub fn refresh(&self, store: &CoinageStore, now: Timestamp) {
        self.refresh_balances(store, now);
    }

    /// How many subscribers the hub currently holds, as
    /// `(events, balances, statuses)`. For diagnostics and tests.
    pub fn subscriber_counts(&self) -> (usize, usize, usize) {
        (
            self.events.lock().expect(POISONED).len(),
            self.balances.lock().expect(POISONED).len(),
            self.statuses.lock().expect(POISONED).len(),
        )
    }

    fn publish_events(&self, events: &[LayerEvent]) {
        let mut subscribers = self.events.lock().expect(POISONED);
        subscribers.retain(|sender| {
            events
                .iter()
                .all(|event| sender.unbounded_send(event.clone()).is_ok())
        });
    }

    fn advance_statuses(&self, events: &[LayerEvent]) {
        let mut subscribers = self.statuses.lock().expect(POISONED);
        subscribers.retain_mut(|subscriber| {
            for event in events {
                match event {
                    LayerEvent::OperationProgress { handle, status }
                        if *handle == subscriber.handle =>
                    {
                        // A status equal to the last one emitted carries no
                        // information, and is what a subscription taken between
                        // the mutation and this publish would otherwise see
                        // twice.
                        if *status == subscriber.last {
                            continue;
                        }
                        subscriber.last = status.clone();
                        if subscriber.sender.unbounded_send(status.clone()).is_err() {
                            return false;
                        }
                    }
                    LayerEvent::OperationCompleted { handle, terminal }
                        if *handle == subscriber.handle =>
                    {
                        // The terminal item is the last one the stream carries,
                        // so the subscriber is dropped whether or not the send
                        // lands.
                        let _ = subscriber
                            .sender
                            .unbounded_send(OperationStatus::from(terminal.clone()));
                        return false;
                    }
                    _ => {}
                }
            }

            !subscriber.sender.is_closed()
        });
    }

    fn refresh_balances(&self, store: &CoinageStore, now: Timestamp) {
        let mut subscribers = self.balances.lock().expect(POISONED);
        subscribers.retain_mut(|subscriber| {
            // A purse that no longer exists was drained and closed; its balance
            // can never change again, so the stream closes.
            let Ok(balance) = store.balance(subscriber.purse, now) else {
                return false;
            };

            if balance == subscriber.last {
                return !subscriber.sender.is_closed();
            }

            subscriber.last = balance;
            subscriber.sender.unbounded_send(balance).is_ok()
        });
    }
}

#[cfg(test)]
mod tests {
    use core::time::Duration;

    use futures::executor::block_on;
    use futures::{FutureExt, StreamExt};

    use crate::host_logic::coinage::chain_constants::next_people_paseo;
    use crate::host_logic::coinage::operation::{OperationReceipt, TerminalStatus};
    use crate::host_logic::coinage::params::CoinageParameters;
    use crate::host_logic::coinage::selection::{OutputRequirement, SelectionRequest};
    use crate::host_logic::coinage::types::{
        Amount, CoinAge, CoinIndex, DenominationExponent, EntryIndex, OperationKind, RevisionIndex,
        RingIndex, RingLocation,
    };

    use super::*;

    const NOW: Timestamp = Timestamp(1_000_000);

    fn exponent(value: i8) -> DenominationExponent {
        DenominationExponent::new(value).expect("exponent is in range")
    }

    fn store() -> CoinageStore {
        CoinageStore::new("Main".to_string())
    }

    /// Add a coin the chain already reports as populated.
    fn fund(store: &mut CoinageStore, purse: PurseId, exponent_value: i8) -> CoinIndex {
        let index = store
            .add_pending_coin(purse, exponent(exponent_value))
            .expect("purse exists");
        store
            .observe_coin(purse, index, CoinAge(0))
            .expect("coin exists");
        index
    }

    /// Allocate an entry in a full-anonymity ring, still inside its jitter
    /// delay.
    fn entry_awaiting_jitter(
        store: &mut CoinageStore,
        purse: PurseId,
        jitter: Duration,
    ) -> EntryIndex {
        let index = store
            .allocate_entry(purse, exponent(4), NOW, jitter)
            .expect("purse exists");
        store
            .observe_entry_ring(
                purse,
                index,
                RingLocation::new(RingIndex(0), RevisionIndex(0)),
                64,
                &CoinageParameters::default(),
            )
            .expect("entry exists");
        index
    }

    /// Start an operation holding one coin.
    fn begin(store: &mut CoinageStore, purse: PurseId, cents: u64) -> OperationHandle {
        let (handle, _plan) = store
            .begin_operation(
                purse,
                OperationKind::Transfer,
                &SelectionRequest {
                    amount: Amount::from_cents(cents),
                    outputs: OutputRequirement::AnyDenominations,
                    allow_degraded: true,
                },
                &next_people_paseo(),
                NOW,
            )
            .expect("selection succeeds");
        handle
    }

    /// Drain the store's events into the hub, the way the persistence path does.
    fn publish(hub: &CoinageSubscriptions, store: &mut CoinageStore, now: Timestamp) {
        let events = store.take_events();
        hub.publish(&events, store, now);
    }

    // -- events ------------------------------------------------------------

    #[test]
    fn the_event_stream_carries_published_events_in_order() {
        let mut store = store();
        let hub = CoinageSubscriptions::new();
        let mut events = hub.subscribe_events();

        let savings = store.create_purse("Savings".to_string());
        store
            .rename_purse(savings, "Rent".to_string())
            .expect("purse exists");
        publish(&hub, &mut store, NOW);

        assert_eq!(
            block_on(events.next()),
            Some(LayerEvent::PurseCreated {
                purse: savings,
                name: "Savings".to_string(),
            })
        );
        assert_eq!(
            block_on(events.next()),
            Some(LayerEvent::PurseRenamed {
                purse: savings,
                name: "Rent".to_string(),
            })
        );
    }

    #[test]
    fn the_event_stream_starts_live_with_no_backlog() {
        let mut store = store();
        let hub = CoinageSubscriptions::new();
        store.create_purse("Savings".to_string());
        publish(&hub, &mut store, NOW);

        // Subscribing after the fact does not replay: an event is a change, not
        // a value with a current reading.
        let mut events = hub.subscribe_events();
        assert!(events.next().now_or_never().is_none());
    }

    #[test]
    fn event_subscriptions_are_independent() {
        let mut store = store();
        let hub = CoinageSubscriptions::new();
        let mut first = hub.subscribe_events();
        let mut second = hub.subscribe_events();

        store.create_purse("Savings".to_string());
        publish(&hub, &mut store, NOW);

        assert!(block_on(first.next()).is_some());
        assert!(block_on(second.next()).is_some());
    }

    #[test]
    fn a_dropped_event_subscriber_is_pruned() {
        let mut store = store();
        let hub = CoinageSubscriptions::new();
        drop(hub.subscribe_events());

        store.create_purse("Savings".to_string());
        publish(&hub, &mut store, NOW);

        assert_eq!(hub.subscriber_counts().0, 0);
    }

    // -- balance -----------------------------------------------------------

    #[test]
    fn a_balance_subscription_opens_with_the_current_value() {
        let mut store = store();
        fund(&mut store, PurseId::MAIN, 4);
        let hub = CoinageSubscriptions::new();

        let mut balances = hub
            .subscribe_purse_balance(&store, PurseId::MAIN, NOW)
            .expect("purse exists");

        let first = block_on(balances.next()).expect("an item at subscribe time");
        assert_eq!(first.spendable, Amount::from_cents(16));
        assert_eq!(first.pending, Amount::ZERO);
    }

    #[test]
    fn a_balance_subscription_for_an_unknown_purse_is_refused() {
        let store = store();
        let hub = CoinageSubscriptions::new();

        let refused = hub.subscribe_purse_balance(&store, PurseId(7), NOW);

        assert_eq!(refused.err(), Some(CoinageError::PurseNotFound(PurseId(7))));
    }

    #[test]
    fn a_balance_item_arrives_on_a_change_and_only_on_a_change() {
        let mut store = store();
        let hub = CoinageSubscriptions::new();
        let mut balances = hub
            .subscribe_purse_balance(&store, PurseId::MAIN, NOW)
            .expect("purse exists");
        let _ = block_on(balances.next());

        fund(&mut store, PurseId::MAIN, 4);
        publish(&hub, &mut store, NOW);

        assert_eq!(
            block_on(balances.next())
                .expect("the coin moved the balance")
                .spendable,
            Amount::from_cents(16)
        );

        // A publish that leaves the balance where it was emits nothing: the
        // rename changes the purse's name, not its value.
        store
            .rename_purse(PurseId::MAIN, "Everyday".to_string())
            .expect("purse exists");
        publish(&hub, &mut store, NOW);

        assert!(balances.next().now_or_never().is_none());
    }

    #[test]
    fn locking_a_coin_for_an_operation_moves_it_from_spendable_to_pending() {
        let mut store = store();
        fund(&mut store, PurseId::MAIN, 4);
        let hub = CoinageSubscriptions::new();
        let mut balances = hub
            .subscribe_purse_balance(&store, PurseId::MAIN, NOW)
            .expect("purse exists");
        let _ = block_on(balances.next());

        begin(&mut store, PurseId::MAIN, 16);
        publish(&hub, &mut store, NOW);

        let locked = block_on(balances.next()).expect("the lock moved the balance");
        assert_eq!(locked.spendable, Amount::ZERO);
        assert_eq!(locked.pending, Amount::from_cents(16));
    }

    #[test]
    fn the_clock_alone_can_move_a_balance() {
        // The reason balances are recomputed rather than carried on an event:
        // an entry leaving its jitter delay changes the balance with no record
        // changing at all.
        let mut store = store();
        let hub = CoinageSubscriptions::new();
        entry_awaiting_jitter(&mut store, PurseId::MAIN, Duration::from_secs(60));
        publish(&hub, &mut store, NOW);
        let mut balances = hub
            .subscribe_purse_balance(&store, PurseId::MAIN, NOW)
            .expect("purse exists");

        let waiting = block_on(balances.next()).expect("an item at subscribe time");
        assert_eq!(waiting.spendable, Amount::ZERO);
        assert_eq!(waiting.pending, Amount::from_cents(16));

        hub.refresh(&store, NOW.saturating_add(Duration::from_secs(61)));

        let ready = block_on(balances.next()).expect("the jitter delay elapsed");
        assert_eq!(ready.spendable, Amount::from_cents(16));
        assert_eq!(ready.pending, Amount::ZERO);
    }

    #[test]
    fn a_closed_purse_closes_its_balance_stream() {
        let mut store = store();
        let savings = store.create_purse("Savings".to_string());
        let hub = CoinageSubscriptions::new();
        let mut balances = hub
            .subscribe_purse_balance(&store, savings, NOW)
            .expect("purse exists");
        let _ = block_on(balances.next());

        store
            .close_purse(savings, PurseId::MAIN, Amount::ZERO)
            .expect("close is valid");
        publish(&hub, &mut store, NOW);

        assert_eq!(
            block_on(balances.next()),
            None,
            "nothing further can change"
        );
        assert_eq!(hub.subscriber_counts().1, 0);
    }

    #[test]
    fn a_dropped_balance_subscriber_is_pruned_even_without_a_change() {
        let mut store = store();
        let hub = CoinageSubscriptions::new();
        drop(
            hub.subscribe_purse_balance(&store, PurseId::MAIN, NOW)
                .expect("purse exists"),
        );

        publish(&hub, &mut store, NOW);

        assert_eq!(hub.subscriber_counts().1, 0);
    }

    // -- operation status --------------------------------------------------

    #[test]
    fn a_status_subscription_opens_with_the_current_status() {
        let mut store = store();
        fund(&mut store, PurseId::MAIN, 4);
        let handle = begin(&mut store, PurseId::MAIN, 16);
        let hub = CoinageSubscriptions::new();
        publish(&hub, &mut store, NOW);

        let mut statuses = hub
            .subscribe_operation_status(&store, handle)
            .expect("the operation is open");

        assert_eq!(block_on(statuses.next()), Some(OperationStatus::Preparing));
    }

    #[test]
    fn a_status_subscription_for_an_unknown_handle_is_refused() {
        let store = store();
        let hub = CoinageSubscriptions::new();

        let refused = hub.subscribe_operation_status(&store, OperationHandle(9));

        assert_eq!(
            refused.err(),
            Some(CoinageError::OperationNotFound(OperationHandle(9)))
        );
    }

    #[test]
    fn every_intermediate_status_reaches_the_stream() {
        let mut store = store();
        fund(&mut store, PurseId::MAIN, 4);
        let handle = begin(&mut store, PurseId::MAIN, 16);
        let hub = CoinageSubscriptions::new();
        publish(&hub, &mut store, NOW);
        let mut statuses = hub
            .subscribe_operation_status(&store, handle)
            .expect("the operation is open");
        let _ = block_on(statuses.next());

        store
            .advance_operation(handle, OperationStatus::Submitted)
            .expect("the operation is open");
        store
            .advance_operation(handle, OperationStatus::InBlock)
            .expect("the operation is open");
        publish(&hub, &mut store, NOW);

        assert_eq!(block_on(statuses.next()), Some(OperationStatus::Submitted));
        assert_eq!(block_on(statuses.next()), Some(OperationStatus::InBlock));
    }

    #[test]
    fn a_status_equal_to_the_one_already_emitted_is_not_repeated() {
        // The window a subscription can be taken in: the store already holds
        // the new status while the event announcing it is still undrained.
        let mut store = store();
        fund(&mut store, PurseId::MAIN, 4);
        let handle = begin(&mut store, PurseId::MAIN, 16);
        let hub = CoinageSubscriptions::new();
        publish(&hub, &mut store, NOW);
        store
            .advance_operation(handle, OperationStatus::Submitted)
            .expect("the operation is open");

        let mut statuses = hub
            .subscribe_operation_status(&store, handle)
            .expect("the operation is open");
        assert_eq!(block_on(statuses.next()), Some(OperationStatus::Submitted));

        publish(&hub, &mut store, NOW);

        assert!(statuses.next().now_or_never().is_none());
    }

    #[test]
    fn the_terminal_status_is_emitted_once_and_closes_the_stream() {
        let mut store = store();
        fund(&mut store, PurseId::MAIN, 4);
        let handle = begin(&mut store, PurseId::MAIN, 16);
        let hub = CoinageSubscriptions::new();
        publish(&hub, &mut store, NOW);
        let mut statuses = hub
            .subscribe_operation_status(&store, handle)
            .expect("the operation is open");
        let _ = block_on(statuses.next());

        store
            .fail_operation(handle, CoinageError::Cancelled)
            .expect("the operation is open");
        publish(&hub, &mut store, NOW);

        assert_eq!(
            block_on(statuses.next()),
            Some(OperationStatus::Failed(CoinageError::Cancelled))
        );
        assert_eq!(block_on(statuses.next()), None, "the stream then closes");
        assert_eq!(hub.subscriber_counts().2, 0);
    }

    #[test]
    fn the_terminal_status_carries_the_receipt() {
        // §7.8 lets the store drop the operation record the moment its status is
        // emitted, so the event is the only place the receipt still exists.
        let mut store = store();
        fund(&mut store, PurseId::MAIN, 4);
        let handle = begin(&mut store, PurseId::MAIN, 16);
        let hub = CoinageSubscriptions::new();
        publish(&hub, &mut store, NOW);
        let mut statuses = hub
            .subscribe_operation_status(&store, handle)
            .expect("the operation is open");
        let _ = block_on(statuses.next());
        let receipt = OperationReceipt::default();

        store
            .finish_operation(handle, receipt.clone(), &Default::default())
            .expect("the operation is open");
        publish(&hub, &mut store, NOW);

        assert_eq!(
            block_on(statuses.next()),
            Some(OperationStatus::Done(receipt))
        );
        assert!(
            store.operation(handle).is_none(),
            "the record the receipt came from is already gone"
        );
    }

    #[test]
    fn a_terminated_operation_cannot_be_subscribed_to() {
        let mut store = store();
        fund(&mut store, PurseId::MAIN, 4);
        let handle = begin(&mut store, PurseId::MAIN, 16);
        let hub = CoinageSubscriptions::new();
        store
            .fail_operation(handle, CoinageError::Cancelled)
            .expect("the operation is open");
        publish(&hub, &mut store, NOW);

        assert_eq!(
            hub.subscribe_operation_status(&store, handle).err(),
            Some(CoinageError::OperationNotFound(handle))
        );
    }

    #[test]
    fn statuses_are_delivered_only_to_the_subscribed_operation() {
        let mut store = store();
        fund(&mut store, PurseId::MAIN, 4);
        fund(&mut store, PurseId::MAIN, 5);
        let watched = begin(&mut store, PurseId::MAIN, 16);
        let other = begin(&mut store, PurseId::MAIN, 32);
        let hub = CoinageSubscriptions::new();
        publish(&hub, &mut store, NOW);
        let mut statuses = hub
            .subscribe_operation_status(&store, watched)
            .expect("the operation is open");
        let _ = block_on(statuses.next());

        store
            .advance_operation(other, OperationStatus::Submitted)
            .expect("the operation is open");
        publish(&hub, &mut store, NOW);

        assert!(statuses.next().now_or_never().is_none());
    }

    #[test]
    fn a_dropped_status_subscriber_is_pruned() {
        let mut store = store();
        fund(&mut store, PurseId::MAIN, 4);
        let handle = begin(&mut store, PurseId::MAIN, 16);
        let hub = CoinageSubscriptions::new();
        publish(&hub, &mut store, NOW);
        drop(
            hub.subscribe_operation_status(&store, handle)
                .expect("the operation is open"),
        );

        publish(&hub, &mut store, NOW);

        assert_eq!(hub.subscriber_counts().2, 0);
    }

    #[test]
    fn a_restart_reaches_the_streams_it_affects() {
        // `reconcile_after_restart` fails everything that never broadcast and
        // then announces `Resynced`; a subscriber must see both.
        let mut store = store();
        fund(&mut store, PurseId::MAIN, 4);
        let handle = begin(&mut store, PurseId::MAIN, 16);
        let hub = CoinageSubscriptions::new();
        publish(&hub, &mut store, NOW);
        let mut statuses = hub
            .subscribe_operation_status(&store, handle)
            .expect("the operation is open");
        let _ = block_on(statuses.next());
        let mut events = hub.subscribe_events();
        let mut balances = hub
            .subscribe_purse_balance(&store, PurseId::MAIN, NOW)
            .expect("purse exists");
        let _ = block_on(balances.next());

        assert!(
            store.reconcile_after_restart().is_empty(),
            "nothing was broadcast, so nothing needs reconciling"
        );
        publish(&hub, &mut store, NOW);

        assert_eq!(
            block_on(statuses.next()),
            Some(OperationStatus::Failed(
                CoinageError::InterruptedPreSubmission
            ))
        );
        assert_eq!(block_on(statuses.next()), None);
        // The coin the interrupted operation held is spendable again.
        assert_eq!(
            block_on(balances.next())
                .expect("the lock was released")
                .spendable,
            Amount::from_cents(16)
        );
        let published: Vec<_> =
            core::iter::from_fn(|| events.next().now_or_never().flatten()).collect();
        assert_eq!(published.last(), Some(&LayerEvent::Resynced));
    }

    #[test]
    fn a_terminal_status_reaches_a_subscriber_that_stopped_reading() {
        // Dropping a subscription is safe, but a subscriber that simply stops
        // polling must still find the terminal item waiting: the channel is
        // unbounded, so nothing is dropped on the floor.
        let mut store = store();
        fund(&mut store, PurseId::MAIN, 4);
        let handle = begin(&mut store, PurseId::MAIN, 16);
        let hub = CoinageSubscriptions::new();
        publish(&hub, &mut store, NOW);
        let statuses = hub
            .subscribe_operation_status(&store, handle)
            .expect("the operation is open");

        store
            .advance_operation(handle, OperationStatus::Submitted)
            .expect("the operation is open");
        store
            .fail_operation(handle, CoinageError::SnipedCoin)
            .expect("the operation is open");
        publish(&hub, &mut store, NOW);

        let items: Vec<_> = block_on(statuses.collect());
        assert_eq!(
            items,
            vec![
                OperationStatus::Preparing,
                OperationStatus::Submitted,
                OperationStatus::Failed(CoinageError::SnipedCoin),
            ]
        );
    }

    #[test]
    fn a_terminal_status_is_the_last_item_even_mid_batch() {
        // Events published after the completion in the same batch must not
        // appear on the operation's stream.
        let mut store = store();
        fund(&mut store, PurseId::MAIN, 4);
        let handle = begin(&mut store, PurseId::MAIN, 16);
        let hub = CoinageSubscriptions::new();
        publish(&hub, &mut store, NOW);
        let mut statuses = hub
            .subscribe_operation_status(&store, handle)
            .expect("the operation is open");
        let _ = block_on(statuses.next());

        let events = vec![
            LayerEvent::OperationCompleted {
                handle,
                terminal: TerminalStatus::Failed(CoinageError::Cancelled),
            },
            LayerEvent::OperationProgress {
                handle,
                status: OperationStatus::Preparing,
            },
        ];
        hub.publish(&events, &store, NOW);

        assert_eq!(
            block_on(statuses.next()),
            Some(OperationStatus::Failed(CoinageError::Cancelled))
        );
        assert_eq!(block_on(statuses.next()), None);
    }
}
