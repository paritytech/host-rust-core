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
//!
//! # Coin origins carry a signature after all
//!
//! `AsCoinage::AsCoin` *transmutes* a signed origin into `Origin::Coin`; it does
//! not conjure one. The signature comes from the `VerifyMultiSignature`
//! extension, signed by the coin account's own sr25519 key, and the coin the
//! call spends is whichever account that signature names. So `split`, `transfer`
//! and `load_recycler_with_coin` are assembled by
//! [`build_coin_origin_extrinsic`], which fills two extension slots rather than
//! one.
//!
//! The order between those two slots is load-bearing and easy to get backwards.
//! `VerifyMultiSignature` sits *before* `AsCoinage` in the runtime's extension
//! list, so the implication it signs over includes `AsCoinage`'s extra. The
//! coinage extra must therefore be built first and be visible to the signature —
//! signing against the default `None` extra produces bytes the runtime rejects
//! as a bad proof, with nothing to say why.

use parity_scale_codec::Encode;
use schnorrkel::Keypair;

use super::extension::{AS_COINAGE, AsCoinageInfo};
use crate::host_logic::coinage::error::CoinageError;
use crate::host_logic::coinage::types::CoinAccountId;
use crate::host_logic::product_account::SR25519_SIGNING_CONTEXT;
use crate::runtime::statement_allowance::extension::{ChainState, Metadata, blake2b256};

/// Pallet whose calls this module builds.
const PALLET: &str = "Coinage";

/// Extension that turns a signature into the signed origin `AsCoinage` consumes.
pub const VERIFY_MULTI_SIGNATURE: &str = "VerifyMultiSignature";

/// `VerifySignature::Signed` variant index.
const VERIFY_SIGNATURE_SIGNED: u8 = 1;

/// `MultiSignature::Sr25519` variant index.
const MULTI_SIGNATURE_SR25519: u8 = 1;

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
    /// `Coinage::unload_recycler_into_external_asset_and_vouchers`.
    UnloadRecyclerIntoExternalAssetAndVouchers,
    /// `Coinage::load_recycler_with_external_asset_unpaid_batch`.
    LoadRecyclerWithExternalAssetUnpaidBatch,
}

impl CoinageCall {
    /// The pallet's name for this call.
    pub const fn name(self) -> &'static str {
        match self {
            Self::Split => "split",
            Self::Transfer => "transfer",
            Self::LoadRecyclerWithCoin => "load_recycler_with_coin",
            Self::UnloadRecyclerIntoCoins => "unload_recycler_into_coins",
            Self::UnloadRecyclerIntoExternalAssetAndVouchers => {
                "unload_recycler_into_external_asset_and_vouchers"
            }
            Self::LoadRecyclerWithExternalAssetUnpaidBatch => {
                "load_recycler_with_external_asset_unpaid_batch"
            }
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

/// One extension slot whose encoding is supplied rather than derived from
/// metadata defaults.
type SlotOverride = (usize, Vec<u8>);

/// The extension extras in metadata order, with `overrides` applied.
fn extras_with(
    metadata: &Metadata,
    state: &ChainState,
    overrides: &[SlotOverride],
) -> Vec<Vec<u8>> {
    metadata
        .encode_signed_extensions(state)
        .into_iter()
        .enumerate()
        .map(|(position, extension)| {
            overrides
                .iter()
                .find(|(slot, _)| *slot == position)
                .map_or(extension.extra, |(_, extra)| extra.clone())
        })
        .collect()
}

/// The slot an extension occupies, or a loud failure.
fn slot_of(metadata: &Metadata, identifier: &str) -> Result<usize, CoinageError> {
    metadata.extension_index(identifier).ok_or_else(|| {
        CoinageError::Internal(format!("{identifier} extension not found in metadata"))
    })
}

/// The bytes `VerifyMultiSignature` signs over, with the coinage extra in place.
///
/// Built separately from [`inherited_implication`] because the two extensions
/// sit at different positions: this implication *contains* the coinage extra,
/// while the coinage one does not contain its own.
fn signature_implication(
    metadata: &Metadata,
    call_data: &[u8],
    state: &ChainState,
    as_coinage_extra: &[u8],
) -> Result<Vec<u8>, CoinageError> {
    let signature_slot = slot_of(metadata, VERIFY_MULTI_SIGNATURE)?;
    let coinage_slot = slot_of(metadata, AS_COINAGE)?;
    if coinage_slot <= signature_slot {
        return Err(CoinageError::Internal(format!(
            "{AS_COINAGE} precedes {VERIFY_MULTI_SIGNATURE} in this runtime, so a coin origin \
             cannot be signed over its own extra"
        )));
    }

    let extras = extras_with(
        metadata,
        state,
        &[(coinage_slot, as_coinage_extra.to_vec())],
    );
    let implicits = metadata.encode_signed_extensions(state);

    let mut payload = vec![EXTENSION_VERSION];
    payload.extend_from_slice(call_data);
    for extra in extras.iter().skip(signature_slot + 1) {
        payload.extend_from_slice(extra);
    }
    for extension in implicits.iter().skip(signature_slot + 1) {
        payload.extend_from_slice(&extension.additional_signed);
    }
    Ok(payload)
}

/// The `VerifySignature::Signed` extra for an sr25519 signature over `message`.
fn signed_extra(signature: &[u8; 64], account: CoinAccountId) -> Vec<u8> {
    let mut extra = vec![VERIFY_SIGNATURE_SIGNED, MULTI_SIGNATURE_SR25519];
    extra.extend_from_slice(signature);
    extra.extend_from_slice(&account.0);
    extra
}

/// Assemble a coinage extrinsic whose origin is the coin `keypair` controls.
///
/// Signs `blake2_256(implication)` with the coin's own key, which is what makes
/// the coin account the signed origin `AsCoinage::AsCoin` then transmutes into
/// `Origin::Coin`. The account the signature names *is* the coin being spent, so
/// a caller that signs with the wrong key does not get a rejected proof — it gets
/// a different coin spent.
pub fn build_coin_origin_extrinsic(
    metadata: &Metadata,
    state: &ChainState,
    call_data: &[u8],
    keypair: &Keypair,
) -> Result<Vec<u8>, CoinageError> {
    let as_coinage_extra = AsCoinageInfo::AsCoin.encode_extra(metadata)?;
    let implication = signature_implication(metadata, call_data, state, &as_coinage_extra)?;
    let message = blake2b256(&implication);

    let signature = keypair
        .sign_simple(SR25519_SIGNING_CONTEXT, &message)
        .to_bytes();
    let account = CoinAccountId(keypair.public.to_bytes());

    build_extrinsic_with(
        metadata,
        state,
        call_data,
        &[
            (
                slot_of(metadata, VERIFY_MULTI_SIGNATURE)?,
                signed_extra(&signature, account),
            ),
            (slot_of(metadata, AS_COINAGE)?, as_coinage_extra),
        ],
    )
}

/// Assemble the unsigned extrinsic, splicing `as_coinage_extra` into the
/// extension slot metadata says it occupies.
///
/// Refuses an immortal `state`. Mortality is a correctness requirement for this
/// layer, not a fee optimization: recovery decides that a lost transaction is
/// dead by watching the finalized height pass the era's end, and an immortal
/// extrinsic never reaches such a point, so its inputs could never safely be
/// returned to the spendable pool. Enforced here because this is the one place
/// every coinage extrinsic passes through.
pub fn build_unsigned_extrinsic(
    metadata: &Metadata,
    state: &ChainState,
    call_data: &[u8],
    as_coinage_extra: &[u8],
) -> Result<Vec<u8>, CoinageError> {
    let slot = slot_of(metadata, AS_COINAGE)?;
    build_extrinsic_with(
        metadata,
        state,
        call_data,
        &[(slot, as_coinage_extra.to_vec())],
    )
}

/// Assemble the extrinsic with an arbitrary set of extension slots supplied.
///
/// The mortality refusal lives here because this is the one place every coinage
/// extrinsic — signed coin origin or unload token — passes through.
fn build_extrinsic_with(
    metadata: &Metadata,
    state: &ChainState,
    call_data: &[u8],
    overrides: &[SlotOverride],
) -> Result<Vec<u8>, CoinageError> {
    if state.mortality.is_none() {
        return Err(CoinageError::Internal(
            "a coinage extrinsic must be mortal; chain state carries no era anchor".to_string(),
        ));
    }

    let mut body = vec![GENERAL_V5_PREAMBLE, EXTENSION_VERSION];
    for extra in extras_with(metadata, state, overrides) {
        body.extend_from_slice(&extra);
    }
    body.extend_from_slice(call_data);

    // The outer length prefix an extrinsic carries on the wire.
    Ok(body.encode())
}

/// Who holds the external asset a top-up converts, and who signs for it (§8.2).
///
/// The layer never holds this account: a top-up moves value that is not coinage
/// yet, from an account the caller owns. So the caller signs, and the layer only
/// says what to sign.
pub trait FundingOrigin {
    /// The account holding the external asset.
    fn external_account(&self) -> CoinAccountId;

    /// Sign the extrinsic's signer payload with that account's sr25519 key.
    fn sign(&self, payload: &[u8]) -> [u8; 64];

    /// Sign a protected value transfer, if the runtime gates one.
    ///
    /// Not in `coinage-layer.md` §8.2, and deliberately defaulted away: the
    /// deployed runtime puts test-asset transfers behind an `AuthorizeValueTransfer`
    /// extension holding an Ed25519 signature, and an origin that cannot produce one
    /// simply omits the extra — which is right for a runtime that does not gate it,
    /// and a loud refusal on one that does.
    fn authorize_value_transfer(&self, _message: &[u8; 32]) -> Option<[u8; 64]> {
        None
    }
}

/// Extension gating protected test-asset transfers on the deployed runtime.
pub const AUTHORIZE_VALUE_TRANSFER: &str = "AuthorizeValueTransfer";

/// Signed Extrinsic V4 version byte.
const V4_SIGNED: u8 = 0x84;

/// `MultiAddress::Id` discriminant.
const MULTI_ADDRESS_ID: u8 = 0x00;

/// Assemble a signed V4 extrinsic for an external-asset load (§8.2).
///
/// Not a General v5 transaction like the rest of this module, because its origin is
/// an ordinary account rather than a coin or a token: `AsCoinage` carries
/// `InfallibleUnpaidSigned`, which transmutes a conventional signed origin the
/// pallet promises will not fail before dispatch.
///
/// The two extension extras are filled in a fixed order, and the order is not
/// arbitrary. `AuthorizeValueTransfer` signs over everything that follows it, which
/// includes the coinage extra — so the coinage extra has to exist first, exactly as
/// it does for a coin origin.
pub fn build_external_asset_load_extrinsic(
    metadata: &Metadata,
    state: &ChainState,
    origin: &dyn FundingOrigin,
    nonce: u32,
    call_data: &[u8],
) -> Result<Vec<u8>, CoinageError> {
    let mut state = *state;
    state.nonce = nonce;

    let coinage_slot = slot_of(metadata, AS_COINAGE)?;
    let coinage_extra = AsCoinageInfo::InfallibleUnpaidSigned { nonce }.encode_extra(metadata)?;
    let mut overrides = vec![(coinage_slot, coinage_extra)];

    // The authorization signs the implication of its own slot, with the coinage
    // extra already in place.
    if let Some(authorization_slot) = metadata.extension_index(AUTHORIZE_VALUE_TRANSFER) {
        let extras = extras_with(metadata, &state, &overrides);
        let all = metadata.encode_signed_extensions(&state);

        let mut payload = vec![EXTENSION_VERSION];
        payload.extend_from_slice(call_data);
        for extra in extras.iter().skip(authorization_slot + 1) {
            payload.extend_from_slice(extra);
        }
        for extension in all.iter().skip(authorization_slot + 1) {
            payload.extend_from_slice(&extension.additional_signed);
        }

        if let Some(signature) = origin.authorize_value_transfer(&blake2b256(&payload)) {
            let mut extra = vec![1u8];
            extra.extend_from_slice(&signature);
            overrides.push((authorization_slot, extra));
        }
    }

    let extras = extras_with(metadata, &state, &overrides);
    let implicits = metadata.encode_signed_extensions(&state);

    // V4's signer payload puts the call first, then every extra, then every
    // implicit — a different order from the body, and hashed once it grows past
    // 256 bytes.
    let mut signer_payload = call_data.to_vec();
    for extra in &extras {
        signer_payload.extend_from_slice(extra);
    }
    for extension in &implicits {
        signer_payload.extend_from_slice(&extension.additional_signed);
    }
    if signer_payload.len() > 256 {
        signer_payload = blake2b256(&signer_payload).to_vec();
    }

    let signature = origin.sign(&signer_payload);
    let mut body = vec![V4_SIGNED, MULTI_ADDRESS_ID];
    body.extend_from_slice(&origin.external_account().0);
    body.push(MULTI_SIGNATURE_SR25519);
    body.extend_from_slice(&signature);
    for extra in &extras {
        body.extend_from_slice(extra);
    }
    body.extend_from_slice(call_data);

    Ok(body.encode())
}

#[cfg(test)]
mod tests {
    use parity_scale_codec::CompactLen;

    use crate::host_logic::coinage::chain_constants::next_people_paseo;
    use crate::host_logic::coinage::derivation;
    use crate::host_logic::coinage::types::{CoinIndex, DenominationExponent, PurseId};
    use crate::runtime::coinage::call::{CoinOutput, SplitArgs, TransferArgs};
    use crate::runtime::statement_allowance::extension::EraAnchor;

    use super::*;

    const FIXTURE: &[u8] = include_bytes!("../../../tests/fixtures/paseo-next-v2-metadata.scale");

    fn metadata() -> Metadata {
        Metadata::decode(FIXTURE).expect("the fixture decodes")
    }

    /// A mortal chain state, because assembly refuses anything else.
    fn state() -> ChainState {
        ChainState {
            mortality: Some(EraAnchor::new(1_000, [0xcd; 32], 256)),
            ..immortal_state()
        }
    }

    fn immortal_state() -> ChainState {
        ChainState {
            spec_version: 1_000_000,
            transaction_version: 1,
            genesis_hash: [0xab; 32],
            nonce: 0,
            mortality: None,
        }
    }

    fn exponent(value: i8) -> DenominationExponent {
        DenominationExponent::new(value).expect("exponent is in range")
    }

    #[test]
    fn an_immortal_extrinsic_is_refused() {
        // The layer cannot recover an immortal transaction it loses track of:
        // there is no height past which inclusion becomes impossible, so its
        // inputs could never be released. Refused at assembly rather than
        // discovered during recovery.
        let metadata = metadata();
        let call = build_call(
            &metadata,
            CoinageCall::Transfer,
            &TransferArgs::new(CoinAccountId([1; 32])),
        )
        .expect("resolves");
        let extra = AsCoinageInfo::AsCoin
            .encode_extra(&metadata)
            .expect("resolves");

        let refused = build_unsigned_extrinsic(&metadata, &immortal_state(), &call, &extra)
            .expect_err("an immortal coinage extrinsic is refused");

        assert!(refused.to_string().contains("must be mortal"));
        assert!(build_unsigned_extrinsic(&metadata, &state(), &call, &extra).is_ok());
    }

    #[test]
    fn the_era_binds_the_extrinsic_to_its_anchor() {
        // Two extrinsics identical but for their era anchor must differ, or the
        // checkpoint recorded in the operation log would not describe the
        // transaction that was actually broadcast.
        let metadata = metadata();
        let call = build_call(
            &metadata,
            CoinageCall::Transfer,
            &TransferArgs::new(CoinAccountId([1; 32])),
        )
        .expect("resolves");
        let extra = AsCoinageInfo::AsCoin
            .encode_extra(&metadata)
            .expect("resolves");
        let elsewhere = ChainState {
            mortality: Some(EraAnchor::new(2_000, [0xef; 32], 256)),
            ..immortal_state()
        };

        let here = build_unsigned_extrinsic(&metadata, &state(), &call, &extra).expect("assembles");
        let there =
            build_unsigned_extrinsic(&metadata, &elsewhere, &call, &extra).expect("assembles");

        assert_ne!(here, there);
        assert_ne!(
            inherited_implication(&metadata, &call, &state()).expect("builds"),
            inherited_implication(&metadata, &call, &elsewhere).expect("builds"),
            "the proof must sign over the era it was built for"
        );
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

    /// The coin keypair a coin-origin extrinsic is signed with.
    fn coin_keypair(index: u32) -> Keypair {
        derivation::coin_keypair(&[7u8; 32], PurseId::MAIN, CoinIndex(index))
            .expect("derivation succeeds")
    }

    /// The signature and account the assembler put in the `VerifyMultiSignature`
    /// slot, read back out of the assembled bytes.
    ///
    /// sr25519 signs with a random nonce, so a test cannot re-derive the
    /// signature and compare: it has to read the one that was actually embedded.
    /// Locating it also pins the body layout — extras in metadata order, the call
    /// last.
    fn embedded_signature(
        metadata: &Metadata,
        state: &ChainState,
        extrinsic: &[u8],
        as_coinage_extra: &[u8],
    ) -> ([u8; 64], [u8; 32]) {
        let signature_slot = slot_of(metadata, VERIFY_MULTI_SIGNATURE).expect("present");
        let coinage_slot = slot_of(metadata, AS_COINAGE).expect("present");
        let extras = extras_with(
            metadata,
            state,
            &[(coinage_slot, as_coinage_extra.to_vec())],
        );

        // Skip the compact length prefix, the preamble and the version byte,
        // then every extra before the signature's slot.
        let prefix = parity_scale_codec::Compact::<u32>::compact_len(&(extrinsic.len() as u32 - 1));
        let mut cursor = prefix + 2;
        for extra in extras.iter().take(signature_slot) {
            cursor += extra.len();
        }

        assert_eq!(
            &extrinsic[cursor..cursor + 2],
            &[VERIFY_SIGNATURE_SIGNED, MULTI_SIGNATURE_SR25519],
            "the signature slot holds `Signed(Sr25519(..))`"
        );
        let signature: [u8; 64] = extrinsic[cursor + 2..cursor + 66]
            .try_into()
            .expect("64 bytes");
        let account: [u8; 32] = extrinsic[cursor + 66..cursor + 98]
            .try_into()
            .expect("32 bytes");
        (signature, account)
    }

    #[test]
    fn a_coin_origin_extrinsic_embeds_a_signature_that_verifies() {
        // Closes the loop the runtime will close: the bytes in the signature slot
        // verify, under sr25519, against the account named beside them, over the
        // implication that includes the coinage extra.
        let metadata = metadata();
        let keypair = coin_keypair(0);
        let call = build_call(
            &metadata,
            CoinageCall::Transfer,
            &TransferArgs::new(CoinAccountId([9; 32])),
        )
        .expect("resolves");
        let coinage_extra = AsCoinageInfo::AsCoin
            .encode_extra(&metadata)
            .expect("resolves");

        let extrinsic =
            build_coin_origin_extrinsic(&metadata, &state(), &call, &keypair).expect("assembles");

        let (signature, account) =
            embedded_signature(&metadata, &state(), &extrinsic, &coinage_extra);
        // The account the signature names *is* the coin being spent.
        assert_eq!(account, keypair.public.to_bytes());

        let implication = signature_implication(&metadata, &call, &state(), &coinage_extra)
            .expect("the runtime orders both");
        let parsed = schnorrkel::Signature::from_bytes(&signature).expect("64 bytes");
        assert!(
            keypair
                .public
                .verify_simple(SR25519_SIGNING_CONTEXT, &blake2b256(&implication), &parsed)
                .is_ok(),
            "the coin's own key must verify what was embedded"
        );
        assert!(extrinsic.ends_with(&call));
    }

    #[test]
    fn the_signed_message_covers_the_coinage_extra() {
        // The bug this guards: signing the implication built from metadata
        // defaults, where the coinage slot is `None`. The runtime would then see
        // a signature over bytes that are not the transaction it was handed, and
        // reject it as a bad proof with nothing to say why.
        let metadata = metadata();
        let call = build_call(
            &metadata,
            CoinageCall::Transfer,
            &TransferArgs::new(CoinAccountId([1; 32])),
        )
        .expect("resolves");
        let coinage_extra = AsCoinageInfo::AsCoin
            .encode_extra(&metadata)
            .expect("resolves");

        let with_coinage = signature_implication(&metadata, &call, &state(), &coinage_extra)
            .expect("the runtime orders both");
        let with_default = metadata
            .inherited_implication(VERIFY_MULTI_SIGNATURE, &call, &state())
            .expect("builds");

        assert_ne!(
            with_coinage, with_default,
            "the coin's signature must cover the coinage extra"
        );
        assert!(
            with_coinage
                .windows(coinage_extra.len())
                .any(|window| window == coinage_extra.as_slice()),
            "the coinage extra is inside what the coin signs"
        );
    }

    #[test]
    fn two_coins_sign_as_two_different_accounts() {
        let metadata = metadata();
        let call = build_call(
            &metadata,
            CoinageCall::Transfer,
            &TransferArgs::new(CoinAccountId([3; 32])),
        )
        .expect("resolves");
        let coinage_extra = AsCoinageInfo::AsCoin
            .encode_extra(&metadata)
            .expect("resolves");

        let first = build_coin_origin_extrinsic(&metadata, &state(), &call, &coin_keypair(0))
            .expect("assembles");
        let second = build_coin_origin_extrinsic(&metadata, &state(), &call, &coin_keypair(1))
            .expect("assembles");

        let (_, one) = embedded_signature(&metadata, &state(), &first, &coinage_extra);
        let (_, two) = embedded_signature(&metadata, &state(), &second, &coinage_extra);
        assert_ne!(one, two, "each coin signs as itself");
    }

    #[test]
    fn a_coin_origin_extrinsic_is_refused_when_immortal() {
        let metadata = metadata();
        let call = build_call(
            &metadata,
            CoinageCall::Transfer,
            &TransferArgs::new(CoinAccountId([1; 32])),
        )
        .expect("resolves");

        let refused =
            build_coin_origin_extrinsic(&metadata, &immortal_state(), &call, &coin_keypair(0))
                .expect_err("mortality is not optional for coinage");

        assert!(refused.to_string().contains("must be mortal"));
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
