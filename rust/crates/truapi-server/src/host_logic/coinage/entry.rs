//! Recycler entries: their on-chain readiness, local lifecycle, and the
//! anonymity floor.
//!
//! An entry is a Bandersnatch keypair the layer placed into a chain recycler
//! ring. It holds no spendable value on its own; value is realized at unload
//! time, when a ring VRF proof hides the prover among the ring's members. Two
//! dimensions govern an entry independently: what the chain says about its ring,
//! and what the layer is doing with it.

use core::time::Duration;

use parity_scale_codec::{Decode, Encode};

use super::error::InvalidTransition;
use super::params::CoinageParameters;
use super::types::{
    Amount, DenominationExponent, EntryIndex, OperationHandle, PurseId, RingLocation, Timestamp,
};

const SUBJECT: &str = "recycler entry";

/// What the chain says about an entry's ring.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Encode, Decode)]
pub enum EntryOnChainState {
    /// No recycler location for the entry's member key. The load extrinsic has
    /// not finalized, or the entry has been consumed.
    Missing,
    /// A recycler location exists, but the ring is onboarding or chain-side
    /// readiness conditions are unmet.
    Waiting,
    /// The ring's member count meets the layer's anonymity floor.
    Ready,
    /// The ring is usable but smaller than the anonymity floor. The payload is
    /// the observed member count.
    Degraded(u32),
}

impl EntryOnChainState {
    /// Classify an observed ring against the anonymity floor.
    pub fn from_ring_member_count(member_count: u32, params: &CoinageParameters) -> Self {
        if params.clears_anonymity_floor(member_count) {
            Self::Ready
        } else {
            Self::Degraded(member_count)
        }
    }

    /// Whether the chain would accept an unload of this entry.
    ///
    /// Both `Ready` and `Degraded` qualify; the caller decides per operation
    /// whether to accept the weaker anonymity.
    pub const fn is_usable(&self) -> bool {
        matches!(self, Self::Ready | Self::Degraded(_))
    }

    /// Whether the entry's anonymity claim is at full strength.
    pub const fn is_full_anonymity(&self) -> bool {
        matches!(self, Self::Ready)
    }
}

/// What the layer is doing with an entry.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Encode, Decode)]
pub enum EntryLocalState {
    /// Free for selection.
    Available,
    /// Held by an in-flight operation.
    LockedFor(OperationHandle),
    /// Terminal. The entry was unloaded. Retained so its index is never reused,
    /// because its public key sits in a public ring member list.
    Consumed,
}

impl EntryLocalState {
    /// A short label for diagnostics.
    pub const fn label(&self) -> &'static str {
        match self {
            Self::Available => "available",
            Self::LockedFor(_) => "locked",
            Self::Consumed => "consumed",
        }
    }

    /// The operation holding this entry, if any.
    pub const fn locked_by(&self) -> Option<OperationHandle> {
        match self {
            Self::LockedFor(handle) => Some(*handle),
            _ => None,
        }
    }
}

/// A recycler entry the layer controls.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Encode, Decode)]
pub struct RecyclerEntry {
    /// Purse owning the entry.
    pub purse: PurseId,
    /// Derivation index within the purse.
    pub index: EntryIndex,
    /// Denomination the entry will realize when unloaded.
    pub exponent: DenominationExponent,
    /// Where the entry sits on chain, once the chain reports it. Carries the
    /// ring's revision as well as its index, because both are needed to unload
    /// and a proof is only valid against the revision it was built for.
    pub ring: Option<RingLocation>,
    /// Chain-side readiness.
    pub on_chain: EntryOnChainState,
    /// Layer-side lifecycle.
    pub local: EntryLocalState,
    /// When the layer created the entry.
    pub allocated_at: Timestamp,
    /// When the entry becomes selectable, `allocated_at` plus a random delay.
    /// The delay decorrelates a load from its later unload.
    pub ready_at: Timestamp,
}

impl RecyclerEntry {
    /// Record a newly created entry whose load has not been observed yet.
    ///
    /// `jitter` is drawn by the caller from `[0, jitter_upper_bound]`; the
    /// domain layer holds no randomness source.
    pub fn allocated(
        purse: PurseId,
        index: EntryIndex,
        exponent: DenominationExponent,
        allocated_at: Timestamp,
        jitter: Duration,
    ) -> Self {
        Self {
            purse,
            index,
            exponent,
            ring: None,
            on_chain: EntryOnChainState::Missing,
            local: EntryLocalState::Available,
            allocated_at,
            ready_at: allocated_at.saturating_add(jitter),
        }
    }

    /// The value the entry realizes when unloaded.
    pub fn value(&self) -> Amount {
        self.exponent.value()
    }

    /// Whether the jitter delay has elapsed.
    pub fn jitter_elapsed(&self, now: Timestamp) -> bool {
        self.ready_at <= now
    }

    /// Whether selection may consider this entry.
    ///
    /// This is the maximum selectable set; `allow_degraded = false` narrows it
    /// to entries at full anonymity.
    pub fn is_selectable(&self, now: Timestamp, allow_degraded: bool) -> bool {
        let anonymity_ok = if allow_degraded {
            self.on_chain.is_usable()
        } else {
            self.on_chain.is_full_anonymity()
        };

        self.local == EntryLocalState::Available && anonymity_ok && self.jitter_elapsed(now)
    }

    /// Whether the ring-expiration rescue sweep should unload this entry.
    ///
    /// The chain destroys the backing value of any entry still in a ring when
    /// the ring is cleaned up, `recycler_expiration_time` after it became
    /// immutable. The margin is the slack the layer keeps ahead of that.
    pub fn needs_rescue(
        &self,
        now: Timestamp,
        ring_immutable_since: Timestamp,
        recycler_expiration_time: Duration,
        rescue_margin: Duration,
    ) -> bool {
        if self.local != EntryLocalState::Available || !self.on_chain.is_usable() {
            return false;
        }

        let expires_at = ring_immutable_since.saturating_add(recycler_expiration_time);
        now >= expires_at.saturating_sub(rescue_margin)
    }

    /// Record a chain observation of the entry's ring.
    pub fn observe_ring(
        &mut self,
        ring: RingLocation,
        member_count: u32,
        params: &CoinageParameters,
    ) {
        self.ring = Some(ring);
        self.on_chain = EntryOnChainState::from_ring_member_count(member_count, params);
    }

    /// Record that the chain no longer reports a location for the entry.
    pub fn observe_missing(&mut self) {
        self.on_chain = EntryOnChainState::Missing;
    }

    /// Record that the ring exists but is not yet usable.
    pub fn observe_waiting(&mut self, ring: RingLocation) {
        self.ring = Some(ring);
        self.on_chain = EntryOnChainState::Waiting;
    }

    /// Lock the entry for an operation that is preparing.
    pub fn lock_for(&mut self, handle: OperationHandle) -> Result<(), InvalidTransition> {
        match self.local {
            EntryLocalState::Available => {
                self.local = EntryLocalState::LockedFor(handle);
                Ok(())
            }
            _ => Err(InvalidTransition::new(SUBJECT, self.local.label(), "lock")),
        }
    }

    /// Return the entry to the selectable pool.
    pub fn release(&mut self, handle: OperationHandle) -> Result<(), InvalidTransition> {
        match self.local {
            EntryLocalState::LockedFor(holder) if holder == handle => {
                self.local = EntryLocalState::Available;
                Ok(())
            }
            _ => Err(InvalidTransition::new(
                SUBJECT,
                self.local.label(),
                "release",
            )),
        }
    }

    /// Retire the entry after its owning operation unloaded it.
    pub fn mark_consumed(&mut self, handle: OperationHandle) -> Result<(), InvalidTransition> {
        match self.local {
            EntryLocalState::LockedFor(holder) if holder == handle => {
                self.local = EntryLocalState::Consumed;
                self.on_chain = EntryOnChainState::Missing;
                Ok(())
            }
            _ => Err(InvalidTransition::new(
                SUBJECT,
                self.local.label(),
                "mark consumed",
            )),
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    const HOUR: Duration = Duration::from_secs(60 * 60);
    const DAY: Duration = Duration::from_secs(24 * 60 * 60);

    fn exponent(value: i8) -> DenominationExponent {
        DenominationExponent::new(value).expect("exponent is in range")
    }

    fn ring(index: u32) -> RingLocation {
        RingLocation::new(
            super::super::types::RingIndex(index),
            super::super::types::RevisionIndex(0),
        )
    }

    fn ready_entry(now: Timestamp) -> RecyclerEntry {
        let params = CoinageParameters::default();
        let mut entry = RecyclerEntry::allocated(
            PurseId::MAIN,
            EntryIndex(0),
            exponent(5),
            now,
            Duration::ZERO,
        );
        entry.observe_ring(ring(1), params.minimum_anonymous_ring_size, &params);
        entry
    }

    #[test]
    fn a_fresh_entry_is_missing_on_chain_and_available_locally() {
        let entry = RecyclerEntry::allocated(
            PurseId::MAIN,
            EntryIndex(3),
            exponent(2),
            Timestamp(0),
            Duration::ZERO,
        );

        assert_eq!(entry.on_chain, EntryOnChainState::Missing);
        assert_eq!(entry.local, EntryLocalState::Available);
        assert!(!entry.is_selectable(Timestamp(0), true));
    }

    #[test]
    fn ring_member_count_is_classified_against_the_anonymity_floor() {
        let params = CoinageParameters::default();

        assert_eq!(
            EntryOnChainState::from_ring_member_count(10, &params),
            EntryOnChainState::Ready
        );
        assert_eq!(
            EntryOnChainState::from_ring_member_count(9, &params),
            EntryOnChainState::Degraded(9)
        );
    }

    #[test]
    fn degraded_entries_are_selectable_only_when_the_caller_allows_them() {
        let params = CoinageParameters::default();
        let now = Timestamp(1_000);
        let mut entry = ready_entry(now);
        entry.observe_ring(ring(1), 4, &params);

        assert!(entry.is_selectable(now, true));
        assert!(!entry.is_selectable(now, false));
    }

    #[test]
    fn jitter_delays_selectability_regardless_of_chain_readiness() {
        let params = CoinageParameters::default();
        let allocated_at = Timestamp(0);
        let mut entry = RecyclerEntry::allocated(
            PurseId::MAIN,
            EntryIndex(0),
            exponent(5),
            allocated_at,
            HOUR,
        );
        entry.observe_ring(ring(1), 32, &params);

        assert_eq!(entry.on_chain, EntryOnChainState::Ready);
        assert!(!entry.is_selectable(Timestamp(HOUR.as_millis() as u64 - 1), true));
        assert!(entry.is_selectable(Timestamp(HOUR.as_millis() as u64), true));
    }

    #[test]
    fn waiting_and_missing_entries_are_never_selectable() {
        let now = Timestamp(1_000);
        let mut entry = ready_entry(now);

        entry.observe_waiting(ring(1));
        assert!(!entry.is_selectable(now, true));

        entry.observe_missing();
        assert!(!entry.is_selectable(now, true));
    }

    #[test]
    fn locking_removes_the_entry_from_selection() {
        let now = Timestamp(1_000);
        let mut entry = ready_entry(now);

        entry.lock_for(OperationHandle(2)).expect("lock is valid");

        assert!(!entry.is_selectable(now, true));
        assert_eq!(entry.local.locked_by(), Some(OperationHandle(2)));
        assert!(entry.lock_for(OperationHandle(3)).is_err());
    }

    #[test]
    fn only_the_holding_operation_may_release_or_consume() {
        let now = Timestamp(1_000);
        let mut entry = ready_entry(now);
        entry.lock_for(OperationHandle(1)).expect("lock is valid");

        assert!(entry.release(OperationHandle(9)).is_err());
        assert!(entry.mark_consumed(OperationHandle(9)).is_err());
    }

    #[test]
    fn consuming_is_terminal_and_clears_the_chain_view() {
        let now = Timestamp(1_000);
        let mut entry = ready_entry(now);
        entry.lock_for(OperationHandle(1)).expect("lock is valid");

        entry
            .mark_consumed(OperationHandle(1))
            .expect("consume is valid");

        assert_eq!(entry.local, EntryLocalState::Consumed);
        assert_eq!(entry.on_chain, EntryOnChainState::Missing);
        assert!(!entry.is_selectable(now, true));
        assert!(entry.lock_for(OperationHandle(2)).is_err());
    }

    #[test]
    fn rescue_fires_once_the_margin_is_reached_and_not_before() {
        let params = CoinageParameters::default();
        let immutable_since = Timestamp(0);
        let expiration = DAY * 40;
        let margin = params.rescue_margin(expiration);
        let entry = ready_entry(Timestamp(0));

        let deadline = immutable_since.saturating_add(expiration);
        let trigger = deadline.saturating_sub(margin);

        assert!(!entry.needs_rescue(
            Timestamp(trigger.0 - 1),
            immutable_since,
            expiration,
            margin
        ));
        assert!(entry.needs_rescue(trigger, immutable_since, expiration, margin));
    }

    #[test]
    fn a_locked_or_consumed_entry_is_never_rescued() {
        let params = CoinageParameters::default();
        let expiration = DAY * 40;
        let margin = params.rescue_margin(expiration);
        let past_deadline = Timestamp(expiration.as_millis() as u64);
        let mut entry = ready_entry(Timestamp(0));

        entry.lock_for(OperationHandle(1)).expect("lock is valid");
        assert!(!entry.needs_rescue(past_deadline, Timestamp(0), expiration, margin));

        entry
            .mark_consumed(OperationHandle(1))
            .expect("consume is valid");
        assert!(!entry.needs_rescue(past_deadline, Timestamp(0), expiration, margin));
    }
}
