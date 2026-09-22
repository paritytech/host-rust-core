use super::ring_vrf::member_from_entropy;
use super::{SigningHost, product_authority_error};
use crate::host_logic::product_account::{
    derive_full_person_ring_vrf_entropy, derive_identity_keypair,
    derive_lite_person_ring_vrf_entropy, derive_root_keypair_from_entropy,
};
use crate::host_logic::session::SessionInfo;
use crate::host_logic::sso::pairing::derive_identity_chat_private_key;
use crate::runtime::authority::AuthorityError;
use crate::runtime::connected_session_ui_info;

use zeroize::Zeroizing;

/// Establish a wallet-local session from host-held secret material.
///
/// A signing host owns the user's keys, so it establishes sessions directly
/// rather than through the SSO pairing flow. Only [`SigningHost`] implements
/// this; pairing hosts have no local secret to activate.
#[async_trait::async_trait]
pub(crate) trait LocalActivation: Send + Sync {
    /// Activate a local session from raw BIP-39 entropy, deriving the root
    /// public key and marking the session connected.
    async fn activate_local_session(&self, secret: Vec<u8>) -> Result<(), AuthorityError>;

    /// Activate a local session and attach known identity metadata from the
    /// host's signer/account store.
    async fn activate_local_session_with_identity(
        &self,
        secret: Vec<u8>,
        lite_username: Option<String>,
    ) -> Result<(), AuthorityError>;
}

#[async_trait::async_trait]
impl LocalActivation for SigningHost {
    async fn activate_local_session(&self, secret: Vec<u8>) -> Result<(), AuthorityError> {
        self.activate_local_session_with_identity(secret, None)
            .await
    }

    async fn activate_local_session_with_identity(
        &self,
        secret: Vec<u8>,
        lite_username: Option<String>,
    ) -> Result<(), AuthorityError> {
        let secret = Zeroizing::new(secret);
        let root = derive_root_keypair_from_entropy(&secret).map_err(product_authority_error)?;
        let public_key = root.public.to_bytes();
        let identity_account_id = derive_identity_keypair(&secret, self.network_suffix())
            .map_err(product_authority_error)?
            .public
            .to_bytes();
        let identity_chat_private_key = derive_identity_chat_private_key(&secret);
        let session = SessionInfo {
            public_key,
            sso: None,
            root_entropy_source: None,
            identity_account_id: Some(identity_account_id),
            identity_chat_private_key: Some(identity_chat_private_key),
            // A local session has no answering remote device to address.
            device_enc_public_key: None,
            lite_username,
            full_username: None,
        };
        let ui_info = connected_session_ui_info(&session);
        record_personhood_ring_keys(self, &secret, public_key).await;
        self.install_local_session(secret, session);
        self.auth_state.connected(&ui_info);
        Ok(())
    }
}

/// The two personhood ring collections, as the chain names them, in 32 ASCII
/// bytes padded with spaces.
const LITE_PEOPLE_COLLECTION: &[u8; 32] = b"pop:polkadot.network/people-lite";
const PEOPLE_COLLECTION: &[u8; 32] = b"pop:polkadot.network/people     ";

/// Records the ring-VRF keys of this person under the personhood product that
/// owns them, so a product can borrow one to prove personhood.
///
/// The registry holds only what was registered through this host, and a
/// product may register under itself alone, so nothing else can ever put
/// these entries there. `listRingVrfKeys("peopl.<tld>")` came back empty on a
/// wallet whose key is in the ring, and every proof-authorized call a product
/// made died on a handle it could not find. A wallet that has just unlocked
/// derives the key from the same entropy the ring member was minted from, so
/// it is the one place that can record it.
///
/// Recording is best effort on purpose. A session that cannot record these is
/// still usable for everything that does not prove personhood, and failing
/// activation over it would lock the user out of the host.
async fn record_personhood_ring_keys(host: &SigningHost, entropy: &[u8], session_key: [u8; 32]) {
    let suffix = host.network_suffix().to_string();
    let chain_id = host.services.people_chain_genesis_hash();
    let candidates = [
        (
            1u32,
            derive_lite_person_ring_vrf_entropy(entropy, &suffix),
            LITE_PEOPLE_COLLECTION,
        ),
        (
            0u32,
            derive_full_person_ring_vrf_entropy(entropy, &suffix),
            PEOPLE_COLLECTION,
        ),
    ];
    for (index, ring_entropy, collection) in candidates {
        let public_key = match member_from_entropy(&ring_entropy) {
            Ok(key) => key,
            Err(error) => {
                tracing::warn!(index, %error, "could not derive a personhood ring key");
                continue;
            }
        };
        let handle = truapi::v01::ProductAccountId {
            dot_ns_identifier: format!("peopl.{suffix}"),
            derivation_index: truapi::v01::DerivationIndex::Index(index),
        };
        // The collection alone addresses the ring. The host resolves the
        // Members pallet by name, and a pallet-instance junction here would
        // not match what a product asks for.
        let ring = truapi::v01::RingLocation {
            chain_id,
            junctions: vec![truapi::v01::RingLocationJunction::CollectionId(
                collection.to_vec(),
            )],
        };
        if let Err(error) = host
            .ring_vrf_registry
            .register(session_key, handle, ring, public_key)
            .await
        {
            tracing::warn!(index, %error, "could not record a personhood ring key");
        }
    }
}
