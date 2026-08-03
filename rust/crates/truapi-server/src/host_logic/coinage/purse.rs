//! Purses and the balance projection over their contents.
//!
//! A purse is a named, firewalled coinage balance with an isolated derivation
//! namespace. Index `i` in one purse and index `i` in another address different
//! on-chain accounts, so purse membership is implied by derivation rather than
//! stored as a pointer.

use parity_scale_codec::{Decode, Encode};

use super::coin::Coin;
use super::entry::RecyclerEntry;
use super::types::{Amount, CoinIndex, EntryIndex, PurseId, Timestamp};

/// A purse record.
#[derive(Debug, Clone, PartialEq, Eq, Encode, Decode)]
pub struct Purse {
    /// Identifier, reserved for the main purse or freshly assigned.
    pub id: PurseId,
    /// User-facing name.
    pub name: String,
    /// Next coin index to hand out. Never decreases, so an index is never
    /// reused even after every coin in the purse is spent.
    pub next_coin_index: CoinIndex,
    /// Next recycler-entry index to hand out, with the same no-reuse guarantee.
    pub next_entry_index: EntryIndex,
}

impl Purse {
    /// Create a purse with empty index spaces.
    pub fn new(id: PurseId, name: String) -> Self {
        Self {
            id,
            name,
            next_coin_index: CoinIndex(0),
            next_entry_index: EntryIndex(0),
        }
    }

    /// Whether this is the main purse, which exists by construction and cannot
    /// be deleted.
    pub fn is_main(&self) -> bool {
        self.id.is_main()
    }

    /// Hand out the next coin index.
    pub fn allocate_coin_index(&mut self) -> CoinIndex {
        let index = self.next_coin_index;
        self.next_coin_index = CoinIndex(index.0 + 1);
        index
    }

    /// Hand out the next recycler-entry index.
    pub fn allocate_entry_index(&mut self) -> EntryIndex {
        let index = self.next_entry_index;
        self.next_entry_index = EntryIndex(index.0 + 1);
        index
    }
}

/// The three-value balance the layer publishes for a purse.
#[derive(Debug, Clone, Copy, Default, PartialEq, Eq, Encode, Decode)]
pub struct PurseBalance {
    /// Available coins plus every currently selectable recycler entry.
    pub spendable: Amount,
    /// The same, counting only entries at full anonymity. Never exceeds
    /// [`PurseBalance::spendable`]; the difference is the value sitting in
    /// degraded rings.
    pub spendable_strict: Amount,
    /// Value that exists but cannot be spent right now: coins that are pending
    /// or locked, and entries that are missing, waiting, locked, or still
    /// inside their jitter delay.
    pub pending: Amount,
}

/// A purse together with its current balance.
#[derive(Debug, Clone, PartialEq, Eq, Encode, Decode)]
pub struct PurseInfo {
    /// Purse identifier.
    pub id: PurseId,
    /// User-facing name.
    pub name: String,
    /// Spendable value.
    pub spendable: Amount,
    /// Spendable value at full anonymity.
    pub spendable_strict: Amount,
    /// Value not currently spendable.
    pub pending: Amount,
}

impl PurseInfo {
    /// Combine a purse record with a computed balance.
    pub fn new(purse: &Purse, balance: PurseBalance) -> Self {
        Self {
            id: purse.id,
            name: purse.name.clone(),
            spendable: balance.spendable,
            spendable_strict: balance.spendable_strict,
            pending: balance.pending,
        }
    }
}

/// Project a purse's coins and recycler entries onto its balance triple.
///
/// Terminal records — spent coins and consumed entries — contribute nothing;
/// they are retained only so their indices are never reused.
pub fn compute_balance<'a>(
    coins: impl IntoIterator<Item = &'a Coin>,
    entries: impl IntoIterator<Item = &'a RecyclerEntry>,
    now: Timestamp,
) -> PurseBalance {
    use super::coin::CoinState;
    use super::entry::EntryLocalState;

    let mut balance = PurseBalance::default();

    for coin in coins {
        match coin.state {
            CoinState::Available => {
                balance.spendable = balance
                    .spendable
                    .checked_add(coin.value())
                    .unwrap_or(balance.spendable);
                balance.spendable_strict = balance
                    .spendable_strict
                    .checked_add(coin.value())
                    .unwrap_or(balance.spendable_strict);
            }
            CoinState::Pending | CoinState::LockedFor(_) => {
                balance.pending = balance
                    .pending
                    .checked_add(coin.value())
                    .unwrap_or(balance.pending);
            }
            CoinState::Spent => {}
        }
    }

    for entry in entries {
        if entry.local == EntryLocalState::Consumed {
            continue;
        }

        let value = entry.value();

        if entry.is_selectable(now, true) {
            balance.spendable = balance
                .spendable
                .checked_add(value)
                .unwrap_or(balance.spendable);

            if entry.is_selectable(now, false) {
                balance.spendable_strict = balance
                    .spendable_strict
                    .checked_add(value)
                    .unwrap_or(balance.spendable_strict);
            }
        } else {
            balance.pending = balance
                .pending
                .checked_add(value)
                .unwrap_or(balance.pending);
        }
    }

    balance
}

#[cfg(test)]
mod tests {
    use core::time::Duration;

    use super::super::entry::{EntryOnChainState, RecyclerEntry};
    use super::super::params::CoinageParameters;
    use super::super::types::{CoinAge, DenominationExponent, OperationHandle, RingIndex};
    use super::*;

    const NOW: Timestamp = Timestamp(1_000_000);

    fn exponent(value: u8) -> DenominationExponent {
        DenominationExponent::new(value).expect("exponent is in range")
    }

    fn available_coin(index: u32, exponent_value: u8) -> Coin {
        let mut coin = Coin::pending(PurseId::MAIN, CoinIndex(index), exponent(exponent_value));
        coin.observe_populated(CoinAge(0))
            .expect("observe is valid");
        coin
    }

    fn entry_with(index: u32, exponent_value: u8, on_chain: EntryOnChainState) -> RecyclerEntry {
        let mut entry = RecyclerEntry::allocated(
            PurseId::MAIN,
            EntryIndex(index),
            exponent(exponent_value),
            Timestamp(0),
            Duration::ZERO,
        );
        entry.ring = Some(RingIndex(1));
        entry.on_chain = on_chain;
        entry
    }

    #[test]
    fn a_new_purse_starts_both_index_spaces_at_zero() {
        let purse = Purse::new(PurseId::MAIN, "Main".to_string());

        assert!(purse.is_main());
        assert_eq!(purse.next_coin_index, CoinIndex(0));
        assert_eq!(purse.next_entry_index, EntryIndex(0));
    }

    #[test]
    fn index_allocation_never_repeats() {
        let mut purse = Purse::new(PurseId(1), "Savings".to_string());

        let first = purse.allocate_coin_index();
        let second = purse.allocate_coin_index();
        let entry = purse.allocate_entry_index();

        assert_eq!(first, CoinIndex(0));
        assert_eq!(second, CoinIndex(1));
        assert_eq!(purse.next_coin_index, CoinIndex(2));
        assert_eq!(entry, EntryIndex(0));
        assert_eq!(purse.next_entry_index, EntryIndex(1));
    }

    #[test]
    fn coin_and_entry_index_spaces_are_independent() {
        let mut purse = Purse::new(PurseId(1), "Savings".to_string());

        purse.allocate_coin_index();
        purse.allocate_coin_index();

        assert_eq!(purse.allocate_entry_index(), EntryIndex(0));
    }

    #[test]
    fn an_empty_purse_has_a_zero_balance() {
        let balance = compute_balance(&[], &[], NOW);

        assert_eq!(balance, PurseBalance::default());
    }

    #[test]
    fn available_coins_count_towards_both_spendable_figures() {
        let coins = vec![available_coin(0, 3), available_coin(1, 2)];

        let balance = compute_balance(&coins, &[], NOW);

        assert_eq!(balance.spendable, Amount::from_cents(12));
        assert_eq!(balance.spendable_strict, Amount::from_cents(12));
        assert_eq!(balance.pending, Amount::ZERO);
    }

    #[test]
    fn pending_and_locked_coins_count_as_pending() {
        let mut locked = available_coin(0, 4);
        locked.lock_for(OperationHandle(1)).expect("lock is valid");
        let coins = vec![
            locked,
            Coin::pending(PurseId::MAIN, CoinIndex(1), exponent(3)),
        ];

        let balance = compute_balance(&coins, &[], NOW);

        assert_eq!(balance.spendable, Amount::ZERO);
        assert_eq!(balance.pending, Amount::from_cents(24));
    }

    #[test]
    fn spent_coins_count_nowhere() {
        let mut spent = available_coin(0, 5);
        spent.lock_for(OperationHandle(1)).expect("lock is valid");
        spent
            .mark_spent(OperationHandle(1))
            .expect("spend is valid");

        let balance = compute_balance(&[spent], &[], NOW);

        assert_eq!(balance, PurseBalance::default());
    }

    #[test]
    fn degraded_entries_separate_the_two_spendable_figures() {
        let entries = vec![
            entry_with(0, 4, EntryOnChainState::Ready),
            entry_with(1, 3, EntryOnChainState::Degraded(2)),
        ];

        let balance = compute_balance(&[], &entries, NOW);

        assert_eq!(balance.spendable, Amount::from_cents(24));
        assert_eq!(balance.spendable_strict, Amount::from_cents(16));
        assert_eq!(balance.pending, Amount::ZERO);
    }

    #[test]
    fn unusable_entries_count_as_pending() {
        let entries = vec![
            entry_with(0, 4, EntryOnChainState::Waiting),
            entry_with(1, 3, EntryOnChainState::Missing),
        ];

        let balance = compute_balance(&[], &entries, NOW);

        assert_eq!(balance.spendable, Amount::ZERO);
        assert_eq!(balance.spendable_strict, Amount::ZERO);
        assert_eq!(balance.pending, Amount::from_cents(24));
    }

    #[test]
    fn an_entry_inside_its_jitter_window_counts_as_pending() {
        let params = CoinageParameters::default();
        let mut entry = RecyclerEntry::allocated(
            PurseId::MAIN,
            EntryIndex(0),
            exponent(4),
            NOW,
            Duration::from_secs(60),
        );
        entry.observe_ring(RingIndex(1), 32, &params);

        let balance = compute_balance(&[], core::slice::from_ref(&entry), NOW);

        assert_eq!(balance.spendable, Amount::ZERO);
        assert_eq!(balance.pending, Amount::from_cents(16));
    }

    #[test]
    fn consumed_entries_count_nowhere() {
        let mut entry = entry_with(0, 4, EntryOnChainState::Ready);
        entry.lock_for(OperationHandle(1)).expect("lock is valid");
        entry
            .mark_consumed(OperationHandle(1))
            .expect("consume is valid");

        let balance = compute_balance(&[], core::slice::from_ref(&entry), NOW);

        assert_eq!(balance, PurseBalance::default());
    }

    #[test]
    fn strict_spendable_never_exceeds_spendable() {
        let coins = vec![available_coin(0, 3)];
        let entries = vec![
            entry_with(0, 4, EntryOnChainState::Ready),
            entry_with(1, 2, EntryOnChainState::Degraded(1)),
            entry_with(2, 5, EntryOnChainState::Waiting),
        ];

        let balance = compute_balance(&coins, &entries, NOW);

        assert!(balance.spendable_strict <= balance.spendable);
        assert_eq!(balance.spendable, Amount::from_cents(8 + 16 + 4));
        assert_eq!(balance.spendable_strict, Amount::from_cents(8 + 16));
        assert_eq!(balance.pending, Amount::from_cents(32));
    }

    #[test]
    fn purse_info_carries_the_balance_alongside_identity() {
        let purse = Purse::new(PurseId(7), "Groceries".to_string());
        let balance = PurseBalance {
            spendable: Amount::from_cents(10),
            spendable_strict: Amount::from_cents(6),
            pending: Amount::from_cents(4),
        };

        let info = PurseInfo::new(&purse, balance);

        assert_eq!(info.id, PurseId(7));
        assert_eq!(info.name, "Groceries");
        assert_eq!(info.spendable, Amount::from_cents(10));
        assert_eq!(info.spendable_strict, Amount::from_cents(6));
        assert_eq!(info.pending, Amount::from_cents(4));
    }
}
