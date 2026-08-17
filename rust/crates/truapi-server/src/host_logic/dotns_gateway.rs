//! dotNS gateway (Asset Hub) payload building and contract reads.
//!
//! Every host shares these helpers. They cover the candidate-signed
//! reservation message for `pallet_dotns_gateway::reserve_name`, the ring-VRF
//! proof message for `register_name`, the minimal Solidity ABI surface for
//! reading usernames back through `ReviveApi_call`, and the raw storage keys of
//! the gateway pallet.
//!
//! Username resolution ([`discover_pop_controller`], [`resolve_labels`]) is
//! written once against the [`DotnsTransport`] trait. The headless CLI's
//! plain-RPC reader and the in-core `chainHead_v1` lookup therefore walk the
//! same contract chain.
//!
//! Byte layouts mirror `pallets/dotns-gateway` in `paritytech/individuality`
//! and the dotNS contracts (`paritytech/dotns`).

use parity_scale_codec::{Compact, Decode, Encode};
use sp_crypto_hashing::{blake2_128, blake2_256, keccak_256, twox_128};
use thiserror::Error;

/// Ring-VRF context for `register_name` proofs.
///
/// The ASCII label, space-padded to 32 bytes. Matches `DOTNS_GATEWAY_CONTEXT`
/// in the gateway pallet.
pub const DOTNS_GATEWAY_CONTEXT: [u8; 32] = *b"pop:polkadot.network/dotns      ";

/// Reservation message prefix, matching `RESERVE_MSG_PREFIX` in the gateway
/// pallet.
pub const RESERVE_MSG_PREFIX: &[u8] = b"pop:dotns-gateway:reserve";

/// Origin for read-only `ReviveApi_call` dry-runs.
///
/// `pallet_revive` rejects unmapped signed origins with `AccountUnmapped`.
/// Eth-derived accounts — trailing 12 bytes `0xEE` — are implicitly mapped.
/// They need no on-chain state. Views therefore work from this synthetic
/// account on any network.
pub const VIEW_CALL_ORIGIN: [u8; 32] = {
    let mut origin = [0xEEu8; 32];
    let mut i = 0;
    while i < 20 {
        origin[i] = 0;
        i += 1;
    }
    origin
};

/// Builds the payload the candidate signs to authorize a lite-name
/// reservation.
///
/// Commits to the *base* of the lite label only. The digit suffix is excluded,
/// so the candidate can sign before the gateway assigns digits. Mirrors
/// `Pallet::construct_reservation_message`: a SCALE tuple of
/// `(prefix, candidate, attester, username_base, chat_key, reserved, signed_at)`.
pub fn build_reservation_message(
    candidate: &[u8; 32],
    attester: &[u8; 32],
    username_base: &[u8],
    chat_key: &[u8; 65],
    reserved_base_label: Option<&[u8]>,
    signed_at_secs: u64,
) -> Vec<u8> {
    (
        RESERVE_MSG_PREFIX,
        candidate,
        attester,
        username_base,
        chat_key.as_slice(),
        reserved_base_label,
        signed_at_secs,
    )
        .encode()
}

/// The `Link` argument of `register_name`: how the new full-person username
/// relates to the account's previous lite identity.
#[derive(Debug, Clone, PartialEq, Eq, Encode)]
pub enum Link {
    /// Links the full username to an existing lite username, in dotted form
    /// such as `alice.01`. The chat key is inherited from the lite entry.
    LiteUsername(Vec<u8>),
    /// Standalone registration carrying a fresh 65-byte uncompressed ECDH
    /// chat key.
    None([u8; 65]),
}

/// Hashes the registration intent into the 32-byte ring-VRF proof message.
/// Matches the pallet's `(who, label, link).using_encoded(blake2_256)`.
pub fn build_register_proof_message(who: &[u8; 32], label: &[u8], link: &Link) -> [u8; 32] {
    blake2_256(&(who, label, link).encode())
}

/// Encodes the `DotnsGateway.register_name { who, label, link }` call.
/// Layout: dispatch indices, the raw account, the compact-prefixed label, then
/// the link.
pub fn encode_register_name_call(
    call_indices: [u8; 2],
    who: &[u8; 32],
    label: &[u8],
    link: &Link,
) -> Vec<u8> {
    let mut call = call_indices.to_vec();
    (who, label, link).encode_to(&mut call);
    call
}

/// Encodes the `AsDotnsGateway` extension extra.
///
/// The value is `Some(RegisterFullName { proof, ring_index, revision,
/// signature })`; `revision` is the People-collection root revision the proof
/// was built against, which Asset Hub's `members-subscriber` must hold. The
/// signature is wrapped as `MultiSignature::Sr25519`.
pub fn encode_register_full_name_extra(
    info_variant: u8,
    proof: &[u8],
    ring_index: u32,
    revision: u32,
    signature: &[u8; 64],
) -> Vec<u8> {
    // Option::Some ‖ info variant ‖ Vec(proof) ‖ ring_index ‖ revision ‖
    // Sr25519 ‖ sig.
    let mut extra = vec![0x01, info_variant];
    proof.encode_to(&mut extra);
    ring_index.encode_to(&mut extra);
    revision.encode_to(&mut extra);
    extra.push(0x01);
    extra.extend_from_slice(signature);
    extra
}

/// Maps an AccountId32 to the H160 the contracts see.
///
/// Mirrors `pallet_revive::AccountId32Mapper::to_address`. Eth-derived
/// accounts — trailing 12 bytes all `0xEE` — truncate. Everything else hashes.
pub fn account_to_h160(public_key: &[u8; 32]) -> [u8; 20] {
    if public_key[20..].iter().all(|byte| *byte == 0xEE) {
        public_key[..20]
            .try_into()
            .expect("slice of first 20 bytes from a 32-byte array; qed")
    } else {
        keccak_256(public_key)[12..]
            .try_into()
            .expect("keccak_256 output is 32 bytes, tail slice is 20; qed")
    }
}

/// Solidity `bytes32("name")` literal: ASCII left-aligned in a 32-byte word.
/// The dotNS protocol registry keys (`storeFactory`, `registrar`, ...) use this
/// form. They are not hashes.
pub fn registry_key(name: &str) -> [u8; 32] {
    let bytes = name.as_bytes();
    assert!(bytes.len() <= 32, "registry key exceeds 32 bytes");
    let mut out = [0u8; 32];
    out[..bytes.len()].copy_from_slice(bytes);
    out
}

/// First 4 bytes of `keccak256(signature)` — the Solidity function selector.
pub fn selector(signature: &str) -> [u8; 4] {
    keccak_256(signature.as_bytes())[..4]
        .try_into()
        .expect("keccak_256 output is 32 bytes, head slice is 4; qed")
}

/// Calldata for a view function without arguments.
pub fn call_no_args(signature: &str) -> Vec<u8> {
    selector(signature).to_vec()
}

/// Calldata for a view function taking one `address` argument.
pub fn call_address(signature: &str, address: &[u8; 20]) -> Vec<u8> {
    let mut data = call_no_args(signature);
    data.extend_from_slice(&[0u8; 12]);
    data.extend_from_slice(address);
    data
}

/// Calldata for a view function taking one `bytes32` argument.
pub fn call_bytes32(signature: &str, word: &[u8; 32]) -> Vec<u8> {
    let mut data = call_no_args(signature);
    data.extend_from_slice(word);
    data
}

/// Calldata for a view function taking two `uint256` arguments.
pub fn call_u256_pair(signature: &str, first: u64, second: u64) -> Vec<u8> {
    let mut data = call_no_args(signature);
    for value in [first, second] {
        let mut word = [0u8; 32];
        word[24..].copy_from_slice(&value.to_be_bytes());
        data.extend_from_slice(&word);
    }
    data
}

/// Error decoding a dotNS contract round-trip.
#[derive(Debug, Error)]
pub enum DotnsContractError {
    /// `ContractResult` bytes ended before the expected field.
    #[error("ContractResult truncated at {context}")]
    Truncated {
        /// Field being decoded when the input ended.
        context: &'static str,
    },
    /// The runtime rejected the call before reaching the contract.
    #[error("ReviveApi_call dispatch failed: {detail}")]
    Dispatch {
        /// Raw hex of the `DispatchError` payload.
        detail: String,
    },
    /// The contract executed but reverted.
    #[error("contract reverted: {detail}")]
    Reverted {
        /// Rendered revert reason.
        detail: String,
    },
    /// ABI return data did not match the expected shape.
    #[error("ABI decode failed at {context}")]
    Abi {
        /// Value being decoded when the shape mismatched.
        context: &'static str,
    },
    /// ABI return data was not valid UTF-8 where a string was expected.
    #[error("ABI string is not UTF-8")]
    AbiUtf8,
}

/// SCALE arguments for the `ReviveApi_call` runtime API.
/// A zero-value, unlimited-gas dry-run of `input` against `dest` from `origin`.
pub fn encode_revive_call(origin: &[u8; 32], dest: &[u8; 20], input: &[u8]) -> Vec<u8> {
    let mut args = Vec::with_capacity(32 + 20 + 16 + 2 + 5 + input.len());
    args.extend_from_slice(origin);
    args.extend_from_slice(dest);
    args.extend_from_slice(&0u128.to_le_bytes());
    // gas_limit: Option<Weight> and storage_deposit_limit: Option<u128>.
    // Both absent, so the node estimates.
    args.push(0x00);
    args.push(0x00);
    input.encode_to(&mut args);
    args
}

/// Extracts the contract return data from a `ReviveApi_call` output.
/// The output is a `pallet_revive::ContractResult`. Dispatch errors and reverts
/// are rejected.
pub fn decode_revive_call_output(output: &[u8]) -> Result<Vec<u8>, DotnsContractError> {
    let truncated = |context| DotnsContractError::Truncated { context };
    let input = &mut &output[..];
    // weight_consumed + weight_required. Weight is a compact ref_time plus a
    // compact proof_size.
    for _ in 0..4 {
        Compact::<u64>::decode(input).map_err(|_| truncated("weight"))?;
    }
    // storage_deposit + max_storage_deposit. StorageDeposit is variant ‖ u128.
    for _ in 0..2 {
        <(u8, u128)>::decode(input).map_err(|_| truncated("storage_deposit"))?;
    }
    u128::decode(input).map_err(|_| truncated("gas_consumed"))?;
    match u8::decode(input).map_err(|_| truncated("result"))? {
        0 => {
            let flags = u32::decode(input).map_err(|_| truncated("flags"))?;
            let data = Vec::<u8>::decode(input).map_err(|_| truncated("data"))?;
            // ReturnFlags::REVERT.
            if flags & 1 == 1 {
                return Err(DotnsContractError::Reverted {
                    detail: describe_revert(&data),
                });
            }
            Ok(data)
        }
        _ => Err(DotnsContractError::Dispatch {
            detail: format!("0x{}", hex::encode(*input)),
        }),
    }
}

/// Renders a Solidity revert payload. Recognizes `Error(string)` and
/// `Panic(uint256)`.
fn describe_revert(data: &[u8]) -> String {
    if data.is_empty() {
        return "(empty)".to_string();
    }
    if data.starts_with(&[0x08, 0xc3, 0x79, 0xa0]) && data.len() >= 68 {
        let len = u64::from_be_bytes(
            data[60..68]
                .try_into()
                .expect("8-byte slice from a length-checked buffer; qed"),
        ) as usize;
        if let Some(message) = 68usize
            .checked_add(len)
            .and_then(|end| data.get(68..end))
            .and_then(|bytes| core::str::from_utf8(bytes).ok())
        {
            return format!("Error({message:?})");
        }
    }
    if data.starts_with(&[0x4e, 0x48, 0x7b, 0x71]) && data.len() >= 36 {
        return format!("Panic(0x{})", hex::encode(&data[32..36]));
    }
    format!("0x{}", hex::encode(data))
}

/// Reads the 32-byte ABI word at index `index`.
fn word(data: &[u8], index: usize) -> Result<&[u8], DotnsContractError> {
    data.get(index * 32..(index + 1) * 32)
        .ok_or(DotnsContractError::Abi { context: "word" })
}

/// Interprets an ABI word as a right-aligned usize offset or length.
fn word_usize(data: &[u8], index: usize) -> Result<usize, DotnsContractError> {
    let bytes = word(data, index)?;
    if bytes[..24].iter().any(|b| *b != 0) {
        return Err(DotnsContractError::Abi {
            context: "oversized word",
        });
    }
    Ok(u64::from_be_bytes(
        bytes[24..]
            .try_into()
            .expect("8-byte tail of a 32-byte word; qed"),
    ) as usize)
}

/// Decodes an ABI `string` at byte offset `at`.
/// The layout is a length word followed by padded UTF-8 bytes.
fn decode_string_at(data: &[u8], at: usize) -> Result<String, DotnsContractError> {
    let region = data.get(at..).ok_or(DotnsContractError::Abi {
        context: "string offset",
    })?;
    let len = word_usize(region, 0)?;
    let bytes = 32usize
        .checked_add(len)
        .and_then(|end| region.get(32..end))
        .ok_or(DotnsContractError::Abi {
            context: "string bytes",
        })?;
    String::from_utf8(bytes.to_vec()).map_err(|_| DotnsContractError::AbiUtf8)
}

/// Decodes a single `string` return value (`ProtocolRegistry.tld()`).
pub fn decode_string(data: &[u8]) -> Result<String, DotnsContractError> {
    decode_string_at(data, word_usize(data, 0)?)
}

/// Decodes a single `bool` return value.
pub fn decode_bool(data: &[u8]) -> Result<bool, DotnsContractError> {
    let bytes = word(data, 0)?;
    match bytes {
        [0, .., 0] => Ok(false),
        [0, .., 1] if bytes[..31].iter().all(|b| *b == 0) => Ok(true),
        _ => Err(DotnsContractError::Abi { context: "bool" }),
    }
}

/// Decodes a single `address` return value.
pub fn decode_address(data: &[u8]) -> Result<[u8; 20], DotnsContractError> {
    let bytes = word(data, 0)?;
    if bytes[..12].iter().any(|b| *b != 0) {
        return Err(DotnsContractError::Abi { context: "address" });
    }
    Ok(bytes[12..]
        .try_into()
        .expect("20-byte tail of a 32-byte word; qed"))
}

/// Decodes a `string[]` return value (`LabelStore.getLabels`).
pub fn decode_string_array(data: &[u8]) -> Result<Vec<String>, DotnsContractError> {
    let array_at = word_usize(data, 0)?;
    let array = data.get(array_at..).ok_or(DotnsContractError::Abi {
        context: "array offset",
    })?;
    let len = word_usize(array, 0)?;
    let elements = array.get(32..).ok_or(DotnsContractError::Abi {
        context: "array elements",
    })?;
    (0..len)
        .map(|i| decode_string_at(elements, word_usize(elements, i)?))
        .collect()
}

/// Decodes `DotnsPopController.pendingClaim(address)`, an ABI
/// `(string label, uint64 mintedAt)`. An empty label means no pending claim.
pub fn decode_pending_claim(data: &[u8]) -> Result<(String, u64), DotnsContractError> {
    let struct_at = word_usize(data, 0)?;
    let claim = data.get(struct_at..).ok_or(DotnsContractError::Abi {
        context: "struct offset",
    })?;
    let label = decode_string_at(claim, word_usize(claim, 0)?)?;
    let minted_at = word_usize(claim, 1)? as u64;
    Ok((label, minted_at))
}

/// Decodes the deployed-era `pendingClaims(address)`, an ABI
/// `(string label, uint64 mintedAt)[]`. Returns the labels.
pub fn decode_pending_claims_array(data: &[u8]) -> Result<Vec<String>, DotnsContractError> {
    let array_at = word_usize(data, 0)?;
    let array = data.get(array_at..).ok_or(DotnsContractError::Abi {
        context: "claims offset",
    })?;
    let len = word_usize(array, 0)?;
    let elements = array.get(32..).ok_or(DotnsContractError::Abi {
        context: "claims elements",
    })?;
    (0..len)
        .map(|i| {
            let claim =
                elements
                    .get(word_usize(elements, i)?..)
                    .ok_or(DotnsContractError::Abi {
                        context: "claim offset",
                    })?;
            decode_string_at(claim, word_usize(claim, 0)?)
        })
        .collect()
}

/// Usernames of one account as recorded by the dotNS contracts.
#[derive(Debug, Clone, Default, PartialEq, Eq)]
pub struct DotnsIdentity {
    /// Dotted lite username (`alice.01`), if any.
    pub lite_username: Option<String>,
    /// Full-person username, if any.
    pub full_username: Option<String>,
}

/// Classifies bare contract labels into lite and full usernames.
///
/// The gateway flattens a lite username `stem.NN` (a DNS-label stem plus exactly
/// two digits, `StringUtils.isSingleDotLiteLabel`) into the flat label `stemNN`
/// before minting, so a flat label whose last two characters are digits after a
/// DNS-label stem is read back as a lite username and re-dotted (`alice01` →
/// `alice.01`). Everything else is a full username. First hit per slot wins.
/// Labels are expected bare: [`resolve_labels`] strips the network TLD, and any
/// label still carrying a dot (a subname such as `app.alice`) is skipped.
///
/// Lite and public names share one namespace on the contract side, so a public
/// name ending in two digits is indistinguishable from a flattened lite name
/// here; the contract documents that ambiguity as accepted.
pub fn classify_labels<I>(labels: I) -> DotnsIdentity
where
    I: IntoIterator,
    I::Item: AsRef<str>,
{
    let mut identity = DotnsIdentity::default();
    for label in labels {
        let label = label.as_ref();
        if label.contains('.') {
            continue;
        }
        let (stem, digits) = label.split_at(label.len().saturating_sub(2));
        let is_lite =
            is_dns_label(stem) && digits.len() == 2 && digits.chars().all(|c| c.is_ascii_digit());
        if is_lite {
            identity
                .lite_username
                .get_or_insert_with(|| format!("{stem}.{digits}"));
        } else if !label.is_empty() {
            identity
                .full_username
                .get_or_insert_with(|| label.to_string());
        }
    }
    identity
}

/// A canonical DNS label: lowercase ASCII letters, digits and hyphens, neither
/// starting nor ending with a hyphen (`StringUtils._isDnsLabel`).
pub fn is_dns_label(value: &str) -> bool {
    !value.is_empty()
        && !value.starts_with('-')
        && !value.ends_with('-')
        && value
            .chars()
            .all(|c| c.is_ascii_lowercase() || c.is_ascii_digit() || c == '-')
}

/// Longest label the gateway pallet accepts (`BaseLabel = BoundedVec<u8, 32>`).
pub const MAX_BASE_LABEL_LEN: usize = 32;

/// Whether `label` can be a full-person base label: a DNS label of at most
/// [`MAX_BASE_LABEL_LEN`] bytes with no trailing digits, so it can never be
/// mistaken for a flattened lite username (`is_lite_person_label`).
pub fn is_full_person_label(label: &str) -> bool {
    is_dns_label(label)
        && label.len() <= MAX_BASE_LABEL_LEN
        && !label.ends_with(|c: char| c.is_ascii_digit())
}

/// Whether `value` is a dotted lite username, `stem.NN`: a DNS-label stem, one
/// dot, exactly two digits (`StringUtils.isSingleDotLiteLabel`), and at most
/// [`MAX_BASE_LABEL_LEN`] bytes once flattened.
pub fn is_dotted_lite_username(value: &str) -> bool {
    match value.rsplit_once('.') {
        Some((stem, digits)) => {
            is_dns_label(stem)
                && digits.len() == 2
                && digits.chars().all(|c| c.is_ascii_digit())
                && stem.len() + 2 <= MAX_BASE_LABEL_LEN
        }
        None => false,
    }
}

/// Page size for `LabelStore.getLabels`.
const LABEL_PAGE_LIMIT: u64 = 16;
/// Upper bound on pages read from one `LabelStore`. The store is an append-only
/// ledger shared with public registrations and incoming transfers, so it can
/// grow well past the one lite and one full name a gateway user holds.
const LABEL_PAGE_MAX: u64 = 16;

/// How a caller reaches Asset Hub for dotNS reads.
///
/// The surface is one storage read plus one contract view. The headless CLI
/// implements it over plain RPC. The in-core runtime implements it over a
/// `chainHead_v1` follow. The resolution steps below are written once.
#[truapi_platform::async_trait]
pub trait DotnsTransport {
    /// Reads one storage value. `None` when the entry is absent.
    async fn storage(&mut self, key: Vec<u8>) -> Result<Option<Vec<u8>>, String>;

    /// Dry-runs a contract view against `dest` and returns its return data.
    async fn view(&mut self, dest: &[u8; 20], input: Vec<u8>) -> Result<Vec<u8>, String>;
}

/// Resolves the `DotnsPopController` address.
///
/// The pallet's stored controller wins when present. Otherwise the dispatcher's
/// target getter answers: `TARGET()` on the deployed `RootGatewayDispatcher`
/// (dotNS `master`), with `target()` kept as a fallback for older builds. `None`
/// when the gateway is not deployed on the chain at all.
pub async fn discover_pop_controller<T: DotnsTransport + ?Sized>(
    transport: &mut T,
) -> Result<Option<[u8; 20]>, String> {
    if let Some(controller) = transport
        .storage(pop_controller_address_key())
        .await?
        .and_then(|value| <[u8; 20]>::try_from(value).ok())
    {
        return Ok(Some(controller));
    }
    let Some(dispatcher) = transport
        .storage(dispatcher_address_key())
        .await?
        .and_then(|value| <[u8; 20]>::try_from(value).ok())
    else {
        return Ok(None);
    };
    let output = match transport.view(&dispatcher, call_no_args("TARGET()")).await {
        Ok(output) => output,
        Err(_) => {
            transport
                .view(&dispatcher, call_no_args("target()"))
                .await?
        }
    };
    decode_address(&output)
        .map(Some)
        .map_err(|err| format!("RootGatewayDispatcher target getter: {err}"))
}

/// Resolves the bare contract labels `account` holds.
///
/// Two sources are merged. The controller's pending claims hold gateway-minted
/// names the user has not settled into a `LabelStore` yet (`claimLabelStore`);
/// those come first. The user's `LabelStore`, when deployed, holds every name
/// written for them: gateway names once settled, plus public registrations and
/// incoming transfers. Store labels carry the network TLD (`alice01.paseo`),
/// which is stripped here; subnames (`app.alice`) are dropped.
///
/// A store alone is not proof that pending claims are settled: a public
/// registration or an incoming transfer deploys the store while gateway names
/// stay pending, so both sources are always read.
pub async fn resolve_labels<T: DotnsTransport + ?Sized>(
    transport: &mut T,
    controller: &[u8; 20],
    account: &[u8; 32],
) -> Result<Vec<String>, String> {
    let user = account_to_h160(account);

    let mut labels = pending_claim_labels(transport, controller, &user).await?;

    let registry_output = transport
        .view(controller, call_no_args("protocolRegistry()"))
        .await?;
    let registry = decode_address(&registry_output)
        .map_err(|err| format!("DotnsPopController.protocolRegistry(): {err}"))?;

    let factory_output = transport
        .view(
            &registry,
            call_bytes32("get(bytes32)", &registry_key("storeFactory")),
        )
        .await?;
    let factory = decode_address(&factory_output)
        .map_err(|err| format!("ProtocolRegistry.get(storeFactory): {err}"))?;

    let store_output = transport
        .view(&factory, call_address("getLabelStore(address)", &user))
        .await?;
    let store = decode_address(&store_output)
        .map_err(|err| format!("StoreFactory.getLabelStore: {err}"))?;
    if store == [0u8; 20] {
        return Ok(labels);
    }

    let tld_output = transport.view(&registry, call_no_args("tld()")).await?;
    let tld = decode_string(&tld_output).map_err(|err| format!("ProtocolRegistry.tld(): {err}"))?;

    for page in 0..LABEL_PAGE_MAX {
        let labels_output = transport
            .view(
                &store,
                call_u256_pair(
                    "getLabels(uint256,uint256)",
                    page * LABEL_PAGE_LIMIT,
                    LABEL_PAGE_LIMIT,
                ),
            )
            .await?;
        let stored = decode_string_array(&labels_output)
            .map_err(|err| format!("LabelStore.getLabels: {err}"))?;
        let short_page = (stored.len() as u64) < LABEL_PAGE_LIMIT;
        for label in stored {
            if let Some(bare) = bare_store_label(&label, &tld)
                && !labels.iter().any(|known| known == bare)
            {
                labels.push(bare.to_string());
            }
        }
        if short_page {
            break;
        }
    }
    Ok(labels)
}

/// Strips the network TLD from a `LabelStore` label. `None` for labels that do
/// not carry it or that still hold a dot afterwards (subnames).
fn bare_store_label<'a>(label: &'a str, tld: &str) -> Option<&'a str> {
    let bare = if tld.is_empty() {
        label
    } else {
        label.strip_suffix(tld)?
    };
    (!bare.is_empty() && !bare.contains('.')).then_some(bare)
}

/// ENS-style node of `label` directly under `parent`:
/// `keccak256(parent ‖ keccak256(label))`.
pub fn namehash_under(parent: &[u8; 32], label: &str) -> [u8; 32] {
    keccak_256(&[parent.as_slice(), &keccak_256(label.as_bytes())].concat())
}

/// Whether the registrar would still mint `label` on this network: the name's
/// node under the network TLD is unminted, or held by the name escrow
/// (`DotnsRegistrar.available`).
///
/// A lite-name reservation carrying a `reserved_base_label` that is already
/// registered can never be claimed, yet it holds the reservation queue for
/// that stem for the whole reservation window. The gateway pallet does not
/// check this, so callers ask before attesting or registering.
pub async fn label_available<T: DotnsTransport + ?Sized>(
    transport: &mut T,
    controller: &[u8; 20],
    label: &str,
) -> Result<bool, String> {
    let registry_output = transport
        .view(controller, call_no_args("protocolRegistry()"))
        .await?;
    let registry = decode_address(&registry_output)
        .map_err(|err| format!("DotnsPopController.protocolRegistry(): {err}"))?;

    let tld_node_output = transport.view(&registry, call_no_args("tldNode()")).await?;
    let tld_node: [u8; 32] = word(&tld_node_output, 0)
        .map_err(|err| format!("ProtocolRegistry.tldNode(): {err}"))?
        .try_into()
        .expect("a 32-byte ABI word; qed");

    let registrar_output = transport
        .view(
            &registry,
            call_bytes32("get(bytes32)", &registry_key("registrar")),
        )
        .await?;
    let registrar = decode_address(&registrar_output)
        .map_err(|err| format!("ProtocolRegistry.get(registrar): {err}"))?;

    let node = namehash_under(&tld_node, label);
    let output = transport
        .view(&registrar, call_bytes32("available(uint256)", &node))
        .await?;
    decode_bool(&output).map_err(|err| format!("DotnsRegistrar.available: {err}"))
}

/// Gateway-minted labels of `user` still waiting for `claimLabelStore`.
///
/// The deployed controller exposes `pendingClaims(address)`, an array. Older
/// builds exposed `pendingClaim(address)`, one struct; it is kept as a fallback.
async fn pending_claim_labels<T: DotnsTransport + ?Sized>(
    transport: &mut T,
    controller: &[u8; 20],
    user: &[u8; 20],
) -> Result<Vec<String>, String> {
    match transport
        .view(controller, call_address("pendingClaims(address)", user))
        .await
    {
        Ok(claims_output) => decode_pending_claims_array(&claims_output)
            .map_err(|err| format!("DotnsPopController.pendingClaims: {err}")),
        Err(_) => {
            let claim_output = transport
                .view(controller, call_address("pendingClaim(address)", user))
                .await?;
            let (label, minted_at) = decode_pending_claim(&claim_output)
                .map_err(|err| format!("DotnsPopController.pendingClaim: {err}"))?;
            Ok(if minted_at == 0 { vec![] } else { vec![label] })
        }
    }
}

/// `DotnsGateway.PopControllerAddress` storage key.
/// Older runtimes store the controller directly. It is absent on runtimes that
/// wire a dispatcher instead.
pub fn pop_controller_address_key() -> Vec<u8> {
    plain_key(b"DotnsGateway", b"PopControllerAddress")
}

/// `DotnsGateway.DispatcherAddress` storage key.
/// The entry holds the `RootGatewayDispatcher`. Its `target()` is the
/// `DotnsPopController`.
pub fn dispatcher_address_key() -> Vec<u8> {
    plain_key(b"DotnsGateway", b"DispatcherAddress")
}

/// `DotnsGateway.AccountAlias[account]` storage key.
/// The value is the 32-byte alias the account registered with.
pub fn account_alias_key(account: &[u8; 32]) -> Vec<u8> {
    let mut key = plain_key(b"DotnsGateway", b"AccountAlias");
    key.extend_from_slice(&blake2_128(account));
    key.extend_from_slice(account);
    key
}

/// `Timestamp.Now` storage key. The value is a u64 of Unix milliseconds.
pub fn timestamp_now_key() -> Vec<u8> {
    plain_key(b"Timestamp", b"Now")
}

/// `twox128(pallet) ‖ twox128(entry)`.
fn plain_key(pallet: &[u8], entry: &[u8]) -> Vec<u8> {
    [twox_128(pallet).as_slice(), twox_128(entry).as_slice()].concat()
}

#[cfg(test)]
mod tests {
    use super::*;

    // Golden vectors from the validated reference implementation in
    // pop-dotns-testing: reservation.ts, proof.ts, verify.ts, abi.ts.
    const RESERVATION_WITH_RESERVED: &str = "64706f703a646f746e732d676174657761793a72657365727665111111111111111111111111111111111111111111111111111111111111111122222222222222222222222222222222222222222222222222222222222222221c616c696365626305013333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333013072657365727665646e616d65035e486800000000";
    const RESERVATION_NO_RESERVED: &str = "64706f703a646f746e732d676174657761793a72657365727665111111111111111111111111111111111111111111111111111111111111111122222222222222222222222222222222222222222222222222222222222222221c616c69636562630501333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333300035e486800000000";

    #[test]
    fn reservation_message_matches_reference_vectors() {
        let with_reserved = build_reservation_message(
            &[0x11; 32],
            &[0x22; 32],
            b"alicebc",
            &[0x33; 65],
            Some(b"reservedname"),
            1749573123,
        );
        assert_eq!(hex::encode(&with_reserved), RESERVATION_WITH_RESERVED);

        let without = build_reservation_message(
            &[0x11; 32],
            &[0x22; 32],
            b"alicebc",
            &[0x33; 65],
            None,
            1749573123,
        );
        assert_eq!(hex::encode(&without), RESERVATION_NO_RESERVED);
    }

    #[test]
    fn link_and_proof_message_match_reference_vectors() {
        let lite = Link::LiteUsername(b"alice.01".to_vec());
        assert_eq!(hex::encode(lite.encode()), "0020616c6963652e3031");
        assert_eq!(
            hex::encode(build_register_proof_message(&[0x44; 32], b"alicebc", &lite)),
            "506fe3afcb13b2e4fd182d49ff165bc9c834f9dd21d0d545eccb925993b68675"
        );

        let standalone = Link::None([0x55; 65]);
        assert_eq!(
            hex::encode(standalone.encode()),
            format!("01{}", hex::encode([0x55; 65]))
        );
        assert_eq!(
            hex::encode(build_register_proof_message(
                &[0x44; 32],
                b"alicebc",
                &standalone
            )),
            "255da65ea6687123d5ac035a438a5c6fa18f7d04f23433611095a0fe58c479ab"
        );
    }

    #[test]
    fn register_name_call_and_extension_extra_have_the_reference_layout() {
        let link = Link::LiteUsername(b"alice.01".to_vec());
        let call = encode_register_name_call([0x6a, 0x01], &[0x44; 32], b"alicebc", &link);
        assert_eq!(&call[..2], &[0x6a, 0x01]);
        assert_eq!(&call[2..34], &[0x44; 32]);
        assert_eq!(
            &call[34..],
            &[b"alicebc".to_vec().encode(), link.encode()].concat()[..]
        );

        // Layout: 0x01 (Some) ‖ variant ‖ compact-len proof ‖ ring_index LE ‖
        // revision LE ‖ 0x01 (Sr25519) ‖ signature. Matches registerTx.ts
        // encodeAsDotnsGatewayValue plus the revision field the runtime added
        // (individuality#1013).
        let extra = encode_register_full_name_extra(0, &[0xEE; 785], 3, 5, &[0xAB; 64]);
        assert_eq!(
            extra,
            [
                vec![0x01, 0x00],
                vec![0xEEu8; 785].encode(),
                3u32.to_le_bytes().to_vec(),
                5u32.to_le_bytes().to_vec(),
                vec![0x01],
                vec![0xAB; 64],
            ]
            .concat()
        );
    }

    #[test]
    fn selectors_match_reference_vectors() {
        assert_eq!(hex::encode(selector("getLabelStore(address)")), "4fc5dce9");
        assert_eq!(
            hex::encode(selector("getLabels(uint256,uint256)")),
            "2d7b5794"
        );
        assert_eq!(hex::encode(selector("pendingClaim(address)")), "0ef4b248");
        assert_eq!(hex::encode(selector("protocolRegistry()")), "7656419f");
        assert_eq!(hex::encode(selector("get(bytes32)")), "8eaa6ac0");
        assert_eq!(hex::encode(selector("target()")), "d4b83992");
        assert_eq!(hex::encode(selector("TARGET()")), "cc1f2afa");
        assert_eq!(hex::encode(selector("pendingClaims(address)")), "ca78533d");
        assert_eq!(hex::encode(selector("tld()")), "2d551432");
        assert_eq!(hex::encode(selector("tldNode()")), "114902c5");
        assert_eq!(hex::encode(selector("available(uint256)")), "96e494e8");
    }

    #[test]
    fn namehash_matches_the_reference_derivation() {
        // `cast namehash paseo` and `cast namehash alicebc.paseo`.
        let tld_node = namehash_under(&[0u8; 32], "paseo");
        assert_eq!(
            hex::encode(tld_node),
            "096b436ee9a398429fe33ad4b359bad4398dd74b412ec1dd043c93dfbf581874"
        );
        assert_eq!(
            hex::encode(namehash_under(&tld_node, "alicebc")),
            "d3b106171373cd9fea783acd85f69def1bb2085f81cf5f2a65088b0ce4edd82e"
        );
    }

    #[test]
    fn bool_words_decode_strictly() {
        assert!(decode_bool(&abi_word(1)).unwrap());
        assert!(!decode_bool(&abi_word(0)).unwrap());
        assert!(decode_bool(&abi_word(2)).is_err());
        assert!(decode_bool(&[0u8; 16]).is_err());
    }

    #[test]
    fn calldata_encoders_place_arguments_in_padded_words() {
        let address_call = call_address("getLabelStore(address)", &[0xAA; 20]);
        assert_eq!(address_call.len(), 4 + 32);
        assert_eq!(&address_call[..4], &selector("getLabelStore(address)"));
        assert!(address_call[4..16].iter().all(|b| *b == 0));
        assert_eq!(&address_call[16..], &[0xAA; 20]);

        let pair_call = call_u256_pair("getLabels(uint256,uint256)", 0, 16);
        assert_eq!(pair_call.len(), 4 + 64);
        assert_eq!(pair_call[35], 0);
        assert_eq!(pair_call[67], 16);

        let key_call = call_bytes32("get(bytes32)", &registry_key("storeFactory"));
        assert_eq!(&key_call[4..16], b"storeFactory");
        assert!(key_call[16..36].iter().all(|b| *b == 0));
    }

    #[test]
    fn account_to_h160_follows_the_revive_mapper() {
        let mut eth_derived = [0x0Fu8; 32];
        eth_derived[20..].fill(0xEE);
        assert_eq!(account_to_h160(&eth_derived), [0x0F; 20]);

        let hashed = account_to_h160(&[0x11; 32]);
        assert_eq!(hashed, keccak_256(&[0x11; 32])[12..]);
    }

    /// Encodes a `ContractResult` prefix followed by `result`.
    fn contract_result(result: &[u8]) -> Vec<u8> {
        let mut out = Vec::new();
        for _ in 0..4 {
            Compact(7u64).encode_to(&mut out);
        }
        for _ in 0..2 {
            (1u8, 0u128).encode_to(&mut out);
        }
        0u128.encode_to(&mut out);
        out.extend_from_slice(result);
        out
    }

    #[test]
    fn revive_call_output_surfaces_data_reverts_and_dispatch_errors() {
        let mut ok = vec![0u8];
        0u32.encode_to(&mut ok);
        vec![0xABu8, 0xCD].encode_to(&mut ok);
        assert_eq!(
            decode_revive_call_output(&contract_result(&ok)).unwrap(),
            vec![0xAB, 0xCD]
        );

        // Error("nope") revert payload under ReturnFlags::REVERT.
        let mut revert_data = vec![0x08, 0xc3, 0x79, 0xa0];
        revert_data.extend_from_slice(&{
            let mut word = [0u8; 32];
            word[31] = 0x20;
            word
        });
        revert_data.extend_from_slice(&{
            let mut word = [0u8; 32];
            word[31] = 4;
            word
        });
        revert_data.extend_from_slice(b"nope");
        revert_data.extend_from_slice(&[0u8; 28]);
        let mut reverted = vec![0u8];
        1u32.encode_to(&mut reverted);
        revert_data.encode_to(&mut reverted);
        let err = decode_revive_call_output(&contract_result(&reverted)).unwrap_err();
        assert!(
            matches!(&err, DotnsContractError::Reverted { detail } if detail == "Error(\"nope\")"),
            "unexpected error: {err}"
        );

        let dispatch = contract_result(&[0x01, 0x02, 0x03]);
        assert!(matches!(
            decode_revive_call_output(&dispatch).unwrap_err(),
            DotnsContractError::Dispatch { .. }
        ));
    }

    /// ABI word with `value` right-aligned.
    fn abi_word(value: u64) -> [u8; 32] {
        let mut word = [0u8; 32];
        word[24..].copy_from_slice(&value.to_be_bytes());
        word
    }

    /// ABI string tail: a length word plus padded bytes.
    fn abi_string(value: &str) -> Vec<u8> {
        let mut out = abi_word(value.len() as u64).to_vec();
        out.extend_from_slice(value.as_bytes());
        out.resize(out.len().div_ceil(32) * 32, 0);
        out
    }

    #[test]
    fn abi_decoders_handle_addresses_string_arrays_and_pending_claims() {
        let mut address = [0u8; 32];
        address[12..].fill(0xBC);
        assert_eq!(decode_address(&address).unwrap(), [0xBC; 20]);
        assert!(decode_address(&[0xFF; 32]).is_err());

        // string[] = ["alice01", "bob"].
        let mut array = abi_word(0x20).to_vec();
        array.extend_from_slice(&abi_word(2));
        array.extend_from_slice(&abi_word(0x40));
        array.extend_from_slice(&abi_word(0x40 + 0x40));
        array.extend_from_slice(&abi_string("alice01"));
        array.extend_from_slice(&abi_string("bob"));
        assert_eq!(
            decode_string_array(&array).unwrap(),
            vec!["alice01".to_string(), "bob".to_string()]
        );
        assert_eq!(
            decode_string_array(&[abi_word(0x20), abi_word(0)].concat()).unwrap(),
            Vec::<String>::new()
        );

        // pendingClaim = ("alice", 42).
        let mut claim = abi_word(0x20).to_vec();
        claim.extend_from_slice(&abi_word(0x40));
        claim.extend_from_slice(&abi_word(42));
        claim.extend_from_slice(&abi_string("alice"));
        assert_eq!(
            decode_pending_claim(&claim).unwrap(),
            ("alice".to_string(), 42)
        );

        // pendingClaims = [("alice01", 42), ("bob", 7)]. Deployed-era plural.
        let struct_a = [
            abi_word(0x40).to_vec(),
            abi_word(42).to_vec(),
            abi_string("alice01"),
        ]
        .concat();
        let struct_b = [
            abi_word(0x40).to_vec(),
            abi_word(7).to_vec(),
            abi_string("bob"),
        ]
        .concat();
        let mut claims = abi_word(0x20).to_vec();
        claims.extend_from_slice(&abi_word(2));
        claims.extend_from_slice(&abi_word(0x40));
        claims.extend_from_slice(&abi_word(0x40 + struct_a.len() as u64));
        claims.extend_from_slice(&struct_a);
        claims.extend_from_slice(&struct_b);
        assert_eq!(
            decode_pending_claims_array(&claims).unwrap(),
            vec!["alice01".to_string(), "bob".to_string()]
        );
        assert_eq!(
            decode_pending_claims_array(&[abi_word(0x20), abi_word(0)].concat()).unwrap(),
            Vec::<String>::new()
        );
    }

    #[test]
    fn labels_classify_into_lite_and_full_usernames() {
        let identity = classify_labels(["alice01", "myproject"]);
        assert_eq!(identity.lite_username.as_deref(), Some("alice.01"));
        assert_eq!(identity.full_username.as_deref(), Some("myproject"));

        // Dotted labels are not base names and are skipped; a DNS stem may hold
        // digits and hyphens (`isSingleDotLiteLabel`), a hyphen may not lead or
        // trail it.
        let identity = classify_labels(["bobby42.dot", "app.web3app", "web3app", "a2b34", "-x01"]);
        assert_eq!(identity.lite_username.as_deref(), Some("a2b.34"));
        assert_eq!(identity.full_username.as_deref(), Some("web3app"));

        assert_eq!(
            classify_labels(Vec::<String>::new()),
            DotnsIdentity::default()
        );
        // One trailing digit is not lite format.
        let identity = classify_labels(["alice1"]);
        assert_eq!(identity.lite_username, None);
        assert_eq!(identity.full_username.as_deref(), Some("alice1"));
    }

    #[test]
    fn label_validators_follow_the_contract_rules() {
        assert!(is_full_person_label("alicebc"));
        assert!(is_full_person_label("web3-app"));
        assert!(
            !is_full_person_label("alice01"),
            "trailing digits are lite format"
        );
        assert!(!is_full_person_label("Alice"));
        assert!(!is_full_person_label("alice.bc"));
        assert!(!is_full_person_label("-alice"));
        assert!(!is_full_person_label(&"a".repeat(33)));

        assert!(is_dotted_lite_username("alice.01"));
        assert!(is_dotted_lite_username("a2b.34"));
        assert!(!is_dotted_lite_username("alice01"));
        assert!(!is_dotted_lite_username("alice.1"));
        assert!(!is_dotted_lite_username("alice.012"));
        assert!(!is_dotted_lite_username("a.lice.01"));
        assert!(!is_dotted_lite_username(".01"));
        assert!(!is_dotted_lite_username(&format!("{}.01", "a".repeat(31))));
    }

    #[test]
    fn store_labels_lose_the_network_tld_and_subnames_are_dropped() {
        assert_eq!(bare_store_label("alice01.paseo", ".paseo"), Some("alice01"));
        assert_eq!(bare_store_label("alice01.dot", ".dot"), Some("alice01"));
        // Wrong TLD, subname, or nothing left after the TLD.
        assert_eq!(bare_store_label("alice01.dot", ".paseo"), None);
        assert_eq!(bare_store_label("app.alice.paseo", ".paseo"), None);
        assert_eq!(bare_store_label(".paseo", ".paseo"), None);
        // An empty TLD leaves bare labels as they are.
        assert_eq!(bare_store_label("alice01", ""), Some("alice01"));
    }

    #[test]
    fn storage_keys_have_the_expected_layout() {
        let alias_key = account_alias_key(&[0x11; 32]);
        let prefix = [
            twox_128(b"DotnsGateway").as_slice(),
            twox_128(b"AccountAlias").as_slice(),
        ]
        .concat();
        assert_eq!(&alias_key[..32], prefix.as_slice());
        // Blake2_128Concat over the raw account bytes.
        assert_eq!(&alias_key[48..], &[0x11; 32]);

        assert_eq!(pop_controller_address_key().len(), 32);
        assert_eq!(dispatcher_address_key().len(), 32);
        assert_eq!(timestamp_now_key().len(), 32);
    }

    #[test]
    fn revive_call_args_encode_origin_dest_and_input() {
        let args = encode_revive_call(&[0x11; 32], &[0x22; 20], &[0xAB, 0xCD]);
        assert_eq!(&args[..32], &[0x11; 32]);
        assert_eq!(&args[32..52], &[0x22; 20]);
        assert_eq!(&args[52..68], &[0u8; 16], "value is zero");
        assert_eq!(&args[68..70], &[0x00, 0x00], "no gas or deposit limit");
        assert_eq!(&args[70..], vec![0xABu8, 0xCD].encode().as_slice());
    }
}
