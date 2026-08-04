//! The external-offload phase decision (`coinage-layer.md` §8.6).
//!
//! Sending value out of coinage is the one primitive that cannot be planned in a
//! single pass. Only recycler entries can be offboarded — a coin has to become an
//! entry first — and an entry is not usable the moment it is created, because §5.3
//! makes it wait out a decorrelation delay. So the operation loops: work out what
//! is possible right now, do that, look again.
//!
//! This module is the "look again" step, and nothing else. It reads a snapshot and
//! names the next phase; submitting, waiting and recycling belong to the caller.
//! Keeping it pure is what makes the four-way choice testable without a chain,
//! which matters because three of the four outcomes are indistinguishable from the
//! outside — "wait", "wait longer" and "you cannot do this" all look like an
//! operation that has not finished.
//!
//! # Records the operation already holds count as available
//!
//! An offload locks everything it touches for its whole life, including entries it
//! created along the way. Those entries are `LockedFor` this operation, which makes
//! them unselectable to everyone — including, naively, to the operation that owns
//! them. The decision therefore asks "available, or held by me?", or an offload
//! would recycle coins forever and never offboard what it had just made.

use core::time::Duration;

use super::chain_constants::CoinageChainConstants;
use super::coin::{Coin, CoinState};
use super::entry::{EntryLocalState, RecyclerEntry};
use super::types::{
    Amount, CoinIndex, DenominationExponent, EntryIndex, OperationHandle, RingLocation, Timestamp,
};

/// Entries of one denomination in one ring, offboarded together.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct OffboardGroup {
    /// Where the entries sit on chain.
    pub ring: RingLocation,
    /// Denomination shared by the group.
    pub exponent: DenominationExponent,
    /// Entries to unload.
    pub entries: Vec<EntryIndex>,
}

impl OffboardGroup {
    /// Total value the group's entries carry.
    pub fn value(&self) -> Amount {
        Amount::from_cents(
            self.exponent
                .value()
                .cents()
                .saturating_mul(self.entries.len() as u64),
        )
    }
}

/// What an offload should do next.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum OffloadPhase {
    /// Unload these groups to the destination. The last phase.
    Offboard {
        /// Groups to offboard, in deterministic order.
        groups: Vec<OffboardGroup>,
        /// Value the groups carry beyond the requested amount, which the same
        /// extrinsic must reload into fresh entries rather than let land as a
        /// coin.
        surplus: Amount,
    },
    /// Turn these coins into entries first, then look again.
    Recycle {
        /// Coins to recycle, in the layer's canonical order.
        coins: Vec<(CoinIndex, DenominationExponent)>,
    },
    /// Nothing can move yet. Sleep until `until`, then look again.
    Wait {
        /// When to re-plan.
        until: Timestamp,
        /// Why the wait is expected to help.
        reason: WaitReason,
    },
    /// The purse cannot cover the amount, now or later.
    Insufficient {
        /// Amount asked for.
        requested: Amount,
        /// Everything the purse holds that could ever reach the destination.
        available: Amount,
    },
}

/// Why an offload is waiting.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum WaitReason {
    /// Entries exist and cover the amount, but are still inside their
    /// decorrelation delay.
    EntriesRipening,
    /// Coins that could cover the deficit are in transient states — locked by
    /// another operation, pending confirmation, or held by a chain lock — so a
    /// short retry may find them.
    CoinsInTransit,
}

/// Decide the next phase of an offload.
///
/// `held_by` is the offload's own handle: records it locked earlier are its to
/// use, and treating them as unavailable would loop forever.
#[allow(clippy::too_many_arguments)]
pub fn decide(
    coins: &[Coin],
    entries: &[RecyclerEntry],
    amount: Amount,
    allow_degraded: bool,
    constants: &CoinageChainConstants,
    retry_interval: Duration,
    now: Timestamp,
    held_by: OperationHandle,
) -> OffloadPhase {
    // 1. Entries that could be offboarded right now.
    let ready: Vec<&RecyclerEntry> = ordered_entries(entries)
        .into_iter()
        .filter(|entry| usable_entry(entry, held_by) && offboardable(entry, allow_degraded, now))
        .collect();

    if let Some((groups, surplus)) = cover(&ready, amount, constants) {
        return OffloadPhase::Offboard { groups, surplus };
    }

    // 2. Entries that will be offboardable once their delay elapses.
    let ripening: Vec<&RecyclerEntry> = ordered_entries(entries)
        .into_iter()
        .filter(|entry| {
            usable_entry(entry, held_by)
                && !offboardable(entry, allow_degraded, now)
                && entry.ring.is_some()
        })
        .collect();
    let ready_value = total(ready.iter().copied());
    let ripening_value = total(ripening.iter().copied());

    if ready_value
        .checked_add(ripening_value)
        .unwrap_or(ready_value)
        >= amount
        && let Some(until) = ripening.iter().map(|entry| entry.ready_at).max()
    {
        return OffloadPhase::Wait {
            // A delay that has already elapsed would spin; the caller's retry
            // interval bounds how often re-planning happens either way.
            until,
            reason: WaitReason::EntriesRipening,
        };
    }

    // 3. Coins that can become entries now.
    let deficit = amount.saturating_sub(ready_value);
    let spendable: Vec<&Coin> = ordered_coins(coins)
        .into_iter()
        .filter(|coin| usable_coin(coin, held_by) && !coin.is_chain_locked(now))
        .collect();

    if total_coins(spendable.iter().copied()) >= deficit && !spendable.is_empty() {
        return OffloadPhase::Recycle {
            coins: take_for(&spendable, deficit),
        };
    }

    // 4. Coins that might become available shortly: anything not terminal.
    let salvageable: Vec<&Coin> = ordered_coins(coins)
        .into_iter()
        .filter(|coin| coin.state != CoinState::Spent)
        .collect();
    if total_coins(salvageable.iter().copied()) >= deficit {
        return OffloadPhase::Wait {
            until: now.saturating_add(retry_interval),
            reason: WaitReason::CoinsInTransit,
        };
    }

    OffloadPhase::Insufficient {
        requested: amount,
        available: total_coins(salvageable.iter().copied())
            .checked_add(ready_value)
            .and_then(|sum| sum.checked_add(ripening_value))
            .unwrap_or(ready_value),
    }
}

/// Whether an entry belongs to this operation or to nobody.
fn usable_entry(entry: &RecyclerEntry, held_by: OperationHandle) -> bool {
    match entry.local {
        EntryLocalState::Available => true,
        EntryLocalState::LockedFor(holder) => holder == held_by,
        _ => false,
    }
}

/// Whether a coin belongs to this operation or to nobody.
fn usable_coin(coin: &Coin, held_by: OperationHandle) -> bool {
    match coin.state {
        CoinState::Available => true,
        CoinState::LockedFor(holder) => holder == held_by,
        _ => false,
    }
}

/// Whether the chain would accept an unload of this entry right now.
fn offboardable(entry: &RecyclerEntry, allow_degraded: bool, now: Timestamp) -> bool {
    let anonymity = if allow_degraded {
        entry.on_chain.is_usable()
    } else {
        entry.on_chain.is_full_anonymity()
    };
    anonymity && entry.jitter_elapsed(now) && !entry.is_alias_locked(now) && entry.ring.is_some()
}

/// Entries in the layer's canonical order: largest first, then lowest ring, then
/// lowest index.
fn ordered_entries(entries: &[RecyclerEntry]) -> Vec<&RecyclerEntry> {
    let mut ordered: Vec<&RecyclerEntry> = entries
        .iter()
        .filter(|entry| entry.local != EntryLocalState::Consumed)
        .collect();
    ordered.sort_by(|left, right| {
        right
            .exponent
            .cmp(&left.exponent)
            .then(ring_key(left).cmp(&ring_key(right)))
            .then(left.index.cmp(&right.index))
    });
    ordered
}

/// Coins in the layer's canonical order: largest first, then oldest, then lowest
/// index.
fn ordered_coins(coins: &[Coin]) -> Vec<&Coin> {
    let mut ordered: Vec<&Coin> = coins.iter().collect();
    ordered.sort_by(|left, right| {
        right
            .exponent
            .cmp(&left.exponent)
            .then(right.age.cmp(&left.age))
            .then(left.index.cmp(&right.index))
    });
    ordered
}

fn ring_key(entry: &RecyclerEntry) -> u32 {
    entry.ring.map_or(u32::MAX, |ring| ring.index.0)
}

fn total<'a>(entries: impl Iterator<Item = &'a RecyclerEntry>) -> Amount {
    entries.map(|entry| entry.value()).sum()
}

fn total_coins<'a>(coins: impl Iterator<Item = &'a Coin>) -> Amount {
    coins.map(|coin| coin.value()).sum()
}

/// Coins to recycle so their value covers `deficit`, largest first.
fn take_for(coins: &[&Coin], deficit: Amount) -> Vec<(CoinIndex, DenominationExponent)> {
    let mut taken = Vec::new();
    let mut covered = Amount::ZERO;

    for coin in coins {
        if covered >= deficit {
            break;
        }
        covered = covered.checked_add(coin.value()).unwrap_or(covered);
        taken.push((coin.index, coin.exponent));
    }

    taken
}

/// Group ready entries into the extrinsics that would carry `amount`, plus the
/// surplus those groups would produce.
///
/// Returns `None` when the ready entries cannot cover the amount. Groups respect
/// the runtime's consolidation cap, since each is one extrinsic.
fn cover(
    ready: &[&RecyclerEntry],
    amount: Amount,
    constants: &CoinageChainConstants,
) -> Option<(Vec<OffboardGroup>, Amount)> {
    if amount.is_zero() {
        return Some((Vec::new(), Amount::ZERO));
    }

    let cap = constants.max_consolidation.max(1) as usize;
    let mut groups: Vec<OffboardGroup> = Vec::new();
    let mut covered = Amount::ZERO;

    for entry in ready {
        if covered >= amount {
            break;
        }
        let Some(ring) = entry.ring else {
            continue;
        };

        covered = covered.checked_add(entry.value())?;
        match groups.iter_mut().find(|group| {
            group.ring == ring && group.exponent == entry.exponent && group.entries.len() < cap
        }) {
            Some(group) => group.entries.push(entry.index),
            None => groups.push(OffboardGroup {
                ring,
                exponent: entry.exponent,
                entries: vec![entry.index],
            }),
        }
    }

    (covered >= amount).then(|| (groups, covered.saturating_sub(amount)))
}

#[cfg(test)]
mod tests {
    use super::super::chain_constants::next_people_paseo;
    use super::super::params::CoinageParameters;
    use super::super::types::{CoinAge, PurseId, RevisionIndex, RingIndex};
    use super::*;

    const NOW: Timestamp = Timestamp(1_000_000);
    const HANDLE: OperationHandle = OperationHandle(1);
    const OTHER: OperationHandle = OperationHandle(2);

    fn exponent(value: i8) -> DenominationExponent {
        DenominationExponent::new(value).expect("exponent is in range")
    }

    fn ring(index: u32) -> RingLocation {
        RingLocation::new(RingIndex(index), RevisionIndex(0))
    }

    fn retry() -> Duration {
        CoinageParameters::default().external_offload_retry_interval
    }

    /// A coin the chain confirms.
    fn coin(index: u32, exponent_value: i8) -> Coin {
        let mut coin = Coin::pending(PurseId::MAIN, CoinIndex(index), exponent(exponent_value));
        coin.observe_populated(CoinAge(0)).expect("observes");
        coin
    }

    /// An entry in a full-anonymity ring, past its jitter delay.
    fn ready_entry(index: u32, exponent_value: i8, ring_index: u32) -> RecyclerEntry {
        let mut entry = RecyclerEntry::allocated(
            PurseId::MAIN,
            EntryIndex(index),
            exponent(exponent_value),
            NOW,
            Duration::ZERO,
        );
        entry.observe_ring(ring(ring_index), 64, &CoinageParameters::default());
        entry
    }

    /// An entry still inside its decorrelation delay.
    fn ripening_entry(index: u32, exponent_value: i8, delay: Duration) -> RecyclerEntry {
        let mut entry = RecyclerEntry::allocated(
            PurseId::MAIN,
            EntryIndex(index),
            exponent(exponent_value),
            NOW,
            delay,
        );
        entry.observe_ring(ring(1), 64, &CoinageParameters::default());
        entry
    }

    fn decide_for(
        coins: &[Coin],
        entries: &[RecyclerEntry],
        cents: u64,
        allow_degraded: bool,
    ) -> OffloadPhase {
        decide(
            coins,
            entries,
            Amount::from_cents(cents),
            allow_degraded,
            &next_people_paseo(),
            retry(),
            NOW,
            HANDLE,
        )
    }

    #[test]
    fn ready_entries_that_cover_the_amount_go_straight_to_offboard() {
        let entries = vec![ready_entry(0, 4, 3), ready_entry(1, 4, 3)];

        let phase = decide_for(&[], &entries, 32, true);

        match phase {
            OffloadPhase::Offboard { groups, surplus } => {
                assert_eq!(groups.len(), 1, "one ring, one extrinsic");
                assert_eq!(groups[0].entries.len(), 2);
                assert_eq!(groups[0].value(), Amount::from_cents(32));
                assert_eq!(surplus, Amount::ZERO);
            }
            other => panic!("expected Offboard, got {other:?}"),
        }
    }

    #[test]
    fn a_group_that_overshoots_reports_the_surplus_it_must_reload() {
        // §8.6: surplus must be reloaded into fresh entries by the same extrinsic.
        // Letting it land as a coin would re-link the entry-side anonymity set to a
        // fresh account, which is the whole thing the ring exists to prevent.
        let entries = vec![ready_entry(0, 4, 3)];

        let phase = decide_for(&[], &entries, 8, true);

        match phase {
            OffloadPhase::Offboard { groups, surplus } => {
                assert_eq!(groups[0].value(), Amount::from_cents(16));
                assert_eq!(surplus, Amount::from_cents(8));
            }
            other => panic!("expected Offboard, got {other:?}"),
        }
    }

    #[test]
    fn entries_in_two_rings_become_two_groups() {
        let entries = vec![ready_entry(0, 4, 3), ready_entry(1, 4, 7)];

        let phase = decide_for(&[], &entries, 32, true);

        match phase {
            OffloadPhase::Offboard { groups, .. } => {
                assert_eq!(groups.len(), 2, "a group cannot span two rings");
                assert_eq!(groups[0].ring, ring(3));
                assert_eq!(groups[1].ring, ring(7));
            }
            other => panic!("expected Offboard, got {other:?}"),
        }
    }

    #[test]
    fn entries_still_ripening_are_waited_for_rather_than_worked_around() {
        let delay = Duration::from_secs(3_600);
        let entries = vec![ripening_entry(0, 4, delay)];

        let phase = decide_for(&[], &entries, 16, true);

        assert_eq!(
            phase,
            OffloadPhase::Wait {
                until: NOW.saturating_add(delay),
                reason: WaitReason::EntriesRipening,
            },
            "the value is there; only the delay is not done"
        );
    }

    #[test]
    fn coins_are_recycled_when_entries_cannot_cover_the_amount() {
        let coins = vec![coin(0, 4), coin(1, 3)];

        let phase = decide_for(&coins, &[], 16, true);

        assert_eq!(
            phase,
            OffloadPhase::Recycle {
                coins: vec![(CoinIndex(0), exponent(4))]
            },
            "the largest coin alone covers it, in canonical order"
        );
    }

    #[test]
    fn ready_entries_are_used_first_and_only_the_deficit_is_recycled() {
        let coins = vec![coin(0, 4)];
        let entries = vec![ready_entry(0, 3, 3)];

        // 8 cents ready, 24 wanted: the 16-cent coin covers the 16-cent deficit.
        let phase = decide_for(&coins, &entries, 24, true);

        assert_eq!(
            phase,
            OffloadPhase::Recycle {
                coins: vec![(CoinIndex(0), exponent(4))]
            }
        );
    }

    #[test]
    fn a_coin_in_transit_is_waited_for_with_the_retry_interval() {
        // Locked by another operation: it may come back, and a short retry is the
        // difference between "wait" and "you cannot do this".
        let mut locked = coin(0, 4);
        locked.lock_for(OTHER).expect("locks");
        let coins = vec![locked];

        let phase = decide_for(&coins, &[], 16, true);

        assert_eq!(
            phase,
            OffloadPhase::Wait {
                until: NOW.saturating_add(retry()),
                reason: WaitReason::CoinsInTransit,
            }
        );
    }

    #[test]
    fn a_chain_locked_coin_is_waited_for_not_recycled() {
        // Selecting it would build an extrinsic the runtime refuses at validate.
        let mut locked = coin(0, 4);
        locked.observe_chain_lock(Some(NOW.saturating_add(Duration::from_secs(60))));
        let coins = vec![locked];

        let phase = decide_for(&coins, &[], 16, true);

        assert!(matches!(
            phase,
            OffloadPhase::Wait {
                reason: WaitReason::CoinsInTransit,
                ..
            }
        ));
    }

    #[test]
    fn an_empty_purse_cannot_offload_and_says_so() {
        let phase = decide_for(&[], &[], 16, true);

        assert_eq!(
            phase,
            OffloadPhase::Insufficient {
                requested: Amount::from_cents(16),
                available: Amount::ZERO,
            }
        );
    }

    #[test]
    fn records_the_offload_already_holds_are_its_own_to_use() {
        // The loop's central subtlety: an offload locks what it creates, and if it
        // then read its own locks as unavailable it would recycle forever.
        let mut held = ready_entry(0, 4, 3);
        held.lock_for(HANDLE).expect("locks");

        let phase = decide_for(&[], &[held], 16, true);
        assert!(
            matches!(phase, OffloadPhase::Offboard { .. }),
            "an entry this operation holds is offboardable: {phase:?}"
        );

        // Held by somebody else, the same entry is not usable at all.
        let mut theirs = ready_entry(0, 4, 3);
        theirs.lock_for(OTHER).expect("locks");
        assert_eq!(
            decide_for(&[], &[theirs], 16, true),
            OffloadPhase::Insufficient {
                requested: Amount::from_cents(16),
                available: Amount::ZERO,
            }
        );
    }

    #[test]
    fn a_degraded_ring_is_refused_unless_the_caller_opted_in() {
        // An offload reveals the unloaded value on chain, so the anonymity set
        // should be at full strength unless the caller says otherwise.
        let mut degraded = RecyclerEntry::allocated(
            PurseId::MAIN,
            EntryIndex(0),
            exponent(4),
            NOW,
            Duration::ZERO,
        );
        degraded.observe_ring(ring(3), 2, &CoinageParameters::default());

        let refused = decide_for(&[], &[degraded], 16, false);
        assert!(
            matches!(
                refused,
                OffloadPhase::Wait { .. } | OffloadPhase::Insufficient { .. }
            ),
            "a thin ring is not offboarded by default: {refused:?}"
        );

        assert!(matches!(
            decide_for(&[], &[degraded], 16, true),
            OffloadPhase::Offboard { .. }
        ));
    }

    #[test]
    fn a_group_never_exceeds_what_the_runtime_consolidates() {
        let constants = CoinageChainConstants {
            max_consolidation: 2,
            ..next_people_paseo()
        };
        let entries: Vec<RecyclerEntry> = (0..3).map(|index| ready_entry(index, 4, 3)).collect();

        let phase = decide(
            &[],
            &entries,
            Amount::from_cents(48),
            true,
            &constants,
            retry(),
            NOW,
            HANDLE,
        );

        match phase {
            OffloadPhase::Offboard { groups, .. } => {
                assert_eq!(groups.len(), 2, "three entries, cap of two");
                assert_eq!(groups[0].entries.len(), 2);
                assert_eq!(groups[1].entries.len(), 1);
            }
            other => panic!("expected Offboard, got {other:?}"),
        }
    }
}
