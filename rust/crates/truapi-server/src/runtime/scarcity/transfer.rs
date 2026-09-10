//! Moving one item between purse keys: build, sign, broadcast, verify.
//!
//! A holder transfer is a signed v4 transaction from the purse key carrying
//! `AsScarcity(Some(AsNft { instance, state_nonce }))`. The extension replaces
//! the signed origin before the account checks, so the purse needs no System
//! account and pays no fee; the nonce is therefore always zero. The era must
//! end before the pallet's failure lock does, so the transaction is mortal and
//! short. Inclusion is not success: the pallet restores the item on a failed
//! dispatch, so ownership is re-read at the included block.

use parity_scale_codec::Encode;
use serde_json::{Value, json};
use truapi::latest::{ScarcityTransferStatus, TxPayloadExtension};

use super::chain::{self, Nft, ScarcityChainError};
use super::store::WalEntry;
use super::{AssetHub, PocketError};
use crate::host_logic::extrinsic::{Sr25519Signer, build_signed_extrinsic_v4};
use crate::host_logic::pocket::derive_purse_keypair;
use crate::runtime::statement_allowance::StatementAllowanceError;
use crate::runtime::statement_allowance::extension::{
    AS_SCARCITY, ChainState, Era, Metadata, MetadataError,
};
use crate::runtime::statement_allowance::rpc::RpcClient;
use crate::runtime::statement_allowance::slot::read_chain_now_seconds;

/// Era length in blocks. Under the runtime's 60-second `LockPeriod` at
/// six-second blocks, so a failed transaction expires before the lock lifts
/// and every retry is a fresh signature.
pub(crate) const TRANSFER_ERA_BLOCKS: u64 = 8;

/// `Option::Some` discriminant of the `AsScarcity` extra.
const OPTION_SOME: u8 = 0x01;

/// Why a transfer did not move the item.
#[derive(Debug, derive_more::Display)]
pub(crate) enum TransferError {
    /// The purse does not hold the named instance.
    #[display("the purse does not hold instance {instance}")]
    NotHeld {
        /// Instance asked for.
        instance: u64,
    },
    /// The destination is the holding key itself.
    #[display("the destination is the holding key")]
    TransferToSelf,
    /// The destination already holds an item.
    #[display("the destination already holds an item")]
    AddressOccupied,
    /// The holding key is locked after a failed dispatch.
    #[display("the holding key is locked until {until}")]
    Locked {
        /// Unix seconds when the lock lifts.
        until: u64,
    },
    /// The item definition binds the instance to its key.
    #[display("the item is soulbound")]
    Soulbound,
    /// The item moved between the read and the signature.
    #[display("the item's state changed before the transaction was built")]
    StateMismatch,
    /// The chain refused or dropped the transaction.
    #[display("the transaction was rejected: {reason}")]
    Rejected {
        /// Node or pool reason.
        reason: String,
    },
    /// Engine failure.
    #[display("{_0}")]
    Pocket(PocketError),
}

impl From<PocketError> for TransferError {
    fn from(err: PocketError) -> Self {
        Self::Pocket(err)
    }
}
impl From<ScarcityChainError> for TransferError {
    fn from(err: ScarcityChainError) -> Self {
        Self::Pocket(err.into())
    }
}
impl From<StatementAllowanceError> for TransferError {
    fn from(err: StatementAllowanceError) -> Self {
        Self::Pocket(err.into())
    }
}

impl TransferError {
    /// The service's view of this failure.
    pub(crate) fn to_service_error(&self) -> truapi::latest::ScarcityError {
        use truapi::latest::ScarcityError;
        match self {
            Self::NotHeld { .. } => ScarcityError::NotFound,
            Self::TransferToSelf | Self::Rejected { .. } => ScarcityError::Unknown {
                reason: self.to_string(),
            },
            Self::AddressOccupied => ScarcityError::AddressOccupied,
            Self::Locked { until } => ScarcityError::Locked { until: *until },
            Self::Soulbound => ScarcityError::Soulbound,
            Self::StateMismatch => ScarcityError::StateMismatch,
            Self::Pocket(PocketError::ChainNotServed) => ScarcityError::ChainNotServed,
            Self::Pocket(other) => ScarcityError::Unknown {
                reason: other.to_string(),
            },
        }
    }
}

/// The best block's number and hash: the mortal era's anchor.
pub(crate) async fn best_block(rpc: &RpcClient) -> Result<(u32, [u8; 32]), TransferError> {
    let header = rpc.call("chain_getHeader", json!([])).await?;
    let number = header
        .get("number")
        .and_then(Value::as_str)
        .and_then(|hex| u32::from_str_radix(hex.trim_start_matches("0x"), 16).ok())
        .ok_or_else(|| PocketError::Unknown {
            reason: "chain_getHeader returned no block number".into(),
        })?;
    let hash = rpc.call("chain_getBlockHash", json!([number])).await?;
    let hash = hash
        .as_str()
        .and_then(|hex| hex::decode(hex.trim_start_matches("0x")).ok())
        .and_then(|bytes| <[u8; 32]>::try_from(bytes).ok())
        .ok_or_else(|| PocketError::Unknown {
            reason: "chain_getBlockHash returned no hash".into(),
        })?;
    Ok((number, hash))
}

/// The `AsScarcity` extra: `Some(AsNft { instance, state_nonce })`, the
/// variant index taken from metadata.
pub(crate) fn as_scarcity_extra(
    metadata: &Metadata,
    instance: u64,
    state_nonce: u64,
) -> Result<Vec<u8>, StatementAllowanceError> {
    let variant = metadata.extension_info_variant_index(AS_SCARCITY, "AsNft")?;
    let mut extra = Vec::with_capacity(2 + 8 + 8);
    extra.push(OPTION_SOME);
    extra.push(variant);
    instance.encode_to(&mut extra);
    state_nonce.encode_to(&mut extra);
    Ok(extra)
}

/// Build and sign the holder transfer of `instance` at `state_nonce` from the
/// purse key `signer` to `to`, mortal from `state.era`.
pub(crate) fn build_transfer_extrinsic(
    metadata: &Metadata,
    state: &ChainState,
    signer: &Sr25519Signer,
    instance: u64,
    state_nonce: u64,
    to: &[u8; 32],
) -> Result<Vec<u8>, StatementAllowanceError> {
    let mut call = metadata.call_indices(chain::PALLET, "transfer")?.to_vec();
    to.encode_to(&mut call);
    let authorizing =
        metadata
            .extension_index(AS_SCARCITY)
            .ok_or_else(|| MetadataError::MissingExtension {
                identifier: AS_SCARCITY.to_string(),
            })?;
    let extra = as_scarcity_extra(metadata, instance, state_nonce)?;
    let extensions: Vec<TxPayloadExtension> = metadata
        .encode_signed_extensions(state)
        .into_iter()
        .zip(metadata.extension_ids())
        .enumerate()
        .map(|(index, (encoded, id))| TxPayloadExtension {
            id: id.to_string(),
            extra: if index == authorizing {
                extra.clone()
            } else {
                encoded.extra
            },
            additional_signed: encoded.additional_signed,
        })
        .collect();
    Ok(build_signed_extrinsic_v4(signer, &call, &extensions))
}

/// What the chain says about a logged transfer at a finalized block.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub(crate) enum Resolution {
    /// The destination holds the instance: the transfer landed.
    Landed,
    /// The source still holds it and the era has passed: it will never land.
    Expired,
    /// The source still holds it and the era is open: keep waiting.
    Pending,
    /// Neither key holds it: a force move or burn intervened; nothing to
    /// recover.
    Gone,
}

/// Decide a logged transfer from the instance's owner at a finalized block.
pub(crate) fn resolve(
    entry: &WalEntry,
    source: &[u8; 32],
    owner_now: Option<&[u8; 32]>,
    finalized_number: u32,
) -> Resolution {
    match owner_now {
        Some(owner) if owner == &entry.to => Resolution::Landed,
        Some(owner) if owner == source => {
            if finalized_number >= entry.birth_block.saturating_add(entry.period) {
                Resolution::Expired
            } else {
                Resolution::Pending
            }
        }
        _ => Resolution::Gone,
    }
}

/// What to move where.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub(crate) struct TransferSpec<'a> {
    /// Purse the item leaves.
    pub from_product_id: &'a str,
    /// Instance to move.
    pub instance: u64,
    /// Destination purse key.
    pub to: [u8; 32],
}

/// The transfer, from validation to verified ownership. `progress` receives
/// `Started` after the signed transaction is broadcast and `InBlock` when it
/// lands; the terminal `Landed` or `Failed` is the return value's job.
pub(crate) async fn execute(
    pocket: &super::ScarcityPocket,
    hub: &AssetHub,
    entropy: &[u8],
    root_public_key: [u8; 32],
    spec: TransferSpec<'_>,
    progress: &(dyn Fn(ScarcityTransferStatus) + Send + Sync),
) -> Result<[u8; 32], TransferError> {
    let TransferSpec {
        from_product_id,
        instance,
        to,
    } = spec;
    let metadata = &hub.context.metadata;
    let held = pocket
        .scan_purse_with(hub, entropy, root_public_key, from_product_id)
        .await?;
    let item = held
        .into_iter()
        .find(|item| item.nft.instance == instance)
        .ok_or(TransferError::NotHeld { instance })?;
    if item.address == to {
        return Err(TransferError::TransferToSelf);
    }
    validate_destination_and_lock(&hub.rpc, metadata, &item.address, &to).await?;
    match chain::read_transferability(&hub.rpc, metadata, item.nft.collection, item.nft.item)
        .await?
    {
        Some(chain::Transferability::Transferable) => {}
        _ => return Err(TransferError::Soulbound),
    }
    // The signature binds the state the pool will check, so read it last.
    let fresh: Nft = chain::read_nft(&hub.rpc, metadata, &item.address, None)
        .await?
        .ok_or(TransferError::StateMismatch)?;
    if fresh.instance != instance {
        return Err(TransferError::StateMismatch);
    }
    let (number, hash) = best_block(&hub.rpc).await?;
    let state = ChainState {
        era: Era::mortal(TRANSFER_ERA_BLOCKS, u64::from(number), hash),
        nonce: 0,
        ..hub.context.state
    };
    let keypair =
        derive_purse_keypair(entropy, from_product_id, item.index).map_err(PocketError::from)?;
    let signer = Sr25519Signer::from_keypair(&keypair);
    let extrinsic =
        build_transfer_extrinsic(metadata, &state, &signer, instance, fresh.state_nonce, &to)?;

    let wal_id = pocket
        .store()
        .wal_append(
            root_public_key,
            WalEntry {
                id: 0,
                from_product_id: from_product_id.to_string(),
                from_index: item.index,
                instance,
                to,
                state_nonce: fresh.state_nonce,
                birth_block: number,
                period: TRANSFER_ERA_BLOCKS as u32,
            },
        )
        .await
        .map_err(PocketError::from)?;

    progress(ScarcityTransferStatus::Started);
    let block = match hub.rpc.submit_and_watch(&extrinsic).await {
        Ok(block) => block,
        Err(err) => {
            // Never included, so nothing to recover.
            let _ = pocket.store().wal_remove(root_public_key, wal_id).await;
            return Err(TransferError::Rejected {
                reason: err.to_string(),
            });
        }
    };
    let block_hash = hex::decode(block.trim_start_matches("0x"))
        .ok()
        .and_then(|bytes| <[u8; 32]>::try_from(bytes).ok())
        .unwrap_or([0; 32]);
    progress(ScarcityTransferStatus::InBlock { block: block_hash });

    let owner = chain::read_instance_owner(&hub.rpc, metadata, instance, Some(&block)).await?;
    let _ = pocket.store().wal_remove(root_public_key, wal_id).await;
    match owner {
        Some(owner) if owner == to => {
            let _ = pocket
                .store()
                .observe_occupied(root_public_key, from_product_id, &[])
                .await;
            Ok(block_hash)
        }
        Some(owner) if owner == item.address => {
            let until = chain::read_lock(&hub.rpc, metadata, &item.address)
                .await?
                .map_or(0, |lock| lock.until);
            Err(TransferError::Locked { until })
        }
        other => Err(TransferError::Rejected {
            reason: format!(
                "included in {block} but the instance is now held by {:?}",
                other.map(hex::encode)
            ),
        }),
    }
}

async fn validate_destination_and_lock(
    rpc: &RpcClient,
    metadata: &Metadata,
    source: &[u8; 32],
    to: &[u8; 32],
) -> Result<(), TransferError> {
    if chain::read_nft(rpc, metadata, to, None).await?.is_some() {
        return Err(TransferError::AddressOccupied);
    }
    if let Some(lock) = chain::read_lock(rpc, metadata, source).await? {
        let now = read_chain_now_seconds(rpc).await?;
        if lock.until > now {
            return Err(TransferError::Locked { until: lock.until });
        }
    }
    Ok(())
}

/// Resolve every logged transfer against the finalized head and drop the ones
/// the chain has settled. Runs before a purse scan so a restart never reports
/// an item both moved and held.
pub(crate) async fn recover(
    pocket: &super::ScarcityPocket,
    hub: &AssetHub,
    entropy: &[u8],
    root_public_key: [u8; 32],
) -> Result<(), TransferError> {
    let entries = pocket
        .store()
        .wal_entries(root_public_key)
        .await
        .map_err(PocketError::from)?;
    if entries.is_empty() {
        return Ok(());
    }
    let finalized = hub.rpc.finalized_head().await?;
    let finalized_number = block_number_of(&hub.rpc, &finalized).await?;
    for entry in entries {
        let source = derive_purse_keypair(entropy, &entry.from_product_id, entry.from_index)
            .map_err(PocketError::from)?
            .public
            .to_bytes();
        let owner = chain::read_instance_owner(
            &hub.rpc,
            &hub.context.metadata,
            entry.instance,
            Some(&finalized),
        )
        .await?;
        match resolve(&entry, &source, owner.as_ref(), finalized_number) {
            Resolution::Pending => {}
            Resolution::Landed | Resolution::Expired | Resolution::Gone => {
                pocket
                    .store()
                    .wal_remove(root_public_key, entry.id)
                    .await
                    .map_err(PocketError::from)?;
            }
        }
    }
    Ok(())
}

async fn block_number_of(rpc: &RpcClient, hash: &str) -> Result<u32, TransferError> {
    let header = rpc.call("chain_getHeader", json!([hash])).await?;
    header
        .get("number")
        .and_then(Value::as_str)
        .and_then(|hex| u32::from_str_radix(hex.trim_start_matches("0x"), 16).ok())
        .ok_or_else(|| {
            PocketError::Unknown {
                reason: "chain_getHeader returned no block number".into(),
            }
            .into()
        })
}

#[cfg(test)]
mod tests {
    use parity_scale_codec::{Compact, Decode};

    use super::*;
    use crate::host_logic::pocket::derive_purse_keypair;
    use crate::runtime::statement_allowance::test_fixtures;

    const ENTROPY: [u8; 16] = [0xAB; 16];

    fn state(metadata: &Metadata) -> ChainState {
        let _ = metadata;
        ChainState {
            spec_version: 2_000_036,
            transaction_version: 1,
            genesis_hash: [0x11; 32],
            nonce: 0,
            restrict_origins: false,
            era: Era::mortal(TRANSFER_ERA_BLOCKS, 1000, [0x22; 32]),
        }
    }

    /// The signed v4 body carries the purse key as signer, the metadata-order
    /// extras with only `AsScarcity` replaced, and the call; the signature
    /// verifies over the v4 payload with the purse key.
    #[test]
    fn transfer_extrinsic_has_the_pallet_shape() {
        let metadata = test_fixtures::asset_hub();
        let state = state(metadata);
        let keypair = derive_purse_keypair(&ENTROPY, "cardclash.dot", 1).unwrap();
        let signer = Sr25519Signer::from_keypair(&keypair);
        let to = [0x33u8; 32];
        let extrinsic = build_transfer_extrinsic(metadata, &state, &signer, 34, 3, &to).unwrap();

        let mut input = extrinsic.as_slice();
        let len = Compact::<u32>::decode(&mut input).unwrap().0 as usize;
        assert_eq!(input.len(), len);
        assert_eq!(input[0], 0x84, "signed v4");
        assert_eq!(input[1], 0x00, "MultiAddress::Id");
        assert_eq!(&input[2..34], &keypair.public.to_bytes());
        assert_eq!(input[34], 0x01, "MultiSignature::Sr25519");
        let signature = &input[35..99];
        let rest = &input[99..];

        // Extras: metadata order, AsScarcity = Some(AsNft{34, 3}).
        let expected_extra = as_scarcity_extra(metadata, 34, 3).unwrap();
        let variant = metadata
            .extension_info_variant_index(AS_SCARCITY, "AsNft")
            .unwrap();
        assert_eq!(
            expected_extra,
            [vec![0x01, variant], 34u64.encode(), 3u64.encode()].concat()
        );
        let authorizing = metadata.extension_index(AS_SCARCITY).unwrap();
        let mut extras = Vec::new();
        let mut implicits = Vec::new();
        for (index, encoded) in metadata
            .encode_signed_extensions(&state)
            .into_iter()
            .enumerate()
        {
            if index == authorizing {
                extras.extend(&expected_extra);
            } else {
                extras.extend(&encoded.extra);
            }
            implicits.extend(&encoded.additional_signed);
        }
        let mut call = metadata
            .call_indices("Scarcity", "transfer")
            .unwrap()
            .to_vec();
        call.extend(to);
        assert_eq!(rest, [extras.clone(), call.clone()].concat());
        // The era anchors to the birth block, not genesis.
        assert!(implicits.windows(32).any(|w| w == [0x22; 32]));

        let mut payload = [call, extras, implicits].concat();
        if payload.len() > 256 {
            payload = sp_crypto_hashing::blake2_256(&payload).to_vec();
        }
        let signature = schnorrkel::Signature::from_bytes(signature).unwrap();
        keypair
            .public
            .verify_simple(b"substrate", &payload, &signature)
            .expect("the purse key signed the v4 payload");
    }

    #[test]
    fn logged_transfers_resolve_from_the_finalized_owner() {
        let entry = WalEntry {
            id: 0,
            from_product_id: "cardclash.dot".into(),
            from_index: 0,
            instance: 34,
            to: [2; 32],
            state_nonce: 0,
            birth_block: 100,
            period: 8,
        };
        let source = [1u8; 32];
        assert_eq!(
            resolve(&entry, &source, Some(&[2; 32]), 101),
            Resolution::Landed
        );
        assert_eq!(
            resolve(&entry, &source, Some(&source), 105),
            Resolution::Pending
        );
        assert_eq!(
            resolve(&entry, &source, Some(&source), 108),
            Resolution::Expired
        );
        assert_eq!(
            resolve(&entry, &source, Some(&[7; 32]), 101),
            Resolution::Gone
        );
        assert_eq!(resolve(&entry, &source, None, 101), Resolution::Gone);
    }
}
