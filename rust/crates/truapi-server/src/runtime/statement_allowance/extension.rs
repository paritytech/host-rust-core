//! Signed-extension encoding for the unsigned General (v5) `AsResources`
//! extrinsic, driven by live chain metadata.
//!
//! The extension **order** and per-extension type ids come from the runtime
//! metadata (`state_getMetadata`, V14/V15/V16); the per-extension `extra` /
//! `additional_signed` bytes come from a name-keyed encoder mirroring
//! signing-bot `src/core/create-transaction.ts` `encodeSignedExtensions`, with a
//! generic default for the personhood extensions (all `Option`/void).
//!
//! Two concatenations are derived from the same encoded list:
//! - the ring-VRF proof message (`build_proof_message`) over the extensions
//!   strictly *after* `AsResources` (host-spec inherited implication), and
//! - the full extrinsic body's `Σ extra` (see `extrinsic.rs`), over *all*
//!   extensions with `AsResources` carrying `Some(AsResourcesInfo)`.

use std::collections::HashMap;

use frame_metadata::RuntimeMetadata;
use frame_metadata::RuntimeMetadataPrefixed;
use parity_scale_codec::{Compact, Decode, Encode};
use scale_info::form::PortableForm;
use scale_info::{PortableRegistry, TypeDef, TypeDefPrimitive, TypeDefVariant};
use thiserror::Error;

use super::StatementAllowanceError;

/// Signed-extension identifier that carries the `AsResources` authorization.
pub const AS_RESOURCES: &str = "AsResources";

/// Error while decoding runtime metadata or resolving allowance-specific
/// metadata entries.
#[derive(Debug, Error)]
pub enum MetadataError {
    /// `state_getMetadata` did not return a hex string.
    #[error("state_getMetadata returned non-string")]
    MetadataResultNotString,
    /// Metadata hex payload was invalid.
    #[error("metadata hex: {0}")]
    MetadataHex(#[source] hex::FromHexError),
    /// Opaque metadata wrapper could not be decoded.
    #[error("opaque metadata: {0}")]
    OpaqueMetadata(#[source] parity_scale_codec::Error),
    /// Runtime metadata prefix could not be decoded.
    #[error("metadata decode failed: {0}")]
    Decode(#[source] parity_scale_codec::Error),
    /// Runtime metadata version is not supported by this encoder.
    #[error("unsupported metadata version {version}")]
    UnsupportedVersion {
        /// Runtime metadata version.
        version: u32,
    },
    /// Pallet has no call enum.
    #[error("pallet `{pallet}` has no calls in metadata")]
    MissingPalletCalls {
        /// Pallet name.
        pallet: String,
    },
    /// Named pallet call was not found.
    #[error("call `{pallet}.{call}` not found in metadata")]
    MissingCall {
        /// Pallet name.
        pallet: String,
        /// Call name.
        call: String,
    },
    /// `AsResources` extension is absent from metadata.
    #[error("{AS_RESOURCES} extension not found in metadata")]
    MissingAsResourcesExtension,
    /// `AsResources` extra type did not contain the expected `Option`.
    #[error("{AS_RESOURCES} extra is not an Option")]
    AsResourcesExtraNotOption,
    /// Named `AsResourcesInfo` variant was not found.
    #[error("AsResourcesInfo::{variant} not found in metadata")]
    MissingAsResourcesInfoVariant {
        /// Variant name.
        variant: String,
    },
    /// Named `AsResourcesInfo` variant did not carry a membership collection.
    #[error("AsResourcesInfo::{variant} carries no MembershipCollection field")]
    MissingMembershipCollection {
        /// Variant name.
        variant: String,
    },
    /// `MembershipCollection::LitePeople` variant was not found.
    #[error("MembershipCollection::LitePeople not found in metadata")]
    MissingLitePeopleCollection,
    /// A transaction extension named in a request is absent from metadata.
    #[error("`{identifier}` extension not found in metadata")]
    MissingExtension {
        /// Extension identifier that was looked up.
        identifier: String,
    },
    /// An extension's extra is not the `Option<Info>` shape this resolver walks.
    #[error("`{identifier}` extra is not an Option")]
    ExtensionExtraNotOption {
        /// Extension identifier that was looked up.
        identifier: String,
    },
    /// The named variant is absent from an extension's info enum.
    #[error("`{extension}` info enum has no variant `{variant}`")]
    MissingExtensionInfoVariant {
        /// Extension identifier that was looked up.
        extension: String,
        /// Variant name that was looked up.
        variant: String,
    },
    /// Type id did not resolve in the portable registry.
    #[error("unknown type id {type_id}")]
    UnknownTypeId {
        /// Missing type id.
        type_id: u32,
    },
    /// Type id did not resolve to an enum.
    #[error("type {type_id} is not an enum")]
    TypeNotEnum {
        /// Type id.
        type_id: u32,
    },
    /// Type id did not resolve to a composite.
    #[error("type {type_id} is not a composite")]
    TypeNotComposite {
        /// Type id.
        type_id: u32,
    },
    /// Composite type had the wrong field count.
    #[error("type {type_id} has {actual} fields, expected 1")]
    CompositeFieldCount {
        /// Type id.
        type_id: u32,
        /// Actual field count.
        actual: usize,
    },
    /// Storage value type was missing from metadata.
    #[error("{pallet}.{entry} type not in metadata")]
    MissingStorageType {
        /// Pallet name.
        pallet: &'static str,
        /// Storage entry name.
        entry: &'static str,
    },
    /// Pallet constant was missing from metadata.
    #[error("{pallet}.{constant} constant missing")]
    MissingConstant {
        /// Pallet name.
        pallet: &'static str,
        /// Constant name.
        constant: &'static str,
    },
}

/// Anchor for a mortal transaction era.
///
/// A mortal extrinsic is only includable in `[anchor, anchor + period]`. That
/// bound is what lets a caller eventually decide that a transaction it lost
/// track of can never land — an immortal extrinsic offers no such point, so
/// returning its inputs to a spendable pool is never safe.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct EraAnchor {
    /// Height of the anchor block.
    pub number: u64,
    /// Hash of the anchor block; the `CheckMortality` implicit.
    pub hash: [u8; 32],
    /// Era length in blocks.
    pub period: u64,
}

/// Smallest era period Substrate's encoding admits.
const MIN_ERA_PERIOD: u64 = 4;
/// Largest era period Substrate's encoding admits.
const MAX_ERA_PERIOD: u64 = 1 << 16;

impl EraAnchor {
    /// Anchor an era of `period` blocks at the given block.
    ///
    /// `period` is rounded up to a power of two and clamped to Substrate's
    /// `[4, 65536]`, matching `sp_runtime::generic::Era::mortal`.
    pub fn new(number: u64, hash: [u8; 32], period: u64) -> Self {
        let period = period
            .checked_next_power_of_two()
            .unwrap_or(MAX_ERA_PERIOD)
            .clamp(MIN_ERA_PERIOD, MAX_ERA_PERIOD);
        Self {
            number,
            hash,
            period,
        }
    }

    /// Last block height at which the extrinsic can still be included.
    ///
    /// The anchor is its own era birth: this layer only ever quantizes by one
    /// (periods up to 4096), so `birth(number) == number`.
    pub const fn last_valid_block(&self) -> u64 {
        self.number.saturating_add(self.period)
    }

    /// SCALE-encoded `Era::Mortal`: a little-endian `u16` carrying
    /// `log2(period) - 1` in the low nibble and the quantized phase above it.
    pub fn encode_era(&self) -> Vec<u8> {
        let quantize_factor = (self.period >> 12).max(1);
        let phase = self.number % self.period;
        let quantized_phase = phase / quantize_factor * quantize_factor;

        let low = (self.period.trailing_zeros() as u16)
            .saturating_sub(1)
            .clamp(1, 15);
        let high = ((quantized_phase / quantize_factor) as u16) << 4;
        (low | high).encode()
    }
}

/// Chain state needed to fill the standard signed extensions.
#[derive(Debug, Clone, Copy)]
pub struct ChainState {
    /// Runtime `specVersion` (CheckSpecVersion implicit).
    pub spec_version: u32,
    /// Runtime `transactionVersion` (CheckTxVersion implicit).
    pub transaction_version: u32,
    /// Genesis block hash (CheckGenesis implicit; also CheckMortality's when
    /// the transaction is immortal).
    pub genesis_hash: [u8; 32],
    /// Account nonce (CheckNonce extra); ignored by the unsigned path.
    pub nonce: u32,
    /// Era anchor, or `None` for an immortal transaction.
    ///
    /// Opt-in rather than always-on: allowance registration has always used
    /// immortal extrinsics and has no recovery procedure that needs an expiry,
    /// whereas coinage requires mortality (`coinage-layer.md` §7.4).
    pub mortality: Option<EraAnchor>,
}

/// A signed extension's identifier plus the type ids of its `extra` and
/// `additional_signed` fields, in metadata order.
struct ExtensionDef {
    identifier: String,
    extra_type: u32,
    additional_signed_type: u32,
}

/// A signed extension encoded to its `extra` and `additional_signed` bytes.
pub struct EncodedExtension {
    /// SCALE-encoded `extra` (goes into the extrinsic body).
    pub extra: Vec<u8>,
    /// SCALE-encoded `additional_signed` (the implicit, part of the signed data).
    pub additional_signed: Vec<u8>,
}

/// Decoded metadata: the ordered signed-extension defs, the type registry,
/// each storage entry's value type id (`(pallet, entry) -> type id`), pallet
/// constants, and each pallet's `(index, call enum type id)`.
pub struct Metadata {
    extensions: Vec<ExtensionDef>,
    registry: PortableRegistry,
    storage_values: HashMap<(String, String), u32>,
    constants: HashMap<(String, String), Vec<u8>>,
    calls: HashMap<String, (u8, u32)>,
}

/// Collect extensions, type registry, storage value types, and pallet constants
/// from decoded metadata; `$set` is the version's `StorageEntryType`.
macro_rules! collect_metadata {
    ($m:expr, $set:path) => {{
        let extensions = $m
            .extrinsic
            .signed_extensions
            .iter()
            .map(|e| ExtensionDef {
                identifier: e.identifier.clone(),
                extra_type: e.ty.id,
                additional_signed_type: e.additional_signed.id,
            })
            .collect();
        let mut storage_values = HashMap::new();
        let mut constants = HashMap::new();
        let mut calls = HashMap::new();
        for pallet in &$m.pallets {
            if let Some(pallet_calls) = &pallet.calls {
                calls.insert(pallet.name.clone(), (pallet.index, pallet_calls.ty.id));
            }
            for constant in &pallet.constants {
                constants.insert(
                    (pallet.name.clone(), constant.name.clone()),
                    constant.value.clone(),
                );
            }
            let Some(storage) = &pallet.storage else {
                continue;
            };
            for entry in &storage.entries {
                use $set as EntryType;
                let value_type = match &entry.ty {
                    EntryType::Plain(ty) => ty.id,
                    EntryType::Map { value, .. } => value.id,
                };
                storage_values.insert((pallet.name.clone(), entry.name.clone()), value_type);
            }
        }
        (extensions, $m.types, storage_values, constants, calls)
    }};
}

macro_rules! collect_metadata_v16 {
    ($m:expr) => {{
        let extension_indexes = $m
            .extrinsic
            .transaction_extensions_by_version
            .get(&5)
            .map(|indexes| {
                indexes
                    .iter()
                    .map(|Compact(index)| *index as usize)
                    .collect::<Vec<_>>()
            })
            .unwrap_or_else(|| (0..$m.extrinsic.transaction_extensions.len()).collect());
        let extensions = extension_indexes
            .into_iter()
            .filter_map(|index| $m.extrinsic.transaction_extensions.get(index))
            .map(|e| ExtensionDef {
                identifier: e.identifier.clone(),
                extra_type: e.ty.id,
                additional_signed_type: e.implicit.id,
            })
            .collect();
        let mut storage_values = HashMap::new();
        let mut constants = HashMap::new();
        let mut calls = HashMap::new();
        for pallet in &$m.pallets {
            if let Some(pallet_calls) = &pallet.calls {
                calls.insert(pallet.name.clone(), (pallet.index, pallet_calls.ty.id));
            }
            for constant in &pallet.constants {
                constants.insert(
                    (pallet.name.clone(), constant.name.clone()),
                    constant.value.clone(),
                );
            }
            let Some(storage) = &pallet.storage else {
                continue;
            };
            for entry in &storage.entries {
                use frame_metadata::v16::StorageEntryType as EntryType;
                let value_type = match &entry.ty {
                    EntryType::Plain(ty) => ty.id,
                    EntryType::Map { value, .. } => value.id,
                };
                storage_values.insert((pallet.name.clone(), entry.name.clone()), value_type);
            }
        }
        (extensions, $m.types, storage_values, constants, calls)
    }};
}

impl Metadata {
    /// Decode `state_getMetadata` bytes (a `RuntimeMetadataPrefixed`, V14
    /// through V16) into the ordered signed-extension defs, type registry,
    /// storage value types, constants, and call enums.
    pub fn decode(bytes: &[u8]) -> Result<Self, StatementAllowanceError> {
        let prefixed =
            RuntimeMetadataPrefixed::decode(&mut &bytes[..]).map_err(MetadataError::Decode)?;
        let (extensions, registry, storage_values, constants, calls) = match prefixed.1 {
            RuntimeMetadata::V14(m) => collect_metadata!(m, frame_metadata::v14::StorageEntryType),
            RuntimeMetadata::V15(m) => collect_metadata!(m, frame_metadata::v15::StorageEntryType),
            RuntimeMetadata::V16(m) => collect_metadata_v16!(m),
            other => {
                return Err(MetadataError::UnsupportedVersion {
                    version: other.version(),
                }
                .into());
            }
        };
        Ok(Self {
            extensions,
            registry,
            storage_values,
            constants,
            calls,
        })
    }

    /// The type registry, for dynamic decoding of storage values.
    pub fn registry(&self) -> &PortableRegistry {
        &self.registry
    }

    /// The value type id of storage entry `pallet::entry`, if present.
    pub fn storage_value_type(&self, pallet: &str, entry: &str) -> Option<u32> {
        self.storage_values
            .get(&(pallet.to_string(), entry.to_string()))
            .copied()
    }

    /// The SCALE-encoded value bytes of pallet constant `pallet::name`.
    pub fn constant(&self, pallet: &str, name: &str) -> Option<&[u8]> {
        self.constants
            .get(&(pallet.to_string(), name.to_string()))
            .map(Vec::as_slice)
    }

    /// Resolve `pallet::call` by name to its `[pallet_index, call_index]`
    /// dispatch bytes.
    pub fn call_indices(
        &self,
        pallet: &str,
        call: &str,
    ) -> Result<[u8; 2], StatementAllowanceError> {
        let (pallet_index, call_type) =
            self.calls
                .get(pallet)
                .copied()
                .ok_or_else(|| MetadataError::MissingPalletCalls {
                    pallet: pallet.to_string(),
                })?;
        let variants = self.resolve_variant(call_type)?;
        let variant = variants
            .variants
            .iter()
            .find(|v| v.name == call)
            .ok_or_else(|| MetadataError::MissingCall {
                pallet: pallet.to_string(),
                call: call.to_string(),
            })?;
        Ok([pallet_index, variant.index])
    }

    /// Resolve `AsResourcesInfo::<info_variant>` and the
    /// `MembershipCollection::LitePeople` index it carries, by name, from the
    /// `AsResources` extension type.
    pub fn as_resources_variant_indices(
        &self,
        info_variant: &str,
    ) -> Result<(u8, u8), StatementAllowanceError> {
        let ext = self
            .extensions
            .iter()
            .find(|e| e.identifier == AS_RESOURCES)
            .ok_or(MetadataError::MissingAsResourcesExtension)?;
        // extra = `AsResources(Option<AsResourcesInfo>)`, with or without the
        // struct wrapper.
        let option_type = match &self.resolve_type(ext.extra_type)?.type_def {
            TypeDef::Composite(_) => self.single_field_type(ext.extra_type)?,
            _ => ext.extra_type,
        };
        let info_type = self
            .resolve_variant(option_type)?
            .variants
            .iter()
            .find(|v| v.name == "Some")
            .and_then(|some| match some.fields.as_slice() {
                [field] => Some(field.ty.id),
                _ => None,
            })
            .ok_or(MetadataError::AsResourcesExtraNotOption)?;
        let variant = self
            .resolve_variant(info_type)?
            .variants
            .iter()
            .find(|v| v.name == info_variant)
            .ok_or_else(|| MetadataError::MissingAsResourcesInfoVariant {
                variant: info_variant.to_string(),
            })?;
        let collection_type = variant
            .fields
            .iter()
            .rev()
            .map(|field| field.ty.id)
            .find(|&id| {
                self.resolve_type(id).is_ok_and(|ty| {
                    ty.path.segments.last().map(String::as_str) == Some("MembershipCollection")
                })
            })
            .ok_or_else(|| MetadataError::MissingMembershipCollection {
                variant: info_variant.to_string(),
            })?;
        let lite_people = self
            .resolve_variant(collection_type)?
            .variants
            .iter()
            .find(|v| v.name == "LitePeople")
            .ok_or(MetadataError::MissingLitePeopleCollection)?;
        Ok((variant.index, lite_people.index))
    }

    /// Position of a transaction extension in metadata order.
    pub fn extension_index(&self, identifier: &str) -> Option<usize> {
        self.extensions
            .iter()
            .position(|e| e.identifier == identifier)
    }

    /// The raw inherited implication for `identifier`: everything the extension
    /// signs over, unhashed.
    ///
    /// That is the extension version byte, the call, then the extras and the
    /// implicits of every extension that follows this one. Returned raw rather
    /// than hashed because some proofs prepend their own material before
    /// hashing — a free unload token signs
    /// `blake2_256(alias_proofs ++ implication)` while an individual alias proof
    /// signs `blake2_256(implication)`.
    pub fn inherited_implication(
        &self,
        identifier: &str,
        call_data: &[u8],
        state: &ChainState,
    ) -> Result<Vec<u8>, StatementAllowanceError> {
        let all = self.encode_signed_extensions(state);
        let tail_start = self
            .extension_index(identifier)
            .map(|i| i + 1)
            .ok_or_else(|| MetadataError::MissingExtension {
                identifier: identifier.to_string(),
            })?;
        let tail = &all[tail_start..];

        let mut payload = Vec::with_capacity(1 + call_data.len());
        payload.push(0x00);
        payload.extend_from_slice(call_data);
        for ext in tail {
            payload.extend_from_slice(&ext.extra);
        }
        for ext in tail {
            payload.extend_from_slice(&ext.additional_signed);
        }
        Ok(payload)
    }

    /// Index of a named variant inside a transaction extension's
    /// `Option<...Info>` extra.
    ///
    /// Variant indices are positional in SCALE and therefore not stable across
    /// runtime upgrades, so callers resolve them by name for the same reason
    /// they resolve call indices by name: a reordered enum should fail loudly
    /// rather than silently select a different mode.
    pub fn extension_info_variant_index(
        &self,
        identifier: &str,
        variant: &str,
    ) -> Result<u8, StatementAllowanceError> {
        let ext = self
            .extensions
            .iter()
            .find(|e| e.identifier == identifier)
            .ok_or_else(|| MetadataError::MissingExtension {
                identifier: identifier.to_string(),
            })?;

        // extra = `Extension(Option<Info>)`, with or without the struct wrapper.
        let option_type = match &self.resolve_type(ext.extra_type)?.type_def {
            TypeDef::Composite(_) => self.single_field_type(ext.extra_type)?,
            _ => ext.extra_type,
        };
        let info_type = self
            .resolve_variant(option_type)?
            .variants
            .iter()
            .find(|v| v.name == "Some")
            .and_then(|some| match some.fields.as_slice() {
                [field] => Some(field.ty.id),
                _ => None,
            })
            .ok_or_else(|| MetadataError::ExtensionExtraNotOption {
                identifier: identifier.to_string(),
            })?;

        self.resolve_variant(info_type)?
            .variants
            .iter()
            .find(|v| v.name == variant)
            .map(|found| found.index)
            .ok_or_else(|| {
                MetadataError::MissingExtensionInfoVariant {
                    extension: identifier.to_string(),
                    variant: variant.to_string(),
                }
                .into()
            })
    }

    /// Resolve a type id in the registry.
    fn resolve_type(
        &self,
        type_id: u32,
    ) -> Result<&scale_info::Type<PortableForm>, StatementAllowanceError> {
        self.registry
            .resolve(type_id)
            .ok_or(MetadataError::UnknownTypeId { type_id }.into())
    }

    /// Resolve `type_id` as an enum definition.
    fn resolve_variant(
        &self,
        type_id: u32,
    ) -> Result<&TypeDefVariant<PortableForm>, StatementAllowanceError> {
        match &self.resolve_type(type_id)?.type_def {
            TypeDef::Variant(variant) => Ok(variant),
            _ => Err(MetadataError::TypeNotEnum { type_id }.into()),
        }
    }

    /// The field type of a one-field composite.
    fn single_field_type(&self, type_id: u32) -> Result<u32, StatementAllowanceError> {
        let TypeDef::Composite(composite) = &self.resolve_type(type_id)?.type_def else {
            return Err(MetadataError::TypeNotComposite { type_id }.into());
        };
        match composite.fields.as_slice() {
            [field] => Ok(field.ty.id),
            fields => Err(MetadataError::CompositeFieldCount {
                type_id,
                actual: fields.len(),
            }
            .into()),
        }
    }

    /// Encode every signed extension in metadata order.
    pub fn encode_signed_extensions(&self, state: &ChainState) -> Vec<EncodedExtension> {
        self.extensions
            .iter()
            .map(|ext| {
                let (extra, additional_signed) = self.encode_one(ext, state);
                EncodedExtension {
                    extra,
                    additional_signed,
                }
            })
            .collect()
    }

    /// The signed-extension identifiers, in metadata order.
    #[cfg(test)]
    pub fn extension_ids(&self) -> Vec<&str> {
        self.extensions
            .iter()
            .map(|e| e.identifier.as_str())
            .collect()
    }

    /// Encode a single extension's `(extra, additional_signed)`, mirroring the
    /// signing-bot switch; unknown personhood extensions fall back to the
    /// metadata type default (`Option` -> None, void -> empty).
    fn encode_one(&self, ext: &ExtensionDef, state: &ChainState) -> (Vec<u8>, Vec<u8>) {
        match ext.identifier.as_str() {
            "CheckNonce" => (Compact(state.nonce).encode(), Vec::new()),
            "CheckSpecVersion" => (Vec::new(), state.spec_version.to_le_bytes().to_vec()),
            "CheckTxVersion" => (Vec::new(), state.transaction_version.to_le_bytes().to_vec()),
            "CheckGenesis" => (Vec::new(), state.genesis_hash.to_vec()),
            // Immortal: extra = 0x00, implicit = genesis hash. Mortal: extra =
            // the encoded era, implicit = the anchor block's hash.
            "CheckMortality" => match state.mortality {
                None => (vec![0x00], state.genesis_hash.to_vec()),
                Some(anchor) => (anchor.encode_era(), anchor.hash.to_vec()),
            },
            // extra = first variant `Disabled` (void) = 0x00.
            "VerifyMultiSignature" => (vec![0x00], Vec::new()),
            // extra = { tip: compact(0), asset_id: None } = 0x00 0x00.
            "ChargeAssetTxPayment" => (vec![0x00, 0x00], Vec::new()),
            // extra = bool false = 0x00.
            "RestrictOrigins" => (vec![0x00], Vec::new()),
            _ => (
                self.encode_default(ext.extra_type),
                self.encode_default(ext.additional_signed_type),
            ),
        }
    }

    /// Encode the "disabled" default value for a metadata type: `Option` -> None
    /// (`0x00`), void/empty tuple -> empty, enums -> first variant, primitives
    /// -> zero. Matches signing-bot `defaultValueForType`.
    fn encode_default(&self, type_id: u32) -> Vec<u8> {
        let Some(ty) = self.registry.resolve(type_id) else {
            return Vec::new();
        };
        match &ty.type_def {
            TypeDef::Composite(c) => c
                .fields
                .iter()
                .flat_map(|f| self.encode_default(f.ty.id))
                .collect(),
            TypeDef::Tuple(t) => t
                .fields
                .iter()
                .flat_map(|f| self.encode_default(f.id))
                .collect(),
            TypeDef::Variant(v) => {
                // Option<T> encodes None as 0x00.
                if ty.path.segments.last().map(String::as_str) == Some("Option") {
                    return vec![0x00];
                }
                match v.variants.iter().min_by_key(|var| var.index) {
                    None => Vec::new(),
                    Some(first) => {
                        let mut out = vec![first.index];
                        for field in &first.fields {
                            out.extend(self.encode_default(field.ty.id));
                        }
                        out
                    }
                }
            }
            TypeDef::Array(a) => {
                let elem = self.encode_default(a.type_param.id);
                elem.repeat(a.len as usize)
            }
            // Sequences / strings / bit-sequences encode an empty run as compact(0).
            TypeDef::Sequence(_) | TypeDef::BitSequence(_) => vec![0x00],
            TypeDef::Compact(_) => vec![0x00],
            TypeDef::Primitive(p) => match p {
                TypeDefPrimitive::Bool | TypeDefPrimitive::U8 | TypeDefPrimitive::I8 => vec![0],
                TypeDefPrimitive::Char | TypeDefPrimitive::U32 | TypeDefPrimitive::I32 => {
                    vec![0; 4]
                }
                TypeDefPrimitive::U16 | TypeDefPrimitive::I16 => vec![0; 2],
                TypeDefPrimitive::U64 | TypeDefPrimitive::I64 => vec![0; 8],
                TypeDefPrimitive::U128 | TypeDefPrimitive::I128 => vec![0; 16],
                TypeDefPrimitive::U256 | TypeDefPrimitive::I256 => vec![0; 32],
                // Length-prefixed string: empty = compact(0).
                TypeDefPrimitive::Str => vec![0x00],
            },
        }
    }

    /// Index of `AsResources` in the extension list, if present.
    pub fn as_resources_index(&self) -> Option<usize> {
        self.extensions
            .iter()
            .position(|e| e.identifier == AS_RESOURCES)
    }
}

/// Build the ring-VRF proof message for an `AsResources`-authorized call:
/// `blake2b256(0x00 ‖ call ‖ Σ tail.extra ‖ Σ tail.additional_signed)`, where
/// the tail is the extensions ordered strictly after `AsResources`. The leading
/// `0x00` is the General-transaction extension-version byte.
pub fn build_proof_message(
    metadata: &Metadata,
    call_data: &[u8],
    state: &ChainState,
) -> Result<[u8; 32], StatementAllowanceError> {
    let all = metadata.encode_signed_extensions(state);
    let tail_start = metadata
        .as_resources_index()
        .map(|i| i + 1)
        .ok_or(MetadataError::MissingAsResourcesExtension)?;
    let tail = &all[tail_start..];

    let mut payload = Vec::with_capacity(1 + call_data.len());
    payload.push(0x00);
    payload.extend_from_slice(call_data);
    for ext in tail {
        payload.extend_from_slice(&ext.extra);
    }
    for ext in tail {
        payload.extend_from_slice(&ext.additional_signed);
    }
    Ok(blake2b256(&payload))
}

/// BLAKE2b-256 of `message`.
pub fn blake2b256(message: &[u8]) -> [u8; 32] {
    blake2b_simd::Params::new()
        .hash_length(32)
        .hash(message)
        .as_bytes()
        .try_into()
        .expect("hash_length(32) configures BLAKE2b output to exactly 32 bytes; qed")
}

#[cfg(test)]
mod tests {
    use super::*;

    /// Fixture metadata captured from paseo-next-v2 (raw `RuntimeMetadataPrefixed`).
    const FIXTURE: &[u8] = include_bytes!("../../../tests/fixtures/paseo-next-v2-metadata.scale");

    /// The known-answer chain state frozen alongside the fixture.
    fn fixture_state() -> ChainState {
        ChainState {
            spec_version: 1_000_000,
            transaction_version: 1,
            genesis_hash: [0xab; 32],
            nonce: 0,
            mortality: None,
        }
    }

    #[test]
    fn a_mortal_era_matches_substrates_encoding() {
        // Golden against a known-answer pair: `Era::Mortal(64, 61)` is the
        // familiar `d5 03` seen on Polkadot extrinsics. Getting the nibble
        // layout wrong yields a valid-looking era with the wrong lifetime, so a
        // transaction would expire at a time recovery does not expect.
        let anchor = EraAnchor::new(64 * 3 + 61, [0u8; 32], 64);

        assert_eq!(anchor.period, 64);
        assert_eq!(anchor.encode_era(), vec![0xd5, 0x03]);
    }

    #[test]
    fn the_coinage_period_encodes_and_bounds_the_transaction() {
        use crate::host_logic::coinage::params::EXTRINSIC_MORTALITY_BLOCKS;

        let anchor = EraAnchor::new(1_000, [0u8; 32], EXTRINSIC_MORTALITY_BLOCKS);

        assert_eq!(anchor.period, 256);
        // log2(256) - 1 = 7 in the low nibble; phase 1000 % 256 = 232 above it.
        assert_eq!(anchor.encode_era(), (7u16 | (232u16 << 4)).encode());
        assert_eq!(anchor.last_valid_block(), 1_256);
    }

    #[test]
    fn a_period_is_rounded_and_clamped_to_what_the_encoding_admits() {
        let hash = [0u8; 32];

        assert_eq!(EraAnchor::new(0, hash, 100).period, 128, "rounded up");
        assert_eq!(EraAnchor::new(0, hash, 1).period, 4, "clamped up");
        assert_eq!(
            EraAnchor::new(0, hash, 1 << 20).period,
            1 << 16,
            "clamped down"
        );
    }

    #[test]
    fn mortality_changes_both_the_extra_and_the_implicit() {
        let metadata = Metadata::decode(FIXTURE).unwrap();
        let immortal = fixture_state();
        let anchor = EraAnchor::new(1_000, [0x5c; 32], 256);
        let mortal = ChainState {
            mortality: Some(anchor),
            ..immortal
        };

        let find = |state: &ChainState| {
            metadata
                .extension_ids()
                .iter()
                .position(|id| *id == "CheckMortality")
                .map(|index| {
                    let all = metadata.encode_signed_extensions(state);
                    (
                        all[index].extra.clone(),
                        all[index].additional_signed.clone(),
                    )
                })
                .expect("the runtime carries CheckMortality")
        };

        let (immortal_extra, immortal_implicit) = find(&immortal);
        let (mortal_extra, mortal_implicit) = find(&mortal);

        assert_eq!(immortal_extra, vec![0x00]);
        assert_eq!(immortal_implicit, immortal.genesis_hash.to_vec());
        assert_eq!(mortal_extra, anchor.encode_era());
        assert_eq!(
            mortal_implicit,
            anchor.hash.to_vec(),
            "a mortal era is anchored to its own block, not to genesis"
        );
    }

    /// `Resources.set_statement_store_account(period=7, seq=0, target=0)`.
    fn fixture_call() -> Vec<u8> {
        let mut call = vec![0x3f, 0x0a];
        call.extend_from_slice(&7u32.to_le_bytes());
        call.extend_from_slice(&0u32.to_le_bytes());
        call.extend_from_slice(&[0u8; 32]);
        call
    }

    #[test]
    fn proof_message_matches_frozen_known_answer() {
        let metadata = Metadata::decode(FIXTURE).unwrap();
        let msg = build_proof_message(&metadata, &fixture_call(), &fixture_state()).unwrap();
        assert_eq!(
            hex::encode(msg),
            "1d2e6d8d8f421b0857097c6076115507432d66fea47ebe0c3be282a369f6743c",
        );
    }

    #[test]
    fn as_resources_tail_is_indices_10_through_20() {
        let metadata = Metadata::decode(FIXTURE).unwrap();
        let idx = metadata.as_resources_index().unwrap();
        // AsResources sits at index 9; the proof tail is everything after it.
        assert_eq!(idx, 9);
        let ids = metadata.extension_ids();
        assert_eq!(
            ids[idx + 1..].to_vec(),
            vec![
                "AuthorizeCall",
                "RestrictOrigins",
                "CheckNonZeroSender",
                "CheckSpecVersion",
                "CheckTxVersion",
                "CheckGenesis",
                "CheckMortality",
                "CheckNonce",
                "CheckWeight",
                "ChargeAssetTxPayment",
                "StorageWeightReclaim",
            ],
        );
    }

    #[test]
    fn call_and_variant_indices_resolve_by_name() {
        let metadata = Metadata::decode(FIXTURE).unwrap();

        assert_eq!(
            (
                metadata
                    .call_indices("Resources", "set_statement_store_account")
                    .unwrap(),
                metadata
                    .call_indices("Resources", "claim_long_term_storage")
                    .unwrap(),
                metadata
                    .as_resources_variant_indices("RegisterStatementStoreAllowance")
                    .unwrap(),
                metadata
                    .as_resources_variant_indices("ClaimLongTermStorage")
                    .unwrap(),
            ),
            ([0x3f, 0x0a], [0x3f, 0x0c], (0x02, 0x01), (0x03, 0x01)),
        );
    }

    #[test]
    fn index_resolution_fails_for_unknown_names() {
        let metadata = Metadata::decode(FIXTURE).unwrap();

        assert_eq!(
            (
                metadata.call_indices("Resources", "no_such_call").is_err(),
                metadata.call_indices("NoSuchPallet", "transfer").is_err(),
                metadata
                    .as_resources_variant_indices("NoSuchVariant")
                    .is_err(),
            ),
            (true, true, true),
        );
    }

    #[test]
    fn dropping_the_version_byte_changes_the_hash() {
        let metadata = Metadata::decode(FIXTURE).unwrap();
        let state = fixture_state();
        let call = fixture_call();
        let all = metadata.encode_signed_extensions(&state);
        let tail = &all[metadata.as_resources_index().unwrap() + 1..];
        let mut without = call.clone();
        for e in tail {
            without.extend_from_slice(&e.extra);
        }
        for e in tail {
            without.extend_from_slice(&e.additional_signed);
        }
        assert_ne!(
            build_proof_message(&metadata, &call, &state).unwrap(),
            blake2b256(&without),
        );
    }
}
