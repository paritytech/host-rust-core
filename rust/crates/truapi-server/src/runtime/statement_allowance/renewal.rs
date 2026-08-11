//! Proactive renewal of statement-store allowances across period boundaries.
//!
//! Allowances are claimed per UTC-day period and die at the boundary, so a
//! long-lived host must re-register every account it promised to keep allowed
//! (RFC-0010 assigns renewal to the Account Holder). This module is the
//! chain-pure pass: given already-resolved targets, register each for the
//! requested period. Scheduling and target persistence live in
//! `signing_host::allowance_renewal`.

use std::time::Duration;

use futures::lock::Mutex;
use tracing::{debug, info, warn};

use super::extension::{ChainState, Metadata};
use super::ring::RingParams;
use super::rpc::RpcClient;
use super::slot::{STATEMENT_STORE_PERIOD_SECONDS, SlotError};
use super::{
    RegistrationOutcome, RegistrationParams, StatementAllowanceError, register_statement_account,
};

/// Cap between renewal ticks, mirroring the on-chain grace period after a
/// period boundary.
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

/// Summary of one renewal pass.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct StatementRenewalReport {
    /// Period the pass registered for.
    pub period: u32,
    /// Per-target `(label, status)` in ledger order.
    pub outcomes: Vec<(String, TargetRenewalStatus)>,
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
    /// Ring the host's membership proof is built against.
    pub ring: &'a RingParams,
}

/// Register every target for `period`, continuing past per-target failures
/// and stopping early once the host's slots for the period are exhausted
/// (remaining targets are reported as skipped).
///
/// `registration_lock` is held per target, not for the whole pass, so an
/// on-demand allocation sharing the lock waits at most one registration.
pub async fn renew_targets(
    context: &RenewalChainContext<'_>,
    entropy: [u8; 32],
    period: u32,
    targets: &[ResolvedRenewalTarget],
    registration_lock: &Mutex<()>,
) -> StatementRenewalReport {
    let mut results = Vec::with_capacity(targets.len());
    for target in targets {
        let result = {
            let _guard = registration_lock.lock().await;
            register_statement_account(
                context.rpc,
                context.metadata,
                context.chain_state,
                entropy,
                RegistrationParams {
                    target: &target.account_id,
                    period,
                    ring: context.ring,
                    reuse_existing: true,
                },
            )
            .await
            .map_err(RenewalFailure::from)
        };
        log_target_result(period, &target.label, &result);
        let exhausted = matches!(&result, Err(failure) if failure.slots_exhausted);
        results.push(result);
        if exhausted {
            break;
        }
    }
    fold_outcomes(period, targets, results)
}

/// Delay until the next renewal tick: hourly, but always shortly after each
/// period boundary so expired allowances are refreshed within the grace window.
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
        Ok(RegistrationOutcome::AlreadyAllocated { seq }) => {
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
                Some(Ok(RegistrationOutcome::AlreadyAllocated { seq })) => {
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
            (target.label.clone(), status)
        })
        .collect();
    StatementRenewalReport {
        period,
        outcomes,
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
                Ok(RegistrationOutcome::AlreadyAllocated { seq: 1 }),
                Err(RenewalFailure {
                    reason: "rpc timeout".to_string(),
                    slots_exhausted: false,
                }),
                Ok(RegistrationOutcome::Registered {
                    block_hash: "0xabc".to_string(),
                    seq: 2,
                    ring_index: 0,
                }),
            ],
        );
        assert_eq!(
            report,
            StatementRenewalReport {
                period: 7,
                outcomes: vec![
                    (
                        "a".to_string(),
                        TargetRenewalStatus::AlreadyAllocated { seq: 1 }
                    ),
                    (
                        "b".to_string(),
                        TargetRenewalStatus::Failed {
                            reason: "rpc timeout".to_string()
                        }
                    ),
                    (
                        "c".to_string(),
                        TargetRenewalStatus::Registered {
                            seq: 2,
                            block_hash: "0xabc".to_string()
                        }
                    ),
                ],
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
                Ok(RegistrationOutcome::AlreadyAllocated { seq: 0 }),
                Err(exhausted_failure()),
            ],
        );
        assert_eq!(
            report,
            StatementRenewalReport {
                period: 7,
                outcomes: vec![
                    (
                        "a".to_string(),
                        TargetRenewalStatus::AlreadyAllocated { seq: 0 }
                    ),
                    (
                        "b".to_string(),
                        TargetRenewalStatus::Failed {
                            reason: exhausted_failure().reason
                        }
                    ),
                    ("c".to_string(), TargetRenewalStatus::SkippedExhausted),
                ],
                slots_exhausted: true,
            }
        );
    }
}
