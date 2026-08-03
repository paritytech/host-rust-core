//! Argument construction for the coinage pallet's dispatchables.
//!
//! Each type here mirrors one call's arguments as the pallet declares them, so a
//! plan from the domain layer becomes something submittable without any shape
//! guessing in between. Pallet and call indices are deliberately absent: the
//! house rule is to resolve them by name from live metadata, so a re-indexed
//! runtime fails loudly instead of silently dispatching the wrong call.
//!
//! Two pallet constraints are enforced here rather than discovered on chain,
//! because a rejected extrinsic after a coin has been consumed is expensive:
//! the split-output cap, and conservation of value across a split.

use parity_scale_codec::{Encode, Output};

use crate::host_logic::coinage::chain_constants::CoinageChainConstants;
use crate::host_logic::coinage::error::CoinageError;
use crate::host_logic::coinage::types::{
    Amount, CoinAccountId, DenominationExponent, RingLocation,
};

/// A SCALE blob that is spliced in as-is.
///
/// Ring-VRF proofs and bandersnatch signatures are runtime-specific types whose
/// layout this crate does not model. They arrive already encoded by the
/// `verifiable` crate and must reach the extrinsic byte-for-byte, so this
/// wrapper writes its contents verbatim — no length prefix, unlike `Vec<u8>`.
#[derive(Debug, Clone, PartialEq, Eq, Default)]
pub struct RawEncoded(pub Vec<u8>);

impl Encode for RawEncoded {
    fn size_hint(&self) -> usize {
        self.0.len()
    }

    fn encode_to<T: Output + ?Sized>(&self, dest: &mut T) {
        dest.write(&self.0);
    }
}

/// A coin the chain is being asked to create: its denomination and the account
/// that will hold it.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct CoinOutput {
    /// Denomination of the coin to mint.
    pub exponent: DenominationExponent,
    /// Account that will hold it.
    pub account: CoinAccountId,
}

/// The pallet's `split_into` argument: destinations grouped under each
/// denomination.
///
/// The nesting is the pallet's, not ours — one denomination may have several
/// destination accounts, which is how a transfer sends two equal outputs to two
/// different recipients.
#[derive(Debug, Clone, PartialEq, Eq, Encode)]
pub struct SplitInto(pub Vec<(i8, Vec<[u8; 32]>)>);

impl SplitInto {
    /// Group outputs by denomination, preserving the order in which each
    /// denomination first appears so the encoding is deterministic.
    pub fn from_outputs(
        outputs: &[CoinOutput],
        constants: &CoinageChainConstants,
    ) -> Result<Self, CoinageError> {
        let cap = constants.max_split_outputs as usize;
        if outputs.len() > cap {
            return Err(CoinageError::Internal(format!(
                "{} outputs exceeds the runtime's MaxSplitOutputs of {cap}",
                outputs.len()
            )));
        }

        let mut grouped: Vec<(i8, Vec<[u8; 32]>)> = Vec::new();
        for output in outputs {
            if !constants.accepts(output.exponent) {
                return Err(CoinageError::Internal(format!(
                    "denomination {} is outside the runtime's range",
                    output.exponent
                )));
            }

            let value = output.exponent.get();
            match grouped.iter_mut().find(|(existing, _)| *existing == value) {
                Some((_, accounts)) => accounts.push(output.account.0),
                None => grouped.push((value, vec![output.account.0])),
            }
        }

        // The outer vector is bounded by the same cap as the inner ones.
        if grouped.len() > cap {
            return Err(CoinageError::Internal(format!(
                "{} distinct denominations exceeds the runtime's MaxSplitOutputs of {cap}",
                grouped.len()
            )));
        }

        Ok(Self(grouped))
    }

    /// Total value of every output.
    pub fn total_value(&self) -> Amount {
        self.0
            .iter()
            .filter_map(|(value, accounts)| {
                DenominationExponent::new(*value)
                    .map(|exponent| (exponent.value(), accounts.len() as u64))
            })
            .map(|(unit, count)| Amount::from_cents(unit.cents().saturating_mul(count)))
            .sum()
    }

    /// How many coins the call will create.
    pub fn output_count(&self) -> usize {
        self.0.iter().map(|(_, accounts)| accounts.len()).sum()
    }
}

/// Arguments of `Coinage::split`.
///
/// The origin is the coin being split, supplied by the `AsCoinage` extension
/// rather than as an argument.
#[derive(Debug, Clone, PartialEq, Eq, Encode)]
pub struct SplitArgs {
    /// Denominations and destinations of the resulting coins.
    pub split_into: SplitInto,
}

impl SplitArgs {
    /// Build a split of `source` into `outputs`.
    ///
    /// Rejects an output set whose value differs from the source coin's. The
    /// pallet requires equality, and by the time it says so the coin has already
    /// been consumed by the extension.
    pub fn new(
        source: DenominationExponent,
        outputs: &[CoinOutput],
        constants: &CoinageChainConstants,
    ) -> Result<Self, CoinageError> {
        let split_into = SplitInto::from_outputs(outputs, constants)?;
        let produced = split_into.total_value();

        if produced != source.value() {
            return Err(CoinageError::Internal(format!(
                "split of {source} would produce {produced}, not {}",
                source.value()
            )));
        }

        Ok(Self { split_into })
    }
}

/// Arguments of `Coinage::transfer`.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Encode)]
pub struct TransferArgs {
    /// Account that will hold the coin.
    pub to: [u8; 32],
}

impl TransferArgs {
    /// Transfer the origin coin to `to`.
    pub fn new(to: CoinAccountId) -> Self {
        Self { to: to.0 }
    }
}

/// Arguments of `Coinage::load_recycler_with_coin`.
#[derive(Debug, Clone, PartialEq, Eq, Encode)]
pub struct LoadRecyclerWithCoinArgs {
    /// Bandersnatch member key the entry publishes into the ring.
    pub member_key: [u8; 32],
    /// Signature proving control of that member key.
    pub proof_of_ownership: RawEncoded,
}

impl LoadRecyclerWithCoinArgs {
    /// Recycle the origin coin into a fresh entry under `member_key`.
    pub fn new(member_key: [u8; 32], proof_of_ownership: RawEncoded) -> Self {
        Self {
            member_key,
            proof_of_ownership,
        }
    }
}

/// Arguments of `Coinage::unload_recycler_into_coins`.
///
/// One call per `(denomination, ring)` group, each consuming one unload token.
#[derive(Debug, Clone, PartialEq, Eq, Encode)]
pub struct UnloadRecyclerIntoCoinsArgs {
    /// Aliases of the entries being unloaded, one per entry.
    pub aliases: Vec<[u8; 32]>,
    /// Denomination shared by every entry in the group.
    pub value: i8,
    /// Ring the entries belong to.
    pub index: u32,
    /// Membership revision the aliases were proven against.
    pub revision: u32,
    /// Denominations and destinations of the resulting coins.
    pub split_into: SplitInto,
    /// Fee ceiling. Zero under `UnloadFee::Prepaid`; otherwise it must cover the
    /// network fee taken from the output.
    pub max_fee: u128,
}

impl UnloadRecyclerIntoCoinsArgs {
    /// Unload one group of entries into `outputs`.
    ///
    /// Rejects a group larger than the runtime consolidates, and an output set
    /// whose value differs from the group's — the pallet returns the group's own
    /// change to the purse, so the two must balance exactly.
    pub fn new(
        aliases: Vec<[u8; 32]>,
        exponent: DenominationExponent,
        ring: RingLocation,
        outputs: &[CoinOutput],
        max_fee: u128,
        constants: &CoinageChainConstants,
    ) -> Result<Self, CoinageError> {
        if aliases.is_empty() {
            return Err(CoinageError::Internal(
                "an unload group needs at least one alias".to_string(),
            ));
        }
        let cap = constants.max_consolidation as usize;
        if aliases.len() > cap {
            return Err(CoinageError::Internal(format!(
                "{} aliases exceeds the runtime's MaxConsolidation of {cap}",
                aliases.len()
            )));
        }

        let split_into = SplitInto::from_outputs(outputs, constants)?;
        let group_value = Amount::from_cents(
            exponent
                .value()
                .cents()
                .saturating_mul(aliases.len() as u64),
        );
        let produced = split_into.total_value();

        if produced != group_value {
            return Err(CoinageError::Internal(format!(
                "unload of {} entries at {exponent} would produce {produced}, not {group_value}",
                aliases.len()
            )));
        }

        Ok(Self {
            aliases,
            value: exponent.get(),
            index: ring.index.0,
            revision: ring.revision.0,
            split_into,
            max_fee,
        })
    }
}

#[cfg(test)]
mod tests {
    use crate::host_logic::coinage::chain_constants::next_people_paseo;
    use crate::host_logic::coinage::types::{RevisionIndex, RingIndex};

    use super::*;

    fn exponent(value: i8) -> DenominationExponent {
        DenominationExponent::new(value).expect("exponent is in range")
    }

    fn account(byte: u8) -> CoinAccountId {
        CoinAccountId([byte; 32])
    }

    fn output(exponent_value: i8, account_byte: u8) -> CoinOutput {
        CoinOutput {
            exponent: exponent(exponent_value),
            account: account(account_byte),
        }
    }

    fn ring() -> RingLocation {
        RingLocation::new(RingIndex(4), RevisionIndex(9))
    }

    #[test]
    fn raw_encoded_bytes_are_spliced_without_a_length_prefix() {
        let raw = RawEncoded(vec![1, 2, 3]);

        assert_eq!(raw.encode(), vec![1, 2, 3]);
        // A `Vec<u8>` would prepend a compact length, which the pallet's
        // fixed-size proof types do not carry.
        assert_ne!(raw.encode(), vec![1u8, 2, 3].encode());
    }

    #[test]
    fn outputs_are_grouped_under_each_denomination() {
        let outputs = vec![output(3, 1), output(2, 2), output(3, 3)];

        let grouped = SplitInto::from_outputs(&outputs, &next_people_paseo())
            .expect("within the runtime caps");

        // Two 8-cent destinations share one entry; grouping order follows first
        // appearance.
        assert_eq!(grouped.0.len(), 2);
        assert_eq!(grouped.0[0].0, 3);
        assert_eq!(grouped.0[0].1, vec![[1u8; 32], [3u8; 32]]);
        assert_eq!(grouped.0[1].0, 2);
        assert_eq!(grouped.0[1].1, vec![[2u8; 32]]);
        assert_eq!(grouped.output_count(), 3);
    }

    #[test]
    fn grouped_outputs_report_their_total_value() {
        let outputs = vec![output(3, 1), output(3, 2), output(1, 3)];

        let grouped = SplitInto::from_outputs(&outputs, &next_people_paseo())
            .expect("within the runtime caps");

        assert_eq!(grouped.total_value(), Amount::from_cents(8 + 8 + 2));
    }

    #[test]
    fn too_many_outputs_are_refused_before_submission() {
        let constants = CoinageChainConstants {
            max_split_outputs: 2,
            ..next_people_paseo()
        };
        let outputs = vec![output(0, 1), output(0, 2), output(0, 3)];

        assert!(SplitInto::from_outputs(&outputs, &constants).is_err());
    }

    #[test]
    fn a_denomination_the_runtime_rejects_is_refused() {
        let outputs = vec![output(15, 1)];

        assert!(SplitInto::from_outputs(&outputs, &next_people_paseo()).is_err());
    }

    #[test]
    fn a_split_must_conserve_value() {
        let constants = next_people_paseo();
        // 2^4 = 16 splits into 8 + 4 + 4.
        let balanced = vec![output(3, 1), output(2, 2), output(2, 3)];
        let short = vec![output(3, 1), output(2, 2)];

        assert!(SplitArgs::new(exponent(4), &balanced, &constants).is_ok());
        assert!(SplitArgs::new(exponent(4), &short, &constants).is_err());
    }

    #[test]
    fn a_split_into_a_single_equal_output_is_valid() {
        // Reshaping without changing value: one 16-cent coin to one 16-cent
        // destination. This is how a transfer of the wrong shape is served.
        let constants = next_people_paseo();
        let outputs = vec![output(4, 1)];

        assert!(SplitArgs::new(exponent(4), &outputs, &constants).is_ok());
    }

    #[test]
    fn transfer_carries_the_destination_verbatim() {
        let args = TransferArgs::new(account(7));

        assert_eq!(args.to, [7u8; 32]);
        assert_eq!(args.encode(), [7u8; 32].encode());
    }

    #[test]
    fn an_unload_group_must_conserve_value() {
        let constants = next_people_paseo();
        let aliases = vec![[1u8; 32], [2u8; 32]];
        // Two 16-cent entries produce 32 cents: 16 toward the target plus 16
        // change, or any other partition summing to 32.
        let balanced = vec![output(4, 10), output(3, 11), output(3, 12)];
        let short = vec![output(4, 10)];

        assert!(
            UnloadRecyclerIntoCoinsArgs::new(
                aliases.clone(),
                exponent(4),
                ring(),
                &balanced,
                0,
                &constants
            )
            .is_ok()
        );
        assert!(
            UnloadRecyclerIntoCoinsArgs::new(aliases, exponent(4), ring(), &short, 0, &constants)
                .is_err()
        );
    }

    #[test]
    fn an_unload_group_carries_both_halves_of_the_ring_location() {
        let args = UnloadRecyclerIntoCoinsArgs::new(
            vec![[1u8; 32]],
            exponent(4),
            ring(),
            &[output(4, 10)],
            0,
            &next_people_paseo(),
        )
        .expect("balanced");

        assert_eq!(args.index, 4);
        assert_eq!(args.revision, 9);
        assert_eq!(args.value, 4);
    }

    #[test]
    fn an_empty_unload_group_is_refused() {
        assert!(
            UnloadRecyclerIntoCoinsArgs::new(
                Vec::new(),
                exponent(4),
                ring(),
                &[],
                0,
                &next_people_paseo()
            )
            .is_err()
        );
    }

    #[test]
    fn a_group_beyond_the_consolidation_cap_is_refused() {
        let constants = CoinageChainConstants {
            max_consolidation: 2,
            ..next_people_paseo()
        };
        let aliases = vec![[1u8; 32], [2u8; 32], [3u8; 32]];
        let outputs = vec![output(5, 10), output(4, 11)];

        assert!(
            UnloadRecyclerIntoCoinsArgs::new(aliases, exponent(4), ring(), &outputs, 0, &constants)
                .is_err()
        );
    }

    #[test]
    fn split_arguments_encode_as_the_pallet_declares_them() {
        let args = SplitArgs::new(
            exponent(1),
            &[output(0, 1), output(0, 2)],
            &next_people_paseo(),
        )
        .expect("2 = 1 + 1");

        // One denomination group, value 0, two 32-byte destinations.
        let expected = vec![(0i8, vec![[1u8; 32], [2u8; 32]])].encode();

        assert_eq!(args.encode(), expected);
    }
}
