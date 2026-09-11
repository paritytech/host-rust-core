//! `pallet-scarcity` reads: storage keys from the chain's own metadata, values
//! decoded against its type registry.
//!
//! Hashers are never assumed. `NftsByOwner` and `Locked` are `Blake2_128Concat`
//! and `Instances` is `Twox64Concat` on every runtime seen so far, but the key
//! is built from whatever the connected chain declares, so a runtime that
//! changes a hasher changes nothing here.

use parity_scale_codec::{Decode, Encode};
use scale_decode::DecodeAsType;

use crate::runtime::statement_allowance::StatementAllowanceError;
use crate::runtime::statement_allowance::extension::Metadata;
use crate::runtime::statement_allowance::rpc::RpcClient;

/// The pallet's name in metadata.
pub(crate) const PALLET: &str = "Scarcity";

/// `Scarcity.NftsByOwner[purse]`: the one item a purse key holds.
#[derive(Debug, Clone, PartialEq, Eq, DecodeAsType)]
pub(crate) struct Nft {
    /// Globally unique instance id.
    pub instance: u64,
    /// Collection of the item definition.
    pub collection: u32,
    /// Item definition within the collection.
    pub item: u32,
    /// Unix seconds at mint.
    pub minted_at: u64,
    /// Unix seconds of the last move.
    pub last_moved: u64,
    /// Ownership-state revision; every move increments it.
    pub state_nonce: u64,
}

/// `Scarcity.Locked[purse]`: the backoff lock after a failed dispatch.
#[derive(Debug, Clone, Copy, PartialEq, Eq, DecodeAsType)]
pub(crate) struct LockInfo {
    /// Consecutive failed dispatches.
    pub retries: u8,
    /// Unix seconds when the lock lifts.
    pub until: u64,
}

/// Whether an item definition lets holders move its instances.
#[derive(Debug, Clone, Copy, PartialEq, Eq, DecodeAsType)]
pub(crate) enum Transferability {
    /// Holders may transfer.
    Transferable,
    /// Bound to the purse key it was minted into.
    Soulbound,
}

/// The fields of `Scarcity.ItemDefs` this layer reads.
#[derive(Debug, Clone, PartialEq, Eq, DecodeAsType)]
struct ItemDefinition {
    transferability: Transferability,
}

/// Failure reading the pallet.
#[derive(Debug, derive_more::Display)]
pub(crate) enum ScarcityChainError {
    /// The connected chain's metadata declares no such Scarcity storage entry.
    #[display("Scarcity.{entry} is not in the chain's metadata")]
    EntryMissing {
        /// Storage entry name.
        entry: &'static str,
    },
    /// A value did not decode against the chain's type registry.
    #[display("Scarcity.{entry}: {reason}")]
    Decode {
        /// Storage entry name.
        entry: &'static str,
        /// Decoder's reason.
        reason: String,
    },
    /// The RPC read failed.
    #[display("{_0}")]
    Rpc(StatementAllowanceError),
}

impl From<StatementAllowanceError> for ScarcityChainError {
    fn from(err: StatementAllowanceError) -> Self {
        Self::Rpc(err)
    }
}

fn storage_key(
    metadata: &Metadata,
    entry: &'static str,
    keys: &[&[u8]],
) -> Result<Vec<u8>, ScarcityChainError> {
    metadata
        .storage_key(PALLET, entry, keys)
        .ok_or(ScarcityChainError::EntryMissing { entry })
}

fn decode_value<T: DecodeAsType>(
    metadata: &Metadata,
    entry: &'static str,
    bytes: &[u8],
) -> Result<T, ScarcityChainError> {
    let value_type = metadata
        .storage_value_type(PALLET, entry)
        .ok_or(ScarcityChainError::EntryMissing { entry })?;
    let mut input = bytes;
    T::decode_as_type(&mut input, value_type, metadata.registry()).map_err(|err| {
        ScarcityChainError::Decode {
            entry,
            reason: err.to_string(),
        }
    })
}

/// The storage key of `NftsByOwner[owner]`.
pub(crate) fn nfts_by_owner_key(
    metadata: &Metadata,
    owner: &[u8; 32],
) -> Result<Vec<u8>, ScarcityChainError> {
    storage_key(metadata, "NftsByOwner", &[owner])
}

/// The item each purse key in `owners` holds, in order, `None` for an empty
/// key. One `state_queryStorageAt` round trip for the whole set.
pub(crate) async fn read_nfts(
    rpc: &RpcClient,
    metadata: &Metadata,
    owners: &[[u8; 32]],
) -> Result<Vec<Option<Nft>>, ScarcityChainError> {
    let keys = owners
        .iter()
        .map(|owner| nfts_by_owner_key(metadata, owner))
        .collect::<Result<Vec<_>, _>>()?;
    rpc.get_storage_many(&keys)
        .await?
        .into_iter()
        .map(|value| {
            value
                .map(|bytes| decode_value::<Nft>(metadata, "NftsByOwner", &bytes))
                .transpose()
        })
        .collect()
}

/// The item `owner` holds at block `at` (or the best block), if any.
pub(crate) async fn read_nft(
    rpc: &RpcClient,
    metadata: &Metadata,
    owner: &[u8; 32],
    at: Option<&str>,
) -> Result<Option<Nft>, ScarcityChainError> {
    let key = nfts_by_owner_key(metadata, owner)?;
    let value = match at {
        Some(at) => rpc.get_storage_at(&key, at).await?,
        None => rpc.get_storage(&key).await?,
    };
    value
        .map(|bytes| decode_value::<Nft>(metadata, "NftsByOwner", &bytes))
        .transpose()
}

/// The purse key holding `instance` at block `at` (or the best block), if the
/// instance exists.
pub(crate) async fn read_instance_owner(
    rpc: &RpcClient,
    metadata: &Metadata,
    instance: u64,
    at: Option<&str>,
) -> Result<Option<[u8; 32]>, ScarcityChainError> {
    let key = storage_key(metadata, "Instances", &[&instance.encode()])?;
    let value = match at {
        Some(at) => rpc.get_storage_at(&key, at).await?,
        None => rpc.get_storage(&key).await?,
    };
    value
        .map(|bytes| {
            // `AccountId32` is 32 raw bytes on the wire.
            <[u8; 32]>::decode(&mut bytes.as_slice()).map_err(|err| ScarcityChainError::Decode {
                entry: "Instances",
                reason: err.to_string(),
            })
        })
        .transpose()
}

/// The failure lock on `owner`, if one is recorded.
pub(crate) async fn read_lock(
    rpc: &RpcClient,
    metadata: &Metadata,
    owner: &[u8; 32],
) -> Result<Option<LockInfo>, ScarcityChainError> {
    let key = storage_key(metadata, "Locked", &[owner])?;
    rpc.get_storage(&key)
        .await?
        .map(|bytes| decode_value::<LockInfo>(metadata, "Locked", &bytes))
        .transpose()
}

/// Whether holders may move instances of `(collection, item)`. `None` when the
/// item definition no longer exists.
pub(crate) async fn read_transferability(
    rpc: &RpcClient,
    metadata: &Metadata,
    collection: u32,
    item: u32,
) -> Result<Option<Transferability>, ScarcityChainError> {
    let key = item_defs_key(metadata, collection, item)?;
    rpc.get_storage(&key)
        .await?
        .map(|bytes| {
            decode_value::<ItemDefinition>(metadata, "ItemDefs", &bytes)
                .map(|definition| definition.transferability)
        })
        .transpose()
}

/// `ItemDefs` is keyed by `(collection, item)`; the chain may declare it as a
/// double map or as a single tuple-keyed map, so ask for both shapes.
fn item_defs_key(
    metadata: &Metadata,
    collection: u32,
    item: u32,
) -> Result<Vec<u8>, ScarcityChainError> {
    let (collection, item) = (collection.encode(), item.encode());
    metadata
        .storage_key(PALLET, "ItemDefs", &[&collection, &item])
        .or_else(|| {
            let tuple = [collection.as_slice(), item.as_slice()].concat();
            metadata.storage_key(PALLET, "ItemDefs", &[&tuple])
        })
        .ok_or(ScarcityChainError::EntryMissing { entry: "ItemDefs" })
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::runtime::statement_allowance::test_fixtures;

    /// A hand-encoded `Nft` decodes against the fixture's `NftsByOwner` value
    /// type, proving the field order and widths this layer assumes.
    #[test]
    fn nft_decodes_against_asset_hub_metadata() {
        let metadata = test_fixtures::asset_hub();
        let mut bytes = Vec::new();
        bytes.extend(34u64.encode());
        bytes.extend(7u32.encode());
        bytes.extend(2u32.encode());
        bytes.extend(1_700_000_000u64.encode());
        bytes.extend(1_700_000_600u64.encode());
        bytes.extend(3u64.encode());
        let nft: Nft = decode_value(metadata, "NftsByOwner", &bytes).unwrap();
        assert_eq!(
            nft,
            Nft {
                instance: 34,
                collection: 7,
                item: 2,
                minted_at: 1_700_000_000,
                last_moved: 1_700_000_600,
                state_nonce: 3,
            }
        );
        let lock: LockInfo =
            decode_value(metadata, "Locked", &[2u8, 0, 0, 0, 0, 0, 0, 0, 60]).unwrap();
        assert_eq!(
            lock,
            LockInfo {
                retries: 2,
                until: 60 << 56
            }
        );
    }

    #[test]
    fn every_entry_this_layer_reads_exists_in_asset_hub_metadata() {
        let metadata = test_fixtures::asset_hub();
        assert!(nfts_by_owner_key(metadata, &[1; 32]).is_ok());
        assert!(storage_key(metadata, "Instances", &[&1u64.encode()]).is_ok());
        assert!(storage_key(metadata, "Locked", &[&[1u8; 32]]).is_ok());
        assert!(item_defs_key(metadata, 1, 2).is_ok());
        assert!(matches!(
            storage_key(metadata, "NoSuchEntry", &[]),
            Err(ScarcityChainError::EntryMissing { .. })
        ));
    }
}
