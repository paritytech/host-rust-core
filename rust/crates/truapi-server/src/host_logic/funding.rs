//! Core-owned funding sessions and their status machine.
//!
//! A session is one funding intent in flight. The core owns it, not the host
//! surface that opened it, so dismissing the sheet is not cancelling: the
//! session keeps running, persists across app death through
//! [`CoreStorageKey::FundingSessions`], and is re-attached by
//! `Funding::status_subscribe`.
//!
//! Two rules from `docs/rfcs/funding-modality.md` are enforced here rather than
//! left to callers, because both are load-bearing for correctness:
//!
//! - **A session terminates without any provider report.** Arrival is the
//!   core's own on-chain observation and expiry is its own clock, so a provider
//!   that says nothing — including a page-entered one, which cannot report at
//!   all — still reaches a terminal state.
//! - **An observed state is never overridden by a reported one.** Reports say
//!   when to look and what to display. They never decide what happened.

use parity_scale_codec::{Decode, Encode};
use truapi::latest::{
    FundingAmount, FundingDirection, FundingFailure, FundingIntentId, FundingRail,
    HostFundingReportRequest, HostFundingStatusSubscribeItem,
};
use truapi_platform::{CoreStorage, CoreStorageKey};

/// How long a session may go unheard before it expires.
///
/// Measured from the last provider report where there is one, and from handoff
/// where there is not: a session reporting progress is allowed to take much
/// longer than a silent one, because verification legitimately does.
const SILENT_WINDOW_MS: u64 = 30 * 60 * 1_000;
/// Window extension granted by any provider report.
const REPORTING_WINDOW_MS: u64 = 6 * 60 * 60 * 1_000;

/// What the core knows about one session, independent of any host surface.
#[derive(Debug, Clone, PartialEq, Eq, Encode, Decode)]
pub struct FundingSession {
    /// Identifier handed back to the caller and used to re-attach.
    pub intent: FundingIntentId,
    /// Product that declared the intent, and the only one shown `resume`.
    pub owner_product_id: String,
    /// Which way value crosses the boundary.
    pub direction: FundingDirection,
    /// External side the user picked.
    pub rail: FundingRail,
    /// Amount sought, in the session's own asset.
    pub amount: FundingAmount,
    /// Opaque caller context, returned verbatim on the terminal item.
    pub resume: Option<Vec<u8>>,
    /// Current stage.
    pub stage: FundingStage,
    /// When the session was opened, in Unix milliseconds.
    pub opened_at_ms: u64,
    /// Deadline after which the session expires, in Unix milliseconds.
    pub deadline_ms: u64,
}

/// Stage of a session, as the core understands it.
///
/// Distinct from [`HostFundingStatusSubscribeItem`]: that is the wire
/// projection, which carries `resume` on terminal items and is what subscribers
/// see. This is the persisted state machine.
#[derive(Debug, Clone, PartialEq, Eq, Encode, Decode)]
pub enum FundingStage {
    /// Opened; the provider surface has not been entered.
    Created,
    /// Inbound: waiting for the user's deposit on the external side.
    AwaitingDeposit {
        /// Provider window close, in Unix milliseconds.
        expires_at: Option<u64>,
    },
    /// Outbound: waiting for the user to authorize the release.
    AwaitingRelease,
    /// Inside the provider's own flow, stage unknown to the core.
    ProviderSide {
        /// Provider-supplied detail, when one was reported.
        note: Option<String>,
    },
    /// External-side leg seen but not settled.
    Confirming,
    /// Value moving between chains or venues.
    Bridging,
    /// Inbound terminal success: funds observed on chain by the core.
    Delivered {
        /// Amount observed, which may differ from the amount sought.
        credited: FundingAmount,
    },
    /// Outbound terminal success: funds left under the user's authorization.
    Released {
        /// Amount debited.
        debited: FundingAmount,
    },
    /// Terminal failure.
    Failed {
        /// Why it ended.
        reason: FundingFailure,
        /// Amount moved before the failure, which may be non-zero.
        moved: FundingAmount,
    },
}

impl FundingStage {
    /// Whether this stage ends the session.
    pub fn is_terminal(&self) -> bool {
        matches!(
            self,
            Self::Delivered { .. } | Self::Released { .. } | Self::Failed { .. }
        )
    }
}

/// Why a session could not accept a transition.
#[derive(Debug, Clone, PartialEq, Eq, derive_more::Display, derive_more::Error)]
pub enum FundingSessionError {
    /// The session already reached a terminal stage.
    #[display("funding session already settled")]
    AlreadySettled,
    /// The transition does not apply to this session's direction.
    #[display("transition does not apply to this session's direction")]
    WrongDirection,
    /// Persisted session bytes could not be decoded.
    #[display("invalid persisted funding sessions: {reason}")]
    Corrupt {
        /// Decode failure detail.
        reason: String,
    },
    /// The host's storage callback failed.
    #[display("funding session storage failed: {reason}")]
    Storage {
        /// Failure detail.
        reason: String,
    },
}

impl FundingSession {
    /// Open a session in [`FundingStage::Created`].
    pub fn new(
        intent: FundingIntentId,
        owner_product_id: String,
        direction: FundingDirection,
        rail: FundingRail,
        amount: FundingAmount,
        resume: Option<Vec<u8>>,
        now_ms: u64,
    ) -> Self {
        Self {
            intent,
            owner_product_id,
            direction,
            rail,
            amount,
            resume,
            stage: FundingStage::Created,
            opened_at_ms: now_ms,
            deadline_ms: now_ms.saturating_add(SILENT_WINDOW_MS),
        }
    }

    /// Project the current stage onto the wire item subscribers receive.
    ///
    /// `resume` rides only on terminal items, and only for the product that
    /// declared the intent.
    pub fn wire_item(&self, subscriber_product_id: &str) -> HostFundingStatusSubscribeItem {
        let resume = if subscriber_product_id == self.owner_product_id {
            self.resume.clone()
        } else {
            None
        };
        match &self.stage {
            FundingStage::Created | FundingStage::AwaitingDeposit { expires_at: None } => {
                HostFundingStatusSubscribeItem::AwaitingDeposit { expires_at: None }
            }
            FundingStage::AwaitingDeposit { expires_at } => {
                HostFundingStatusSubscribeItem::AwaitingDeposit {
                    expires_at: *expires_at,
                }
            }
            FundingStage::AwaitingRelease => HostFundingStatusSubscribeItem::AwaitingRelease,
            FundingStage::ProviderSide { note } => {
                HostFundingStatusSubscribeItem::ProviderSide { note: note.clone() }
            }
            FundingStage::Confirming => HostFundingStatusSubscribeItem::Confirming,
            FundingStage::Bridging => HostFundingStatusSubscribeItem::Bridging,
            FundingStage::Delivered { credited } => HostFundingStatusSubscribeItem::Delivered {
                credited: *credited,
                resume,
            },
            FundingStage::Released { debited } => HostFundingStatusSubscribeItem::Released {
                debited: *debited,
                resume,
            },
            FundingStage::Failed { reason, moved } => HostFundingStatusSubscribeItem::Failed {
                reason: reason.clone(),
                moved: *moved,
                resume,
            },
        }
    }

    /// Record the core's own on-chain observation that funds arrived.
    ///
    /// Inbound only, and the only path to [`FundingStage::Delivered`]: no
    /// provider report reaches it.
    pub fn observe_arrival(&mut self, credited: FundingAmount) -> Result<(), FundingSessionError> {
        self.guard_open()?;
        if self.direction != FundingDirection::In {
            return Err(FundingSessionError::WrongDirection);
        }
        self.stage = FundingStage::Delivered { credited };
        Ok(())
    }

    /// Record that funds left under the user's authorization.
    ///
    /// Outbound only. Asserts nothing about the off-chain leg.
    pub fn observe_release(&mut self, debited: FundingAmount) -> Result<(), FundingSessionError> {
        self.guard_open()?;
        if self.direction != FundingDirection::Out {
            return Err(FundingSessionError::WrongDirection);
        }
        self.stage = FundingStage::Released { debited };
        Ok(())
    }

    /// Fold a provider report into the session.
    ///
    /// Reports advance presentation, never settlement: `Sent` moves no further
    /// than [`FundingStage::Bridging`], and a report on a settled session is
    /// rejected rather than allowed to rewrite an observed outcome.
    pub fn apply_report(
        &mut self,
        report: &HostFundingReportRequest,
    ) -> Result<(), FundingSessionError> {
        self.guard_open()?;
        match report {
            HostFundingReportRequest::InProgress { note, .. } => {
                self.stage = FundingStage::ProviderSide { note: note.clone() };
            }
            HostFundingReportRequest::Deposited { .. } => {
                self.stage = FundingStage::Confirming;
            }
            HostFundingReportRequest::Bridging { .. } | HostFundingReportRequest::Sent { .. } => {
                self.stage = FundingStage::Bridging;
            }
            HostFundingReportRequest::Failed { reason, .. } => {
                self.stage = FundingStage::Failed {
                    reason: reason.clone(),
                    moved: 0,
                };
            }
            HostFundingReportRequest::SettlementTarget { .. } => {
                if self.direction != FundingDirection::Out {
                    return Err(FundingSessionError::WrongDirection);
                }
                self.stage = FundingStage::AwaitingRelease;
            }
        }
        // Any report is evidence of a live counterparty, so a reporting session
        // earns the longer window.
        self.deadline_ms = self.opened_at_ms.saturating_add(REPORTING_WINDOW_MS);
        Ok(())
    }

    /// Expire the session if its deadline has passed and it is still open.
    ///
    /// Returns whether the session expired. This is the path that guarantees
    /// termination with no provider cooperation whatsoever.
    pub fn expire_if_due(&mut self, now_ms: u64) -> bool {
        if self.stage.is_terminal() || now_ms < self.deadline_ms {
            return false;
        }
        self.stage = FundingStage::Failed {
            reason: FundingFailure::Expired,
            moved: 0,
        };
        true
    }

    fn guard_open(&self) -> Result<(), FundingSessionError> {
        if self.stage.is_terminal() {
            return Err(FundingSessionError::AlreadySettled);
        }
        Ok(())
    }
}

/// Read every persisted session.
pub async fn load_sessions(
    storage: &(impl CoreStorage + ?Sized),
) -> Result<Vec<FundingSession>, FundingSessionError> {
    let Some(blob) = storage
        .read_core_storage(CoreStorageKey::FundingSessions)
        .await
        .map_err(|err| FundingSessionError::Storage { reason: err.reason })?
    else {
        return Ok(Vec::new());
    };
    decode_sessions(&blob)
}

/// Replace the persisted set, dropping sessions that have settled.
///
/// Terminal sessions are delivered once and then forgotten, which is what keeps
/// `resume` from outliving the intent that carried it.
pub async fn store_sessions(
    storage: &(impl CoreStorage + ?Sized),
    sessions: &[FundingSession],
) -> Result<(), FundingSessionError> {
    let live: Vec<FundingSession> = sessions
        .iter()
        .filter(|session| !session.stage.is_terminal())
        .cloned()
        .collect();
    if live.is_empty() {
        return storage
            .clear_core_storage(CoreStorageKey::FundingSessions)
            .await
            .map_err(|err| FundingSessionError::Storage { reason: err.reason });
    }
    storage
        .write_core_storage(CoreStorageKey::FundingSessions, live.encode())
        .await
        .map_err(|err| FundingSessionError::Storage { reason: err.reason })
}

fn decode_sessions(blob: &[u8]) -> Result<Vec<FundingSession>, FundingSessionError> {
    let mut input = blob;
    let sessions =
        Vec::<FundingSession>::decode(&mut input).map_err(|err| FundingSessionError::Corrupt {
            reason: err.to_string(),
        })?;
    if !input.is_empty() {
        return Err(FundingSessionError::Corrupt {
            reason: "trailing bytes".to_string(),
        });
    }
    Ok(sessions)
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::collections::HashMap;
    use std::sync::Mutex;

    use futures::executor::block_on;
    use truapi::latest::GenericError;

    const NOW: u64 = 1_700_000_000_000;
    const OWNER: &str = "wallet.dot";

    #[derive(Default)]
    struct MemStorage {
        inner: Mutex<HashMap<Vec<u8>, Vec<u8>>>,
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

    fn inbound() -> FundingSession {
        FundingSession::new(
            "fs_1".to_string(),
            OWNER.to_string(),
            FundingDirection::In,
            FundingRail::BankOrCard,
            100,
            Some(b"cart-42".to_vec()),
            NOW,
        )
    }

    fn outbound() -> FundingSession {
        FundingSession::new(
            "fs_2".to_string(),
            OWNER.to_string(),
            FundingDirection::Out,
            FundingRail::BankOrCard,
            250,
            None,
            NOW,
        )
    }

    // --- requirement 12: terminates with zero provider reports ---

    #[test]
    fn inbound_reaches_delivered_from_observation_alone() {
        let mut session = inbound();

        session.observe_arrival(100).expect("arrival accepted");

        assert_eq!(session.stage, FundingStage::Delivered { credited: 100 });
    }

    #[test]
    fn silent_session_expires_rather_than_hanging() {
        let mut session = inbound();

        assert!(session.expire_if_due(NOW + SILENT_WINDOW_MS));
        assert_eq!(
            session.stage,
            FundingStage::Failed {
                reason: FundingFailure::Expired,
                moved: 0,
            }
        );
    }

    #[test]
    fn session_does_not_expire_before_its_deadline() {
        let mut session = inbound();

        assert!(!session.expire_if_due(NOW + SILENT_WINDOW_MS - 1));
        assert_eq!(session.stage, FundingStage::Created);
    }

    #[test]
    fn a_reporting_session_gets_a_longer_window_than_a_silent_one() {
        let mut session = inbound();
        session
            .apply_report(&HostFundingReportRequest::InProgress {
                intent: session.intent.clone(),
                note: Some("verifying your ID".to_string()),
            })
            .expect("report accepted");

        // Past the silent window, but still inside the reporting one.
        assert!(!session.expire_if_due(NOW + SILENT_WINDOW_MS + 1));
        assert!(session.expire_if_due(NOW + REPORTING_WINDOW_MS));
    }

    #[test]
    fn outbound_terminates_at_released() {
        let mut session = outbound();

        session.observe_release(250).expect("release accepted");

        assert_eq!(session.stage, FundingStage::Released { debited: 250 });
    }

    // --- requirement 13: observed is never overridden by reported ---

    #[test]
    fn a_failure_report_cannot_override_an_observed_arrival() {
        let mut session = inbound();
        session.observe_arrival(100).expect("arrival accepted");

        let rejected = session.apply_report(&HostFundingReportRequest::Failed {
            intent: session.intent.clone(),
            reason: FundingFailure::ProviderTimeout,
        });

        assert_eq!(rejected, Err(FundingSessionError::AlreadySettled));
        assert_eq!(session.stage, FundingStage::Delivered { credited: 100 });
    }

    #[test]
    fn sent_advances_no_further_than_bridging() {
        let mut session = inbound();

        session
            .apply_report(&HostFundingReportRequest::Sent {
                intent: session.intent.clone(),
            })
            .expect("report accepted");

        assert_eq!(session.stage, FundingStage::Bridging);
    }

    #[test]
    fn expiry_does_not_reopen_a_settled_session() {
        let mut session = inbound();
        session.observe_arrival(100).expect("arrival accepted");

        assert!(!session.expire_if_due(NOW + REPORTING_WINDOW_MS * 10));
        assert_eq!(session.stage, FundingStage::Delivered { credited: 100 });
    }

    // --- direction guards ---

    #[test]
    fn arrival_is_rejected_on_an_outbound_session() {
        let mut session = outbound();

        assert_eq!(
            session.observe_arrival(250),
            Err(FundingSessionError::WrongDirection)
        );
    }

    #[test]
    fn settlement_target_is_rejected_on_an_inbound_session() {
        let mut session = inbound();

        let rejected = session.apply_report(&HostFundingReportRequest::SettlementTarget {
            intent: session.intent.clone(),
            target: truapi::latest::FundingDelivery::Account {
                account: [7u8; 32],
                genesis_hash: [9u8; 32],
            },
        });

        assert_eq!(rejected, Err(FundingSessionError::WrongDirection));
    }

    // --- resume disclosure ---

    #[test]
    fn resume_reaches_only_the_declaring_product() {
        let mut session = inbound();
        session.observe_arrival(100).expect("arrival accepted");

        let to_owner = session.wire_item(OWNER);
        let to_other = session.wire_item("other.dot");

        assert_eq!(
            to_owner,
            HostFundingStatusSubscribeItem::Delivered {
                credited: 100,
                resume: Some(b"cart-42".to_vec()),
            }
        );
        assert_eq!(
            to_other,
            HostFundingStatusSubscribeItem::Delivered {
                credited: 100,
                resume: None,
            }
        );
    }

    #[test]
    fn resume_does_not_ride_non_terminal_items() {
        let session = inbound();

        assert_eq!(
            session.wire_item(OWNER),
            HostFundingStatusSubscribeItem::AwaitingDeposit { expires_at: None }
        );
    }

    #[test]
    fn provider_side_projects_its_note() {
        let mut session = inbound();
        session
            .apply_report(&HostFundingReportRequest::InProgress {
                intent: session.intent.clone(),
                note: Some("verifying your ID".to_string()),
            })
            .expect("report accepted");

        assert_eq!(
            session.wire_item(OWNER),
            HostFundingStatusSubscribeItem::ProviderSide {
                note: Some("verifying your ID".to_string()),
            }
        );
    }

    // --- persistence ---

    #[test]
    fn sessions_round_trip_through_core_storage() {
        let storage = MemStorage::default();
        let session = inbound();

        block_on(store_sessions(&storage, std::slice::from_ref(&session))).expect("stored");
        let loaded = block_on(load_sessions(&storage)).expect("loaded");

        assert_eq!(loaded, vec![session]);
    }

    #[test]
    fn settled_sessions_are_not_persisted() {
        let storage = MemStorage::default();
        let mut session = inbound();
        session.observe_arrival(100).expect("arrival accepted");

        block_on(store_sessions(&storage, &[session])).expect("stored");

        assert!(
            block_on(load_sessions(&storage))
                .expect("loaded")
                .is_empty()
        );
    }

    #[test]
    fn absent_storage_loads_as_empty() {
        let storage = MemStorage::default();

        assert!(
            block_on(load_sessions(&storage))
                .expect("loaded")
                .is_empty()
        );
    }

    #[test]
    fn trailing_bytes_are_rejected_rather_than_ignored() {
        let storage = MemStorage::default();
        let mut blob = vec![inbound()].encode();
        blob.push(0xff);
        block_on(storage.write_core_storage(CoreStorageKey::FundingSessions, blob))
            .expect("written");

        let failed = block_on(load_sessions(&storage));

        assert!(matches!(failed, Err(FundingSessionError::Corrupt { .. })));
    }
}
