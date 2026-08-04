//! Facts about the coinage pallet the layer is talking to.
//!
//! These are facts about the runtime, not choices of the layer. They are kept
//! apart from [`super::params::CoinageParameters`] because the distinction
//! matters: a policy parameter can be tuned, whereas exceeding one of these
//! makes an extrinsic invalid. Anything the layer builds has to fit inside them.
//!
//! Most are read from metadata. Two are not exposed there and must be carried
//! as per-network configuration — see the field docs for `maximum_age` and
//! `recycler_expiration_time`. `examples/coinage_chain_agreement.rs` checks the
//! rest against a live node.

use core::time::Duration;

use super::error::CoinageError;
use super::types::{CoinAge, DenominationExponent, MAX_SUPPORTED_DENOMINATION_EXPONENT};

/// The coinage pallet's configuration, as observed on the connected chain.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct CoinageChainConstants {
    /// Smallest denomination exponent the pallet accepts (`MinimumExponent`).
    pub minimum_exponent: i8,
    /// Largest denomination exponent the pallet accepts (`MaximumExponent`).
    pub maximum_exponent: i8,
    /// Age at which a coin can no longer be transferred or split
    /// (`MaximumAge`). Past this it can only be recycled or offboarded.
    ///
    /// **Not discoverable.** The pallet declares this without
    /// `#[pallet::constant]`, so it is absent from metadata and has to be
    /// carried as per-network configuration. A runtime that lowers it will not
    /// be noticed, and the layer would then recycle later than the chain
    /// allows — letting coins age out unusable. Confirmed absent on
    /// `paseo-people-next` by `examples/coinage_chain_agreement.rs`.
    pub maximum_age: CoinAge,
    /// Cap on output accounts of a single split or unload-into-coins extrinsic
    /// (`MaxSplitOutputs`).
    pub max_split_outputs: u32,
    /// Cap on recycler entries consolidated into one unload extrinsic
    /// (`MaxConsolidation`).
    pub max_consolidation: u32,
    /// How long after a ring becomes immutable the chain destroys the backing
    /// value of entries still in it (`RecyclerExpirationTime`).
    ///
    /// **Not discoverable on the deployed runtime.** Absent from
    /// `paseo-people-next`'s metadata even though the pallet source marks it
    /// `#[pallet::constant]`, so the deployed runtime predates that attribute.
    /// Carried as configuration until it appears. This one drives the rescue
    /// margin, so a runtime that shortens it without us noticing would make the
    /// ring-expiration sweep fire too late.
    pub recycler_expiration_time: Duration,
    /// Length of a free-unload-token period
    /// (`UnloadTokenTimePeriodPeopleLitePeople`).
    pub unload_token_period: Duration,
    /// Free unload tokens a member may consume per period
    /// (`MaxFreeUnloadTokensPerTimePeriod`).
    pub max_free_unload_tokens_per_period: u32,
    /// Entries one unpaid external-asset load may create
    /// (`MaxBatchUnpaidLoad`). Bounds a top-up: an amount needing more
    /// denominations than this cannot be loaded in one extrinsic.
    pub max_batch_unpaid_load: u32,
    /// Underlying-asset base units in one cent (`UnderlyingAssetUnit`).
    pub underlying_asset_unit: u128,
    /// Base period a coin stays locked after a dispatch that failed with the
    /// coin as its origin (`CoinFailureLockPeriod`).
    ///
    /// The lock the chain writes is `2^retries` times this, counted from
    /// consecutive failures on the same coin. Nothing about the coin is lost —
    /// the extension restores it — but it is unspendable until the lock
    /// expires, and a layer that does not model this reselects the coin and
    /// spends a fresh unload token on an extrinsic the chain will refuse.
    pub coin_failure_lock_period: Duration,
}

impl CoinageChainConstants {
    /// Check that the layer can operate against this runtime.
    ///
    /// Called once when constants are read, so an incompatible runtime is
    /// rejected at connection time rather than at the first failed extrinsic.
    pub fn validate(&self) -> Result<(), CoinageError> {
        if self.minimum_exponent < 0 {
            return Err(CoinageError::Internal(format!(
                "runtime allows sub-cent denominations (MinimumExponent = {}), which this layer \
                 cannot represent",
                self.minimum_exponent
            )));
        }
        if self.maximum_exponent > MAX_SUPPORTED_DENOMINATION_EXPONENT {
            return Err(CoinageError::Internal(format!(
                "runtime MaximumExponent {} exceeds the layer's supported ceiling {}",
                self.maximum_exponent, MAX_SUPPORTED_DENOMINATION_EXPONENT
            )));
        }
        if self.minimum_exponent > self.maximum_exponent {
            return Err(CoinageError::Internal(format!(
                "runtime exponent range is inverted: {}..={}",
                self.minimum_exponent, self.maximum_exponent
            )));
        }
        if self.max_split_outputs == 0 || self.max_consolidation == 0 {
            return Err(CoinageError::Internal(
                "runtime caps a split or consolidation at zero".to_string(),
            ));
        }

        Ok(())
    }

    /// Whether the pallet would accept this denomination.
    pub fn accepts(&self, exponent: DenominationExponent) -> bool {
        (self.minimum_exponent..=self.maximum_exponent).contains(&exponent.get())
    }

    /// The largest denomination the pallet accepts.
    pub fn largest_denomination(&self) -> Option<DenominationExponent> {
        DenominationExponent::new(self.maximum_exponent)
    }

    /// The age at which the layer should recycle a coin, keeping a margin below
    /// the chain's cap.
    pub fn recycle_at_age(&self) -> CoinAge {
        super::params::CoinageParameters::recycle_at_age(self.maximum_age)
    }
}

/// The values configured by the `next-people-paseo` runtime.
///
/// A reference point for tests and for the CLI host's default network. The
/// metadata-exposed values are verified against the live runtime by
/// `examples/coinage_chain_agreement.rs`; the two that metadata does not expose
/// have no such check and are the reason this function exists at all.
pub fn next_people_paseo() -> CoinageChainConstants {
    CoinageChainConstants {
        minimum_exponent: 0,
        maximum_exponent: 14,
        maximum_age: CoinAge(16),
        max_split_outputs: 32,
        max_consolidation: 64,
        recycler_expiration_time: Duration::from_secs(90 * 24 * 60 * 60),
        unload_token_period: Duration::from_secs(24 * 60 * 60),
        max_free_unload_tokens_per_period: 1_000,
        max_batch_unpaid_load: 10,
        underlying_asset_unit: 10u128.pow(4),
        coin_failure_lock_period: Duration::from_secs(60),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn the_reference_runtime_is_supported() {
        let constants = next_people_paseo();

        assert_eq!(constants.validate(), Ok(()));
        assert_eq!(constants.recycle_at_age(), CoinAge(14));
        assert_eq!(
            constants.largest_denomination(),
            DenominationExponent::new(14)
        );
    }

    #[test]
    fn the_largest_reference_coin_is_a_hundred_and_sixty_three_dollars() {
        let largest = next_people_paseo()
            .largest_denomination()
            .expect("14 is representable");

        assert_eq!(largest.value().cents(), 16_384);
    }

    #[test]
    fn denominations_outside_the_runtime_range_are_rejected() {
        let constants = next_people_paseo();

        assert!(constants.accepts(DenominationExponent::new(0).expect("valid")));
        assert!(constants.accepts(DenominationExponent::new(14).expect("valid")));
        assert!(!constants.accepts(DenominationExponent::new(15).expect("valid")));
    }

    #[test]
    fn a_sub_cent_runtime_is_refused_rather_than_truncated() {
        let constants = CoinageChainConstants {
            minimum_exponent: -2,
            ..next_people_paseo()
        };

        assert!(matches!(
            constants.validate(),
            Err(CoinageError::Internal(_))
        ));
    }

    #[test]
    fn a_runtime_beyond_the_arithmetic_ceiling_is_refused() {
        let constants = CoinageChainConstants {
            maximum_exponent: MAX_SUPPORTED_DENOMINATION_EXPONENT + 1,
            ..next_people_paseo()
        };

        assert!(matches!(
            constants.validate(),
            Err(CoinageError::Internal(_))
        ));
    }

    #[test]
    fn an_inverted_or_degenerate_range_is_refused() {
        let inverted = CoinageChainConstants {
            minimum_exponent: 8,
            maximum_exponent: 4,
            ..next_people_paseo()
        };
        let zero_split = CoinageChainConstants {
            max_split_outputs: 0,
            ..next_people_paseo()
        };

        assert!(inverted.validate().is_err());
        assert!(zero_split.validate().is_err());
    }
}
