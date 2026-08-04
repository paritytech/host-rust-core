//! Submitting an assembled coinage extrinsic and reading back what the chain
//! did with it.
//!
//! [`super::extrinsic`] produces the bytes; this module owns everything after
//! that, in three steps:
//!
//! 1. **Dry-run** through `TaggedTransactionQueue_validate_transaction`. A
//!    coinage extrinsic carries no signature, so validity is the only
//!    pre-broadcast signal that the `AsCoinage` extension accepted its proofs.
//! 2. **Submit and watch** until the extrinsic reaches a block.
//! 3. **Classify** the dispatch outcome from that block's `System.Events`.
//!
//! Step 3 is the one that cannot be skipped. Inclusion is not success: a
//! coinage call that lands in a block and then fails to dispatch produces a
//! block hash indistinguishable from a successful one until its events are
//! read.
//!
//! The result is deliberately three-valued ([`TrackerOutcome`]), because a
//! wallet that confuses two of those values loses money:
//!
//! - **definitively not included** — nothing happened, the caller may rebuild
//!   and retry with the same inputs;
//! - **included, with a verdict** — [`SubmissionVerdict`];
//! - **unknown** — everything else, which the caller must resolve by observing
//!   finalized chain state, never by assuming either of the above.
//!
//! Inclusion is also graded. A verdict read at a non-finalized block is
//! *optimistic*: it may move an operation to `InBlock` and drive UI, but it may
//! not retire records or write a receipt, because a reorg can invalidate the
//! transaction on the new canonical chain. Only `SubmissionVerdict::finalized`
//! marks an outcome settled; everything else waits for recovery (§7.7).
//!
//! Note what [`SubmissionVerdict::DispatchFailed`] does *not* mean. A failed
//! dispatch reverts the call's own storage writes, but a transaction
//! extension's `prepare` runs outside that layer, and `AsCoinage` only partly
//! compensates for that in `post_dispatch`:
//!
//! - a coin origin is put back, under a `LockedCoins` entry that refuses it for
//!   `2^retries` times `CoinFailureLockPeriod`;
//! - an output-token's first alias is put back, locked the same way;
//! - a **free or paid unload token is gone**. Nothing restores it.
//!
//! So the operation's records survive, but they are not immediately reusable,
//! and a retry costs a fresh token. Settling this verdict by releasing the
//! locks as if nothing happened produces a resubmission the runtime refuses and
//! a second token spent on it. Observe `LockedCoins` and let the record's own
//! lock decide when it is selectable again.

use serde_json::json;
use sp_crypto_hashing::{blake2_256, twox_128};
use subxt::ext::scale_value::scale::decode_as_type;
use subxt::ext::scale_value::{Composite, Value, ValueDef, Variant};
use thiserror::Error;

use crate::host_logic::coinage::params::EXTRINSIC_MORTALITY_BLOCKS;
use crate::host_logic::coinage::types::{BlockHash, ExtrinsicHash};
use crate::runtime::statement_allowance::extension::{ChainState, EraAnchor, Metadata};
use crate::runtime::statement_allowance::rpc::{RpcClient, RpcError};
use crate::runtime::statement_allowance::{
    StatementAllowanceError, fetch_chain_state, fetch_era_anchor,
};

/// Runtime API answering whether the chain would accept an extrinsic.
const VALIDATE_TRANSACTION: &str = "TaggedTransactionQueue_validate_transaction";

/// `TransactionSource::External` — the extrinsic arrived over RPC rather than
/// from a block or a local author.
const TRANSACTION_SOURCE_EXTERNAL: u8 = 2;

/// `TransactionValidityError::Invalid(InvalidTransaction)` variants, in
/// declaration order.
///
/// Pinned rather than resolved: a runtime API's return type is not in the
/// metadata type registry, so nothing on chain describes this enum. The layout
/// is part of the runtime API's contract and only ever grows at the end, so an
/// unknown discriminant is reported by number instead of guessed at.
const INVALID_TRANSACTION: &[&str] = &[
    "Call",
    "Payment",
    "Future",
    "Stale",
    "BadProof",
    "AncientBirthBlock",
    "ExhaustsResources",
    "Custom",
    "BadMandatory",
    "MandatoryValidation",
    "BadSigner",
    "IndeterminateImplicit",
    "UnknownOrigin",
];

/// Discriminant of `InvalidTransaction::Custom(u8)`, the one variant carrying a
/// payload — and the one a pallet's own extension rejections arrive as.
const INVALID_TRANSACTION_CUSTOM: u8 = 7;

/// `TransactionValidityError::Unknown(UnknownTransaction)` variants, in
/// declaration order.
const UNKNOWN_TRANSACTION: &[&str] = &["CannotLookup", "NoUnsignedValidator", "Custom"];

/// Discriminant of `UnknownTransaction::Custom(u8)`.
const UNKNOWN_TRANSACTION_CUSTOM: u8 = 2;

/// Watch statuses that mean the extrinsic never reached a block, so rebuilding
/// and resubmitting cannot double-spend. Every other terminal status leaves the
/// outcome unknown.
const NOT_INCLUDED_STATUSES: &[&str] = &["invalid", "dropped"];

/// What the chain did with an extrinsic that reached a block.
///
/// **Optimistic unless [`SubmissionVerdict::finalized`].** A verdict read at a
/// non-finalized block says what the chain currently believes, which a reorg
/// can undo. It may drive UI and move an operation to `InBlock`; it may not
/// retire records, release locks, or write a receipt.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum SubmissionVerdict {
    /// Included and dispatched successfully.
    Succeeded {
        /// Block that included the extrinsic.
        block_hash: BlockHash,
        /// Whether that block is finalized.
        finalized: bool,
    },
    /// Included, but the dispatch failed.
    ///
    /// The call's own effects are reverted; whatever the `AsCoinage` extension
    /// consumed to build the origin is not. See the module documentation.
    DispatchFailed {
        /// Block that included the extrinsic.
        block_hash: BlockHash,
        /// Whether that block is finalized.
        finalized: bool,
        /// Rendering of the runtime's dispatch error.
        reason: String,
    },
}

impl SubmissionVerdict {
    /// Whether the dispatch succeeded.
    pub const fn succeeded(&self) -> bool {
        matches!(self, Self::Succeeded { .. })
    }

    /// Block the extrinsic landed in, either way.
    pub const fn block_hash(&self) -> BlockHash {
        match self {
            Self::Succeeded { block_hash, .. } | Self::DispatchFailed { block_hash, .. } => {
                *block_hash
            }
        }
    }

    /// Whether this verdict is settled, i.e. read at a finalized block.
    ///
    /// Only a settled verdict may be written into the operation log.
    pub const fn finalized(&self) -> bool {
        match self {
            Self::Succeeded { finalized, .. } | Self::DispatchFailed { finalized, .. } => {
                *finalized
            }
        }
    }
}

/// The three-valued result of best-effort tracking (`coinage-layer.md` §7.6).
///
/// Modelled as a value rather than a `Result` because all three arms are
/// ordinary outcomes the caller must handle differently, and because collapsing
/// "unknown" into either of the others is the single most dangerous mistake
/// available to this layer: assuming success retires records the chain still
/// holds, and assuming failure releases records the chain is about to consume.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum TrackerOutcome {
    /// The transaction provably never reached a block, so the caller may
    /// rebuild and resubmit against the same records.
    NotIncluded {
        /// Why nothing was included.
        reason: String,
    },
    /// The transaction reached a block and its dispatch outcome was read.
    Included(SubmissionVerdict),
    /// The transaction's fate is not established. Hand it to recovery
    /// (§7.7), which resolves it against finalized chain state.
    Unknown {
        /// What stopped tracking from reaching a verdict.
        reason: String,
    },
}

impl TrackerOutcome {
    /// Whether the caller may reuse the transaction's inputs immediately.
    pub const fn is_definitively_not_included(&self) -> bool {
        matches!(self, Self::NotIncluded { .. })
    }

    /// Whether this outcome settles the transaction with no further work.
    ///
    /// A non-finalized inclusion does not: it still needs recovery to confirm
    /// it at a finalized block.
    pub const fn is_definite(&self) -> bool {
        match self {
            Self::NotIncluded { .. } => true,
            Self::Included(verdict) => verdict.finalized(),
            Self::Unknown { .. } => false,
        }
    }
}

/// Failure to submit a coinage extrinsic, or to learn what became of it.
#[derive(Debug, Error)]
pub enum CoinageSubmitError {
    /// The JSON-RPC surface failed while reading state or broadcasting.
    #[error("chain rpc: {0}")]
    Rpc(#[source] Box<StatementAllowanceError>),
    /// The dry-run rejected the extrinsic; it was never broadcast.
    #[error("dry-run rejected the extrinsic: {reason}")]
    DryRunRejected {
        /// Rendering of the runtime's validity error.
        reason: String,
    },
    /// The node rejected the broadcast without including anything.
    #[error("not included: {reason}")]
    NotIncluded {
        /// Terminal watch status the node reported.
        reason: String,
    },
    /// The extrinsic's fate could not be established. The caller must resolve
    /// this by observing chain state, never by assuming either outcome.
    #[error("inclusion unverified: {reason}")]
    Unverified {
        /// What stopped the classification from reaching a verdict.
        reason: String,
    },
    /// Metadata lacked something the classification needs.
    #[error("metadata: {0}")]
    Metadata(String),
}

impl CoinageSubmitError {
    /// Whether the extrinsic provably never reached a block, so the caller may
    /// rebuild and resubmit against the same records.
    pub const fn is_definitively_not_included(&self) -> bool {
        matches!(self, Self::DryRunRejected { .. } | Self::NotIncluded { .. })
    }
}

/// Hash of an assembled extrinsic, as the chain identifies it.
pub fn extrinsic_hash(extrinsic: &[u8]) -> ExtrinsicHash {
    ExtrinsicHash(blake2_256(extrinsic))
}

/// Read the chain state a coinage extrinsic signs over, anchored for mortality.
///
/// The returned anchor is what the operation log records as its checkpoint; the
/// two must be the same block or the expiry test during recovery is unsound.
pub async fn fetch_mortal_chain_state(
    rpc: &RpcClient,
) -> Result<(ChainState, EraAnchor), CoinageSubmitError> {
    let mut state = fetch_chain_state(rpc).await.map_err(rpc_failed)?;
    let anchor = fetch_era_anchor(rpc, EXTRINSIC_MORTALITY_BLOCKS)
        .await
        .map_err(rpc_failed)?;
    state.mortality = Some(anchor);
    Ok((state, anchor))
}

/// Dry-run, broadcast, and classify one assembled extrinsic.
///
/// Total by construction: every failure mode maps onto one of the three
/// [`TrackerOutcome`] arms rather than escaping as an error, so a caller cannot
/// accidentally treat "we do not know" as "it failed" by handling a `Result`
/// carelessly. A transport failure *before* the broadcast is `NotIncluded`,
/// because nothing was sent; one after it is `Unknown`.
pub async fn submit(rpc: &RpcClient, metadata: &Metadata, extrinsic: &[u8]) -> TrackerOutcome {
    if let Err(error) = dry_run(rpc, extrinsic).await {
        return TrackerOutcome::NotIncluded {
            reason: error.to_string(),
        };
    }

    let inclusion = match rpc.submit_and_watch_inclusion(extrinsic).await {
        Ok(inclusion) => inclusion,
        Err(error) => return classify_watch_failure(error),
    };

    match verdict_at(
        rpc,
        metadata,
        &inclusion.block_hash,
        inclusion.finalized,
        extrinsic,
    )
    .await
    {
        Ok(verdict) => TrackerOutcome::Included(verdict),
        Err(error) => TrackerOutcome::Unknown {
            reason: error.to_string(),
        },
    }
}

/// Ask the runtime whether it would accept the extrinsic, without broadcasting.
///
/// Validated against the finalized head rather than the best block: a coinage
/// proof binds the chain, not a fork, and a rejection seen at a block that is
/// later reorganized away would be an invented failure.
pub async fn dry_run(rpc: &RpcClient, extrinsic: &[u8]) -> Result<(), CoinageSubmitError> {
    let at = rpc.finalized_head().await.map_err(rpc_failed)?;
    let at_bytes = decode_hash(&at)?;

    let mut payload = Vec::with_capacity(1 + extrinsic.len() + at_bytes.0.len());
    payload.push(TRANSACTION_SOURCE_EXTERNAL);
    payload.extend_from_slice(extrinsic);
    payload.extend_from_slice(&at_bytes.0);

    let result = rpc
        .call(
            "state_call",
            json!([
                VALIDATE_TRANSACTION,
                format!("0x{}", hex::encode(&payload)),
                at
            ]),
        )
        .await
        .map_err(rpc_failed)?;
    let encoded = result
        .as_str()
        .ok_or_else(|| CoinageSubmitError::Unverified {
            reason: "state_call returned a non-string result".to_string(),
        })
        .and_then(|hex_str| decode_hex(hex_str, "state_call result"))?;

    decode_validity(&encoded)
}

/// Classify what an already-included extrinsic did, from its inclusion block.
pub async fn verdict_at(
    rpc: &RpcClient,
    metadata: &Metadata,
    block_hash: &str,
    finalized: bool,
    extrinsic: &[u8],
) -> Result<SubmissionVerdict, CoinageSubmitError> {
    let block = rpc
        .call("chain_getBlock", json!([block_hash]))
        .await
        .map_err(rpc_failed)?;
    let index =
        extrinsic_index(&block, extrinsic).ok_or_else(|| CoinageSubmitError::Unverified {
            reason: format!("{block_hash} does not contain the submitted extrinsic"),
        })?;

    let raw = rpc
        .get_storage_at(&system_events_key(), block_hash)
        .await
        .map_err(rpc_failed)?
        .ok_or_else(|| CoinageSubmitError::Unverified {
            reason: format!("{block_hash} reports no System.Events"),
        })?;
    let type_id = metadata
        .storage_value_type("System", "Events")
        .ok_or_else(|| CoinageSubmitError::Metadata("System.Events is absent".to_string()))?;
    let events = decode_as_type(&mut &raw[..], type_id, metadata.registry()).map_err(|error| {
        CoinageSubmitError::Unverified {
            reason: format!("decoding System.Events at {block_hash} failed: {error}"),
        }
    })?;

    classify_events(&events, index, decode_hash(block_hash)?, finalized)
}

/// `System::Events`, an unhashed plain entry.
fn system_events_key() -> Vec<u8> {
    [
        twox_128(b"System").as_slice(),
        twox_128(b"Events").as_slice(),
    ]
    .concat()
}

/// Position of `extrinsic` among a `chain_getBlock` response's extrinsics.
///
/// Matched on the full encoded bytes, length prefix included, which is exactly
/// what both the node and [`super::extrinsic`] produce.
fn extrinsic_index(block: &serde_json::Value, extrinsic: &[u8]) -> Option<u32> {
    let wanted = format!("0x{}", hex::encode(extrinsic));
    block
        .get("block")?
        .get("extrinsics")?
        .as_array()?
        .iter()
        .position(|candidate| candidate.as_str() == Some(wanted.as_str()))
        .and_then(|position| u32::try_from(position).ok())
}

/// Read the dispatch outcome out of a block's decoded events.
///
/// Fail-closed in both directions: failure wins over success, and a block whose
/// events name neither outcome for our extrinsic leaves the result unverified
/// rather than assuming the friendlier one.
fn classify_events(
    events: &Value<u32>,
    index: u32,
    block_hash: BlockHash,
    finalized: bool,
) -> Result<SubmissionVerdict, CoinageSubmitError> {
    let records = match &events.value {
        ValueDef::Composite(composite) => composite,
        other => {
            return Err(CoinageSubmitError::Unverified {
                reason: format!("System.Events decoded as {other:?}, expected a sequence"),
            });
        }
    };

    let ours = records
        .values()
        .filter(|record| record_phase_index(record) == Some(index))
        .filter_map(record_event);

    let mut succeeded = false;
    for event in ours {
        let Some(inner) = pallet_event(event, "System") else {
            continue;
        };
        match inner.name.as_str() {
            "ExtrinsicFailed" => {
                return Ok(SubmissionVerdict::DispatchFailed {
                    block_hash,
                    finalized,
                    reason: describe_dispatch_error(inner),
                });
            }
            "ExtrinsicSuccess" => succeeded = true,
            _ => {}
        }
    }

    if succeeded {
        Ok(SubmissionVerdict::Succeeded {
            block_hash,
            finalized,
        })
    } else {
        Err(CoinageSubmitError::Unverified {
            reason: format!("no dispatch outcome for extrinsic {index} in the inclusion block"),
        })
    }
}

/// The extrinsic index an event record is attributed to, if any.
fn record_phase_index(record: &Value<u32>) -> Option<u32> {
    let phase = as_variant(field(record, "phase", 0)?)?;
    (phase.name == "ApplyExtrinsic")
        .then(|| phase.values.values().next())
        .flatten()?
        .as_u128()
        .and_then(|index| u32::try_from(index).ok())
}

/// The runtime event carried by an event record.
fn record_event(record: &Value<u32>) -> Option<&Variant<u32>> {
    as_variant(field(record, "event", 1)?)
}

/// The pallet-scoped event inside a runtime event, when it belongs to `pallet`.
fn pallet_event<'a>(event: &'a Variant<u32>, pallet: &str) -> Option<&'a Variant<u32>> {
    (event.name == pallet)
        .then(|| event.values.values().next())
        .flatten()
        .and_then(as_variant)
}

/// Render a `System.ExtrinsicFailed` payload's dispatch error.
///
/// Rendered rather than resolved: naming the module error would need each
/// pallet's error type, which the metadata this layer carries does not collect.
/// A structural rendering is honest about that; a fabricated name would not be.
fn describe_dispatch_error(failed: &Variant<u32>) -> String {
    match failed.values.values().next() {
        Some(error) => error.to_string(),
        None => "unspecified".to_string(),
    }
}

/// A composite's field by name, falling back to its position.
fn field<'a>(value: &'a Value<u32>, name: &str, position: usize) -> Option<&'a Value<u32>> {
    match &value.value {
        ValueDef::Composite(Composite::Named(fields)) => fields
            .iter()
            .find_map(|(key, value)| (key == name).then_some(value)),
        ValueDef::Composite(Composite::Unnamed(values)) => values.get(position),
        _ => None,
    }
}

/// A value as an enum variant.
fn as_variant(value: &Value<u32>) -> Option<&Variant<u32>> {
    match &value.value {
        ValueDef::Variant(variant) => Some(variant),
        _ => None,
    }
}

/// Split a `Result<ValidTransaction, TransactionValidityError>` into accepted
/// or rejected, naming the rejection.
fn decode_validity(encoded: &[u8]) -> Result<(), CoinageSubmitError> {
    match encoded.split_first() {
        Some((0, _)) => Ok(()),
        Some((1, rest)) => Err(CoinageSubmitError::DryRunRejected {
            reason: describe_validity_error(rest),
        }),
        Some((other, _)) => Err(CoinageSubmitError::Unverified {
            reason: format!("validate_transaction returned an unknown Result tag {other}"),
        }),
        None => Err(CoinageSubmitError::Unverified {
            reason: "validate_transaction returned nothing".to_string(),
        }),
    }
}

/// Name a `TransactionValidityError`.
fn describe_validity_error(encoded: &[u8]) -> String {
    match encoded.split_first() {
        Some((0, rest)) => format!(
            "Invalid::{}",
            describe_variant(INVALID_TRANSACTION, INVALID_TRANSACTION_CUSTOM, rest)
        ),
        Some((1, rest)) => format!(
            "Unknown::{}",
            describe_variant(UNKNOWN_TRANSACTION, UNKNOWN_TRANSACTION_CUSTOM, rest)
        ),
        Some((other, _)) => format!("unknown TransactionValidityError variant {other}"),
        None => "truncated TransactionValidityError".to_string(),
    }
}

/// Name one variant of a pinned validity enum, unfolding the `Custom(u8)` code
/// a runtime uses to report its own rejections.
fn describe_variant(names: &[&str], custom: u8, encoded: &[u8]) -> String {
    let Some((&discriminant, rest)) = encoded.split_first() else {
        return "truncated".to_string();
    };
    let Some(name) = names.get(discriminant as usize) else {
        return format!("variant {discriminant}");
    };
    match (discriminant == custom, rest.first()) {
        (true, Some(code)) => format!("{name}({code})"),
        (true, None) => format!("{name}(truncated)"),
        (false, _) => (*name).to_string(),
    }
}

/// Decode a `0x`-prefixed 32-byte hash.
fn decode_hash(value: &str) -> Result<BlockHash, CoinageSubmitError> {
    let bytes = decode_hex(value, "block hash")?;
    let length = bytes.len();
    bytes
        .try_into()
        .map(BlockHash)
        .map_err(|_| CoinageSubmitError::Unverified {
            reason: format!("block hash is {length} bytes, expected 32"),
        })
}

/// Decode `0x`-prefixed hex, naming what was being decoded.
fn decode_hex(value: &str, what: &str) -> Result<Vec<u8>, CoinageSubmitError> {
    hex::decode(value.strip_prefix("0x").unwrap_or(value)).map_err(|error| {
        CoinageSubmitError::Unverified {
            reason: format!("{what} is not hex: {error}"),
        }
    })
}

/// Wrap a JSON-RPC failure.
fn rpc_failed(error: StatementAllowanceError) -> CoinageSubmitError {
    CoinageSubmitError::Rpc(Box::new(error))
}

/// Separate a broadcast the node definitively refused from one whose fate the
/// watch simply stopped reporting.
///
/// Only `invalid` and `dropped` mean nothing was included. `retracted`,
/// `usurped` and `finalityTimeout` all describe a transaction that reached a
/// block or a pool and may yet land, so they are unknown rather than refused —
/// treating them as refused would release inputs the chain could still consume.
fn classify_watch_failure(error: StatementAllowanceError) -> TrackerOutcome {
    match &error {
        StatementAllowanceError::Rpc(RpcError::ExtrinsicRejected { status })
            if NOT_INCLUDED_STATUSES.contains(&status.as_str()) =>
        {
            TrackerOutcome::NotIncluded {
                reason: status.clone(),
            }
        }
        _ => TrackerOutcome::Unknown {
            reason: error.to_string(),
        },
    }
}

#[cfg(test)]
mod tests {
    use parity_scale_codec::{Compact, Encode};
    use scale_info::{PortableRegistry, TypeDef, TypeDefPrimitive};
    use subxt::ext::scale_encode::{EncodeAsFields, Field};
    use subxt::ext::scale_value::{Primitive, Value as ScaleValue};
    use subxt::metadata::ArcMetadata;
    use subxt_rpcs::RpcClient as HostRpcClient;

    use crate::runtime::statement_allowance::rpc::testing::ScriptedRpc;

    use super::*;

    const FIXTURE: &[u8] = include_bytes!("../../../tests/fixtures/paseo-next-v2-metadata.scale");

    fn metadata() -> Metadata {
        Metadata::decode(FIXTURE).expect("the fixture decodes")
    }

    /// The same fixture through Subxt, which exposes the event variants the
    /// thin metadata does not, so tests can synthesize a block's events.
    fn subxt_metadata() -> ArcMetadata {
        ArcMetadata::from(
            subxt::Metadata::decode_from(FIXTURE).expect("the fixture decodes for subxt"),
        )
    }

    /// One `System` event attributed to extrinsic `index`, encoded exactly as
    /// the runtime stores `System.Events`.
    fn system_events(event_name: &str, index: u32) -> Vec<u8> {
        let metadata = subxt_metadata();
        let system = metadata.pallet_by_name("System").expect("System exists");
        let event = system
            .event_variants()
            .expect("System has events")
            .iter()
            .find(|event| event.name == event_name)
            .expect("the event exists");
        let values = ScaleValue::unnamed_composite(
            event
                .fields
                .iter()
                .map(|field| default_value(metadata.types(), field.ty.id)),
        );
        let mut fields = event
            .fields
            .iter()
            .map(|field| Field::new(field.ty.id, field.name.as_deref()));

        let mut bytes = Vec::new();
        Compact(1u32).encode_to(&mut bytes);
        // Phase::ApplyExtrinsic(index).
        0u8.encode_to(&mut bytes);
        index.encode_to(&mut bytes);
        system.event_index().encode_to(&mut bytes);
        event.index.encode_to(&mut bytes);
        values
            .encode_as_fields_to(&mut fields, metadata.types(), &mut bytes)
            .expect("the event payload encodes");
        Vec::<[u8; 32]>::new().encode_to(&mut bytes);
        bytes
    }

    fn decoded_events(raw: &[u8], metadata: &Metadata) -> Value<u32> {
        let type_id = metadata
            .storage_value_type("System", "Events")
            .expect("System.Events is in metadata");
        decode_as_type(&mut &raw[..], type_id, metadata.registry()).expect("events decode")
    }

    fn default_value(types: &PortableRegistry, type_id: u32) -> ScaleValue {
        let ty = types.resolve(type_id).expect("metadata type exists");
        match &ty.type_def {
            TypeDef::Composite(composite) => ScaleValue::unnamed_composite(
                composite
                    .fields
                    .iter()
                    .map(|field| default_value(types, field.ty.id)),
            ),
            TypeDef::Variant(variants) => {
                let variant = variants.variants.first().expect("variant exists");
                ScaleValue::unnamed_variant(
                    variant.name.clone(),
                    variant
                        .fields
                        .iter()
                        .map(|field| default_value(types, field.ty.id)),
                )
            }
            TypeDef::Sequence(_) => ScaleValue::unnamed_composite([]),
            TypeDef::Array(array) => ScaleValue::unnamed_composite(
                (0..array.len).map(|_| default_value(types, array.type_param.id)),
            ),
            TypeDef::Tuple(tuple) => ScaleValue::unnamed_composite(
                tuple
                    .fields
                    .iter()
                    .map(|field| default_value(types, field.id)),
            ),
            TypeDef::Primitive(primitive) => match primitive {
                TypeDefPrimitive::Bool => ScaleValue::bool(false),
                TypeDefPrimitive::Char => ScaleValue::char('\0'),
                TypeDefPrimitive::Str => ScaleValue::string(""),
                TypeDefPrimitive::U8
                | TypeDefPrimitive::U16
                | TypeDefPrimitive::U32
                | TypeDefPrimitive::U64
                | TypeDefPrimitive::U128 => ScaleValue::u128(0),
                TypeDefPrimitive::U256 => ScaleValue::primitive(Primitive::U256([0; 32])),
                TypeDefPrimitive::I8
                | TypeDefPrimitive::I16
                | TypeDefPrimitive::I32
                | TypeDefPrimitive::I64
                | TypeDefPrimitive::I128 => ScaleValue::i128(0),
                TypeDefPrimitive::I256 => ScaleValue::primitive(Primitive::I256([0; 32])),
            },
            TypeDef::Compact(_) => ScaleValue::u128(0),
            TypeDef::BitSequence(_) => {
                ScaleValue::bit_sequence(subxt::ext::scale_bits::Bits::new())
            }
        }
    }

    const BLOCK: BlockHash = BlockHash([7; 32]);

    #[test]
    fn a_success_event_for_our_index_is_a_success() {
        let metadata = metadata();
        let events = decoded_events(&system_events("ExtrinsicSuccess", 3), &metadata);

        assert_eq!(
            classify_events(&events, 3, BLOCK, true).expect("classifies"),
            SubmissionVerdict::Succeeded {
                block_hash: BLOCK,
                finalized: true
            }
        );
    }

    #[test]
    fn a_failure_event_for_our_index_is_a_failed_dispatch() {
        let metadata = metadata();
        let events = decoded_events(&system_events("ExtrinsicFailed", 0), &metadata);

        let verdict = classify_events(&events, 0, BLOCK, false).expect("classifies");
        assert!(!verdict.succeeded());
        assert_eq!(verdict.block_hash(), BLOCK);
        let SubmissionVerdict::DispatchFailed { reason, .. } = verdict else {
            unreachable!("the verdict is a failed dispatch");
        };
        assert!(!reason.is_empty(), "the dispatch error is rendered");
    }

    #[test]
    fn another_extrinsics_outcome_is_not_ours() {
        // The dangerous confusion: a block usually carries several extrinsics,
        // and the inherents at the front of it always succeed.
        let metadata = metadata();
        let events = decoded_events(&system_events("ExtrinsicSuccess", 0), &metadata);

        let error = classify_events(&events, 1, BLOCK, true).expect_err("no outcome for index 1");
        assert!(matches!(error, CoinageSubmitError::Unverified { .. }));
        assert!(!error.is_definitively_not_included());
    }

    #[test]
    fn a_block_without_our_outcome_stays_unverified() {
        let metadata = metadata();
        let events = decoded_events(&[0u8], &metadata);

        assert!(matches!(
            classify_events(&events, 0, BLOCK, true),
            Err(CoinageSubmitError::Unverified { .. })
        ));
    }

    #[test]
    fn the_extrinsic_is_found_by_its_exact_bytes() {
        let block = json!({
            "block": {
                "extrinsics": ["0xaabb", "0xccdd", "0xeeff"],
            }
        });

        assert_eq!(extrinsic_index(&block, &[0xcc, 0xdd]), Some(1));
        assert_eq!(extrinsic_index(&block, &[0xcc]), None);
        assert_eq!(extrinsic_index(&block, &[0x11, 0x22]), None);
    }

    #[test]
    fn a_valid_dry_run_is_accepted() {
        // `Ok(ValidTransaction { .. })`; the payload is not inspected.
        let encoded = [0u8, 1, 2, 3];

        assert!(decode_validity(&encoded).is_ok());
    }

    fn rejection_reason(encoded: &[u8]) -> String {
        let error = decode_validity(encoded).expect_err("rejected");
        assert!(
            error.is_definitively_not_included(),
            "a dry-run rejection means nothing was broadcast"
        );
        let CoinageSubmitError::DryRunRejected { reason } = error else {
            unreachable!("the dry-run rejected it");
        };
        reason
    }

    #[test]
    fn an_invalid_dry_run_is_named_and_never_broadcast() {
        // `Err(Invalid(Payment))`.
        assert_eq!(rejection_reason(&[1, 0, 1]), "Invalid::Payment");
        // `Err(Unknown(NoUnsignedValidator))` — what an unsigned coinage
        // extrinsic gets when the extension declines to authorize it.
        assert_eq!(rejection_reason(&[1, 1, 1]), "Unknown::NoUnsignedValidator");
    }

    #[test]
    fn a_custom_rejection_keeps_the_runtime_s_code() {
        // The pallet's own extension rejections arrive this way, and the code
        // is the only thing distinguishing them.
        assert_eq!(rejection_reason(&[1, 0, 7, 42]), "Invalid::Custom(42)");
        assert_eq!(rejection_reason(&[1, 1, 2, 9]), "Unknown::Custom(9)");
    }

    #[test]
    fn an_unknown_discriminant_is_reported_by_number_not_guessed() {
        // The enums only ever grow at the end, so a newer runtime must not be
        // mis-named as the last variant this build happens to know.
        assert_eq!(rejection_reason(&[1, 0, 200]), "Invalid::variant 200");
    }

    #[test]
    fn a_truncated_dry_run_result_is_unverified() {
        assert!(matches!(
            decode_validity(&[]),
            Err(CoinageSubmitError::Unverified { .. })
        ));
    }

    #[test]
    fn only_a_refused_broadcast_clears_the_records_for_reuse() {
        let refused = classify_watch_failure(
            RpcError::ExtrinsicRejected {
                status: "invalid".to_string(),
            }
            .into(),
        );
        assert!(refused.is_definitively_not_included());

        // A transaction that reached a block and was then retracted may still
        // land; treating it as refused would resubmit records the chain could
        // yet consume.
        let retracted = classify_watch_failure(
            RpcError::ExtrinsicRejected {
                status: "retracted".to_string(),
            }
            .into(),
        );
        assert!(!retracted.is_definitively_not_included());
        assert!(matches!(retracted, TrackerOutcome::Unknown { .. }));
        assert!(!retracted.is_definite(), "recovery must resolve it");

        let timeout = classify_watch_failure(RpcError::SubmitTimeout.into());
        assert!(!timeout.is_definitively_not_included());
        assert!(matches!(timeout, TrackerOutcome::Unknown { .. }));
    }

    #[test]
    fn the_extrinsic_hash_is_blake2_256_of_the_encoded_bytes() {
        let extrinsic = [0x45u8, 0x00, 0xff];

        assert_eq!(extrinsic_hash(&extrinsic).0, blake2_256(&extrinsic));
    }

    /// The 32-byte hash matching [`BLOCK`], as the node reports it.
    const BLOCK_HEX: &str = "0x0707070707070707070707070707070707070707070707070707070707070707";

    /// Bytes standing in for an assembled coinage extrinsic.
    const EXTRINSIC: &[u8] = &[0x45, 0x00, 0xff];

    fn scripted(responses: &[String]) -> (ScriptedRpc, RpcClient) {
        let scripted = ScriptedRpc::new(responses.iter().map(String::as_str));
        let rpc = RpcClient::new(HostRpcClient::new(scripted.clone()));
        (scripted, rpc)
    }

    fn quoted_hex(bytes: &[u8]) -> String {
        format!("\"0x{}\"", hex::encode(bytes))
    }

    #[test]
    fn a_submission_runs_dry_run_then_watch_then_events() {
        let events = system_events("ExtrinsicSuccess", 1);
        let (scripted, rpc) = scripted(&[
            format!("\"{BLOCK_HEX}\""),
            // `Ok(ValidTransaction { .. })`, payload elided.
            quoted_hex(&[0]),
            format!(
                r#"{{"block":{{"extrinsics":["0xdeadbeef","0x{}"]}}}}"#,
                hex::encode(EXTRINSIC)
            ),
            quoted_hex(&events),
        ]);
        scripted.script_subscription([format!(r#"{{"inBlock":"{BLOCK_HEX}"}}"#).as_str()]);

        let outcome = futures::executor::block_on(submit(&rpc, &metadata(), EXTRINSIC));

        // The node reported `inBlock`, not `finalized`, so this is optimistic:
        // it says what happened without settling it.
        assert_eq!(
            outcome,
            TrackerOutcome::Included(SubmissionVerdict::Succeeded {
                block_hash: BLOCK,
                finalized: false,
            })
        );
        assert!(
            !outcome.is_definite(),
            "an in-block inclusion is not settled"
        );
        let methods: Vec<_> = scripted
            .calls()
            .into_iter()
            .map(|(method, _)| method)
            .collect();
        assert_eq!(
            methods,
            vec![
                "chain_getFinalizedHead",
                "state_call",
                "author_submitAndWatchExtrinsic",
                "chain_getBlock",
                "state_getStorage",
            ]
        );
    }

    #[test]
    fn a_rejected_dry_run_stops_before_broadcasting() {
        // The whole point of the dry-run: an extrinsic whose proofs the
        // extension refuses must never reach the network.
        let (scripted, rpc) = scripted(&[
            format!("\"{BLOCK_HEX}\""),
            // `Err(Invalid(Custom(3)))`.
            quoted_hex(&[1, 0, 7, 3]),
        ]);

        let outcome = futures::executor::block_on(submit(&rpc, &metadata(), EXTRINSIC));

        assert!(outcome.is_definitively_not_included());
        assert!(
            outcome.is_definite(),
            "nothing was sent, so nothing is open"
        );
        let TrackerOutcome::NotIncluded { reason } = &outcome else {
            unreachable!("the dry-run rejected it");
        };
        assert_eq!(reason, "dry-run rejected the extrinsic: Invalid::Custom(3)");
        assert!(
            !scripted
                .calls()
                .iter()
                .any(|(method, _)| method.contains("submit")),
            "nothing was broadcast"
        );
    }

    #[test]
    fn an_inclusion_block_without_our_extrinsic_is_unverified() {
        let (scripted, rpc) = scripted(&[
            format!("\"{BLOCK_HEX}\""),
            quoted_hex(&[0]),
            r#"{"block":{"extrinsics":["0xdeadbeef"]}}"#.to_string(),
        ]);
        scripted.script_subscription([format!(r#"{{"inBlock":"{BLOCK_HEX}"}}"#).as_str()]);

        let outcome = futures::executor::block_on(submit(&rpc, &metadata(), EXTRINSIC));

        assert!(matches!(outcome, TrackerOutcome::Unknown { .. }));
        assert!(!outcome.is_definitively_not_included());
        assert!(!outcome.is_definite());
    }

    #[test]
    fn a_finalized_inclusion_settles_the_transaction_immediately() {
        // When the node reports `finalized` straight away there is nothing for
        // recovery to do, and the outcome may be written to the log as it is.
        let events = system_events("ExtrinsicSuccess", 1);
        let (scripted, rpc) = scripted(&[
            format!("\"{BLOCK_HEX}\""),
            quoted_hex(&[0]),
            format!(
                r#"{{"block":{{"extrinsics":["0xdeadbeef","0x{}"]}}}}"#,
                hex::encode(EXTRINSIC)
            ),
            quoted_hex(&events),
        ]);
        scripted.script_subscription([format!(r#"{{"finalized":"{BLOCK_HEX}"}}"#).as_str()]);

        let outcome = futures::executor::block_on(submit(&rpc, &metadata(), EXTRINSIC));

        assert_eq!(
            outcome,
            TrackerOutcome::Included(SubmissionVerdict::Succeeded {
                block_hash: BLOCK,
                finalized: true,
            })
        );
        assert!(outcome.is_definite());
    }

    #[test]
    fn the_system_events_key_is_stable() {
        // Golden: a silently changed key returns no events, which would read as
        // "the block had no outcome" rather than as an error.
        assert_eq!(
            hex::encode(system_events_key()),
            "26aa394eea5630e07c48ae0c9558cef780d41e5e16056765bc8461851072c9d7"
        );
    }
}
