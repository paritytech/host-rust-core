//! Unsigned General (v5) extrinsic assembly for coinage calls.
//!
//! A coinage extrinsic is unusual in that it carries no signature: the origin
//! comes from the `AsCoinage` extension, which transmutes it into
//! `Origin::Coin` or `Origin::UnloadToken` and consumes the coin or the token as
//! it does so. The proofs inside the extension are what authorize it.
//!
//! That creates an ordering the caller has to respect, and it is the reason this
//! module exposes the implication separately rather than hiding it:
//!
//! 1. Build the call.
//! 2. Compute the **inherited implication** — everything the extension signs
//!    over, which depends on the call and on the extensions that follow.
//! 3. Prove against that implication.
//! 4. Encode the extension extra with those proofs.
//! 5. Assemble the extrinsic.
//!
//! Steps 2 and 3 cannot be reordered. A proof built before the call is known
//! signs the wrong thing, and the runtime rejects it without saying why.
//!
//! Dispatch indices are resolved by name from metadata, so a re-indexed runtime
//! fails loudly instead of encoding some other call.

use parity_scale_codec::Encode;

use super::extension::AS_COINAGE;
use crate::host_logic::coinage::error::CoinageError;
use crate::runtime::statement_allowance::extension::{ChainState, Metadata};

/// Pallet whose calls this module builds.
const PALLET: &str = "Coinage";

/// General-transaction preamble byte: `0b01` (General) | version 5.
const GENERAL_V5_PREAMBLE: u8 = 0x45;

/// Current transaction-extension version byte.
const EXTENSION_VERSION: u8 = 0x00;

/// A coinage dispatchable, by pallet call name.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum CoinageCall {
    /// `Coinage::split`.
    Split,
    /// `Coinage::transfer`.
    Transfer,
    /// `Coinage::load_recycler_with_coin`.
    LoadRecyclerWithCoin,
    /// `Coinage::unload_recycler_into_coins`.
    UnloadRecyclerIntoCoins,
}

impl CoinageCall {
    /// The pallet's name for this call.
    pub const fn name(self) -> &'static str {
        match self {
            Self::Split => "split",
            Self::Transfer => "transfer",
            Self::LoadRecyclerWithCoin => "load_recycler_with_coin",
            Self::UnloadRecyclerIntoCoins => "unload_recycler_into_coins",
        }
    }
}

/// Dispatch bytes plus SCALE-encoded arguments.
///
/// `args` comes from the matching type in [`super::call`], which has already
/// checked the pallet's own constraints on it.
pub fn build_call(
    metadata: &Metadata,
    call: CoinageCall,
    args: &impl Encode,
) -> Result<Vec<u8>, CoinageError> {
    let indices = metadata
        .call_indices(PALLET, call.name())
        .map_err(|error| {
            CoinageError::Internal(format!(
                "resolving {PALLET}.{} failed: {error}",
                call.name()
            ))
        })?;

    let mut encoded = indices.to_vec();
    encoded.extend(args.encode());
    Ok(encoded)
}

/// The bytes the `AsCoinage` proofs sign over.
///
/// Returned unhashed because the two proof kinds hash different things: an alias
/// proof signs `blake2_256(implication)`, while a free unload token signs
/// `blake2_256(alias_proofs ++ implication)`.
pub fn inherited_implication(
    metadata: &Metadata,
    call_data: &[u8],
    state: &ChainState,
) -> Result<Vec<u8>, CoinageError> {
    metadata
        .inherited_implication(AS_COINAGE, call_data, state)
        .map_err(|error| {
            CoinageError::Internal(format!(
                "building the {AS_COINAGE} implication failed: {error}"
            ))
        })
}

/// Assemble the unsigned extrinsic, splicing `as_coinage_extra` into the
/// extension slot metadata says it occupies.
pub fn build_unsigned_extrinsic(
    metadata: &Metadata,
    state: &ChainState,
    call_data: &[u8],
    as_coinage_extra: &[u8],
) -> Result<Vec<u8>, CoinageError> {
    let all = metadata.encode_signed_extensions(state);
    let slot = metadata.extension_index(AS_COINAGE).ok_or_else(|| {
        CoinageError::Internal(format!("{AS_COINAGE} extension not found in metadata"))
    })?;

    let mut body = vec![GENERAL_V5_PREAMBLE, EXTENSION_VERSION];
    for (position, extension) in all.iter().enumerate() {
        if position == slot {
            body.extend_from_slice(as_coinage_extra);
        } else {
            body.extend_from_slice(&extension.extra);
        }
    }
    body.extend_from_slice(call_data);

    // The outer length prefix an extrinsic carries on the wire.
    Ok(body.encode())
}

#[cfg(test)]
mod tests {
    use crate::host_logic::coinage::chain_constants::next_people_paseo;
    use crate::host_logic::coinage::types::{CoinAccountId, DenominationExponent};
    use crate::runtime::coinage::call::{CoinOutput, SplitArgs, TransferArgs};
    use crate::runtime::coinage::extension::AsCoinageInfo;

    use super::*;

    const FIXTURE: &[u8] = include_bytes!("../../../tests/fixtures/paseo-next-v2-metadata.scale");

    fn metadata() -> Metadata {
        Metadata::decode(FIXTURE).expect("the fixture decodes")
    }

    fn state() -> ChainState {
        ChainState {
            spec_version: 1_000_000,
            transaction_version: 1,
            genesis_hash: [0xab; 32],
            nonce: 0,
        }
    }

    fn exponent(value: i8) -> DenominationExponent {
        DenominationExponent::new(value).expect("exponent is in range")
    }

    #[test]
    fn the_fixture_runtime_carries_coinage() {
        // Everything else here depends on it. Asserted rather than guarded: a
        // fixture regenerated without coinage must fail loudly, not quietly
        // turn the rest of this suite into no-ops.
        let metadata = metadata();

        assert!(metadata.call_indices(PALLET, "transfer").is_ok());
        assert!(metadata.extension_index(AS_COINAGE).is_some());
    }

    #[test]
    fn a_call_is_dispatch_bytes_then_arguments() {
        let metadata = metadata();

        let args = TransferArgs::new(CoinAccountId([5; 32]));
        let call = build_call(&metadata, CoinageCall::Transfer, &args).expect("resolves");

        let indices = metadata.call_indices(PALLET, "transfer").expect("resolves");
        assert_eq!(&call[..2], &indices);
        assert_eq!(&call[2..], &[5u8; 32]);
    }

    #[test]
    fn an_unknown_call_name_fails_loudly() {
        // Guards the by-name discipline: nothing here may fall back to a
        // hard-coded index.
        let metadata = metadata();

        assert!(
            metadata
                .call_indices(PALLET, "definitely_not_a_call")
                .is_err()
        );
    }

    #[test]
    fn the_implication_covers_the_call() {
        let metadata = metadata();
        let first = build_call(
            &metadata,
            CoinageCall::Transfer,
            &TransferArgs::new(CoinAccountId([1; 32])),
        )
        .expect("resolves");
        let second = build_call(
            &metadata,
            CoinageCall::Transfer,
            &TransferArgs::new(CoinAccountId([2; 32])),
        )
        .expect("resolves");

        let one = inherited_implication(&metadata, &first, &state()).expect("builds");
        let two = inherited_implication(&metadata, &second, &state()).expect("builds");

        // A proof built for one call must not validate for another.
        assert_ne!(one, two);
        assert_eq!(one[0], EXTENSION_VERSION);
        assert_eq!(&one[1..1 + first.len()], &first[..]);
    }

    #[test]
    fn the_implication_covers_chain_state() {
        let metadata = metadata();
        let call = build_call(
            &metadata,
            CoinageCall::Transfer,
            &TransferArgs::new(CoinAccountId([1; 32])),
        )
        .expect("resolves");

        let here = inherited_implication(&metadata, &call, &state()).expect("builds");
        let elsewhere = inherited_implication(
            &metadata,
            &call,
            &ChainState {
                genesis_hash: [0xcd; 32],
                ..state()
            },
        )
        .expect("builds");

        assert_ne!(
            here, elsewhere,
            "an implication must bind the chain it was built for"
        );
    }

    #[test]
    fn an_assembled_extrinsic_carries_the_preamble_and_the_extra() {
        let metadata = metadata();
        let call = build_call(
            &metadata,
            CoinageCall::Transfer,
            &TransferArgs::new(CoinAccountId([7; 32])),
        )
        .expect("resolves");
        let extra = AsCoinageInfo::AsCoin
            .encode_extra(&metadata)
            .expect("resolves");

        let extrinsic =
            build_unsigned_extrinsic(&metadata, &state(), &call, &extra).expect("assembles");

        // A compact length prefix, then the General v5 preamble.
        let body_start = extrinsic.len() - (extrinsic.len() - 1);
        assert!(extrinsic.len() > call.len() + extra.len());
        assert_eq!(extrinsic[body_start], GENERAL_V5_PREAMBLE);
        // The call is the tail of the body.
        assert!(extrinsic.ends_with(&call));
        // And our extra appears verbatim.
        assert!(
            extrinsic
                .windows(extra.len())
                .any(|window| window == extra.as_slice())
        );
    }

    #[test]
    fn a_split_assembles_end_to_end() {
        let metadata = metadata();
        // 2^2 = 4 splits into 2 + 2, to two different accounts.
        let outputs = [
            CoinOutput {
                exponent: exponent(1),
                account: CoinAccountId([1; 32]),
            },
            CoinOutput {
                exponent: exponent(1),
                account: CoinAccountId([2; 32]),
            },
        ];
        let args =
            SplitArgs::new(exponent(2), &outputs, &next_people_paseo()).expect("value conserved");

        let call = build_call(&metadata, CoinageCall::Split, &args).expect("resolves");
        let extra = AsCoinageInfo::AsCoin
            .encode_extra(&metadata)
            .expect("resolves");
        let extrinsic =
            build_unsigned_extrinsic(&metadata, &state(), &call, &extra).expect("assembles");

        assert!(extrinsic.ends_with(&call));
    }
}
