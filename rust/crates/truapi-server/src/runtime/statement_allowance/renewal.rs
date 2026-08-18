//! Proactive renewal of statement-store allowances across period boundaries.
//!
//! Allowances are claimed per UTC-day period and stop being renewed at the
//! boundary, so a long-lived host must re-register every account it promised to
//! keep allowed (RFC-0010 assigns renewal to the Account Holder). They are not
//! revoked the instant the period ends: `Resources.StmtStoreGraceWindow` keeps
//! an ended period's allowances active until cleanup catches up, 172800 seconds
//! on `paseo-next-v2` as of 2026-08-15. This module is the
//! chain-pure pass: given already-resolved targets, register each for the
//! requested period. Scheduling and target persistence live in
//! `signing_host::allowance_renewal`.
//!
//! A host owns the schedule. The core answers when the next pass is due and what
//! a pass achieved; it never asks to be woken, because the period arithmetic a
//! host would need is derivable from the clock and the grace window leaves days
//! of slack. Three layers cover it, and only the first needs the operating
//! system: a scheduled wake for an app nobody opens, a pass on session
//! activation for an app somebody does, and on-demand allocation, which covers
//! the account of a product asking for an allowance but not the rest of the
//! ledger.
//!
//! A caller reading [`StatementRenewalReport`] to answer an OS scheduler should
//! treat every `Registered` or `AlreadyAllocated` as success, a `Failed` as worth
//! retrying on the next opportunistic wake, and exhaustion as success: retrying
//! cannot free a slot, only time or a replacement can. Exhaustion still needs
//! reporting somewhere a person can see, which no surface does yet. The host
//! READMEs under `ios/truapi-host` and `android/truapi-host` carry the
//! platform-specific form of this.

use std::time::Duration;

use futures::lock::Mutex;
use tracing::{debug, info, warn};

use super::collection::PersonhoodCollection;
use super::extension::{ChainState, Metadata};
use super::rpc::RpcClient;
use super::slot::{STATEMENT_STORE_PERIOD_SECONDS, SlotError};
use super::{
    CollectionCandidate, CollectionMembership, PooledRegistrationParams, RegistrationOutcome,
    StatementAllowanceError, register_statement_account_pooled, scan_collections,
};

/// Cap between renewal ticks for the in-process loop.
///
/// A retry rhythm, not a deadline. An allowance stays usable for
/// `Resources.StmtStoreGraceWindow` past its period boundary, which is 48 hours
/// on `paseo-next-v2`, so a pass has ample slack and this only decides how
/// promptly a transient failure is retried. A host scheduling its own wake-ups
/// does not need this cadence; one pass per period is enough.
const MAX_TICK_INTERVAL: Duration = Duration::from_secs(3_600);
/// Margin after a period boundary before the boundary tick fires, so the
/// chain has rotated to the new period by the time we scan slots.
const PERIOD_BOUNDARY_MARGIN: Duration = Duration::from_secs(120);

/// Why one target's renewal failed, and whether the host had no slot left.
///
/// The distinction drives the rest of the pass, so it is read off the typed
/// error rather than its rendered text.
#[derive(Debug, Clone, PartialEq, Eq)]
struct RenewalFailure {
    reason: String,
    slots_exhausted: bool,
}

impl From<StatementAllowanceError> for RenewalFailure {
    fn from(err: StatementAllowanceError) -> Self {
        Self {
            slots_exhausted: matches!(
                err,
                StatementAllowanceError::Slot(SlotError::NoFreeStatementStoreSlot { .. })
            ),
            reason: err.to_string(),
        }
    }
}

/// One resolved renewal target: account id plus a label for reports.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ResolvedRenewalTarget {
    /// Human-readable name used in logs and reports.
    pub label: String,
    /// Account to keep allowed.
    pub account_id: [u8; 32],
}

/// Outcome of renewing one target.
#[derive(Debug, Clone, PartialEq, Eq)]
#[cfg_attr(not(target_arch = "wasm32"), derive(uniffi::Enum))]
pub enum TargetRenewalStatus {
    /// The extrinsic reached a block; the target holds `seq` this period.
    Registered {
        /// Claimed slot sequence.
        seq: u32,
        /// Block hash the extrinsic landed in.
        block_hash: String,
    },
    /// The target already held a slot this period; nothing submitted.
    AlreadyAllocated {
        /// Existing slot sequence.
        seq: u32,
    },
    /// Registration failed; the target is retried on the next tick.
    Failed {
        /// Failure detail.
        reason: String,
    },
    /// Not attempted: the host ran out of slots earlier in the pass.
    SkippedExhausted,
}

/// What one target's renewal produced, paired with the label that identifies it
/// in the ledger.
#[derive(Debug, Clone, PartialEq, Eq)]
#[cfg_attr(not(target_arch = "wasm32"), derive(uniffi::Record))]
pub struct StatementRenewalOutcome {
    /// Ledger label for the renewed target.
    pub label: String,
    /// What the pass did for this target.
    pub status: TargetRenewalStatus,
}

/// Summary of one renewal pass.
#[derive(Debug, Clone, PartialEq, Eq)]
#[cfg_attr(not(target_arch = "wasm32"), derive(uniffi::Record))]
pub struct StatementRenewalReport {
    /// Period the pass registered for.
    pub period: u32,
    /// Per-target outcomes in ledger order.
    pub outcomes: Vec<StatementRenewalOutcome>,
    /// Labels of targets this pass dropped because a different identity
    /// promised them.
    ///
    /// Dropping is silent otherwise: a pruned target simply stops appearing in
    /// `outcomes`, and the surface has no way to list the ledger, so a host
    /// could only infer it from an absence. A raw account target does not
    /// survive a change of root entropy, so this is how a host learns to
    /// re-track one.
    pub pruned: Vec<String>,
    /// Whether the pass hit slot exhaustion for this period.
    pub slots_exhausted: bool,
}

/// Chain context shared by every registration in one renewal pass.
pub struct RenewalChainContext<'a> {
    /// People-chain RPC connection.
    pub rpc: &'a RpcClient,
    /// Decoded runtime metadata.
    pub metadata: &'a Metadata,
    /// Signed-extension chain state.
    pub chain_state: &'a ChainState,
    /// Every collection the host can derive aliases for, so an allowance already
    /// held in a collection whose ring cannot currently be proved is still seen.
    pub candidates: &'a [CollectionCandidate],
    /// Every collection the host can prove membership in, widest budget first.
    /// Renewal pools slots across all of them, so a device with full personhood
    /// renews against the combined budget rather than one collection's share.
    pub memberships: &'a [CollectionMembership],
}

/// Register every target for `period`, continuing past per-target failures
/// and stopping early once the host's slots for the period are exhausted
/// (remaining targets are reported as skipped).
///
/// Slots claimed earlier in the pass are protected from replacement by later
/// targets. Without that, a pass with more targets than the period has slots
/// takes each slot back off the target before it: the run would undo its own
/// work and never settle. Protecting them turns that into an exhaustion report,
/// which is the honest answer when the ledger wants more slots than exist.
///
/// `registration_lock` is held per target, not for the whole pass, so an
/// on-demand allocation sharing the lock waits at most one registration.
pub async fn renew_targets(
    context: &RenewalChainContext<'_>,
    period: u32,
    targets: &[ResolvedRenewalTarget],
    registration_lock: &Mutex<()>,
) -> StatementRenewalReport {
    let mut results = Vec::with_capacity(targets.len());
    let mut claimed: Vec<(PersonhoodCollection, u32)> = Vec::new();
    for target in targets {
        let result = {
            let _guard = registration_lock.lock().await;
            let scans = match scan_collections(
                context.rpc,
                context.metadata,
                context.candidates,
                period,
                &target.account_id,
                true,
            )
            .await
            {
                Ok(scans) => scans,
                Err(err) => {
                    results.push(Err(RenewalFailure::from(err)));
                    continue;
                }
            };
            register_statement_account_pooled(
                context.rpc,
                context.metadata,
                context.chain_state,
                &scans,
                context.memberships,
                PooledRegistrationParams {
                    target: &target.account_id,
                    period,
                    reuse_existing: true,
                    // Renewal exists to keep the ledger's targets alive across a
                    // period boundary, so it may reclaim space when full.
                    allow_eviction: true,
                    protected: &claimed,
                },
            )
            .await
            .map_err(RenewalFailure::from)
        };
        log_target_result(period, &target.label, &result);
        if let Ok(outcome) = &result {
            match outcome {
                RegistrationOutcome::Registered {
                    seq, collection, ..
                }
                | RegistrationOutcome::AlreadyAllocated { seq, collection } => {
                    claimed.push((*collection, *seq));
                }
            }
        }
        let exhausted = matches!(&result, Err(failure) if failure.slots_exhausted);
        results.push(result);
        if exhausted {
            break;
        }
    }
    fold_outcomes(period, targets, results)
}

/// Delay until the next renewal tick: hourly, but always shortly after each
/// period boundary rather than before it. The margin is about the chain's clock,
/// not urgency; see the inline note below.
pub fn next_tick_delay(now_seconds: u64) -> Duration {
    let next_boundary =
        (now_seconds / STATEMENT_STORE_PERIOD_SECONDS + 1) * STATEMENT_STORE_PERIOD_SECONDS;
    let until_boundary = next_boundary - now_seconds;
    let until_after_boundary = Duration::from_secs(until_boundary) + PERIOD_BOUNDARY_MARGIN;
    // Once the boundary is within an hour, wait for it plus the margin rather
    // than capping: a capped tick can land inside the margin, where the local
    // clock reports the new period but the chain has not rotated into it, and
    // the pass would scan slots for a period the chain does not agree on.
    if MAX_TICK_INTERVAL.as_secs() >= until_boundary {
        until_after_boundary
    } else {
        MAX_TICK_INTERVAL
    }
}

fn log_target_result(
    period: u32,
    label: &str,
    result: &Result<RegistrationOutcome, RenewalFailure>,
) {
    match result {
        Ok(RegistrationOutcome::Registered {
            block_hash, seq, ..
        }) => info!(period, label, seq, %block_hash, "renewed statement-store allowance"),
        Ok(RegistrationOutcome::AlreadyAllocated { seq, .. }) => {
            debug!(
                period,
                label, seq, "statement-store allowance already fresh"
            );
        }
        Err(failure) => {
            warn!(period, label, reason = %failure.reason, "statement-store renewal failed");
        }
    }
}

/// Pair each target with its registration result; targets past the end of
/// `results` were never attempted (the pass stopped on slot exhaustion).
fn fold_outcomes(
    period: u32,
    targets: &[ResolvedRenewalTarget],
    results: Vec<Result<RegistrationOutcome, RenewalFailure>>,
) -> StatementRenewalReport {
    let mut slots_exhausted = false;
    let mut results = results.into_iter();
    let outcomes = targets
        .iter()
        .map(|target| {
            let status = match results.next() {
                Some(Ok(RegistrationOutcome::Registered {
                    block_hash, seq, ..
                })) => TargetRenewalStatus::Registered { seq, block_hash },
                Some(Ok(RegistrationOutcome::AlreadyAllocated { seq, .. })) => {
                    TargetRenewalStatus::AlreadyAllocated { seq }
                }
                Some(Err(failure)) => {
                    slots_exhausted |= failure.slots_exhausted;
                    TargetRenewalStatus::Failed {
                        reason: failure.reason,
                    }
                }
                None => TargetRenewalStatus::SkippedExhausted,
            };
            StatementRenewalOutcome {
                label: target.label.clone(),
                status,
            }
        })
        .collect();
    StatementRenewalReport {
        period,
        outcomes,
        // fold_outcomes only sees targets that survived to be renewed; the
        // caller that read the ledger attaches what it dropped.
        pruned: Vec::new(),
        slots_exhausted,
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    /// The failure a slot-exhausted registration produces.
    fn exhausted_failure() -> RenewalFailure {
        StatementAllowanceError::Slot(SlotError::NoFreeStatementStoreSlot { period: 7, max: 8 })
            .into()
    }

    /// A two-target pass against a full period must place the second target in a
    /// different slot from the first. If claimed slots were not protected, the
    /// second target would take the slot the first just got, and a pass with more
    /// targets than slots would never settle.
    #[test]
    fn a_pass_does_not_take_back_the_slot_it_just_claimed() {
        use parity_scale_codec::Encode;
        use subxt_rpcs::RpcClient as HostRpcClient;

        use crate::runtime::statement_allowance::CollectionMembership;
        use crate::runtime::statement_allowance::extension::{ChainState, Metadata};
        use crate::runtime::statement_allowance::proof;
        use crate::runtime::statement_allowance::ring::RingParams;
        use crate::runtime::statement_allowance::rpc::RpcClient;
        use crate::runtime::statement_allowance::rpc::testing::ScriptedRpc;

        const FIXTURE: &[u8] =
            include_bytes!("../../../tests/fixtures/paseo-next-v2-metadata.scale");
        const NOW: u64 = 10_000_000;

        /// One occupied slot entry, oldest first by `seq`.
        fn entry(account: [u8; 32], since: u64) -> String {
            format!(r#""0x{}""#, hex::encode((account, 0u32, since).encode()))
        }
        fn clock() -> String {
            format!(r#""0x{}""#, hex::encode((NOW * 1_000).encode()))
        }

        let metadata = Metadata::decode(FIXTURE).unwrap();
        let chain_state = ChainState {
            spec_version: 1_000_000,
            transaction_version: 1,
            genesis_hash: [0xab; 32],
            nonce: 0,
        };
        let entropy = [0x11; 32];
        // One collection, so this stays a test of cross-target protection rather
        // than of pooling; pooling has its own tests.
        let memberships = [CollectionMembership {
            entropy,
            ring: RingParams {
                collection: PersonhoodCollection::LitePeople,
                members: vec![proof::member_key(entropy)],
                exponent: 9,
                ring_index: 0,
                block_hash: "0xfinal".to_string(),
            },
        }];
        let targets = [
            target_with("first", [0xa1; 32]),
            target_with("second", [0xa2; 32]),
        ];

        // Per target: ten occupied slots (seq 0 oldest), the chain clock, the ring
        // revision, then the post-submit verification read. The scripted chain
        // does not mutate, so both passes see the same table; only the protection
        // of slot 0 can push the second target elsewhere.
        let mut owned = Vec::new();
        for target in &targets {
            owned.extend((0..10u64).map(|seq| entry([0x99; 32], 1_000 + seq)));
            owned.push(clock());
            owned.push("null".to_string());
            owned.push(entry(target.account_id, NOW));
        }
        let responses: Vec<&str> = owned.iter().map(String::as_str).collect();
        let scripted = ScriptedRpc::new(responses);
        scripted.script_subscription([r#"{"inBlock":"0xb10c"}"#]);
        scripted.script_subscription([r#"{"inBlock":"0xb10d"}"#]);
        let rpc = RpcClient::new(HostRpcClient::new(scripted));

        let candidates = [CollectionCandidate {
            collection: PersonhoodCollection::LitePeople,
            entropy,
        }];
        let context = RenewalChainContext {
            rpc: &rpc,
            metadata: &metadata,
            chain_state: &chain_state,
            candidates: &candidates,
            memberships: &memberships,
        };
        let lock = Mutex::new(());
        let report = futures::executor::block_on(renew_targets(&context, 7, &targets, &lock));

        let seqs: Vec<u32> = report
            .outcomes
            .iter()
            .filter_map(|outcome| match outcome.status {
                TargetRenewalStatus::Registered { seq, .. }
                | TargetRenewalStatus::AlreadyAllocated { seq } => Some(seq),
                _ => None,
            })
            .collect();
        assert_eq!(
            seqs,
            vec![0, 1],
            "the second target must not reclaim the first target's slot: {:?}",
            report.outcomes
        );
    }

    fn target_with(label: &str, account_id: [u8; 32]) -> ResolvedRenewalTarget {
        ResolvedRenewalTarget {
            label: label.to_string(),
            account_id,
        }
    }

    #[test]
    fn only_a_missing_slot_counts_as_exhaustion() {
        assert!(exhausted_failure().slots_exhausted);

        let other: RenewalFailure = StatementAllowanceError::BulletinAuthorizationTimeout.into();
        assert!(!other.slots_exhausted);
    }

    fn target(label: &str) -> ResolvedRenewalTarget {
        ResolvedRenewalTarget {
            label: label.to_string(),
            account_id: [0u8; 32],
        }
    }

    fn outcome(label: &str, status: TargetRenewalStatus) -> StatementRenewalOutcome {
        StatementRenewalOutcome {
            label: label.to_string(),
            status,
        }
    }

    #[test]
    fn tick_delay_caps_at_one_hour_mid_day() {
        let mid_day = 86_400 * 20_000 + 43_200;
        assert_eq!(next_tick_delay(mid_day), Duration::from_secs(3_600));
    }

    #[test]
    fn tick_delay_lands_after_the_period_boundary() {
        let just_before_boundary = 86_400 * 20_001 - 10;
        assert_eq!(
            next_tick_delay(just_before_boundary),
            Duration::from_secs(10 + 120)
        );
    }

    #[test]
    fn tick_delay_never_lands_inside_the_post_boundary_margin() {
        let boundary = 86_400 * 20_001;
        // Every start in the last two hours before a boundary.
        for offset in 1..=7_200 {
            let now = boundary - offset;
            let landing = now + next_tick_delay(now).as_secs();
            assert!(
                landing < boundary || landing >= boundary + PERIOD_BOUNDARY_MARGIN.as_secs(),
                "tick from {now} lands at {landing}, inside the margin after {boundary}"
            );
        }
    }

    #[test]
    fn tick_delay_waits_for_the_boundary_once_it_is_within_an_hour() {
        let boundary = 86_400 * 20_001;
        // Exactly one hour out, the cap used to land the tick on the boundary.
        assert_eq!(
            next_tick_delay(boundary - 3_600),
            Duration::from_secs(3_600) + PERIOD_BOUNDARY_MARGIN
        );
    }

    #[test]
    fn tick_delay_at_boundary_reverts_to_hourly() {
        assert_eq!(next_tick_delay(86_400 * 20_001), Duration::from_secs(3_600));
    }

    #[test]
    fn mid_list_failure_does_not_stop_the_pass() {
        let targets = [target("a"), target("b"), target("c")];
        let report = fold_outcomes(
            7,
            &targets,
            vec![
                Ok(RegistrationOutcome::AlreadyAllocated {
                    seq: 1,
                    collection: PersonhoodCollection::LitePeople,
                }),
                Err(RenewalFailure {
                    reason: "rpc timeout".to_string(),
                    slots_exhausted: false,
                }),
                Ok(RegistrationOutcome::Registered {
                    block_hash: "0xabc".to_string(),
                    seq: 2,
                    ring_index: 0,
                    collection: PersonhoodCollection::LitePeople,
                }),
            ],
        );
        assert_eq!(
            report,
            StatementRenewalReport {
                period: 7,
                outcomes: vec![
                    outcome("a", TargetRenewalStatus::AlreadyAllocated { seq: 1 }),
                    outcome(
                        "b",
                        TargetRenewalStatus::Failed {
                            reason: "rpc timeout".to_string()
                        }
                    ),
                    outcome(
                        "c",
                        TargetRenewalStatus::Registered {
                            seq: 2,
                            block_hash: "0xabc".to_string()
                        }
                    ),
                ],
                pruned: Vec::new(),
                slots_exhausted: false,
            }
        );
    }

    #[test]
    fn exhaustion_skips_remaining_targets() {
        let targets = [target("a"), target("b"), target("c")];
        let report = fold_outcomes(
            7,
            &targets,
            vec![
                Ok(RegistrationOutcome::AlreadyAllocated {
                    seq: 0,
                    collection: PersonhoodCollection::LitePeople,
                }),
                Err(exhausted_failure()),
            ],
        );
        assert_eq!(
            report,
            StatementRenewalReport {
                period: 7,
                outcomes: vec![
                    outcome("a", TargetRenewalStatus::AlreadyAllocated { seq: 0 }),
                    outcome(
                        "b",
                        TargetRenewalStatus::Failed {
                            reason: exhausted_failure().reason
                        }
                    ),
                    outcome("c", TargetRenewalStatus::SkippedExhausted),
                ],
                pruned: Vec::new(),
                slots_exhausted: true,
            }
        );
    }
}
