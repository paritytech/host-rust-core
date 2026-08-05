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
//! # The two classes count differently
//!
//! A free token is one `(period, counter)` pair, so a single personhood key covers
//! a whole period's allowance. A paid token's context carries the period and *no*
//! counter, so one paid member key is worth exactly one token per period. Wanting
//! three paid tokens in a period means three keys, three joins and three fees —
//! which is why a paid grant names a slot and the plan carries a list of joins
//! rather than a single flag.
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
    /// A token from the period's paid ring, held by one of the wallet's slots.
    Paid {
        /// Period whose paid ring backs the token.
        period: u32,
        /// Which of the wallet's paid-token keys for that period proves it.
        ///
        /// A paid token's alias is produced in a context carrying the period and
        /// **no counter**, so one key yields exactly one token per period. Two
        /// tokens in the same period therefore mean two slots, two joins and two
        /// fees. This is the difference between the paid ring and the free
        /// allowance, where one personhood key covers the whole period.
        slot: u32,
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

/// What one of the wallet's paid-token slots is worth right now.
///
/// Joining and becoming provable are two steps, not one, and the gap between them
/// is why this carries both facts. `pay_for_recycler_unload_fee_token_with_*`
/// registers the key immediately, but the members pallet onboards it into an actual
/// ring afterwards — and a ring-VRF proof needs the ring. A slot between the two is
/// paid for and unusable, and the correct response is to wait.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct PaidSlot {
    /// Index of the slot within the period.
    pub slot: u32,
    /// Whether the slot's key is registered as a paid-token member.
    ///
    /// Once true this is permanent: the pallet refuses a member key it has already
    /// seen, so a registered key can never be joined again.
    pub joined: bool,
    /// Whether the key has been placed in a ring that can be proved against.
    ///
    /// Implies [`Self::joined`]. False while onboarding is outstanding.
    pub onboarded: bool,
    /// Whether the slot's one token for this period has already been spent.
    ///
    /// A spent slot is dead for the rest of the period: its alias is marked
    /// consumed and its key cannot be re-registered.
    pub spent: bool,
}

impl PaidSlot {
    /// Whether this slot can back a token right now, with no join and no wait.
    pub const fn is_ready(&self) -> bool {
        self.onboarded && !self.spent
    }

    /// Whether paying to join this slot would give the wallet a token.
    ///
    /// A registered-but-not-yet-onboarded slot is neither ready nor joinable:
    /// paying again is refused and there is nothing to do but wait.
    pub const fn is_joinable(&self) -> bool {
        !self.joined && !self.spent
    }
}

/// What the chain reports about the period's paid-token ring.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct PaidRingState {
    /// Period the paid ring belongs to.
    pub period: u32,
    /// Whether the pallet has created this period's collection. A ring that does
    /// not exist cannot be joined, however well funded the wallet is.
    pub collection_exists: bool,
    /// Whether the fee account can pay to join, as a dry run answered it.
    pub can_fund_join: bool,
    /// The wallet's slots for this period, in slot order.
    pub slots: Vec<PaidSlot>,
}

impl PaidRingState {
    /// A state in which the paid ring is unusable, whatever the reason.
    pub fn unavailable(period: u32) -> Self {
        Self {
            period,
            collection_exists: false,
            can_fund_join: false,
            slots: Vec::new(),
        }
    }

    /// Record whether the layer can pay for a join.
    ///
    /// Separate from the chain read because the pallet prices a join from a weight
    /// rather than publishing it, so affordability is the caller's judgement, not
    /// a storage value.
    pub fn with_fundable_joins(mut self, can_fund_join: bool) -> Self {
        self.can_fund_join = can_fund_join;
        self
    }
}

/// Which tokens to use, and which paid slots must be joined first.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct UnloadTokenPlan {
    /// One grant per unload group, in group order.
    pub grants: Vec<TokenGrant>,
    /// Slots whose join extrinsic must land — definitely — before the grants
    /// naming them can be presented.
    ///
    /// One join per slot, each paying its own fee. Empty when every paid grant is
    /// backed by a slot the wallet already holds.
    pub joins: Vec<u32>,
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
            joins: Vec::new(),
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
            joins: Vec::new(),
        });
    }

    // Paid tokens make up the shortfall, one slot per remaining group. Slots the
    // wallet has already joined come first: they are paid for, and a slot that
    // needs joining costs both a fee and a wait for the join to become definite.
    let mut joins = Vec::new();
    let ready = paid.slots.iter().filter(|slot| slot.is_ready());
    for slot in ready {
        if grants.len() == needed {
            break;
        }
        grants.push(TokenGrant::Paid {
            period: paid.period,
            slot: slot.slot,
        });
    }

    if grants.len() < needed && paid.collection_exists && paid.can_fund_join {
        let joinable = paid.slots.iter().filter(|slot| slot.is_joinable());
        for slot in joinable {
            if grants.len() == needed {
                break;
            }
            joins.push(slot.slot);
            grants.push(TokenGrant::Paid {
                period: paid.period,
                slot: slot.slot,
            });
        }
    }

    // Short even after the paid ring: the wallet waits for the next period.
    // Reporting a partial plan would spend the free slots and the join fees and
    // still fail, so nothing is committed.
    if grants.len() < needed {
        return Err(CoinageError::NoUnloadToken);
    }

    Ok(UnloadTokenPlan { grants, joins })
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

    /// A paid ring with `ready` slots already joined and `joinable` more the
    /// wallet could join if `can_fund_join`.
    fn paid_with(ready: u32, joinable: u32, can_fund_join: bool) -> PaidRingState {
        let mut slots = Vec::new();
        for slot in 0..ready {
            slots.push(PaidSlot {
                slot,
                joined: true,
                onboarded: true,
                spent: false,
            });
        }
        for offset in 0..joinable {
            slots.push(PaidSlot {
                slot: ready + offset,
                joined: false,
                onboarded: false,
                spent: false,
            });
        }

        PaidRingState {
            period: 42,
            collection_exists: true,
            can_fund_join,
            slots,
        }
    }

    /// The old two-flag shape, expressed in slots: a wallet that either already
    /// holds plenty of paid tokens or can join for as many as it needs.
    fn paid(is_member: bool, can_fund_join: bool) -> PaidRingState {
        if is_member {
            paid_with(8, 0, can_fund_join)
        } else {
            paid_with(0, 8, can_fund_join)
        }
    }

    /// Every free slot in `period` spent, so only the paid ring is left.
    fn no_free_slots(period: u32) -> FreeTokenAvailability {
        FreeTokenAvailability {
            eligible_periods: vec![period],
            consumed: (0..params().free_token_counter_search_range)
                .map(|counter| (period, counter))
                .collect(),
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
        assert!(plan.joins.is_empty());
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
        assert!(plan.joins.is_empty());
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
        let plan =
            resolve_with(2, &no_free_slots(7), &paid(true, true)).expect("the paid ring covers it");

        // Two groups, two distinct slots: one key cannot back both, because its
        // single alias is consumed by the first.
        assert_eq!(
            plan.grants,
            vec![
                TokenGrant::Paid {
                    period: 42,
                    slot: 0
                },
                TokenGrant::Paid {
                    period: 42,
                    slot: 1
                },
            ]
        );
        assert_eq!(plan.paid_count(), 2);
        assert!(plan.joins.is_empty(), "both slots are already joined");
    }

    #[test]
    fn each_paid_grant_names_its_own_slot() {
        // The whole reason a grant carries a slot: reusing one key for two groups
        // would have the second refused as an already-consumed alias, after the
        // first had spent the fee.
        let plan =
            resolve_with(4, &no_free_slots(7), &paid_with(4, 0, false)).expect("four slots exist");

        let slots: Vec<u32> = plan
            .grants
            .iter()
            .map(|grant| match grant {
                TokenGrant::Paid { slot, .. } => *slot,
                TokenGrant::Free { .. } => unreachable!("no free slots remain"),
            })
            .collect();
        assert_eq!(slots, vec![0, 1, 2, 3]);
    }

    #[test]
    fn a_spent_slot_is_not_offered_again() {
        // A slot's token is gone once used, and its key cannot rejoin, so the
        // wallet must reach past it to the next one.
        let state = PaidRingState {
            period: 42,
            collection_exists: true,
            can_fund_join: true,
            slots: vec![
                PaidSlot {
                    slot: 0,
                    joined: true,
                    onboarded: true,
                    spent: true,
                },
                PaidSlot {
                    slot: 1,
                    joined: true,
                    onboarded: true,
                    spent: false,
                },
            ],
        };

        let plan = resolve_with(1, &no_free_slots(7), &state).expect("slot 1 is unspent");

        assert_eq!(
            plan.grants,
            vec![TokenGrant::Paid {
                period: 42,
                slot: 1
            }]
        );
        assert!(plan.joins.is_empty());
    }

    #[test]
    fn already_joined_slots_are_preferred_over_ones_needing_a_fee() {
        let plan = resolve_with(2, &no_free_slots(7), &paid_with(1, 3, true))
            .expect("one held slot plus one join");

        assert_eq!(
            plan.grants,
            vec![
                TokenGrant::Paid {
                    period: 42,
                    slot: 0
                },
                TokenGrant::Paid {
                    period: 42,
                    slot: 1
                },
            ]
        );
        assert_eq!(plan.joins, vec![1], "only the second slot costs a join");
    }

    #[test]
    fn a_period_whose_collection_does_not_exist_cannot_be_joined() {
        // The pallet creates a period's collection in its own `on_poll`. Until it
        // has, a join has nothing to add a member to, however well funded.
        let state = PaidRingState {
            period: 42,
            collection_exists: false,
            can_fund_join: true,
            slots: vec![PaidSlot {
                slot: 0,
                joined: false,
                onboarded: false,
                spent: false,
            }],
        };

        assert_eq!(
            resolve_with(1, &no_free_slots(7), &state),
            Err(CoinageError::NoUnloadToken)
        );
    }

    #[test]
    fn running_out_of_slots_is_refused_rather_than_partly_planned() {
        // A plan short of one token would spend every free slot and every join fee
        // it did name, then fail on the last group.
        assert_eq!(
            resolve_with(3, &no_free_slots(7), &paid_with(1, 1, true)),
            Err(CoinageError::NoUnloadToken)
        );
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
        let plan =
            resolve_with(1, &no_free_slots(7), &paid(false, true)).expect("the join can be funded");

        assert_eq!(plan.joins, vec![0]);
        assert_eq!(
            plan.grants,
            vec![TokenGrant::Paid {
                period: 42,
                slot: 0
            }]
        );
    }

    #[test]
    fn no_free_slots_and_an_unfundable_join_is_a_dead_end() {
        assert_eq!(
            resolve_with(1, &no_free_slots(7), &paid(false, false)),
            Err(CoinageError::NoUnloadToken)
        );
    }

    #[test]
    fn with_no_eligible_period_the_paid_ring_is_the_only_source() {
        let free = FreeTokenAvailability::fresh(Vec::new());

        let plan = resolve_with(1, &free, &paid(true, true)).expect("paid covers it");

        assert_eq!(
            plan.grants,
            vec![TokenGrant::Paid {
                period: 42,
                slot: 0
            }]
        );
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
