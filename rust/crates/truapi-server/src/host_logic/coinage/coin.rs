//! Coin records and their lifecycle.
//!
//! A coin is a chain-level NFT of a fixed dotUSD denomination, addressed by an
//! account derived from the layer's root entropy, the coin's purse, and its
//! index. `Spent` is terminal but the record is retained: a coin index is never
//! reused, because the account may already have appeared in a transfer memo
//! passed out of band.

use parity_scale_codec::{Decode, Encode};

use super::error::InvalidTransition;
use super::types::{Amount, CoinAge, CoinIndex, DenominationExponent, OperationHandle, PurseId};

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
#[derive(Debug, Clone, PartialEq, Eq, Encode, Decode)]
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
        }
    }

    /// The coin's value.
    pub fn value(&self) -> Amount {
        self.exponent.value()
    }

    /// Whether selection may consider this coin.
    pub fn is_selectable(&self) -> bool {
        self.state == CoinState::Available
    }

    /// Whether the chain still accepts the coin, given its age cap.
    pub fn is_usable(&self, chain_coin_max_age: CoinAge) -> bool {
        self.age < chain_coin_max_age
    }

    /// Whether the coin-age sweep should recycle this coin.
    pub fn needs_recycling(&self, recycle_at_age: CoinAge) -> bool {
        self.is_selectable() && self.age >= recycle_at_age
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

    fn exponent(value: u8) -> DenominationExponent {
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
        assert!(!coin.is_selectable());
        assert_eq!(coin.value(), Amount::from_cents(8));
    }

    #[test]
    fn first_chain_observation_makes_a_pending_coin_available() {
        let mut coin = Coin::pending(PurseId::MAIN, CoinIndex(0), exponent(2));

        coin.observe_populated(CoinAge(3))
            .expect("transition is valid");

        assert_eq!(coin.state, CoinState::Available);
        assert_eq!(coin.age, CoinAge(3));
        assert!(coin.is_selectable());
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

        assert!(!coin.is_selectable());
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
        assert!(coin.is_selectable());
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
        assert!(!coin.is_selectable());
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

        assert!(coin.needs_recycling(CoinAge(14)));
        assert!(!coin.needs_recycling(CoinAge(15)));

        coin.lock_for(OperationHandle(1)).expect("lock is valid");
        assert!(!coin.needs_recycling(CoinAge(14)));
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
