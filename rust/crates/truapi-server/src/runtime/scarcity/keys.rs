//! Where purse keys come from.
//!
//! The pocket engine never touches a secret. It asks a [`PurseKeys`] source
//! for public keys, for the next receive key in a purse, and for one signature
//! per move; the source is either the signing host deriving from root entropy
//! it holds in memory, or a pairing host relaying to the paired signing host.
//! Only a source ever allocates an index, so two hosts sharing one wallet can
//! never hand out the same receive key.

use core::fmt;

use async_trait::async_trait;
use zeroize::Zeroizing;

use super::{PocketError, ScarcityPocket, transfer};
use crate::host_logic::extrinsic::{Sr25519Signer, v4_signer_digest};
use crate::host_logic::pocket::{
    derive_purse_keypair, derive_purse_public_key, normalize_purse_product_id,
};
use crate::runtime::authority::AuthoritySession;
use crate::runtime::statement_allowance::extension::{ChainState, Era};
use subxt::tx::Signer;
use subxt::utils::MultiSignature;

/// Most keys one [`PurseKeys::public_keys`] call may ask for; a signing host
/// refuses more, bounding the derivation work one request can demand.
pub(crate) const PURSE_KEYS_MAX_COUNT: u32 = 100;

/// One holder transfer for a purse key to sign, described by what it does
/// rather than by bytes: the signer rebuilds the transaction itself, so it
/// can show and check exactly what it is authorizing.
#[derive(Clone, PartialEq, Eq)]
pub(crate) struct PurseTransfer {
    /// Purse the item is leaving.
    pub from_product_id: String,
    /// Index of the holding key within that purse.
    pub from_index: u32,
    /// Instance being moved, as the requester read it.
    pub instance: u64,
    /// Ownership-state revision the authorization names, as the requester
    /// read it; the signer refuses if the chain says otherwise.
    pub state_nonce: u64,
    /// Destination purse key.
    pub to: [u8; 32],
}

impl fmt::Debug for PurseTransfer {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.debug_struct("PurseTransfer")
            .field("from_product_id", &self.from_product_id)
            .field("from_index", &self.from_index)
            .field("instance", &self.instance)
            .field("state_nonce", &self.state_nonce)
            .field("to", &hex::encode(self.to))
            .finish()
    }
}

/// A purse key's signature over a transfer, with the mortal-era anchor the
/// signer chose right before signing so the era starts after any consent wait.
#[derive(Clone, PartialEq, Eq)]
pub(crate) struct SignedTransfer {
    /// Block number the era is anchored to.
    pub era_block_number: u32,
    /// Hash of that block.
    pub era_block_hash: [u8; 32],
    /// sr25519 signature over the V4 signer digest.
    pub signature: [u8; 64],
}

impl fmt::Debug for SignedTransfer {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.debug_struct("SignedTransfer")
            .field("era_block_number", &self.era_block_number)
            .field("era_block_hash", &hex::encode(self.era_block_hash))
            .field("signature", &hex::encode(self.signature))
            .finish()
    }
}

/// The source of purse keys for one wallet root.
#[async_trait]
pub(crate) trait PurseKeys: Sync {
    /// The public keys at `start..start + count` in `product_id`'s purse.
    async fn public_keys(
        &self,
        session: &AuthoritySession,
        product_id: &str,
        start: u32,
        count: u32,
    ) -> Result<Vec<[u8; 32]>, PocketError>;

    /// The next never-used key in `target_product_id`'s purse for
    /// `requested_by`, or the same key again for a repeated `idempotency_key`,
    /// as `(index, public key)`.
    async fn allocate_receive_key(
        &self,
        session: &AuthoritySession,
        target_product_id: &str,
        requested_by: &str,
        idempotency_key: &str,
    ) -> Result<(u32, [u8; 32]), PocketError>;

    /// Anchor a mortal era at the signer's best block and sign `request` with
    /// the holding purse key.
    async fn sign_transfer(
        &self,
        session: &AuthoritySession,
        request: PurseTransfer,
    ) -> Result<SignedTransfer, PocketError>;
}

/// Purse keys derived from root entropy held in memory: the signing host's
/// source, and the only code that turns entropy into purse keys.
pub(crate) struct LocalPurseKeys<'a> {
    pocket: &'a ScarcityPocket,
    entropy: Zeroizing<Vec<u8>>,
}

impl<'a> LocalPurseKeys<'a> {
    /// A source over `pocket`'s store deriving from `entropy`.
    pub(crate) fn new(pocket: &'a ScarcityPocket, entropy: Zeroizing<Vec<u8>>) -> Self {
        Self { pocket, entropy }
    }
}

#[async_trait]
impl PurseKeys for LocalPurseKeys<'_> {
    async fn public_keys(
        &self,
        _session: &AuthoritySession,
        product_id: &str,
        start: u32,
        count: u32,
    ) -> Result<Vec<[u8; 32]>, PocketError> {
        let end = start.saturating_add(count);
        (start..end)
            .map(|index| Ok(derive_purse_public_key(&self.entropy, product_id, index)?))
            .collect()
    }

    /// The first allocation in a purse the store has never seen scans it
    /// first, so a wallet restored from seed resumes above its occupied keys
    /// instead of handing one out again.
    async fn allocate_receive_key(
        &self,
        session: &AuthoritySession,
        target_product_id: &str,
        requested_by: &str,
        idempotency_key: &str,
    ) -> Result<(u32, [u8; 32]), PocketError> {
        let target = normalize_purse_product_id(target_product_id)?;
        let root = session.public_key;
        if self.pocket.store.purse(root, &target).await?.is_none() {
            self.pocket.scan_purse(self, session, &target).await?;
        }
        let index = self
            .pocket
            .store
            .allocate(root, &target, requested_by, idempotency_key)
            .await?;
        Ok((
            index,
            derive_purse_public_key(&self.entropy, &target, index)?,
        ))
    }

    async fn sign_transfer(
        &self,
        _session: &AuthoritySession,
        request: PurseTransfer,
    ) -> Result<SignedTransfer, PocketError> {
        let hub = self.pocket.asset_hub().await?;
        let (era_block_number, era_block_hash) = transfer::best_block(&hub.rpc).await?;
        let state = ChainState {
            era: Era::mortal(
                transfer::TRANSFER_ERA_BLOCKS,
                u64::from(era_block_number),
                era_block_hash,
            ),
            nonce: 0,
            ..hub.context.state
        };
        let signing = transfer::build_transfer_signing(
            &hub.context.metadata,
            &state,
            request.instance,
            request.state_nonce,
            &request.to,
        )?;
        let keypair =
            derive_purse_keypair(&self.entropy, &request.from_product_id, request.from_index)?;
        let MultiSignature::Sr25519(signature) =
            Sr25519Signer::from_keypair(&keypair).sign(&v4_signer_digest(signing.payload))
        else {
            return Err(PocketError::Unknown {
                reason: "the purse key produced a non-sr25519 signature".into(),
            });
        };
        Ok(SignedTransfer {
            era_block_number,
            era_block_hash,
            signature,
        })
    }
}
