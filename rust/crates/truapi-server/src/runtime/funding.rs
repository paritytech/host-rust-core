//! Host-global registry of funding sessions.
//!
//! A session outlives the surface that opened it and is not scoped to one
//! product connection: the balance card opens one, and a product that reloads
//! attaches to it with `status_subscribe`. So the registry hangs off
//! [`RuntimeServices`](super::services::RuntimeServices) rather than off a
//! product runtime.
//!
//! Every stage change funnels through [`FundingRegistry::mutate`], which is
//! what makes the RFC's invariants hold on all paths at once: subscribers are
//! notified, the host presenter is told, and the persisted set is rewritten,
//! whether the change came from a provider report, an arrival observation, or
//! expiry.

pub(crate) mod arrival;

use std::collections::HashMap;
use std::sync::{Arc, Mutex};

use futures::channel::mpsc;
use futures::stream::{self, BoxStream, StreamExt};
use truapi::latest::HostFundingStatusSubscribeItem;
use truapi_platform::{CoreStorage, FundingPresenter};

use crate::host_logic::funding::{
    FundingIntent, FundingSession, FundingSessionError, load_sessions, store_sessions,
};

/// One subscriber's channel, tagged with who is listening.
///
/// The product id rides along because `resume` is disclosed only to the product
/// that declared the intent, so each subscriber gets its own projection of the
/// same stage.
struct Subscriber {
    product_id: String,
    sender: mpsc::UnboundedSender<HostFundingStatusSubscribeItem>,
}

#[derive(Default)]
struct RegistryState {
    sessions: HashMap<String, FundingSession>,
    subscribers: HashMap<String, Vec<Subscriber>>,
    presenter: Option<Arc<dyn FundingPresenter>>,
}

/// Host-global funding sessions and their subscribers.
#[derive(Default)]
pub(crate) struct FundingRegistry {
    state: Mutex<RegistryState>,
}

impl FundingRegistry {
    /// Build an empty registry with no host UI attached.
    pub(crate) fn new() -> Self {
        Self::default()
    }

    /// Attach the host surface that renders funding status.
    ///
    /// Installed after construction because a host wires its native adapters
    /// once, after the runtime it hands them to already exists.
    pub(crate) fn install_presenter(&self, presenter: Arc<dyn FundingPresenter>) {
        self.lock().presenter = Some(presenter);
    }

    /// Load persisted sessions into memory.
    ///
    /// Called once per runtime so a session interrupted by app death is present
    /// before any host UI asks for the active set. Sessions already past their
    /// deadline expire here rather than being resurrected as live.
    pub(crate) async fn hydrate(
        &self,
        storage: &(impl CoreStorage + ?Sized),
        now_ms: u64,
    ) -> Result<(), FundingSessionError> {
        let mut persisted = load_sessions(storage).await?;
        for session in &mut persisted {
            session.expire_if_due(now_ms);
        }
        {
            let mut state = self.lock();
            for session in persisted {
                state.sessions.insert(session.intent.clone(), session);
            }
        }
        self.persist(storage).await
    }

    /// Open a session and persist it.
    pub(crate) async fn open(
        &self,
        storage: &(impl CoreStorage + ?Sized),
        declared: FundingIntent,
        now_ms: u64,
    ) -> Result<FundingSession, FundingSessionError> {
        let session = FundingSession::new(format!("fs_{}", nanoid::nanoid!(10)), declared, now_ms);
        {
            let mut state = self.lock();
            state
                .sessions
                .insert(session.intent.clone(), session.clone());
        }
        self.persist(storage).await?;
        Ok(session)
    }

    /// Snapshot one session.
    pub(crate) fn get(&self, intent: &str) -> Option<FundingSession> {
        self.lock().sessions.get(intent).cloned()
    }

    /// Sessions that have not reached a terminal stage.
    pub(crate) fn active(&self) -> Vec<FundingSession> {
        let mut active: Vec<FundingSession> = self
            .lock()
            .sessions
            .values()
            .filter(|session| !session.stage.is_terminal())
            .cloned()
            .collect();
        // Deterministic order so a rebuilt dock does not reshuffle on relaunch.
        active.sort_by(|left, right| {
            left.opened_at_ms
                .cmp(&right.opened_at_ms)
                .then_with(|| left.intent.cmp(&right.intent))
        });
        active
    }

    /// Watch one session, receiving its current stage immediately.
    ///
    /// The immediate item is what makes re-attaching after a reload work without
    /// a separate read: a product subscribing late still learns where the
    /// session is. A terminal session yields that one item and then ends.
    pub(crate) fn subscribe(
        &self,
        intent: &str,
        subscriber_product_id: &str,
    ) -> Option<BoxStream<'static, HostFundingStatusSubscribeItem>> {
        let mut state = self.lock();
        let session = state.sessions.get(intent)?;
        let current = session.wire_item(subscriber_product_id);
        if session.stage.is_terminal() {
            return Some(stream::once(async move { current }).boxed());
        }
        let (sender, receiver) = mpsc::unbounded();
        state
            .subscribers
            .entry(intent.to_string())
            .or_default()
            .push(Subscriber {
                product_id: subscriber_product_id.to_string(),
                sender,
            });
        Some(stream::once(async move { current }).chain(receiver).boxed())
    }

    /// Apply a change to one session, then fan out and persist.
    ///
    /// The single write path. `change` sees the live session and may reject the
    /// transition, in which case nothing is notified or persisted.
    pub(crate) async fn mutate<F>(
        &self,
        storage: &(impl CoreStorage + ?Sized),
        intent: &str,
        change: F,
    ) -> Result<FundingSession, FundingSessionError>
    where
        F: FnOnce(&mut FundingSession) -> Result<(), FundingSessionError>,
    {
        let updated = {
            let mut state = self.lock();
            let session = state
                .sessions
                .get_mut(intent)
                .ok_or(FundingSessionError::NotFound)?;
            change(session)?;
            session.clone()
        };
        self.fan_out(&updated);
        self.persist(storage).await?;
        Ok(updated)
    }

    /// Expire every session past its deadline, returning those that changed.
    pub(crate) async fn expire_due(
        &self,
        storage: &(impl CoreStorage + ?Sized),
        now_ms: u64,
    ) -> Result<Vec<FundingSession>, FundingSessionError> {
        let expired = {
            let mut state = self.lock();
            state
                .sessions
                .values_mut()
                .filter(|session| !session.stage.is_terminal())
                .filter_map(|session| session.expire_if_due(now_ms).then(|| session.clone()))
                .collect::<Vec<_>>()
        };
        if expired.is_empty() {
            return Ok(Vec::new());
        }
        for session in &expired {
            self.fan_out(session);
        }
        self.persist(storage).await?;
        Ok(expired)
    }

    /// Notify subscribers and host UI of a session's current stage.
    ///
    /// A terminal stage closes the subscriber list: the item is delivered once
    /// and the streams end, which is what keeps `resume` from being replayable
    /// by resubscribing.
    fn fan_out(&self, session: &FundingSession) {
        let terminal = session.stage.is_terminal();
        {
            let mut state = self.lock();
            if let Some(subscribers) = state.subscribers.get_mut(&session.intent) {
                subscribers.retain(|subscriber| {
                    subscriber
                        .sender
                        .unbounded_send(session.wire_item(&subscriber.product_id))
                        .is_ok()
                });
            }
            if terminal {
                state.subscribers.remove(&session.intent);
            }
        }
        // Cloned out so host UI is never called with the registry lock held.
        let presenter = self.lock().presenter.clone();
        if let Some(presenter) = presenter {
            // Host UI is not a product, so it never receives `resume`.
            presenter.funding_session_changed(session.intent.clone(), session.wire_item(""));
        }
    }

    async fn persist(
        &self,
        storage: &(impl CoreStorage + ?Sized),
    ) -> Result<(), FundingSessionError> {
        let snapshot: Vec<FundingSession> = self.lock().sessions.values().cloned().collect();
        store_sessions(storage, &snapshot).await?;
        // Settled sessions are not persisted, so drop them from memory too once
        // their terminal item has been delivered.
        self.lock()
            .sessions
            .retain(|_, session| !session.stage.is_terminal());
        Ok(())
    }

    fn lock(&self) -> std::sync::MutexGuard<'_, RegistryState> {
        self.state.lock().expect("funding registry mutex poisoned")
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::collections::HashMap as StdHashMap;

    use futures::executor::block_on;
    use parity_scale_codec::Encode;
    use truapi::latest::{
        FundingDirection, FundingFailure, FundingRail, GenericError, HostFundingReportRequest,
    };
    use truapi_platform::CoreStorageKey;

    use crate::host_logic::funding::FundingStage;

    const NOW: u64 = 1_700_000_000_000;
    const OWNER: &str = "wallet.dot";

    #[derive(Default)]
    struct MemStorage {
        inner: Mutex<StdHashMap<Vec<u8>, Vec<u8>>>,
    }

    #[truapi_platform::async_trait]
    impl CoreStorage for MemStorage {
        async fn read_core_storage(
            &self,
            key: CoreStorageKey,
        ) -> Result<Option<Vec<u8>>, GenericError> {
            Ok(self
                .inner
                .lock()
                .expect("storage mutex poisoned")
                .get(&key.encode())
                .cloned())
        }

        async fn write_core_storage(
            &self,
            key: CoreStorageKey,
            value: Vec<u8>,
        ) -> Result<(), GenericError> {
            self.inner
                .lock()
                .expect("storage mutex poisoned")
                .insert(key.encode(), value);
            Ok(())
        }

        async fn clear_core_storage(&self, key: CoreStorageKey) -> Result<(), GenericError> {
            self.inner
                .lock()
                .expect("storage mutex poisoned")
                .remove(&key.encode());
            Ok(())
        }
    }

    #[derive(Default)]
    struct RecordingPresenter {
        seen: Mutex<Vec<(String, HostFundingStatusSubscribeItem)>>,
    }

    impl FundingPresenter for RecordingPresenter {
        fn funding_session_changed(&self, intent: String, status: HostFundingStatusSubscribeItem) {
            self.seen
                .lock()
                .expect("presenter mutex poisoned")
                .push((intent, status));
        }
    }

    fn registry() -> (FundingRegistry, MemStorage) {
        (FundingRegistry::new(), MemStorage::default())
    }

    fn open_inbound(
        registry: &FundingRegistry,
        storage: &MemStorage,
        resume: Option<Vec<u8>>,
    ) -> FundingSession {
        block_on(registry.open(
            storage,
            FundingIntent {
                owner_product_id: OWNER.to_string(),
                direction: FundingDirection::In,
                rail: FundingRail::BankOrCard,
                amount: 100,
                resume,
            },
            NOW,
        ))
        .expect("opened")
    }

    #[test]
    fn an_opened_session_is_active_and_persisted() {
        let (registry, storage) = registry();

        let session = open_inbound(&registry, &storage, None);

        assert_eq!(registry.active().len(), 1);
        assert_eq!(registry.get(&session.intent), Some(session.clone()));
        assert_eq!(
            block_on(load_sessions(&storage)).expect("loaded"),
            vec![session]
        );
    }

    #[test]
    fn intents_are_unique_across_sessions() {
        let (registry, storage) = registry();

        let first = open_inbound(&registry, &storage, None);
        let second = open_inbound(&registry, &storage, None);

        assert_ne!(first.intent, second.intent);
        assert_eq!(registry.active().len(), 2);
    }

    #[test]
    fn a_subscriber_receives_the_current_stage_immediately() {
        let (registry, storage) = registry();
        let session = open_inbound(&registry, &storage, None);

        let mut stream = registry
            .subscribe(&session.intent, OWNER)
            .expect("session exists");

        assert_eq!(
            block_on(stream.next()),
            Some(HostFundingStatusSubscribeItem::AwaitingDeposit { expires_at: None })
        );
    }

    #[test]
    fn subscribing_to_an_unknown_session_yields_nothing() {
        let (registry, _storage) = registry();

        assert!(registry.subscribe("fs_missing", OWNER).is_none());
    }

    #[test]
    fn a_report_reaches_live_subscribers() {
        let (registry, storage) = registry();
        let session = open_inbound(&registry, &storage, None);
        let mut stream = registry
            .subscribe(&session.intent, OWNER)
            .expect("session exists");
        let _current = block_on(stream.next());

        block_on(registry.mutate(&storage, &session.intent, |session| {
            session.apply_report(&HostFundingReportRequest::InProgress {
                intent: "ignored".to_string(),
                note: Some("verifying your ID".to_string()),
            })
        }))
        .expect("mutated");

        assert_eq!(
            block_on(stream.next()),
            Some(HostFundingStatusSubscribeItem::ProviderSide {
                note: Some("verifying your ID".to_string()),
            })
        );
    }

    #[test]
    fn resume_is_projected_per_subscriber() {
        let (registry, storage) = registry();
        let session = open_inbound(&registry, &storage, Some(b"cart-42".to_vec()));
        let mut owner = registry
            .subscribe(&session.intent, OWNER)
            .expect("session exists");
        let mut other = registry
            .subscribe(&session.intent, "other.dot")
            .expect("session exists");
        let _ = block_on(owner.next());
        let _ = block_on(other.next());

        block_on(registry.mutate(&storage, &session.intent, |session| {
            session.observe_arrival(100)
        }))
        .expect("mutated");

        assert_eq!(
            block_on(owner.next()),
            Some(HostFundingStatusSubscribeItem::Delivered {
                credited: 100,
                resume: Some(b"cart-42".to_vec()),
            })
        );
        assert_eq!(
            block_on(other.next()),
            Some(HostFundingStatusSubscribeItem::Delivered {
                credited: 100,
                resume: None,
            })
        );
    }

    #[test]
    fn a_terminal_stage_ends_subscriber_streams() {
        let (registry, storage) = registry();
        let session = open_inbound(&registry, &storage, None);
        let mut stream = registry
            .subscribe(&session.intent, OWNER)
            .expect("session exists");
        let _ = block_on(stream.next());

        block_on(registry.mutate(&storage, &session.intent, |session| {
            session.observe_arrival(100)
        }))
        .expect("mutated");

        assert!(block_on(stream.next()).is_some(), "terminal item delivered");
        assert!(block_on(stream.next()).is_none(), "stream ended");
    }

    #[test]
    fn resume_is_not_replayable_by_resubscribing() {
        let (registry, storage) = registry();
        let session = open_inbound(&registry, &storage, Some(b"cart-42".to_vec()));

        block_on(registry.mutate(&storage, &session.intent, |session| {
            session.observe_arrival(100)
        }))
        .expect("mutated");

        assert!(registry.subscribe(&session.intent, OWNER).is_none());
        assert!(registry.active().is_empty());
    }

    #[test]
    fn a_settled_session_is_dropped_from_storage() {
        let (registry, storage) = registry();
        let session = open_inbound(&registry, &storage, None);

        block_on(registry.mutate(&storage, &session.intent, |session| {
            session.observe_arrival(100)
        }))
        .expect("mutated");

        assert!(
            block_on(load_sessions(&storage))
                .expect("loaded")
                .is_empty()
        );
    }

    #[test]
    fn a_rejected_transition_notifies_nobody() {
        let (registry, storage) = registry();
        let session = open_inbound(&registry, &storage, None);

        let rejected = block_on(registry.mutate(&storage, &session.intent, |session| {
            // Wrong direction for an inbound session.
            session.observe_release(100)
        }));

        assert_eq!(rejected, Err(FundingSessionError::WrongDirection));
        assert_eq!(
            registry.get(&session.intent).map(|session| session.stage),
            Some(FundingStage::Created)
        );
    }

    #[test]
    fn mutating_an_unknown_session_is_not_found() {
        let (registry, storage) = registry();

        let failed =
            block_on(registry.mutate(&storage, "fs_missing", |session| session.observe_arrival(1)));

        assert_eq!(failed, Err(FundingSessionError::NotFound));
    }

    #[test]
    fn due_sessions_expire_and_undue_ones_do_not() {
        let (registry, storage) = registry();
        let session = open_inbound(&registry, &storage, None);

        assert!(
            block_on(registry.expire_due(&storage, session.deadline_ms - 1))
                .expect("swept")
                .is_empty()
        );
        let expired = block_on(registry.expire_due(&storage, session.deadline_ms)).expect("swept");

        assert_eq!(expired.len(), 1);
        assert_eq!(
            expired[0].stage,
            FundingStage::Failed {
                reason: FundingFailure::Expired,
                moved: 0,
            }
        );
    }

    #[test]
    fn hydrate_restores_a_live_session_across_restart() {
        let storage = MemStorage::default();
        let first = FundingRegistry::new();
        let session = open_inbound(&first, &storage, None);

        let second = FundingRegistry::new();
        block_on(second.hydrate(&storage, NOW)).expect("hydrated");

        assert_eq!(second.get(&session.intent), Some(session));
    }

    #[test]
    fn hydrate_expires_a_session_that_died_past_its_deadline() {
        let storage = MemStorage::default();
        let first = FundingRegistry::new();
        let session = open_inbound(&first, &storage, None);

        let second = FundingRegistry::new();
        block_on(second.hydrate(&storage, session.deadline_ms + 1)).expect("hydrated");

        assert!(second.active().is_empty());
        assert!(
            block_on(load_sessions(&storage))
                .expect("loaded")
                .is_empty(),
            "an expired session is not carried forward"
        );
    }

    #[test]
    fn active_is_ordered_by_open_time() {
        let (registry, storage) = registry();
        let intent = |rail| FundingIntent {
            owner_product_id: OWNER.to_string(),
            direction: FundingDirection::In,
            rail,
            amount: 100,
            resume: None,
        };
        let first = block_on(registry.open(&storage, intent(FundingRail::BankOrCard), NOW + 50))
            .expect("opened");
        let second =
            block_on(registry.open(&storage, intent(FundingRail::Cash), NOW)).expect("opened");

        let active = registry.active();

        assert_eq!(active[0].intent, second.intent);
        assert_eq!(active[1].intent, first.intent);
    }

    #[test]
    fn host_ui_is_told_about_every_change_without_resume() {
        let presenter = Arc::new(RecordingPresenter::default());
        let registry = FundingRegistry::new();
        registry.install_presenter(presenter.clone());
        let storage = MemStorage::default();
        let session = open_inbound(&registry, &storage, Some(b"cart-42".to_vec()));

        block_on(registry.mutate(&storage, &session.intent, |session| {
            session.observe_arrival(100)
        }))
        .expect("mutated");

        let seen = presenter.seen.lock().expect("presenter mutex poisoned");
        assert_eq!(
            seen.as_slice(),
            &[(
                session.intent.clone(),
                HostFundingStatusSubscribeItem::Delivered {
                    credited: 100,
                    resume: None,
                },
            )]
        );
    }
}
