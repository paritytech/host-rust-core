//! Tunable parameters governing selection, recycling, and recovery.
//!
//! Every value here is a policy choice of the layer, not a chain constant.
//! Where a recommendation is expressed relative to a chain constant, the
//! constant is a function argument rather than a stored field.

use core::time::Duration;

use super::types::{Amount, CoinAge};

/// Policy parameters for one layer instance.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct CoinageParameters {
    /// Ring member count at or above which an entry's anonymity is considered
    /// adequate. Scoped to the layer instance, never per purse or per call.
    pub minimum_anonymous_ring_size: u32,
    /// Upper bound of the uniform delay applied to a new recycler entry before
    /// it becomes selectable, decorrelating a load from its later unload. Zero
    /// disables jitter.
    pub recycler_entry_jitter_upper_bound: Duration,
    /// How often the coin-age recycling sweep runs.
    pub recycling_sweep_interval: Duration,
    /// How often the ring-expiration rescue sweep runs.
    pub ring_expiration_sweep_interval: Duration,
    /// Fraction of the chain's recycler expiration time to keep as slack before
    /// rescuing an entry, expressed in percent.
    pub rescue_margin_percent: u32,
    /// Lower bound on the rescue margin, whatever the fraction works out to.
    pub rescue_margin_minimum: Duration,
    /// Number of free-unload-token counters to probe per period.
    pub free_token_counter_search_range: u32,
    /// How far past a period boundary a prior period's tokens stay eligible.
    pub period_lookback_grace: Duration,
    /// Derivation indices scanned per batch during recovery.
    pub recovery_batch_size: u32,
    /// Consecutive empty batches after which a recovery scan stops.
    pub recovery_gap_limit: u32,
    /// Chain-enforced cap on outputs of a single split or unload-into-coins
    /// extrinsic.
    pub max_split_outputs: u32,
    /// Chain-enforced cap on entries consolidated into one unload extrinsic.
    pub max_recycler_entries_per_group: u32,
    /// How long external offload waits before re-planning when the deficit
    /// could be covered by coins currently in transient states.
    pub external_offload_retry_interval: Duration,
}

impl CoinageParameters {
    /// Age at which a coin is recycled, given the chain's maximum coin age.
    ///
    /// The two-transfer margin absorbs a retry window under congestion or
    /// downtime.
    pub fn recycle_at_age(chain_coin_max_age: CoinAge) -> CoinAge {
        CoinAge(chain_coin_max_age.0.saturating_sub(2))
    }

    /// Slack between the rescue sweep firing and the chain destroying the
    /// ring's backing value, given the chain's recycler expiration time.
    ///
    /// Too small and the rescue races chain cleanup; too large and entries are
    /// rescued early, burning unload tokens for nothing.
    pub fn rescue_margin(&self, recycler_expiration_time: Duration) -> Duration {
        let fraction =
            recycler_expiration_time.mul_f64(f64::from(self.rescue_margin_percent) / 100.0);
        fraction.max(self.rescue_margin_minimum)
    }

    /// Whether a ring member count clears the anonymity floor.
    pub fn clears_anonymity_floor(&self, ring_member_count: u32) -> bool {
        ring_member_count >= self.minimum_anonymous_ring_size
    }
}

impl Default for CoinageParameters {
    /// The recommended values.
    fn default() -> Self {
        Self {
            minimum_anonymous_ring_size: 10,
            recycler_entry_jitter_upper_bound: Duration::from_secs(6 * 60 * 60),
            recycling_sweep_interval: Duration::from_secs(24 * 60 * 60),
            ring_expiration_sweep_interval: Duration::from_secs(24 * 60 * 60),
            rescue_margin_percent: 25,
            rescue_margin_minimum: Duration::from_secs(7 * 24 * 60 * 60),
            free_token_counter_search_range: 10,
            period_lookback_grace: Duration::from_secs(60 * 60),
            recovery_batch_size: 500,
            recovery_gap_limit: 4,
            max_split_outputs: 32,
            max_recycler_entries_per_group: 8,
            external_offload_retry_interval: Duration::from_secs(30),
        }
    }
}

/// Denomination breakdown of `amount` into powers of two, largest first.
///
/// Every coinage amount is representable, since the set of denominations is
/// exactly the powers of two: the breakdown is the binary expansion of the cent
/// count. Returns `None` if any set bit exceeds the layer's supported
/// denomination ceiling.
pub fn canonical_breakdown(amount: Amount) -> Option<Vec<super::types::DenominationExponent>> {
    let mut exponents = Vec::new();
    let cents = amount.cents();

    for bit in (0..u64::BITS).rev() {
        if cents & (1u64 << bit) != 0 {
            let exponent = u8::try_from(bit).ok()?;
            exponents.push(super::types::DenominationExponent::new(exponent)?);
        }
    }

    Some(exponents)
}

#[cfg(test)]
mod tests {
    use super::super::types::{DenominationExponent, MAX_DENOMINATION_EXPONENT};
    use super::*;

    #[test]
    fn recycle_age_leaves_a_two_transfer_margin() {
        assert_eq!(CoinageParameters::recycle_at_age(CoinAge(16)), CoinAge(14));
    }

    #[test]
    fn recycle_age_saturates_for_tiny_chain_caps() {
        assert_eq!(CoinageParameters::recycle_at_age(CoinAge(1)), CoinAge(0));
    }

    #[test]
    fn rescue_margin_takes_the_fraction_when_it_exceeds_the_floor() {
        let params = CoinageParameters::default();
        let expiration = Duration::from_secs(365 * 24 * 60 * 60);

        // 25% of a year comfortably exceeds the 7-day floor.
        assert_eq!(params.rescue_margin(expiration), expiration.mul_f64(0.25));
    }

    #[test]
    fn rescue_margin_takes_the_floor_when_the_fraction_is_smaller() {
        let params = CoinageParameters::default();
        let expiration = Duration::from_secs(10 * 24 * 60 * 60);

        // 25% of 10 days is 2.5 days, below the 7-day floor.
        assert_eq!(
            params.rescue_margin(expiration),
            params.rescue_margin_minimum
        );
    }

    #[test]
    fn anonymity_floor_is_inclusive() {
        let params = CoinageParameters::default();

        assert!(!params.clears_anonymity_floor(9));
        assert!(params.clears_anonymity_floor(10));
        assert!(params.clears_anonymity_floor(11));
    }

    #[test]
    fn breakdown_is_the_binary_expansion_largest_first() {
        let exponents = canonical_breakdown(Amount::from_cents(13)).expect("13 is representable");
        let raw: Vec<u8> = exponents.iter().map(|e| e.get()).collect();

        // 13 = 8 + 4 + 1
        assert_eq!(raw, vec![3, 2, 0]);
    }

    #[test]
    fn breakdown_of_zero_is_empty() {
        assert_eq!(
            canonical_breakdown(Amount::ZERO),
            Some(Vec::<DenominationExponent>::new())
        );
    }

    #[test]
    fn breakdown_sums_back_to_the_amount() {
        let amount = Amount::from_cents(1_234_567);
        let exponents = canonical_breakdown(amount).expect("representable");
        let total: Amount = exponents.iter().map(|e| e.value()).sum();

        assert_eq!(total, amount);
    }

    #[test]
    fn breakdown_rejects_amounts_needing_an_oversized_denomination() {
        let too_large = Amount::from_cents(1u64 << (MAX_DENOMINATION_EXPONENT + 1));
        assert_eq!(canonical_breakdown(too_large), None);
    }
}
