//! Moving one item between purse keys: build, sign, broadcast, verify.
//!
//! A holder transfer is a signed v4 transaction from the purse key carrying
//! `AsScarcity(Some(AsNft { instance, state_nonce }))`. The extension replaces
//! the signed origin before the account checks, so the purse needs no System
//! account and pays no fee; the nonce is therefore always zero. The era must
//! end before the pallet's failure lock does, so the transaction is mortal and
//! short, and the key source anchors it right before signing so a consent wait
//! never eats into it. The requesting host rebuilds the transaction from the
//! signer's anchor, checks the signature against the holding key, and only then
//! broadcasts. Inclusion is not success: the pallet restores the item on a
//! failed dispatch, so ownership is re-read at the included block.

use parity_scale_codec::Encode;
use schnorrkel::{PublicKey, Signature};
use serde_json::{Value, json};
use subxt::utils::{AccountId32, MultiSignature};
use truapi::latest::{ScarcityTransferStatus, TxPayloadExtension};

use super::chain::{self, Nft, ScarcityChainError};
use super::keys::{PurseKeys, PurseTransfer};
use super::store::WalEntry;
use super::{AssetHub, PocketError};
use crate::host_logic::extrinsic::{
    build_signed_extrinsic_v4_with_signature, v4_signer_digest, v4_signer_payload_unhashed,
};
use crate::host_logic::product_account::SR25519_SIGNING_CONTEXT;
use crate::runtime::authority::AuthoritySession;
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
    /// The key source's signature does not verify over the transaction the
    /// requesting host rebuilt from its anchor.
    #[display("the purse key's signature does not verify over the transfer")]
    SignatureMismatch,
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
    /// A one-line reason for hosts, prefixed with the service error's name so
    /// a wallet UI can branch on it without a second type.
    pub(crate) fn to_service_error_reason(&self) -> String {
        format!("{:?}: {self}", self.to_service_error())
    }

    /// The service's view of this failure.
    pub(crate) fn to_service_error(&self) -> truapi::latest::ScarcityError {
        use crate::runtime::authority::AuthorityError;
        use truapi::latest::ScarcityError;
        match self {
            Self::NotHeld { .. } => ScarcityError::NotFound,
            Self::TransferToSelf | Self::SignatureMismatch | Self::Rejected { .. } => {
                ScarcityError::Unknown {
                    reason: self.to_string(),
                }
            }
            Self::AddressOccupied => ScarcityError::AddressOccupied,
            Self::Locked { until } => ScarcityError::Locked { until: *until },
            Self::Soulbound => ScarcityError::Soulbound,
            Self::StateMismatch => ScarcityError::StateMismatch,
            Self::Pocket(PocketError::ChainNotServed) => ScarcityError::ChainNotServed,
            Self::Pocket(PocketError::Authority(AuthorityError::Rejected)) => {
                ScarcityError::Rejected
            }
            Self::Pocket(PocketError::Authority(AuthorityError::Disconnected)) => {
                ScarcityError::NotConnected
            }
            Self::Pocket(other) => ScarcityError::Unknown {
                reason: other.to_string(),
            },
        }
    }
}

/// The best block's number and hash: the mortal era's anchor.
pub(crate) async fn best_block(rpc: &RpcClient) -> Result<(u32, [u8; 32]), PocketError> {
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

/// The unsigned parts of a holder transfer: the call, the metadata-order
/// extensions with only `AsScarcity` replaced, and the unhashed V4 signer
/// payload over them. Both the requesting host and the key source build this
/// from the same anchor, so the signature made on one verifies on the other.
#[derive(Debug, Clone, PartialEq, Eq)]
pub(crate) struct TransferSigning {
    /// `Scarcity.transfer(to)` call bytes.
    pub call: Vec<u8>,
    /// Transaction extensions in metadata order.
    pub extensions: Vec<TxPayloadExtension>,
    /// [`v4_signer_payload_unhashed`] over `call` and `extensions`.
    pub payload: Vec<u8>,
}

/// Build the holder transfer of `instance` at `state_nonce` to `to`, mortal
/// from `state.era`, ready for a purse key to sign.
pub(crate) fn build_transfer_signing(
    metadata: &Metadata,
    state: &ChainState,
    instance: u64,
    state_nonce: u64,
    to: &[u8; 32],
) -> Result<TransferSigning, StatementAllowanceError> {
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
    let payload = v4_signer_payload_unhashed(&call, &extensions);
    Ok(TransferSigning {
        call,
        extensions,
        payload,
    })
}

/// Whether `signature` by the purse key `signer_public` covers `signing`.
pub(crate) fn verify_transfer_signature(
    signer_public: &[u8; 32],
    signature: &[u8; 64],
    signing: &TransferSigning,
) -> bool {
    let (Ok(public), Ok(signature)) = (
        PublicKey::from_bytes(signer_public),
        Signature::from_bytes(signature),
    ) else {
        return false;
    };
    public
        .verify_simple(
            SR25519_SIGNING_CONTEXT,
            &v4_signer_digest(signing.payload.clone()),
            &signature,
        )
        .is_ok()
}

/// The signed V4 body once the purse key `signer_public` has signed
/// `signing.payload`.
pub(crate) fn assemble_transfer_extrinsic(
    signer_public: [u8; 32],
    signature: [u8; 64],
    signing: &TransferSigning,
) -> Vec<u8> {
    build_signed_extrinsic_v4_with_signature(
        AccountId32(signer_public),
        &MultiSignature::Sr25519(signature),
        &signing.call,
        &signing.extensions,
    )
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
    owner_now: Option<&[u8; 32]>,
    finalized_number: u32,
) -> Resolution {
    match owner_now {
        Some(owner) if owner == &entry.to => Resolution::Landed,
        Some(owner) if owner == &entry.from_address => {
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
    keys: &dyn PurseKeys,
    session: &AuthoritySession,
    spec: TransferSpec<'_>,
    progress: &(dyn Fn(ScarcityTransferStatus) + Send + Sync),
) -> Result<[u8; 32], TransferError> {
    let TransferSpec {
        from_product_id,
        instance,
        to,
    } = spec;
    let metadata = &hub.context.metadata;
    let root = session.public_key;
    let held = pocket
        .scan_purse_with(hub, keys, session, from_product_id)
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

    // The key source anchors the era and signs; a refusal there leaves no
    // trace here.
    let signed = keys
        .sign_transfer(
            session,
            PurseTransfer {
                from_product_id: from_product_id.to_string(),
                from_index: item.index,
                instance,
                state_nonce: fresh.state_nonce,
                to,
            },
        )
        .await?;
    let state = ChainState {
        era: Era::mortal(
            TRANSFER_ERA_BLOCKS,
            u64::from(signed.era_block_number),
            signed.era_block_hash,
        ),
        nonce: 0,
        ..hub.context.state
    };
    let signing = build_transfer_signing(metadata, &state, instance, fresh.state_nonce, &to)?;
    if !verify_transfer_signature(&item.address, &signed.signature, &signing) {
        return Err(TransferError::SignatureMismatch);
    }
    let extrinsic = assemble_transfer_extrinsic(item.address, signed.signature, &signing);

    let wal_id = pocket
        .store()
        .wal_append(
            root,
            WalEntry {
                id: 0,
                from_product_id: from_product_id.to_string(),
                from_index: item.index,
                from_address: item.address,
                instance,
                to,
                state_nonce: fresh.state_nonce,
                birth_block: signed.era_block_number,
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
            let _ = pocket.store().wal_remove(root, wal_id).await;
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
    let _ = pocket.store().wal_remove(root, wal_id).await;
    match owner {
        Some(owner) if owner == to => {
            let _ = pocket
                .store()
                .observe_occupied(root, from_product_id, &[])
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
/// an item both moved and held. Needs no key source: every entry carries its
/// holding key.
pub(crate) async fn recover(
    pocket: &super::ScarcityPocket,
    hub: &AssetHub,
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
        let owner = chain::read_instance_owner(
            &hub.rpc,
            &hub.context.metadata,
            entry.instance,
            Some(&finalized),
        )
        .await?;
        match resolve(&entry, owner.as_ref(), finalized_number) {
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
    use subxt::tx::Signer;

    use super::*;
    use crate::host_logic::extrinsic::Sr25519Signer;
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

    fn sign(keypair: &schnorrkel::Keypair, signing: &TransferSigning) -> [u8; 64] {
        let MultiSignature::Sr25519(signature) =
            Sr25519Signer::from_keypair(keypair).sign(&v4_signer_digest(signing.payload.clone()))
        else {
            panic!("sr25519 signer");
        };
        signature
    }

    /// The signed v4 body carries the purse key as signer, the metadata-order
    /// extras with only `AsScarcity` replaced, and the call; the signature
    /// verifies over the v4 payload with the purse key.
    #[test]
    fn transfer_extrinsic_has_the_pallet_shape() {
        let metadata = test_fixtures::asset_hub();
        let state = state(metadata);
        let keypair = derive_purse_keypair(&ENTROPY, "cardclash.dot", 1).unwrap();
        let to = [0x33u8; 32];
        let signing = build_transfer_signing(metadata, &state, 34, 3, &to).unwrap();
        let signature = sign(&keypair, &signing);
        assert!(verify_transfer_signature(
            &keypair.public.to_bytes(),
            &signature,
            &signing
        ));
        let extrinsic = assemble_transfer_extrinsic(keypair.public.to_bytes(), signature, &signing);

        let mut input = extrinsic.as_slice();
        let len = Compact::<u32>::decode(&mut input).unwrap().0 as usize;
        assert_eq!(input.len(), len);
        assert_eq!(input[0], 0x84, "signed v4");
        assert_eq!(input[1], 0x00, "MultiAddress::Id");
        assert_eq!(&input[2..34], &keypair.public.to_bytes());
        assert_eq!(input[34], 0x01, "MultiSignature::Sr25519");
        assert_eq!(&input[35..99], &signature);
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

        let payload = [call, extras, implicits].concat();
        assert_eq!(signing.payload, payload);
        let signature = schnorrkel::Signature::from_bytes(&signature).unwrap();
        keypair
            .public
            .verify_simple(b"substrate", &v4_signer_digest(payload), &signature)
            .expect("the purse key signed the v4 payload");
    }

    /// A signature made over a different anchor, destination or state nonce
    /// does not verify against the rebuilt transaction, so a signer that lied
    /// about what it signed is caught before broadcast.
    #[test]
    fn a_signature_over_a_different_transfer_does_not_verify() {
        let metadata = test_fixtures::asset_hub();
        let state = state(metadata);
        let keypair = derive_purse_keypair(&ENTROPY, "cardclash.dot", 1).unwrap();
        let public = keypair.public.to_bytes();
        let to = [0x33u8; 32];
        let genuine = build_transfer_signing(metadata, &state, 34, 3, &to).unwrap();
        let signature = sign(&keypair, &genuine);

        let other_nonce = build_transfer_signing(metadata, &state, 34, 4, &to).unwrap();
        assert!(!verify_transfer_signature(
            &public,
            &signature,
            &other_nonce
        ));
        let other_to = build_transfer_signing(metadata, &state, 34, 3, &[0x44; 32]).unwrap();
        assert!(!verify_transfer_signature(&public, &signature, &other_to));
        let other_anchor = ChainState {
            era: Era::mortal(TRANSFER_ERA_BLOCKS, 1001, [0x22; 32]),
            ..state
        };
        let moved = build_transfer_signing(metadata, &other_anchor, 34, 3, &to).unwrap();
        assert!(!verify_transfer_signature(&public, &signature, &moved));
        let other_key = derive_purse_keypair(&ENTROPY, "cardclash.dot", 2).unwrap();
        assert!(!verify_transfer_signature(
            &other_key.public.to_bytes(),
            &signature,
            &genuine
        ));
    }

    #[test]
    fn logged_transfers_resolve_from_the_finalized_owner() {
        let source = [1u8; 32];
        let entry = WalEntry {
            id: 0,
            from_product_id: "cardclash.dot".into(),
            from_index: 0,
            from_address: source,
            instance: 34,
            to: [2; 32],
            state_nonce: 0,
            birth_block: 100,
            period: 8,
        };
        assert_eq!(resolve(&entry, Some(&[2; 32]), 101), Resolution::Landed);
        assert_eq!(resolve(&entry, Some(&source), 105), Resolution::Pending);
        assert_eq!(resolve(&entry, Some(&source), 108), Resolution::Expired);
        assert_eq!(resolve(&entry, Some(&[7; 32]), 101), Resolution::Gone);
        assert_eq!(resolve(&entry, None, 101), Resolution::Gone);
    }
}
