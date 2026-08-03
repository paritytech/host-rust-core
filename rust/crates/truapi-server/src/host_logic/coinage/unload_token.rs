//! Unload-token resolution and fee-mode choice.
//!
//! Every unload of a recycler entry consumes exactly one token, so a plan that
//! unloads three groups needs three tokens. Two classes exist: free tokens, a
//! per-period allowance derived from personhood, and paid tokens from a
//! period-specific ring anyone may join for a fee.
//!
//! The caller does not choose the class. Free slots are spent first and paid
//! tokens make up any shortfall, because a free token costs nothing and expires
//! unused at the end of its period.
//!
//! This module is pure. It decides *which* tokens to use given a snapshot of
//! what the chain reports consumed; fetching that snapshot, proving membership
//! and joining the paid ring are the chain layer's work.

use std::collections::BTreeSet;

use super::chain_constants::CoinageChainConstants;
use super::error::CoinageError;
use super::params::CoinageParameters;

/// Which token an unload group should present.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum TokenGrant {
    /// A free slot backed by personhood, identified by its period and counter.
    Free {
        /// Period the slot belongs to.
        period: u32,
        /// Counter within that period.
        counter: u32,
    },
    /// A token from the period's paid ring.
    Paid {
        /// Period whose paid ring backs the token.
        period: u32,
    },
}

impl TokenGrant {
    /// Whether this grant costs the user a fee.
    pub const fn is_paid(&self) -> bool {
        matches!(self, Self::Paid { .. })
    }
}

/// What the chain reports about the user's free-token allowance.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct FreeTokenAvailability {
    /// Periods whose tokens are still eligible, most preferred first.
    ///
    /// The current period comes first; earlier periods appear only while inside
    /// the lookback grace window, which absorbs a transaction prepared just
    /// before a period boundary.
    pub eligible_periods: Vec<u32>,
    /// `(period, counter)` pairs the chain reports already consumed.
    pub consumed: BTreeSet<(u32, u32)>,
}

impl FreeTokenAvailability {
    /// An availability snapshot with nothing consumed.
    pub fn fresh(eligible_periods: Vec<u32>) -> Self {
        Self {
            eligible_periods,
            consumed: BTreeSet::new(),
        }
    }

    /// Whether a specific slot is still free.
    pub fn is_free(&self, period: u32, counter: u32) -> bool {
        !self.consumed.contains(&(period, counter))
    }
}

/// What the chain reports about the paid-token ring.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct PaidRingState {
    /// Period the paid ring belongs to.
    pub period: u32,
    /// Whether the user is already a member of that ring.
    pub is_member: bool,
    /// Whether the fee account can pay to join it.
    pub can_fund_join: bool,
}

/// Which tokens to use, and whether the paid ring must be joined first.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct UnloadTokenPlan {
    /// One grant per unload group, in group order.
    pub grants: Vec<TokenGrant>,
    /// Whether a pre-step extrinsic must join the paid ring before the grants
    /// can be presented.
    pub join_paid_ring: bool,
}

impl UnloadTokenPlan {
    /// How many grants cost a fee.
    pub fn paid_count(&self) -> usize {
        self.grants.iter().filter(|grant| grant.is_paid()).count()
    }
}

/// Choose tokens for `needed` unload groups.
///
/// Free slots are taken in period order, then by ascending counter, so two
/// conformant implementations spend the same slots. `NoUnloadToken` is returned
/// only when neither class can cover the shortfall — that is the distinction
/// between "wait for the next period" and "this wallet cannot unload at all".
pub fn resolve(
    needed: usize,
    free: &FreeTokenAvailability,
    paid: &PaidRingState,
    params: &CoinageParameters,
    constants: &CoinageChainConstants,
) -> Result<UnloadTokenPlan, CoinageError> {
    if needed == 0 {
        return Ok(UnloadTokenPlan {
            grants: Vec::new(),
            join_paid_ring: false,
        });
    }

    // The layer's probe window can never exceed the chain's per-period
    // allowance; probing past it would only ever find slots the chain refuses.
    let search_range = params
        .free_token_counter_search_range
        .min(constants.max_free_unload_tokens_per_period);

    let mut grants = Vec::with_capacity(needed);

    for &period in &free.eligible_periods {
        for counter in 0..search_range {
            if grants.len() == needed {
                break;
            }
            if free.is_free(period, counter) {
                grants.push(TokenGrant::Free { period, counter });
            }
        }
        if grants.len() == needed {
            break;
        }
    }

    if grants.len() == needed {
        return Ok(UnloadTokenPlan {
            grants,
            join_paid_ring: false,
        });
    }

    // Paid tokens make up the shortfall, joining the ring first if necessary.
    if !paid.is_member && !paid.can_fund_join {
        return Err(CoinageError::NoUnloadToken);
    }

    let join_paid_ring = !paid.is_member;
    while grants.len() < needed {
        grants.push(TokenGrant::Paid {
            period: paid.period,
        });
    }

    Ok(UnloadTokenPlan {
        grants,
        join_paid_ring,
    })
}

/// How the network fee for an unload is settled.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum FeeMode {
    /// Paid from the layer's fee account alongside the unload.
    Prepaid,
    /// Deducted from the unloaded value.
    FromOutput,
}

impl FeeMode {
    /// The `max_fee` argument the unload call carries under this mode.
    ///
    /// The pallet requires zero under `Prepaid`; under `FromOutput` the ceiling
    /// must cover the network fee.
    pub const fn max_fee(&self, estimated_fee: u128) -> u128 {
        match self {
            Self::Prepaid => 0,
            Self::FromOutput => estimated_fee,
        }
    }
}

/// Choose a fee mode from the fee account's balance at submission time.
///
/// Prepaid whenever the account can cover the fee, because taking the fee from
/// the output shrinks the unloaded value and forces a different denomination
/// breakdown. The caller never chooses.
pub fn choose_fee_mode(fee_account_balance: u128, estimated_fee: u128) -> FeeMode {
    if fee_account_balance >= estimated_fee {
        FeeMode::Prepaid
    } else {
        FeeMode::FromOutput
    }
}

#[cfg(test)]
mod tests {
    use super::super::chain_constants::next_people_paseo;
    use super::*;

    fn params() -> CoinageParameters {
        CoinageParameters::default()
    }

    fn paid(is_member: bool, can_fund_join: bool) -> PaidRingState {
        PaidRingState {
            period: 42,
            is_member,
            can_fund_join,
        }
    }

    fn resolve_with(
        needed: usize,
        free: &FreeTokenAvailability,
        paid: &PaidRingState,
    ) -> Result<UnloadTokenPlan, CoinageError> {
        resolve(needed, free, paid, &params(), &next_people_paseo())
    }

    #[test]
    fn no_groups_need_no_tokens() {
        let plan = resolve_with(
            0,
            &FreeTokenAvailability::fresh(vec![7]),
            &paid(false, false),
        )
        .expect("zero is always satisfiable");

        assert!(plan.grants.is_empty());
        assert!(!plan.join_paid_ring);
    }

    #[test]
    fn free_slots_are_spent_before_paid_ones() {
        let plan = resolve_with(2, &FreeTokenAvailability::fresh(vec![7]), &paid(true, true))
            .expect("two free slots exist");

        assert_eq!(
            plan.grants,
            vec![
                TokenGrant::Free {
                    period: 7,
                    counter: 0
                },
                TokenGrant::Free {
                    period: 7,
                    counter: 1
                },
            ]
        );
        assert_eq!(plan.paid_count(), 0);
        assert!(!plan.join_paid_ring);
    }

    #[test]
    fn consumed_slots_are_skipped_in_counter_order() {
        let mut free = FreeTokenAvailability::fresh(vec![7]);
        free.consumed.insert((7, 0));
        free.consumed.insert((7, 2));

        let plan = resolve_with(2, &free, &paid(true, true)).expect("counters 1 and 3 are free");

        assert_eq!(
            plan.grants,
            vec![
                TokenGrant::Free {
                    period: 7,
                    counter: 1
                },
                TokenGrant::Free {
                    period: 7,
                    counter: 3
                },
            ]
        );
    }

    #[test]
    fn a_later_period_is_only_reached_once_the_first_is_exhausted() {
        let mut free = FreeTokenAvailability::fresh(vec![8, 7]);
        for counter in 0..params().free_token_counter_search_range {
            free.consumed.insert((8, counter));
        }

        let plan =
            resolve_with(1, &free, &paid(true, true)).expect("the prior period still has slots");

        assert_eq!(
            plan.grants,
            vec![TokenGrant::Free {
                period: 7,
                counter: 0
            }]
        );
    }

    #[test]
    fn paid_tokens_cover_a_shortfall() {
        let mut free = FreeTokenAvailability::fresh(vec![7]);
        for counter in 0..params().free_token_counter_search_range {
            free.consumed.insert((7, counter));
        }

        let plan = resolve_with(2, &free, &paid(true, true)).expect("the paid ring covers it");

        assert_eq!(
            plan.grants,
            vec![
                TokenGrant::Paid { period: 42 },
                TokenGrant::Paid { period: 42 }
            ]
        );
        assert_eq!(plan.paid_count(), 2);
        assert!(!plan.join_paid_ring);
    }

    #[test]
    fn a_mixed_plan_keeps_free_slots_first() {
        let mut free = FreeTokenAvailability::fresh(vec![7]);
        for counter in 1..params().free_token_counter_search_range {
            free.consumed.insert((7, counter));
        }

        let plan = resolve_with(3, &free, &paid(true, true)).expect("one free plus two paid");

        assert_eq!(
            plan.grants[0],
            TokenGrant::Free {
                period: 7,
                counter: 0
            }
        );
        assert_eq!(plan.paid_count(), 2);
    }

    #[test]
    fn joining_the_paid_ring_is_requested_when_not_a_member() {
        let free = FreeTokenAvailability {
            eligible_periods: vec![7],
            consumed: (0..params().free_token_counter_search_range)
                .map(|counter| (7, counter))
                .collect(),
        };

        let plan = resolve_with(1, &free, &paid(false, true)).expect("the join can be funded");

        assert!(plan.join_paid_ring);
        assert_eq!(plan.grants, vec![TokenGrant::Paid { period: 42 }]);
    }

    #[test]
    fn no_free_slots_and_an_unfundable_join_is_a_dead_end() {
        let free = FreeTokenAvailability {
            eligible_periods: vec![7],
            consumed: (0..params().free_token_counter_search_range)
                .map(|counter| (7, counter))
                .collect(),
        };

        assert_eq!(
            resolve_with(1, &free, &paid(false, false)),
            Err(CoinageError::NoUnloadToken)
        );
    }

    #[test]
    fn with_no_eligible_period_the_paid_ring_is_the_only_source() {
        let free = FreeTokenAvailability::fresh(Vec::new());

        let plan = resolve_with(1, &free, &paid(true, true)).expect("paid covers it");

        assert_eq!(plan.grants, vec![TokenGrant::Paid { period: 42 }]);
    }

    #[test]
    fn the_probe_window_never_exceeds_the_chain_allowance() {
        let constants = CoinageChainConstants {
            max_free_unload_tokens_per_period: 2,
            ..next_people_paseo()
        };
        let params = CoinageParameters {
            free_token_counter_search_range: 10,
            ..params()
        };
        let free = FreeTokenAvailability::fresh(vec![7]);

        let plan = resolve(4, &free, &paid(true, true), &params, &constants)
            .expect("two free then two paid");

        // Only counters 0 and 1 exist on this runtime; the rest must be paid.
        assert_eq!(plan.grants.iter().filter(|g| !g.is_paid()).count(), 2);
        assert_eq!(plan.paid_count(), 2);
    }

    #[test]
    fn prepaid_is_chosen_while_the_fee_account_can_cover_the_fee() {
        assert_eq!(choose_fee_mode(1_000, 100), FeeMode::Prepaid);
        assert_eq!(choose_fee_mode(100, 100), FeeMode::Prepaid);
        assert_eq!(choose_fee_mode(99, 100), FeeMode::FromOutput);
    }

    #[test]
    fn the_max_fee_argument_is_zero_only_under_prepaid() {
        assert_eq!(FeeMode::Prepaid.max_fee(500), 0);
        assert_eq!(FeeMode::FromOutput.max_fee(500), 500);
    }
}
