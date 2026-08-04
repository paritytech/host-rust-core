//! Coin records and their lifecycle.
//!
//! A coin is a chain-level NFT of a fixed dotUSD denomination, addressed by an
//! account derived from the layer's root entropy, the coin's purse, and its
//! index. `Spent` is terminal but the record is retained: a coin index is never
//! reused, because the account may already have appeared in a transfer memo
//! passed out of band.

use parity_scale_codec::{Decode, Encode};

use super::error::InvalidTransition;
use super::types::{
    Amount, CoinAge, CoinIndex, DenominationExponent, OperationHandle, PurseId, Timestamp,
};

const SUBJECT: &str = "coin";

/// Lifecycle state of a coin.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Encode, Decode)]
pub enum CoinState {
    /// Created locally as a future output of an in-flight operation; the chain
    /// account has not been observed yet.
    Pending,
    /// The chain confirms the account holds a coin. Selectable.
    Available,
    /// Held by an in-flight operation. Not selectable.
    LockedFor(OperationHandle),
    /// Terminal. The account is empty, or the coin was exported.
    Spent,
}

impl CoinState {
    /// A short label for diagnostics.
    pub const fn label(&self) -> &'static str {
        match self {
            Self::Pending => "pending",
            Self::Available => "available",
            Self::LockedFor(_) => "locked",
            Self::Spent => "spent",
        }
    }

    /// The operation holding this coin, if any.
    pub const fn locked_by(&self) -> Option<OperationHandle> {
        match self {
            Self::LockedFor(handle) => Some(*handle),
            _ => None,
        }
    }
}

/// A coin the layer controls.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Encode, Decode)]
pub struct Coin {
    /// Purse owning the coin. Together with [`Coin::index`] this is its
    /// identity; membership is implied by derivation.
    pub purse: PurseId,
    /// Derivation index within the purse.
    pub index: CoinIndex,
    /// Denomination.
    pub exponent: DenominationExponent,
    /// Transfers and splits the coin has undergone, as last observed on chain.
    pub age: CoinAge,
    /// Lifecycle state.
    pub state: CoinState,
    /// When the chain's own lock on this coin expires, as last observed.
    ///
    /// Orthogonal to [`Coin::state`], which is the layer's business: a coin can
    /// be locally available and still refused by the chain. The pallet writes
    /// this after a dispatch that used the coin as its origin fails, restoring
    /// the coin but holding it for `2^retries` times
    /// `CoinFailureLockPeriod` to stop a failing extrinsic being resubmitted in
    /// a tight loop.
    pub locked_until: Option<Timestamp>,
}

impl Coin {
    /// Record a coin the layer expects an in-flight operation to produce.
    pub fn pending(purse: PurseId, index: CoinIndex, exponent: DenominationExponent) -> Self {
        Self {
            purse,
            index,
            exponent,
            age: CoinAge::default(),
            state: CoinState::Pending,
            locked_until: None,
        }
    }

    /// The coin's value.
    pub fn value(&self) -> Amount {
        self.exponent.value()
    }

    /// Whether selection may consider this coin.
    ///
    /// Both locks have to be clear: the layer's own, and the chain's. Selecting
    /// a chain-locked coin builds an extrinsic the runtime rejects at validate,
    /// after the proofs and any unload token that went into it are already
    /// spent.
    pub fn is_selectable(&self, now: Timestamp) -> bool {
        self.state == CoinState::Available && !self.is_chain_locked(now)
    }

    /// Whether the chain is still holding its own lock on this coin.
    pub fn is_chain_locked(&self, now: Timestamp) -> bool {
        self.locked_until.is_some_and(|until| now < until)
    }

    /// Whether the chain still accepts the coin, given its age cap.
    pub fn is_usable(&self, chain_coin_max_age: CoinAge) -> bool {
        self.age < chain_coin_max_age
    }

    /// Whether the coin-age sweep should recycle this coin.
    pub fn needs_recycling(&self, recycle_at_age: CoinAge, now: Timestamp) -> bool {
        self.is_selectable(now) && self.age >= recycle_at_age
    }

    /// Record the chain's lock expiry, or its absence.
    ///
    /// Applied unconditionally: the chain's lock is a fact about the account,
    /// independent of what the layer is doing with the record, and it must be
    /// possible to clear it once the chain drops it.
    pub fn observe_chain_lock(&mut self, locked_until: Option<Timestamp>) {
        self.locked_until = locked_until;
    }

    /// Record a chain observation that the account holds a coin of the given
    /// age.
    ///
    /// Valid while `Pending` (first sighting) or `Available` (age refresh). A
    /// locked coin is left alone: its owning operation decides the outcome.
    pub fn observe_populated(&mut self, age: CoinAge) -> Result<(), InvalidTransition> {
        match self.state {
            CoinState::Pending | CoinState::Available => {
                self.age = age;
                self.state = CoinState::Available;
                Ok(())
            }
            _ => Err(InvalidTransition::new(
                SUBJECT,
                self.state.label(),
                "observe as populated",
            )),
        }
    }

    /// Lock the coin for an operation that is preparing.
    pub fn lock_for(&mut self, handle: OperationHandle) -> Result<(), InvalidTransition> {
        match self.state {
            CoinState::Available => {
                self.state = CoinState::LockedFor(handle);
                Ok(())
            }
            _ => Err(InvalidTransition::new(SUBJECT, self.state.label(), "lock")),
        }
    }

    /// Return the coin to the selectable pool.
    ///
    /// Covers both release paths: the operation aborted before submitting
    /// anything, and the operation failed after submission with the account
    /// still populated.
    pub fn release(&mut self, handle: OperationHandle) -> Result<(), InvalidTransition> {
        match self.state {
            CoinState::LockedFor(holder) if holder == handle => {
                self.state = CoinState::Available;
                Ok(())
            }
            _ => Err(InvalidTransition::new(
                SUBJECT,
                self.state.label(),
                "release",
            )),
        }
    }

    /// Retire a coin that was never created, because the transaction meant to
    /// produce it did not take effect.
    ///
    /// Terminal, like [`Self::mark_spent`], and for the same reason: the
    /// derivation index must never be handed out again. The account is empty
    /// either way — the difference is only whether it was ever populated, which
    /// nothing downstream depends on.
    pub fn abandon(&mut self) -> Result<(), InvalidTransition> {
        match self.state {
            CoinState::Pending => {
                self.state = CoinState::Spent;
                Ok(())
            }
            _ => Err(InvalidTransition::new(
                SUBJECT,
                self.state.label(),
                "abandon",
            )),
        }
    }

    /// Retire a coin a definitely-successful transaction just materialized, whose
    /// secret has now left the layer (§8.4).
    ///
    /// Accepts `Pending` alone, which is exactly the state such a coin is in: the
    /// transaction that created it has settled, so the account is populated, but
    /// observation has not caught up and the record has never been `Available`. A
    /// coin the *operation holds* is retired through [`Self::mark_spent`] instead,
    /// because that is its owning operation consuming it.
    pub fn mark_exported(&mut self) -> Result<(), InvalidTransition> {
        if self.state != CoinState::Pending {
            return Err(InvalidTransition::new(
                SUBJECT,
                self.state.label(),
                "export",
            ));
        }
        self.state = CoinState::Spent;
        Ok(())
    }

    /// Retire the coin after its owning operation consumed it.
    pub fn mark_spent(&mut self, handle: OperationHandle) -> Result<(), InvalidTransition> {
        match self.state {
            CoinState::LockedFor(holder) if holder == handle => {
                self.state = CoinState::Spent;
                Ok(())
            }
            _ => Err(InvalidTransition::new(
                SUBJECT,
                self.state.label(),
                "mark spent",
            )),
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    /// A fixed "now" for the tests that do not exercise the chain lock.
    const NOW: Timestamp = Timestamp(1_000_000);

    fn exponent(value: i8) -> DenominationExponent {
        DenominationExponent::new(value).expect("exponent is in range")
    }

    fn available_coin() -> Coin {
        let mut coin = Coin::pending(PurseId::MAIN, CoinIndex(0), exponent(4));
        coin.observe_populated(CoinAge(0))
            .expect("pending observes");
        coin
    }

    #[test]
    fn a_new_coin_is_pending_and_unselectable() {
        let coin = Coin::pending(PurseId::MAIN, CoinIndex(7), exponent(3));

        assert_eq!(coin.state, CoinState::Pending);
        assert!(!coin.is_selectable(NOW));
        assert_eq!(coin.value(), Amount::from_cents(8));
    }

    #[test]
    fn first_chain_observation_makes_a_pending_coin_available() {
        let mut coin = Coin::pending(PurseId::MAIN, CoinIndex(0), exponent(2));

        coin.observe_populated(CoinAge(3))
            .expect("transition is valid");

        assert_eq!(coin.state, CoinState::Available);
        assert_eq!(coin.age, CoinAge(3));
        assert!(coin.is_selectable(NOW));
    }

    #[test]
    fn observation_refreshes_the_age_of_an_available_coin() {
        let mut coin = available_coin();

        coin.observe_populated(CoinAge(5))
            .expect("refresh is valid");

        assert_eq!(coin.age, CoinAge(5));
    }

    #[test]
    fn a_locked_coin_ignores_chain_observation() {
        let mut coin = available_coin();
        coin.lock_for(OperationHandle(1)).expect("lock is valid");

        let rejected = coin.observe_populated(CoinAge(9));

        assert!(rejected.is_err());
        assert_eq!(coin.state, CoinState::LockedFor(OperationHandle(1)));
    }

    #[test]
    fn locking_removes_the_coin_from_selection() {
        let mut coin = available_coin();

        coin.lock_for(OperationHandle(4)).expect("lock is valid");

        assert!(!coin.is_selectable(NOW));
        assert_eq!(coin.state.locked_by(), Some(OperationHandle(4)));
    }

    #[test]
    fn a_coin_cannot_be_locked_twice() {
        let mut coin = available_coin();
        coin.lock_for(OperationHandle(1))
            .expect("first lock is valid");

        assert!(coin.lock_for(OperationHandle(2)).is_err());
        assert_eq!(coin.state, CoinState::LockedFor(OperationHandle(1)));
    }

    #[test]
    fn release_returns_the_coin_to_selection() {
        let mut coin = available_coin();
        coin.lock_for(OperationHandle(1)).expect("lock is valid");

        coin.release(OperationHandle(1)).expect("release is valid");

        assert_eq!(coin.state, CoinState::Available);
        assert!(coin.is_selectable(NOW));
    }

    #[test]
    fn only_the_holding_operation_may_release_or_spend() {
        let mut coin = available_coin();
        coin.lock_for(OperationHandle(1)).expect("lock is valid");

        assert!(coin.release(OperationHandle(2)).is_err());
        assert!(coin.mark_spent(OperationHandle(2)).is_err());
        assert_eq!(coin.state, CoinState::LockedFor(OperationHandle(1)));
    }

    #[test]
    fn spending_is_terminal() {
        let mut coin = available_coin();
        coin.lock_for(OperationHandle(1)).expect("lock is valid");
        coin.mark_spent(OperationHandle(1)).expect("spend is valid");

        assert_eq!(coin.state, CoinState::Spent);
        assert!(!coin.is_selectable(NOW));
        assert!(coin.lock_for(OperationHandle(2)).is_err());
        assert!(coin.observe_populated(CoinAge(1)).is_err());
    }

    #[test]
    fn an_available_coin_cannot_be_spent_without_being_locked() {
        let mut coin = available_coin();

        assert!(coin.mark_spent(OperationHandle(1)).is_err());
        assert_eq!(coin.state, CoinState::Available);
    }

    #[test]
    fn recycling_is_due_at_the_threshold_age_and_only_while_selectable() {
        let mut coin = available_coin();
        coin.observe_populated(CoinAge(14))
            .expect("refresh is valid");

        assert!(coin.needs_recycling(CoinAge(14), NOW));
        assert!(!coin.needs_recycling(CoinAge(15), NOW));

        coin.lock_for(OperationHandle(1)).expect("lock is valid");
        assert!(!coin.needs_recycling(CoinAge(14), NOW));
    }

    #[test]
    fn a_chain_locked_coin_is_intact_but_unselectable() {
        // What the pallet leaves behind after a dispatch failure: the coin is
        // restored, so the layer must not retire it, but the runtime refuses it
        // as an origin until the lock expires.
        let mut coin = available_coin();

        coin.observe_chain_lock(Some(Timestamp(2_000)));

        assert_eq!(coin.state, CoinState::Available, "the coin still exists");
        assert!(coin.is_chain_locked(Timestamp(1_999)));
        assert!(!coin.is_selectable(Timestamp(1_999)));
        assert!(!coin.needs_recycling(CoinAge(0), Timestamp(1_999)));
    }

    #[test]
    fn a_chain_lock_expires_on_its_own() {
        let mut coin = available_coin();
        coin.observe_chain_lock(Some(Timestamp(2_000)));

        // The boundary is exclusive: at the expiry the chain accepts the coin.
        assert!(coin.is_selectable(Timestamp(2_000)));
        assert!(!coin.is_chain_locked(Timestamp(2_000)));
    }

    #[test]
    fn observing_no_lock_clears_a_previous_one() {
        let mut coin = available_coin();
        coin.observe_chain_lock(Some(Timestamp(2_000)));

        coin.observe_chain_lock(None);

        assert!(coin.is_selectable(Timestamp(0)));
    }

    #[test]
    fn the_two_locks_are_independent() {
        // A coin held by an operation is unselectable whatever the chain says,
        // and the chain's lock survives the operation releasing it.
        let mut coin = available_coin();
        coin.observe_chain_lock(Some(Timestamp(2_000)));
        coin.lock_for(OperationHandle(1)).expect("lock is valid");

        assert!(!coin.is_selectable(Timestamp(5_000)));

        coin.release(OperationHandle(1)).expect("release is valid");

        assert!(!coin.is_selectable(Timestamp(1_000)), "chain lock survives");
        assert!(coin.is_selectable(Timestamp(5_000)));
    }

    #[test]
    fn usability_ends_at_the_chain_age_cap() {
        let mut coin = available_coin();
        coin.observe_populated(CoinAge(15))
            .expect("refresh is valid");
        assert!(coin.is_usable(CoinAge(16)));

        coin.observe_populated(CoinAge(16))
            .expect("refresh is valid");
        assert!(!coin.is_usable(CoinAge(16)));
    }
}
