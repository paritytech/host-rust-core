//! LitePeople ring parameters from the People chain (`Members` pallet).
//!
//! Reads the on-chain ring so the membership proof is built against the same
//! members the runtime verifies against: the baked-in `included` prefix of the
//! current ring. Mirrors signing-bot `ring-proof.ts`.

use parity_scale_codec::{Compact, Decode};
use scale_decode::DecodeAsType;
use sp_crypto_hashing::{blake2_128, twox_64, twox_128};
use thiserror::Error;

use super::StatementAllowanceError;
use super::extension::{Metadata, MetadataError};
use super::rpc::RpcClient;

/// Error while reading or decoding LitePeople ring storage.
#[derive(Debug, Error)]
pub enum RingError {
    /// Current ring index storage failed to decode.
    #[error("ring index: {0}")]
    RingIndex(#[source] parity_scale_codec::Error),
    /// LitePeople collection info was absent.
    #[error("Members.Collections[LitePeople] missing")]
    LitePeopleCollectionMissing,
    /// Metadata-aware storage decode failed.
    #[error("{context}: {source}")]
    DecodeAsType {
        /// Decode context.
        context: &'static str,
        /// Metadata-aware decode failure.
        #[source]
        source: scale_decode::Error,
    },
    /// Ring key page compact length failed to decode.
    #[error("ring keys len: {0}")]
    RingKeysLen(#[source] parity_scale_codec::Error),
    /// Ring key page did not contain all advertised members.
    #[error("ring keys page truncated")]
    RingKeysPageTruncated,
    /// Ring status did not contain the included field.
    #[error("ring status truncated before included field")]
    RingStatusTruncated,
    /// Ring status included field failed to decode.
    #[error("ring status: {0}")]
    RingStatus(#[source] parity_scale_codec::Error),
    /// Member has no `Members.Members` record for the collection.
    #[error("member has no Members.Members record for the collection")]
    MemberRecordMissing,
    /// Member is not included in a ring yet.
    #[error("member is not included in a ring (status: {status})")]
    MemberNotIncluded {
        /// Onboarding or suspended.
        status: &'static str,
    },
    /// Subscriber ring exponent was absent for the collection.
    #[error("MembersSubscriber.RingCollectionExponents missing for the collection")]
    SubscriberExponentMissing,
}

/// LitePeople collection identifier: ASCII, exactly 32 bytes.
pub const LITE_PEOPLE_IDENTIFIER: &[u8; 32] = b"pop:polkadot.network/people-lite";
/// Full-person People collection identifier. ASCII, space-padded to 32 bytes.
pub const PEOPLE_IDENTIFIER: &[u8; 32] = b"pop:polkadot.network/people     ";
/// Ring member public key length.
const MEMBER_LEN: usize = 32;

/// Fields read from `Members.Collections`.
#[derive(Debug, PartialEq, Eq, DecodeAsType)]
struct CollectionInfo {
    ring_size: RingExponent,
}

/// Supported LitePeople ring domain sizes.
#[derive(Debug, PartialEq, Eq, DecodeAsType)]
enum RingExponent {
    R2e9,
    R2e10,
    R2e14,
}

impl RingExponent {
    /// Return the exponent represented by the runtime enum variant.
    fn exponent(self) -> u8 {
        match self {
            Self::R2e9 => 9,
            Self::R2e10 => 10,
            Self::R2e14 => 14,
        }
    }
}

/// Fields read from `Members.Root`.
#[derive(Debug, PartialEq, Eq, DecodeAsType)]
struct RingRoot {
    revision: u32,
}

/// On-chain LitePeople ring parameters for building a verifying proof.
pub struct RingParams {
    /// Ring members, sliced to the baked-in `included` prefix.
    pub members: Vec<[u8; 32]>,
    /// Ring size exponent (9 / 10 / 14).
    pub exponent: u8,
    /// Ring index these members belong to.
    pub ring_index: u32,
    /// Finalized block hash the ring snapshot was read at.
    pub block_hash: String,
}

/// `Members.CurrentRingIndex[id]` storage key.
fn current_ring_index_key() -> Vec<u8> {
    [
        twox_128(b"Members").as_slice(),
        twox_128(b"CurrentRingIndex").as_slice(),
        LITE_PEOPLE_IDENTIFIER.as_slice(),
    ]
    .concat()
}

/// `Members.Collections[id]` storage key.
fn collections_key() -> Vec<u8> {
    [
        twox_128(b"Members").as_slice(),
        twox_128(b"Collections").as_slice(),
        LITE_PEOPLE_IDENTIFIER.as_slice(),
    ]
    .concat()
}

/// `Members.Root[(id, ring_index)]` storage key.
fn ring_root_key(ring_index: u32) -> Vec<u8> {
    [
        twox_128(b"Members").as_slice(),
        twox_128(b"Root").as_slice(),
        LITE_PEOPLE_IDENTIFIER.as_slice(),
        &blake2_128_concat(&ring_index.to_le_bytes()),
    ]
    .concat()
}

/// `Members.RingKeys[(identifier, ring_index, page)]` storage key.
fn collection_ring_keys_key(identifier: &[u8; 32], ring_index: u32, page: u32) -> Vec<u8> {
    [
        twox_128(b"Members").as_slice(),
        twox_128(b"RingKeys").as_slice(),
        identifier.as_slice(),
        &blake2_128_concat(&ring_index.to_le_bytes()),
        &twox_64_concat(&page.to_le_bytes()),
    ]
    .concat()
}

/// `Members.RingKeysStatus[(identifier, ring_index)]` storage key.
fn collection_ring_keys_status_key(identifier: &[u8; 32], ring_index: u32) -> Vec<u8> {
    [
        twox_128(b"Members").as_slice(),
        twox_128(b"RingKeysStatus").as_slice(),
        identifier.as_slice(),
        &blake2_128_concat(&ring_index.to_le_bytes()),
    ]
    .concat()
}

/// `Members.Members[(identifier, member)]` storage key.
/// The hashers are `Identity` then `Blake2_128Concat`.
fn member_record_key(identifier: &[u8; 32], member: &[u8; 32]) -> Vec<u8> {
    [
        twox_128(b"Members").as_slice(),
        twox_128(b"Members").as_slice(),
        identifier.as_slice(),
        &blake2_128_concat(member),
    ]
    .concat()
}

/// `MembersSubscriber.RingCollectionExponents[identifier]` storage key.
/// It lives on the subscriber chain, Asset Hub.
fn subscriber_exponent_key(identifier: &[u8; 32]) -> Vec<u8> {
    [
        twox_128(b"MembersSubscriber").as_slice(),
        twox_128(b"RingCollectionExponents").as_slice(),
        &blake2_128_concat(identifier),
    ]
    .concat()
}

/// `Blake2_128Concat(x)` = `blake2_128(x) ‖ x`.
pub(super) fn blake2_128_concat(x: &[u8]) -> Vec<u8> {
    [blake2_128(x).as_slice(), x].concat()
}

/// `Twox64Concat(x)` = `twox_64(x) ‖ x`.
fn twox_64_concat(x: &[u8]) -> Vec<u8> {
    [twox_64(x).as_slice(), x].concat()
}

/// Read the current LitePeople ring index at the current best block
/// (absent => 0).
pub async fn read_current_ring_index(rpc: &RpcClient) -> Result<u32, StatementAllowanceError> {
    decode_ring_index(rpc.get_storage(&current_ring_index_key()).await?)
}

/// Read the current LitePeople ring index pinned to block `at` (absent => 0).
pub async fn read_current_ring_index_at(
    rpc: &RpcClient,
    at: &str,
) -> Result<u32, StatementAllowanceError> {
    decode_ring_index(rpc.get_storage_at(&current_ring_index_key(), at).await?)
}

/// Decode a `CurrentRingIndex` storage value (absent => 0).
fn decode_ring_index(bytes: Option<Vec<u8>>) -> Result<u32, StatementAllowanceError> {
    match bytes {
        Some(bytes) => u32::decode(&mut &bytes[..]).map_err(|err| RingError::RingIndex(err).into()),
        None => Ok(0),
    }
}

/// Read the LitePeople ring size exponent from `Collections[LitePeople].ring_size`,
/// pinned to block `at`. This is a chain constant, so read it once and reuse
/// across ring indices.
pub async fn read_ring_exponent(
    rpc: &RpcClient,
    metadata: &Metadata,
    at: &str,
) -> Result<u8, StatementAllowanceError> {
    let collection = rpc
        .get_storage_at(&collections_key(), at)
        .await?
        .ok_or(RingError::LitePeopleCollectionMissing)?;
    let value_type = metadata
        .storage_value_type("Members", "Collections")
        .ok_or(MetadataError::MissingStorageType {
            pallet: "Members",
            entry: "Collections",
        })?;
    let mut input = collection.as_slice();
    CollectionInfo::decode_as_type(&mut input, value_type, metadata.registry())
        .map(|collection| collection.ring_size.exponent())
        .map_err(|err| {
            RingError::DecodeAsType {
                context: "Members.Collections",
                source: err,
            }
            .into()
        })
}

/// Reads the members of collection `identifier`'s `ring_index`, sliced to the
/// baked-in `included` prefix. Every read is pinned to block `at`, so pages and
/// status come from one consistent snapshot.
pub async fn read_collection_ring_members_at(
    rpc: &RpcClient,
    identifier: &[u8; 32],
    ring_index: u32,
    at: &str,
) -> Result<Vec<[u8; 32]>, StatementAllowanceError> {
    // 1. Page through RingKeys collecting raw 32-byte members.
    let mut members = Vec::new();
    for page in 0.. {
        let Some(bytes) = rpc
            .get_storage_at(&collection_ring_keys_key(identifier, ring_index, page), at)
            .await?
        else {
            break;
        };
        let mut cursor = &bytes[..];
        let Compact(len) = Compact::<u32>::decode(&mut cursor).map_err(RingError::RingKeysLen)?;
        if len == 0 {
            break;
        }
        for i in 0..len as usize {
            let start = i * MEMBER_LEN;
            let member: [u8; 32] = cursor
                .get(start..start + MEMBER_LEN)
                .ok_or(RingError::RingKeysPageTruncated)?
                .try_into()
                .expect("range end uses start + MEMBER_LEN where MEMBER_LEN is 32; qed");
            members.push(member);
        }
    }

    // 2. Slice to the baked-in `included` prefix (absent status => all included).
    if let Some(status) = rpc
        .get_storage_at(&collection_ring_keys_status_key(identifier, ring_index), at)
        .await?
    {
        // RingStatus = { total: u32 LE, included: u32 LE, .. }.
        let included_bytes = status.get(4..).ok_or(RingError::RingStatusTruncated)?;
        let included = u32::decode(&mut &included_bytes[..]).map_err(RingError::RingStatus)?;
        members.truncate(included as usize);
    }

    Ok(members)
}

/// Ring coordinates of one member. Projected from the runtime's `RingPosition`
/// enum.
#[derive(Debug, PartialEq, Eq, DecodeAsType)]
enum MemberRingPosition {
    /// Waiting in the onboarding queue.
    Onboarding {
        #[allow(dead_code)]
        queue_page: u32,
        #[allow(dead_code)]
        queued_at: u64,
    },
    /// Included in a built ring.
    Included {
        ring_index: u32,
        #[allow(dead_code)]
        ring_page: u32,
        #[allow(dead_code)]
        ring_position: u32,
    },
    /// Suspended from all rings.
    Suspended,
}

/// Reads the ring index `member` is included in for collection `identifier`,
/// from `Members.Members`, pinned to block `at`. Errors when the member has no
/// record. Errors too when the member is not `Included` yet.
pub async fn read_member_ring_index(
    rpc: &RpcClient,
    metadata: &Metadata,
    identifier: &[u8; 32],
    member: &[u8; 32],
    at: &str,
) -> Result<u32, StatementAllowanceError> {
    let value = rpc
        .get_storage_at(&member_record_key(identifier, member), at)
        .await?
        .ok_or(RingError::MemberRecordMissing)?;
    let value_type = metadata.storage_value_type("Members", "Members").ok_or(
        MetadataError::MissingStorageType {
            pallet: "Members",
            entry: "Members",
        },
    )?;
    let mut input = value.as_slice();
    let position = MemberRingPosition::decode_as_type(&mut input, value_type, metadata.registry())
        .map_err(|err| RingError::DecodeAsType {
            context: "Members.Members",
            source: err,
        })?;
    match position {
        MemberRingPosition::Included { ring_index, .. } => Ok(ring_index),
        MemberRingPosition::Onboarding { .. } => Err(RingError::MemberNotIncluded {
            status: "onboarding",
        }
        .into()),
        MemberRingPosition::Suspended => Err(RingError::MemberNotIncluded {
            status: "suspended",
        }
        .into()),
    }
}

/// Reads the ring exponent the subscriber chain, Asset Hub, verifies collection
/// `identifier` against. The source is
/// `MembersSubscriber.RingCollectionExponents` at the current best block.
pub async fn read_subscriber_ring_exponent(
    rpc: &RpcClient,
    metadata: &Metadata,
    identifier: &[u8; 32],
) -> Result<u8, StatementAllowanceError> {
    let value = rpc
        .get_storage(&subscriber_exponent_key(identifier))
        .await?
        .ok_or(RingError::SubscriberExponentMissing)?;
    let value_type = metadata
        .storage_value_type("MembersSubscriber", "RingCollectionExponents")
        .ok_or(MetadataError::MissingStorageType {
            pallet: "MembersSubscriber",
            entry: "RingCollectionExponents",
        })?;
    let mut input = value.as_slice();
    RingExponent::decode_as_type(&mut input, value_type, metadata.registry())
        .map(RingExponent::exponent)
        .map_err(|err| {
            RingError::DecodeAsType {
                context: "MembersSubscriber.RingCollectionExponents",
                source: err,
            }
            .into()
        })
}

/// Read `Members.Root[LitePeople][ring_index].revision` pinned to block `at`
/// (absent => 0).
pub async fn read_ring_revision(
    rpc: &RpcClient,
    metadata: &Metadata,
    ring_index: u32,
    at: &str,
) -> Result<u32, StatementAllowanceError> {
    match rpc.get_storage_at(&ring_root_key(ring_index), at).await? {
        Some(bytes) => {
            let value_type = metadata.storage_value_type("Members", "Root").ok_or(
                MetadataError::MissingStorageType {
                    pallet: "Members",
                    entry: "Root",
                },
            )?;
            let mut input = bytes.as_slice();
            RingRoot::decode_as_type(&mut input, value_type, metadata.registry())
                .map(|root| root.revision)
                .map_err(|err| {
                    RingError::DecodeAsType {
                        context: "ring revision",
                        source: err,
                    }
                    .into()
                })
        }
        None => Ok(0),
    }
}

#[cfg(test)]
mod tests {
    use parity_scale_codec::Encode;
    use scale_info::TypeInfo;
    use subxt_rpcs::RpcClient as HostRpcClient;

    use super::super::rpc::testing::ScriptedRpc;
    use super::*;

    fn decode_as<Source, Target>(source: Source) -> Target
    where
        Source: Encode + TypeInfo + 'static,
        Target: DecodeAsType,
    {
        let mut registry = scale_info::Registry::new();
        let type_id = registry
            .register_type(&scale_info::meta_type::<Source>())
            .id;
        let registry: scale_info::PortableRegistry = registry.into();
        let encoded = source.encode();
        Target::decode_as_type(&mut encoded.as_slice(), type_id, &registry).expect(
            "source metadata is registered and target projection matches by field name; qed",
        )
    }

    #[test]
    fn ring_metadata_projections_ignore_unneeded_runtime_fields() {
        #[derive(Encode, TypeInfo)]
        enum SourceRingExponent {
            R2e14,
            R2e9,
            R2e10,
        }

        #[derive(Encode, TypeInfo)]
        struct SourceCollectionInfo {
            owner: u8,
            mode: u8,
            ring_size: SourceRingExponent,
            self_inclusion_delay: Option<u64>,
        }

        #[derive(Encode, TypeInfo)]
        struct SourceRingRoot {
            root: [u8; 4],
            revision: u32,
            intermediate: [u8; 8],
        }

        let collection: CollectionInfo = decode_as(SourceCollectionInfo {
            owner: 7,
            mode: 3,
            ring_size: SourceRingExponent::R2e10,
            self_inclusion_delay: Some(42),
        });
        let root: RingRoot = decode_as(SourceRingRoot {
            root: [0xaa; 4],
            revision: 12,
            intermediate: [0xbb; 8],
        });

        assert_eq!(
            collection,
            CollectionInfo {
                ring_size: RingExponent::R2e10,
            }
        );
        assert_eq!(root, RingRoot { revision: 12 });

        // Keep every source variant in the metadata so index order differs
        // from the projection and variant-name decoding is exercised.
        let _ = SourceRingExponent::R2e14;
        let _ = SourceRingExponent::R2e9;
    }

    #[test]
    fn member_reads_are_pinned_and_truncated_to_included() {
        // Page 0 holds two members; RingStatus { total: 2, included: 1, None }.
        let page = format!(
            r#""0x08{}{}""#,
            hex::encode([0xaa; 32]),
            hex::encode([0xbb; 32]),
        );
        let status = r#""0x020000000100000000""#;
        let scripted = ScriptedRpc::new([page.as_str(), "null", status]);
        let rpc = RpcClient::new(HostRpcClient::new(scripted.clone()));

        let members = futures::executor::block_on(read_collection_ring_members_at(
            &rpc,
            LITE_PEOPLE_IDENTIFIER,
            3,
            "0xat",
        ))
        .unwrap();

        assert_eq!(members, vec![[0xaa; 32]]);
        let expected: Vec<(String, String)> = [
            collection_ring_keys_key(LITE_PEOPLE_IDENTIFIER, 3, 0),
            collection_ring_keys_key(LITE_PEOPLE_IDENTIFIER, 3, 1),
            collection_ring_keys_status_key(LITE_PEOPLE_IDENTIFIER, 3),
        ]
        .into_iter()
        .map(|key| {
            (
                "state_getStorage".to_string(),
                format!(r#"["0x{}","0xat"]"#, hex::encode(key)),
            )
        })
        .collect();
        assert_eq!(scripted.calls(), expected);
    }
}
