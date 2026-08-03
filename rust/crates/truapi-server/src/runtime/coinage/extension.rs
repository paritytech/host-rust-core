//! The `AsCoinage` transaction extension.
//!
//! Coinage calls do not carry a conventional signed origin. The extension
//! transmutes the transaction's origin into `Origin::Coin` or
//! `Origin::UnloadToken`, consuming the coin or the unload token as it does so —
//! *before* dispatch. That ordering is why the rest of this layer validates so
//! much locally: once the extension has run, a call that fails has already cost
//! the coin.
//!
//! The extra is `AsCoinage(Option<AsCoinageInfo>)`. This module builds those
//! bytes. Two things about the encoding are worth stating plainly, because
//! getting either wrong yields an extrinsic the chain rejects with no useful
//! diagnosis:
//!
//! * The variant index is resolved from metadata by name, never hard-coded.
//!   SCALE variant indices are positional and a runtime upgrade may reorder
//!   them.
//! * Ring-VRF proofs pass through verbatim. They are runtime-specific types
//!   whose layout this crate does not model, so they arrive already encoded and
//!   are spliced in without a wrapping length prefix.

use parity_scale_codec::Encode;

use super::call::RawEncoded;
use crate::host_logic::coinage::error::CoinageError;
use crate::host_logic::coinage::types::{DenominationExponent, RingLocation};
use crate::runtime::statement_allowance::extension::Metadata;

/// Transaction-extension identifier as it appears in runtime metadata.
pub const AS_COINAGE: &str = "AsCoinage";

/// Signing context prefix for the personhood proof backing a free unload token.
///
/// The full context is this prefix followed by the period and counter as
/// little-endian `u32`s.
pub const UNLOAD_TOKEN_CONTEXT_PREFIX: &[u8] = b"pop:polkadot.net/coinftk";

/// Alias context for a recycler entry's contextual alias.
pub const RECYCLER_ALIAS_CONTEXT: &[u8] = b"pop:polkadot.network/coinrecyclr";

/// Which membership ring backs a free unload token.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum FreeTokenRing {
    /// Full personhood.
    People,
    /// Lite personhood.
    LitePeople,
}

impl FreeTokenRing {
    /// The `AsCoinageInfo` variant name for this ring.
    pub const fn variant_name(self) -> &'static str {
        match self {
            Self::People => "AsUnloadTokenPeople",
            Self::LitePeople => "AsUnloadTokenLitePeople",
        }
    }
}

/// How the origin for a coinage call should be obtained.
///
/// Mirrors the pallet's `AsCoinageInfo`. Payload field order matches the
/// pallet's declaration, because SCALE encodes struct variants positionally.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum AsCoinageInfo {
    /// Transmute the signed origin into `Origin::Coin`, for `split`, `transfer`
    /// and `load_recycler_with_coin`.
    AsCoin,
    /// Transmute the unsigned origin into `Origin::UnloadToken` using a free
    /// token backed by personhood.
    FreeUnloadToken {
        /// Which membership ring backs the token.
        ring: FreeTokenRing,
        /// Personhood membership proof.
        proof: RawEncoded,
        /// Token period.
        period: u32,
        /// Counter within the period.
        counter: u32,
        /// One alias proof per entry being unloaded.
        alias_proofs: Vec<RawEncoded>,
    },
    /// Transmute the unsigned origin using a token from the period's paid ring.
    PaidUnloadToken {
        /// Paid-ring membership proof.
        proof: RawEncoded,
        /// Token period.
        period: u32,
        /// Paid-token ring the proof was built against.
        ring: RingLocation,
        /// One alias proof per entry being unloaded.
        alias_proofs: Vec<RawEncoded>,
    },
    /// Transmute the unsigned origin with the fee taken from the unloaded value.
    ///
    /// The first alias proof is pre-validated by the extension for spam
    /// protection and must be skipped by call-level validation, so ordering
    /// here is load-bearing: the fee recycler's proof comes first.
    UnloadTokenFromOutput {
        /// Denomination of the fee recycler, which must equal the first input's.
        fee_recycler_value: DenominationExponent,
        /// Ring of the fee recycler, which must equal the first input's.
        fee_recycler_ring: RingLocation,
        /// Retry counter for the extension's backoff.
        retry_counter: u8,
        /// One alias proof per entry, fee recycler first.
        alias_proofs: Vec<RawEncoded>,
    },
    /// A conventional signed origin that the pallet guarantees will not fail
    /// before dispatch.
    InfallibleUnpaidSigned {
        /// Account nonce.
        nonce: u32,
    },
}

impl AsCoinageInfo {
    /// The pallet's variant name, used to resolve the index from metadata.
    pub const fn variant_name(&self) -> &'static str {
        match self {
            Self::AsCoin => "AsCoin",
            Self::FreeUnloadToken { ring, .. } => ring.variant_name(),
            Self::PaidUnloadToken { .. } => "AsUnloadTokenPaid",
            Self::UnloadTokenFromOutput { .. } => "AsUnloadTokenFromOutput",
            Self::InfallibleUnpaidSigned { .. } => "InfallibleUnpaidSigned",
        }
    }

    /// The alias proofs this variant carries, if any.
    pub fn alias_proofs(&self) -> &[RawEncoded] {
        match self {
            Self::FreeUnloadToken { alias_proofs, .. }
            | Self::PaidUnloadToken { alias_proofs, .. }
            | Self::UnloadTokenFromOutput { alias_proofs, .. } => alias_proofs,
            Self::AsCoin | Self::InfallibleUnpaidSigned { .. } => &[],
        }
    }

    /// The variant's payload, without the leading variant index.
    fn encode_payload(&self) -> Vec<u8> {
        match self {
            Self::AsCoin => Vec::new(),
            Self::FreeUnloadToken {
                ring: _,
                proof,
                period,
                counter,
                alias_proofs,
            } => {
                let mut encoded = proof.encode();
                encoded.extend(period.encode());
                encoded.extend(counter.encode());
                encoded.extend(alias_proofs.encode());
                encoded
            }
            Self::PaidUnloadToken {
                proof,
                period,
                ring,
                alias_proofs,
            } => {
                let mut encoded = proof.encode();
                encoded.extend(period.encode());
                encoded.extend(ring.index.0.encode());
                encoded.extend(ring.revision.0.encode());
                encoded.extend(alias_proofs.encode());
                encoded
            }
            Self::UnloadTokenFromOutput {
                fee_recycler_value,
                fee_recycler_ring,
                retry_counter,
                alias_proofs,
            } => {
                let mut encoded = fee_recycler_value.get().encode();
                encoded.extend(fee_recycler_ring.index.0.encode());
                encoded.extend(fee_recycler_ring.revision.0.encode());
                encoded.extend(retry_counter.encode());
                encoded.extend(alias_proofs.encode());
                encoded
            }
            Self::InfallibleUnpaidSigned { nonce } => nonce.encode(),
        }
    }

    /// Encode the extension's extra: `Some(info)` with the index resolved from
    /// metadata.
    pub fn encode_extra(&self, metadata: &Metadata) -> Result<Vec<u8>, CoinageError> {
        let index = metadata
            .extension_info_variant_index(AS_COINAGE, self.variant_name())
            .map_err(|error| {
                CoinageError::Internal(format!("resolving {AS_COINAGE} variant failed: {error}"))
            })?;

        Ok(self.encode_extra_with_index(index))
    }

    /// Encode the extra against an already-resolved variant index.
    ///
    /// The leading `1` is the `Option`'s `Some` discriminant.
    pub fn encode_extra_with_index(&self, variant_index: u8) -> Vec<u8> {
        let mut encoded = vec![1u8, variant_index];
        encoded.extend(self.encode_payload());
        encoded
    }
}

/// The extra for a transaction that declares no coinage origin.
pub fn encode_absent_extra() -> Vec<u8> {
    vec![0u8]
}

/// The signing context for a free unload token's personhood proof.
///
/// `prefix ++ period_le ++ counter_le`.
pub fn free_token_signing_context(period: u32, counter: u32) -> Vec<u8> {
    let mut context = UNLOAD_TOKEN_CONTEXT_PREFIX.to_vec();
    context.extend(period.to_le_bytes());
    context.extend(counter.to_le_bytes());
    context
}

/// The message a free unload token's personhood proof signs.
///
/// `blake2_256(alias_proofs.encode() ++ inherited_implication)`. The alias
/// proofs are inside the signed message, which is what binds the token to the
/// exact set of entries being unloaded.
pub fn free_token_proof_message(
    alias_proofs: &[RawEncoded],
    inherited_implication: &[u8],
) -> [u8; 32] {
    let mut message = alias_proofs.encode();
    message.extend_from_slice(inherited_implication);
    crate::runtime::statement_allowance::extension::blake2b256(&message)
}

/// The message an individual alias proof signs: `blake2_256(inherited_implication)`.
pub fn alias_proof_message(inherited_implication: &[u8]) -> [u8; 32] {
    crate::runtime::statement_allowance::extension::blake2b256(inherited_implication)
}

#[cfg(test)]
mod tests {
    use crate::host_logic::coinage::types::{RevisionIndex, RingIndex};

    use super::*;

    fn proof(byte: u8) -> RawEncoded {
        RawEncoded(vec![byte; 4])
    }

    fn ring() -> RingLocation {
        RingLocation::new(RingIndex(7), RevisionIndex(3))
    }

    fn exponent(value: i8) -> DenominationExponent {
        DenominationExponent::new(value).expect("exponent is in range")
    }

    #[test]
    fn an_absent_extra_is_the_option_none_byte() {
        assert_eq!(encode_absent_extra(), vec![0u8]);
    }

    #[test]
    fn as_coin_carries_no_payload() {
        let extra = AsCoinageInfo::AsCoin.encode_extra_with_index(0);

        // `Some`, then the variant index, and nothing more.
        assert_eq!(extra, vec![1u8, 0]);
    }

    #[test]
    fn the_infallible_signed_variant_matches_the_known_layout() {
        // Cross-check against the shape the CLI already submits: Some, variant
        // index, then the nonce as a little-endian u32.
        let extra = AsCoinageInfo::InfallibleUnpaidSigned { nonce: 5 }.encode_extra_with_index(5);

        assert_eq!(extra, vec![1u8, 5, 5, 0, 0, 0]);
    }

    #[test]
    fn a_free_token_encodes_proof_then_period_counter_then_aliases() {
        let info = AsCoinageInfo::FreeUnloadToken {
            ring: FreeTokenRing::People,
            proof: proof(0xAA),
            period: 1,
            counter: 2,
            alias_proofs: vec![proof(0xBB), proof(0xCC)],
        };

        let extra = info.encode_extra_with_index(1);
        let mut expected = vec![1u8, 1];
        expected.extend([0xAA; 4]); // proof, spliced verbatim
        expected.extend(1u32.encode()); // period
        expected.extend(2u32.encode()); // counter
        expected.extend(vec![proof(0xBB), proof(0xCC)].encode()); // compact len + blobs

        assert_eq!(extra, expected);
    }

    #[test]
    fn alias_proofs_carry_a_compact_length_but_the_blobs_do_not() {
        let proofs = vec![proof(1), proof(2)];
        let encoded = proofs.encode();

        // Compact(2) then two 4-byte blobs, with no per-blob prefix.
        assert_eq!(encoded.len(), 1 + 8);
        assert_eq!(encoded[0], 8); // compact encoding of 2
        assert_eq!(&encoded[1..5], &[1u8; 4]);
    }

    #[test]
    fn the_two_free_token_rings_resolve_to_different_variants() {
        assert_eq!(FreeTokenRing::People.variant_name(), "AsUnloadTokenPeople");
        assert_eq!(
            FreeTokenRing::LitePeople.variant_name(),
            "AsUnloadTokenLitePeople"
        );
    }

    #[test]
    fn a_paid_token_encodes_both_halves_of_its_ring() {
        let info = AsCoinageInfo::PaidUnloadToken {
            proof: proof(1),
            period: 9,
            ring: ring(),
            alias_proofs: vec![proof(2)],
        };

        let extra = info.encode_extra_with_index(3);
        let mut expected = vec![1u8, 3];
        expected.extend([1u8; 4]);
        expected.extend(9u32.encode());
        expected.extend(7u32.encode()); // ring index
        expected.extend(3u32.encode()); // ring revision
        expected.extend(vec![proof(2)].encode());

        assert_eq!(extra, expected);
    }

    #[test]
    fn from_output_encodes_the_fee_recycler_before_the_retry_counter() {
        let info = AsCoinageInfo::UnloadTokenFromOutput {
            fee_recycler_value: exponent(4),
            fee_recycler_ring: ring(),
            retry_counter: 2,
            alias_proofs: vec![proof(5)],
        };

        let extra = info.encode_extra_with_index(4);
        let mut expected = vec![1u8, 4];
        expected.extend(4i8.encode()); // fee recycler denomination
        expected.extend(7u32.encode());
        expected.extend(3u32.encode());
        expected.extend(2u8.encode()); // retry counter
        expected.extend(vec![proof(5)].encode());

        assert_eq!(extra, expected);
    }

    #[test]
    fn variant_names_match_the_pallet() {
        assert_eq!(AsCoinageInfo::AsCoin.variant_name(), "AsCoin");
        assert_eq!(
            AsCoinageInfo::InfallibleUnpaidSigned { nonce: 0 }.variant_name(),
            "InfallibleUnpaidSigned"
        );
        assert_eq!(
            AsCoinageInfo::PaidUnloadToken {
                proof: proof(0),
                period: 0,
                ring: ring(),
                alias_proofs: Vec::new(),
            }
            .variant_name(),
            "AsUnloadTokenPaid"
        );
    }

    #[test]
    fn only_unload_variants_carry_alias_proofs() {
        assert!(AsCoinageInfo::AsCoin.alias_proofs().is_empty());
        assert!(
            AsCoinageInfo::InfallibleUnpaidSigned { nonce: 0 }
                .alias_proofs()
                .is_empty()
        );
        assert_eq!(
            AsCoinageInfo::FreeUnloadToken {
                ring: FreeTokenRing::LitePeople,
                proof: proof(0),
                period: 0,
                counter: 0,
                alias_proofs: vec![proof(1), proof(2)],
            }
            .alias_proofs()
            .len(),
            2
        );
    }

    #[test]
    fn the_free_token_context_appends_period_then_counter() {
        let context = free_token_signing_context(0x0102_0304, 0x0506_0708);

        assert_eq!(
            &context[..UNLOAD_TOKEN_CONTEXT_PREFIX.len()],
            UNLOAD_TOKEN_CONTEXT_PREFIX
        );
        assert_eq!(
            &context[UNLOAD_TOKEN_CONTEXT_PREFIX.len()..],
            &[0x04, 0x03, 0x02, 0x01, 0x08, 0x07, 0x06, 0x05]
        );
    }

    #[test]
    fn the_free_token_message_binds_the_alias_set() {
        // Changing which entries are being unloaded must change the message the
        // personhood proof signs, or a token could be replayed against a
        // different set.
        let implication = [9u8; 8];
        let one = free_token_proof_message(&[proof(1)], &implication);
        let two = free_token_proof_message(&[proof(1), proof(2)], &implication);

        assert_ne!(one, two);
    }

    #[test]
    fn the_free_token_message_also_binds_the_implication() {
        let proofs = [proof(1)];

        assert_ne!(
            free_token_proof_message(&proofs, &[1u8; 8]),
            free_token_proof_message(&proofs, &[2u8; 8])
        );
    }

    #[test]
    fn an_alias_proof_signs_the_bare_implication() {
        let implication = [4u8; 8];

        assert_eq!(
            alias_proof_message(&implication),
            crate::runtime::statement_allowance::extension::blake2b256(&implication)
        );
    }
}
