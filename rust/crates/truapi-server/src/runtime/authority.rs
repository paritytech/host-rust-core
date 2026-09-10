//! Role-neutral account authority contracts used by product runtimes.
//!
//! Pairing and signing hosts implement these traits differently, but
//! `ProductRuntimeHost` can use this module's shared request/session types
//! without knowing where the key material lives.
//! Alias, proof, and ring-VRF operations reuse the request payloads in
//! `host_logic::sso::messages` for both local calls and SSO transport.

use async_trait::async_trait;
use std::sync::Arc;
use truapi::latest::{
    AccountId, HostAccountCreateProofRequest, HostAccountCreateProofResponse,
    HostAccountGetAliasRequest, HostAccountGetAliasResponse, HostAccountListRingVrfKeysRequest,
    HostAccountListRingVrfKeysResponse, HostAccountRegisterRingVrfKeyRequest,
    HostAccountRegisterRingVrfKeyResponse, HostAccountRingVrfSignRequest,
    HostAccountRingVrfSignResponse, HostAccountSignVrfError, HostAccountSignVrfRequest,
    HostCreateTransactionResponse, HostRequestResourceAllocationRequest,
    HostRequestResourceAllocationResponse, HostSignPayloadRequest, HostSignPayloadResponse,
    HostSignPayloadWithLegacyAccountRequest, HostSignRawRequest,
    HostSignRawWithLegacyAccountRequest, LegacyAccountTxPayload, ProductAccountId,
    ProductAccountTxPayload, VrfSignature,
};
use truapi::v01::{
    DerivationIndex, HostProductDeviceChatCipherSuite, HostProductDeviceChatResponse,
};
use truapi::versioned::account::{HostRequestLoginError, HostRequestLoginResponse};
use truapi::{CallContext, CallError, CancellationReason};
use truapi_platform::ProductContext;

use crate::host_logic::session::{SessionInfo, SessionState};
use crate::host_logic::sso::messages::{ProductRequest, RingVrfError};
use crate::host_logic::statement_store::statement_public_key_from_secret;

/// Secret key allocated for Bulletin preimage submission.
///
/// The core is the sole holder: the secret never crosses the host boundary.
/// Zeroized on drop, and its `Debug` redacts the material.
#[derive(Clone, zeroize::Zeroize, zeroize::ZeroizeOnDrop, derive_more::Debug)]
pub(crate) struct BulletinAllowanceKey {
    #[debug("\"<redacted>\"")]
    secret: [u8; 64],
}

impl BulletinAllowanceKey {
    /// Wrap a 64-byte sr25519 secret; other lengths are `Unavailable`.
    pub(crate) fn from_secret_bytes(secret: Vec<u8>) -> Result<Self, AuthorityError> {
        let secret: [u8; 64] =
            secret
                .try_into()
                .map_err(|secret: Vec<u8>| AuthorityError::Unavailable {
                    reason: format!(
                        "bulletin allowance key must be 64 bytes, got {}",
                        secret.len()
                    ),
                })?;
        Ok(Self { secret })
    }

    /// Raw secret for the in-core Bulletin signer.
    pub(crate) fn as_secret_bytes(&self) -> &[u8; 64] {
        &self.secret
    }
}

/// Persisted AutoSigning capability for one hard product subtree.
#[derive(Clone, zeroize::Zeroize, zeroize::ZeroizeOnDrop, derive_more::Debug)]
pub(crate) struct AutoSigningKey {
    #[debug("\"<redacted>\"")]
    secret: [u8; 64],
    #[debug("\"<redacted>\"")]
    ring_vrf_domain_entropy: [u8; 32],
}

impl AutoSigningKey {
    pub(crate) fn from_parts(secret: [u8; 64], ring_vrf_domain_entropy: [u8; 32]) -> Self {
        Self {
            secret,
            ring_vrf_domain_entropy,
        }
    }

    pub(crate) fn as_secret_bytes(&self) -> &[u8; 64] {
        &self.secret
    }

    pub(crate) fn ring_vrf_domain_entropy(&self) -> &[u8; 32] {
        &self.ring_vrf_domain_entropy
    }
}
/// Snapshot of an account-authority session selected by the authority.
///
/// This is the neutral session projection product runtimes can use while
/// preserving authority-private material inside the concrete authority
/// implementation.
#[derive(Clone, Debug, PartialEq, Eq)]
pub(crate) struct AuthoritySession {
    /// Root account public key for the active authority session.
    pub public_key: [u8; 32],
    /// Identity account resolved from the signing host, when available.
    pub identity_account_id: Option<[u8; 32]>,
    /// Lightweight username resolved from the dotNS contracts on Asset Hub, when available.
    pub lite_username: Option<String>,
    /// Fully qualified username resolved from the dotNS contracts on Asset Hub, when available.
    pub full_username: Option<String>,
    /// Opaque session token used to reject stale pre-confirmation snapshots.
    pub validation_id: Vec<u8>,
}

impl AuthoritySession {
    /// Project the neutral snapshot out of a concrete session.
    pub(crate) fn from_session_info(info: &SessionInfo, validation_id: Vec<u8>) -> Self {
        Self {
            public_key: info.public_key,
            identity_account_id: info.identity_account_id,
            lite_username: info.lite_username.clone(),
            full_username: info.full_username.clone(),
            validation_id,
        }
    }

    /// Preferred display username: full over lite, skipping empty values.
    pub(crate) fn primary_username(&self) -> Option<&str> {
        self.full_username
            .as_deref()
            .filter(|value| !value.is_empty())
            .or_else(|| {
                self.lite_username
                    .as_deref()
                    .filter(|value| !value.is_empty())
            })
    }
}

/// Typed account-authority failure before it is mapped to an API-specific error.
#[derive(Debug, Clone, PartialEq, Eq, derive_more::Display, derive_more::Error)]
pub(crate) enum AuthorityError {
    /// User or authority rejected the request.
    #[display("Rejected")]
    Rejected,
    /// The selected authority session is no longer active.
    #[display("Disconnected")]
    Disconnected,
    /// The authority call was cancelled before completion.
    #[display("{_0}")]
    Cancelled(AuthorityCancelError),
    /// The authority cannot service the request.
    #[display("{reason}")]
    Unavailable { reason: String },
    /// The authority cannot service this request shape (e.g. an unsupported
    /// transaction-extension version).
    #[display("{reason}")]
    NotSupported { reason: String },
    /// Catch-all authority failure.
    #[display("{reason}")]
    Unknown { reason: String },
}

impl From<AuthorityError> for RingVrfError {
    fn from(err: AuthorityError) -> Self {
        match err {
            AuthorityError::Rejected => RingVrfError::Rejected,
            other => RingVrfError::Unknown {
                reason: other.to_string(),
            },
        }
    }
}

impl From<AuthorityError> for HostAccountSignVrfError {
    fn from(err: AuthorityError) -> Self {
        match err {
            AuthorityError::Disconnected => Self::NotConnected,
            AuthorityError::Rejected => Self::Rejected,
            AuthorityError::Cancelled(err) => Self::Unknown {
                reason: err.to_string(),
            },
            AuthorityError::Unavailable { reason }
            | AuthorityError::NotSupported { reason }
            | AuthorityError::Unknown { reason } => Self::Unknown { reason },
        }
    }
}

/// Cancellation cause for an account-authority call.
#[derive(Debug, Clone, PartialEq, Eq, derive_more::Display, derive_more::Error)]
#[display(
    "Account authority request {reason}{}",
    if request_id.is_empty() { String::new() } else { format!(" for {request_id}") }
)]
pub(crate) struct AuthorityCancelError {
    request_id: String,
    reason: CancellationReason,
}

impl AuthorityCancelError {
    /// Cancellation attributed to the request it interrupted.
    pub(crate) fn new(request_id: &str, reason: CancellationReason) -> Self {
        Self {
            request_id: request_id.to_string(),
            reason,
        }
    }
}

/// Payload-signing request selected by the product API entrypoint.
#[derive(Clone, Debug, PartialEq, Eq)]
pub(crate) enum SignPayloadAuthorityRequest {
    /// Sign a payload with a product-derived account.
    Product(HostSignPayloadRequest),
    /// Sign a payload through the legacy-account API.
    LegacyAccount {
        /// Product slot-zero account that backs the validated legacy signer.
        product_account: ProductAccountId,
        /// Original legacy-account request.
        request: HostSignPayloadWithLegacyAccountRequest,
    },
}

/// Raw-signing request selected by the product API entrypoint.
#[derive(Clone, Debug, PartialEq, Eq)]
pub(crate) enum SignRawAuthorityRequest {
    /// Sign raw data with a product-derived account.
    Product(HostSignRawRequest),
    /// Sign raw data through the legacy-account API.
    LegacyAccount {
        /// Account selected by the product and validated against the session.
        account: AccountId,
        /// Original legacy-account request.
        request: HostSignRawWithLegacyAccountRequest,
    },
}

/// Transaction-creation request selected by the product API entrypoint.
#[derive(Clone, Debug, PartialEq, Eq)]
pub(crate) enum CreateTransactionAuthorityRequest {
    /// Create a transaction with a product-derived account.
    Product(ProductAccountTxPayload),
    /// Create a transaction through the legacy-account API using the product slot-zero account.
    LegacyAccount {
        /// Product slot-zero account that backs the validated legacy signer.
        product_account: ProductAccountId,
        /// Original legacy-account transaction request.
        request: LegacyAccountTxPayload,
    },
    /// Create a transaction with the active wallet's identity account.
    IdentityAccount(LegacyAccountTxPayload),
}

/// Host-private Chat identity operation after product authorization.
#[derive(Clone, Debug, PartialEq, Eq)]
pub(crate) enum ProductDeviceChatAuthorityRequest {
    Bind {
        calling_product_id: String,
        device_account_id: [u8; 32],
        derivation_index: DerivationIndex,
        peer_identity_account_id: [u8; 32],
        peer_chat_public_key: [u8; 32],
    },
    Seal {
        calling_product_id: String,
        peer_chat_public_key: [u8; 32],
        cipher_suite: HostProductDeviceChatCipherSuite,
        plaintext: Vec<u8>,
    },
    Open {
        calling_product_id: String,
        peer_chat_public_key: [u8; 32],
        cipher_suite: HostProductDeviceChatCipherSuite,
        combined_ciphertext: Vec<u8>,
    },
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub(crate) enum ProductDeviceChatAuthorityError {
    Disconnected,
    Rejected,
    InvalidPeerKey,
    InvalidCiphertext,
    Unavailable(String),
}

impl From<AuthorityError> for ProductDeviceChatAuthorityError {
    fn from(error: AuthorityError) -> Self {
        match error {
            AuthorityError::Disconnected => Self::Disconnected,
            AuthorityError::Rejected => Self::Rejected,
            other => Self::Unavailable(other.to_string()),
        }
    }
}
/// Statement-store allowance signing material held by the authority layer.
#[derive(Clone, PartialEq, Eq, zeroize::Zeroize, zeroize::ZeroizeOnDrop, derive_more::Debug)]
pub(crate) struct StatementStoreAllowanceKey {
    /// sr25519 secret used to sign allowance statements.
    #[debug("\"<redacted>\"")]
    pub(crate) secret: [u8; 64],
    /// Public key derived from `secret`.
    pub(crate) public_key: [u8; 32],
}

impl StatementStoreAllowanceKey {
    /// Wrap a 64-byte sr25519 secret and derive its public key; other lengths
    /// are `Unavailable`.
    pub(crate) fn from_secret_bytes(secret: Vec<u8>) -> Result<Self, AuthorityError> {
        let secret: [u8; 64] =
            secret
                .try_into()
                .map_err(|secret: Vec<u8>| AuthorityError::Unavailable {
                    reason: format!(
                        "statement-store allowance key must be 64 bytes, got {}",
                        secret.len()
                    ),
                })?;
        let public_key = statement_public_key_from_secret(secret)
            .map_err(|reason| AuthorityError::Unavailable { reason })?;
        Ok(Self { secret, public_key })
    }
}

/// Host-level account authority used by product runtimes.
///
/// Pairing hosts implement this by forwarding authority requests to a paired
/// signing host. A signing-host implementation can later provide the same
/// surface from local keys without changing product runtime code.
#[async_trait]
pub(crate) trait ProductAuthority: Send + Sync {
    /// Current account-authority session, if connected.
    fn current_session(&self) -> Option<AuthoritySession>;

    /// Shared session holder owned by this authority.
    ///
    /// Product runtimes use it for connection-status subscriptions. The
    /// concrete authority keeps ownership of the actual session material.
    fn session_state(&self) -> Arc<SessionState>;

    /// Seed a paired product subtree in unit tests that exercise later authority calls.
    #[cfg(test)]
    fn cache_product_subtree_for_test(
        &self,
        _session: &SessionInfo,
        _product_id: &str,
        _public_key: [u8; 32],
    ) {
    }

    /// Request account connection for the calling product.
    async fn request_login(
        &self,
        product: &ProductContext,
    ) -> Result<HostRequestLoginResponse, CallError<HostRequestLoginError>>;

    /// Disconnect the current account-authority session.
    async fn disconnect(&self);

    /// Refresh identity fields for the current session if the authority can do
    /// so without user interaction.
    async fn refresh_session_identity(&self) -> Option<AuthoritySession> {
        self.current_session()
    }

    /// Return the public key of `//product//{product_id}`.
    ///
    /// Pairing hosts obtain this consent-free value from the Account Holder;
    /// signing hosts derive it locally from root entropy.
    async fn product_subtree_public_key(
        &self,
        cx: &CallContext,
        session: &AuthoritySession,
        product_id: String,
    ) -> Result<[u8; 32], AuthorityError>;

    /// Whether resolving `product_id`'s subtree would reach the Account Holder
    /// over SSO rather than resolve locally. Gates a host consent prompt: a
    /// pairing host returns `true` only on a cold cache; a signing host derives
    /// locally and returns `false`. Required rather than defaulted, so a new
    /// authority cannot skip the consent gate by omission.
    async fn subtree_resolution_reaches_account_holder(
        &self,
        session: &AuthoritySession,
        product_id: &str,
    ) -> bool;

    /// Sign an RFC-0023 Merlin transcript with a product account.
    async fn sign_vrf(
        &self,
        cx: &CallContext,
        session: &AuthoritySession,
        calling_product_id: String,
        request: HostAccountSignVrfRequest,
    ) -> Result<VrfSignature, AuthorityError>;

    /// Sign a SCALE transaction payload for a product account.
    async fn sign_payload(
        &self,
        cx: &CallContext,
        session: &AuthoritySession,
        request: SignPayloadAuthorityRequest,
    ) -> Result<HostSignPayloadResponse, AuthorityError>;

    /// Sign arbitrary bytes for a product account.
    async fn sign_raw(
        &self,
        cx: &CallContext,
        session: &AuthoritySession,
        request: SignRawAuthorityRequest,
    ) -> Result<HostSignPayloadResponse, AuthorityError>;

    /// Build a transaction for a product account, signed unless the request
    /// supplies its own V5 `VerifyMultiSignature` extension.
    async fn create_transaction(
        &self,
        cx: &CallContext,
        session: &AuthoritySession,
        request: CreateTransactionAuthorityRequest,
    ) -> Result<HostCreateTransactionResponse, AuthorityError>;

    /// Derive a product-scoped contextual alias for an explicit registered key.
    ///
    /// The Account Holder resolves `key_handle` from the registry and derives
    /// the alias bound to `context`; `create_proof` derives the same alias.
    async fn account_alias(
        &self,
        cx: &CallContext,
        session: &AuthoritySession,
        request: ProductRequest<HostAccountGetAliasRequest>,
    ) -> Result<HostAccountGetAliasResponse, RingVrfError>;

    /// Create a ring-VRF proof bound to a context and message.
    ///
    /// Uses the request's explicit registered key, so the returned
    /// `contextual_alias` matches `account_alias` for the same inputs.
    async fn create_proof(
        &self,
        cx: &CallContext,
        session: &AuthoritySession,
        request: ProductRequest<HostAccountCreateProofRequest>,
    ) -> Result<HostAccountCreateProofResponse, RingVrfError>;

    /// Register a ring-VRF key owned by the calling product.
    async fn register_ring_vrf_key(
        &self,
        cx: &CallContext,
        session: &AuthoritySession,
        request: ProductRequest<HostAccountRegisterRingVrfKeyRequest>,
    ) -> Result<HostAccountRegisterRingVrfKeyResponse, RingVrfError>;

    /// List registered ring-VRF keys.
    async fn list_ring_vrf_keys(
        &self,
        cx: &CallContext,
        session: &AuthoritySession,
        request: ProductRequest<HostAccountListRingVrfKeysRequest>,
    ) -> Result<HostAccountListRingVrfKeysResponse, RingVrfError>;

    /// Sign bytes directly with a registered ring-VRF key.
    async fn ring_vrf_sign(
        &self,
        cx: &CallContext,
        session: &AuthoritySession,
        request: ProductRequest<HostAccountRingVrfSignRequest>,
    ) -> Result<HostAccountRingVrfSignResponse, RingVrfError>;

    /// Bind/seal/open using the active wallet's host-private Chat identity key.
    async fn product_device_chat(
        &self,
        cx: &CallContext,
        session: &AuthoritySession,
        request: ProductDeviceChatAuthorityRequest,
    ) -> Result<HostProductDeviceChatResponse, ProductDeviceChatAuthorityError>;

    /// Ask the account authority to allocate product-scoped resources.
    async fn allocate_resources(
        &self,
        cx: &CallContext,
        session: &AuthoritySession,
        product_id: String,
        request: HostRequestResourceAllocationRequest,
    ) -> Result<HostRequestResourceAllocationResponse, AuthorityError>;

    /// Return statement-store allowance key material for the calling product.
    async fn statement_store_allowance_key(
        &self,
        cx: &CallContext,
        session: &AuthoritySession,
        product_id: String,
    ) -> Result<StatementStoreAllowanceKey, AuthorityError>;

    /// Return Bulletin allowance key material for the calling product.
    async fn bulletin_allowance_key(
        &self,
        cx: &CallContext,
        session: &AuthoritySession,
        product_id: String,
    ) -> Result<BulletinAllowanceKey, AuthorityError>;

    /// Evict any cached Bulletin allowance key for the product and allocate a
    /// fresh one, increasing the existing allowance.
    ///
    /// Called after a submission is rejected for an exhausted/missing
    /// allowance, where reusing the cached key would loop forever.
    async fn refresh_bulletin_allowance_key(
        &self,
        cx: &CallContext,
        session: &AuthoritySession,
        product_id: String,
    ) -> Result<BulletinAllowanceKey, AuthorityError>;

    /// Sign exact statement-store proof bytes with a product-derived account.
    async fn sign_statement_store_product_payload(
        &self,
        cx: &CallContext,
        session: &AuthoritySession,
        account: ProductAccountId,
        payload: Vec<u8>,
    ) -> Result<[u8; 64], AuthorityError>;

    /// Derive product-scoped entropy for a connected session.
    fn derive_entropy(
        &self,
        session: &AuthoritySession,
        product_id: &str,
        context: &[u8],
    ) -> Result<[u8; 32], AuthorityError>;
}

pub(super) fn execute_product_device_chat(
    identity_chat_private_key: &[u8; 32],
    identity_account_id: [u8; 32],
    request: ProductDeviceChatAuthorityRequest,
) -> Result<HostProductDeviceChatResponse, ProductDeviceChatAuthorityError> {
    use chacha20poly1305::aead::{Aead, KeyInit, Payload};
    use chacha20poly1305::{ChaCha20Poly1305, Nonce};
    use hkdf::Hkdf;
    use sha2::Sha256;
    use x25519_dalek::{PublicKey, StaticSecret};
    use zeroize::Zeroizing;

    let peer_public_key = match &request {
        ProductDeviceChatAuthorityRequest::Bind {
            peer_chat_public_key,
            ..
        }
        | ProductDeviceChatAuthorityRequest::Seal {
            peer_chat_public_key,
            ..
        }
        | ProductDeviceChatAuthorityRequest::Open {
            peer_chat_public_key,
            ..
        } => *peer_chat_public_key,
    };
    if !is_canonical_x25519_public_key(&peer_public_key) {
        return Err(ProductDeviceChatAuthorityError::InvalidPeerKey);
    }
    let shared_secret = Zeroizing::new(
        StaticSecret::from(*identity_chat_private_key)
            .diffie_hellman(&PublicKey::from(peer_public_key))
            .to_bytes(),
    );
    if *shared_secret == [0; 32] {
        return Err(ProductDeviceChatAuthorityError::InvalidPeerKey);
    }

    return match request {
        ProductDeviceChatAuthorityRequest::Bind {
            device_account_id,
            peer_identity_account_id,
            ..
        } => {
            let context = b"mds-chat-request";
            let mut payload = Vec::with_capacity(65 + context.len());
            payload.extend_from_slice(&identity_account_id);
            payload.extend_from_slice(&device_account_id);
            payload.push((context.len() as u8) << 2);
            payload.extend_from_slice(context);
            let proof = blake2b_simd::Params::new()
                .hash_length(32)
                .key(shared_secret.as_ref())
                .hash(&payload);
            let mut proof_bytes = [0; 32];
            proof_bytes.copy_from_slice(proof.as_bytes());
            let wallet_own_session_id = chat_identity_session_id(
                &shared_secret,
                &identity_account_id,
                &peer_identity_account_id,
            );
            let peer_own_session_id = chat_identity_session_id(
                &shared_secret,
                &peer_identity_account_id,
                &identity_account_id,
            );
            let wallet_outgoing_channel_id = chat_request_channel_id(
                &shared_secret,
                &identity_account_id,
                &peer_identity_account_id,
            );
            let wallet_incoming_channel_id = chat_request_channel_id(
                &shared_secret,
                &peer_identity_account_id,
                &identity_account_id,
            );
            Ok(HostProductDeviceChatResponse::IdentityBinding {
                identity_account_id,
                proof: proof_bytes,
                wallet_own_session_id,
                peer_own_session_id,
                wallet_outgoing_channel_id,
                wallet_incoming_channel_id,
            })
        }
        ProductDeviceChatAuthorityRequest::Seal {
            calling_product_id,
            cipher_suite,
            plaintext,
            ..
        } => {
            let (key, aad) = product_device_chat_aead_material(
                &shared_secret,
                &calling_product_id,
                &identity_account_id,
                &cipher_suite,
                true,
            )?;
            let key = Zeroizing::new(key);
            let mut nonce = [0; 12];
            getrandom::getrandom(&mut nonce).map_err(|error| {
                ProductDeviceChatAuthorityError::Unavailable(format!(
                    "failed to generate Chat identity-route nonce: {error}"
                ))
            })?;
            let encrypted = ChaCha20Poly1305::new((&*key).into())
                .encrypt(
                    Nonce::from_slice(&nonce),
                    Payload {
                        msg: &plaintext,
                        aad: &aad,
                    },
                )
                .map_err(|_| {
                    ProductDeviceChatAuthorityError::Unavailable(
                        "Chat identity-route encryption failed".to_string(),
                    )
                })?;
            let mut combined_ciphertext = Vec::with_capacity(12 + encrypted.len());
            combined_ciphertext.extend_from_slice(&nonce);
            combined_ciphertext.extend_from_slice(&encrypted);
            Ok(HostProductDeviceChatResponse::Sealed {
                combined_ciphertext,
            })
        }
        ProductDeviceChatAuthorityRequest::Open {
            calling_product_id,
            cipher_suite,
            combined_ciphertext,
            ..
        } => {
            if combined_ciphertext.len() < 28 {
                return Err(ProductDeviceChatAuthorityError::InvalidCiphertext);
            }
            let (key, aad) = product_device_chat_aead_material(
                &shared_secret,
                &calling_product_id,
                &identity_account_id,
                &cipher_suite,
                false,
            )?;
            let key = Zeroizing::new(key);
            let plaintext = ChaCha20Poly1305::new((&*key).into())
                .decrypt(
                    Nonce::from_slice(&combined_ciphertext[..12]),
                    Payload {
                        msg: &combined_ciphertext[12..],
                        aad: &aad,
                    },
                )
                .map_err(|_| ProductDeviceChatAuthorityError::InvalidCiphertext)?;
            Ok(HostProductDeviceChatResponse::Opened { plaintext })
        }
    };

    fn product_device_chat_aead_material(
        shared_secret: &[u8; 32],
        calling_product_id: &str,
        identity_account_id: &[u8; 32],
        cipher_suite: &HostProductDeviceChatCipherSuite,
        sealing: bool,
    ) -> Result<([u8; 32], Vec<u8>), ProductDeviceChatAuthorityError> {
        let mut key = [0; 32];
        let HostProductDeviceChatCipherSuite::ContextBoundV1 {
            peer_account_id,
            channel_id,
        } = cipher_suite
        else {
            Hkdf::<Sha256>::new(Some(&[]), shared_secret)
                .expand(&[], &mut key)
                .map_err(|_| {
                    ProductDeviceChatAuthorityError::Unavailable(
                        "Chat identity-route HKDF failed".to_string(),
                    )
                })?;
            return Ok((key, Vec::new()));
        };
        let product_id_len = u32::try_from(calling_product_id.len()).map_err(|_| {
            ProductDeviceChatAuthorityError::Unavailable(
                "Chat product identifier is too long".to_string(),
            )
        })?;
        let (sender_account_id, recipient_account_id) = if sealing {
            (identity_account_id, peer_account_id)
        } else {
            (peer_account_id, identity_account_id)
        };
        let domain = b"dotli-chat/context-bound/v1";
        let mut aad = Vec::with_capacity(
            domain.len() + 4 + calling_product_id.len() + 32 + 32 + channel_id.len(),
        );
        aad.extend_from_slice(domain);
        aad.extend_from_slice(&product_id_len.to_le_bytes());
        aad.extend_from_slice(calling_product_id.as_bytes());
        aad.extend_from_slice(sender_account_id);
        aad.extend_from_slice(recipient_account_id);
        aad.extend_from_slice(channel_id);
        Hkdf::<Sha256>::new(Some(domain), shared_secret)
            .expand(&aad, &mut key)
            .map_err(|_| {
                ProductDeviceChatAuthorityError::Unavailable(
                    "context-bound Chat identity-route HKDF failed".to_string(),
                )
            })?;
        Ok((key, aad))
    }

    fn is_canonical_x25519_public_key(key: &[u8; 32]) -> bool {
        const FIELD_MODULUS: [u8; 32] = [
            0xed, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff,
            0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff,
            0xff, 0xff, 0xff, 0x7f,
        ];
        if key[31] & 0x80 != 0 {
            return false;
        }
        for index in (0..32).rev() {
            if key[index] < FIELD_MODULUS[index] {
                return true;
            }
            if key[index] > FIELD_MODULUS[index] {
                return false;
            }
        }
        false
    }

    fn chat_identity_session_id(
        shared_secret: &[u8; 32],
        first_account_id: &[u8; 32],
        second_account_id: &[u8; 32],
    ) -> [u8; 32] {
        let mut input = Vec::with_capacity(7 + 32 + 32 + 2);
        input.extend_from_slice(b"session");
        input.extend_from_slice(first_account_id);
        input.extend_from_slice(second_account_id);
        input.extend_from_slice(b"//");
        let hash = blake2b_simd::Params::new()
            .hash_length(32)
            .key(shared_secret)
            .hash(&input);
        let mut output = [0; 32];
        output.copy_from_slice(hash.as_bytes());
        output
    }

    fn chat_request_channel_id(
        shared_secret: &[u8; 32],
        requester_account_id: &[u8; 32],
        acceptor_account_id: &[u8; 32],
    ) -> [u8; 32] {
        let mut input = Vec::with_capacity(12 + 32 + 32 + 2);
        input.extend_from_slice(b"chat-request");
        input.extend_from_slice(requester_account_id);
        input.extend_from_slice(acceptor_account_id);
        input.extend_from_slice(b"//");
        let hash = blake2b_simd::Params::new()
            .hash_length(32)
            .key(shared_secret)
            .hash(&input);
        let mut output = [0; 32];
        output.copy_from_slice(hash.as_bytes());
        output
    }
}

/// Build the neutral authority-session snapshot for `session`.
pub(super) fn authority_session(session: &SessionInfo) -> AuthoritySession {
    AuthoritySession::from_session_info(session, authority_session_validation_id(session))
}

/// Revalidate a pre-confirmation snapshot against the live session, returning
/// the current [`SessionInfo`] when it still matches.
///
/// Both roles use this before touching key material: a snapshot taken before
/// user confirmation must still be the current authority session when the
/// signature or derivation happens, otherwise the request is rejected.
pub(super) fn require_current_session(
    session_state: &SessionState,
    session: &AuthoritySession,
) -> Result<SessionInfo, AuthorityError> {
    let current = session_state
        .current()
        .ok_or(AuthorityError::Disconnected)?;
    if authority_session_validation_id(&current) == session.validation_id {
        Ok(current)
    } else {
        Err(AuthorityError::Disconnected)
    }
}

/// Opaque token identifying which concrete session a snapshot was taken from.
pub(super) fn authority_session_validation_id(session: &SessionInfo) -> Vec<u8> {
    let mut id = Vec::with_capacity(67);
    if let Some(sso) = &session.sso {
        id.extend_from_slice(b"sso");
        id.extend_from_slice(&sso.session_id_own);
        id.extend_from_slice(&sso.session_id_peer);
    } else {
        id.extend_from_slice(b"local");
        id.extend_from_slice(&session.public_key);
    }
    id
}

#[cfg(test)]
mod tests {
    use super::*;

    fn hex32(value: &str) -> [u8; 32] {
        hex::decode(value).unwrap().try_into().unwrap()
    }

    #[test]
    fn product_device_bind_matches_ios_chat_v2_derivations() {
        let peer_public_key =
            x25519_dalek::PublicKey::from(&x25519_dalek::StaticSecret::from([0x22; 32])).to_bytes();
        assert_eq!(
            peer_public_key,
            hex32("0faa684ed28867b97f4a6a2dee5df8ce974e76b7018e3f22a1c4cf2678570f20")
        );

        let response = execute_product_device_chat(
            &[0x11; 32],
            [0x33; 32],
            ProductDeviceChatAuthorityRequest::Bind {
                calling_product_id: "egui-chat.paseo".to_string(),
                device_account_id: [0x44; 32],
                derivation_index: DerivationIndex::Index(0),
                peer_identity_account_id: [0x55; 32],
                peer_chat_public_key: peer_public_key,
            },
        )
        .unwrap();
        let HostProductDeviceChatResponse::IdentityBinding {
            identity_account_id,
            proof,
            wallet_own_session_id,
            peer_own_session_id,
            wallet_outgoing_channel_id,
            wallet_incoming_channel_id,
        } = response
        else {
            panic!("Bind must return an identity binding");
        };
        assert_eq!(identity_account_id, [0x33; 32]);
        assert_eq!(
            proof,
            hex32("0263d1995da865e34e06de38b4f4c0c88524e2e591b1ae6714578219bffad333")
        );
        assert_eq!(
            wallet_own_session_id,
            hex32("460db8611d842e65414f9eea4aa74d3fe1ac2e31468d4fbebededd914be28422")
        );
        assert_eq!(
            peer_own_session_id,
            hex32("bfb5eb8c0b959f95b3ab09bd0f8001ab80f100cf5bb617640534372ab777c5c3")
        );
        assert_eq!(
            wallet_outgoing_channel_id,
            hex32("576f71aa7f51aa340f411c20779c35f476361d8008247db367a8ce4d7e087d70")
        );
        assert_eq!(
            wallet_incoming_channel_id,
            hex32("19de8cf16554a8463d0f8af7ad23717f4106463af331ee33f297b7367c8fe9fa")
        );
    }

    #[test]
    fn product_device_seal_open_round_trip_and_authenticate() {
        let identity_chat_private_key = [0x11; 32];
        let peer_chat_public_key =
            x25519_dalek::PublicKey::from(&x25519_dalek::StaticSecret::from([0x22; 32])).to_bytes();
        let plaintext = b"private first-contact payload".to_vec();
        let sealed = execute_product_device_chat(
            &identity_chat_private_key,
            [0x33; 32],
            ProductDeviceChatAuthorityRequest::Seal {
                calling_product_id: "egui-chat.paseo".to_string(),
                peer_chat_public_key,
                cipher_suite: HostProductDeviceChatCipherSuite::LegacyV2,
                plaintext: plaintext.clone(),
            },
        )
        .unwrap();
        let HostProductDeviceChatResponse::Sealed {
            mut combined_ciphertext,
        } = sealed
        else {
            panic!("Seal must return ciphertext");
        };

        let opened = execute_product_device_chat(
            &identity_chat_private_key,
            [0x33; 32],
            ProductDeviceChatAuthorityRequest::Open {
                calling_product_id: "egui-chat.paseo".to_string(),
                peer_chat_public_key,
                cipher_suite: HostProductDeviceChatCipherSuite::LegacyV2,
                combined_ciphertext: combined_ciphertext.clone(),
            },
        )
        .unwrap();
        assert_eq!(opened, HostProductDeviceChatResponse::Opened { plaintext });

        let last = combined_ciphertext.len() - 1;
        combined_ciphertext[last] ^= 1;
        assert_eq!(
            execute_product_device_chat(
                &identity_chat_private_key,
                [0x33; 32],
                ProductDeviceChatAuthorityRequest::Open {
                    calling_product_id: "egui-chat.paseo".to_string(),
                    peer_chat_public_key,
                    cipher_suite: HostProductDeviceChatCipherSuite::LegacyV2,
                    combined_ciphertext,
                },
            ),
            Err(ProductDeviceChatAuthorityError::InvalidCiphertext)
        );
    }

    #[test]
    fn context_bound_product_device_chat_rejects_downgrade_and_wrong_context() {
        let sender_private_key = [0x11; 32];
        let recipient_private_key = [0x22; 32];
        let sender_public_key =
            x25519_dalek::PublicKey::from(&x25519_dalek::StaticSecret::from(sender_private_key))
                .to_bytes();
        let recipient_public_key =
            x25519_dalek::PublicKey::from(&x25519_dalek::StaticSecret::from(recipient_private_key))
                .to_bytes();
        let sender_account_id = [0x33; 32];
        let recipient_account_id = [0x44; 32];
        let channel_id = [0x55; 32];
        let plaintext = b"context-bound identity payload".to_vec();
        let sealed = execute_product_device_chat(
            &sender_private_key,
            sender_account_id,
            ProductDeviceChatAuthorityRequest::Seal {
                calling_product_id: "egui-chat.paseo".to_string(),
                peer_chat_public_key: recipient_public_key,
                cipher_suite: HostProductDeviceChatCipherSuite::ContextBoundV1 {
                    peer_account_id: recipient_account_id,
                    channel_id,
                },
                plaintext: plaintext.clone(),
            },
        )
        .unwrap();
        let HostProductDeviceChatResponse::Sealed {
            combined_ciphertext,
        } = sealed
        else {
            panic!("Seal must return ciphertext");
        };

        let open = |calling_product_id: &str, cipher_suite: HostProductDeviceChatCipherSuite| {
            execute_product_device_chat(
                &recipient_private_key,
                recipient_account_id,
                ProductDeviceChatAuthorityRequest::Open {
                    calling_product_id: calling_product_id.to_string(),
                    peer_chat_public_key: sender_public_key,
                    cipher_suite,
                    combined_ciphertext: combined_ciphertext.clone(),
                },
            )
        };
        assert_eq!(
            open(
                "egui-chat.paseo",
                HostProductDeviceChatCipherSuite::ContextBoundV1 {
                    peer_account_id: sender_account_id,
                    channel_id,
                },
            ),
            Ok(HostProductDeviceChatResponse::Opened {
                plaintext: plaintext.clone(),
            })
        );
        assert_eq!(
            open(
                "egui-chat.paseo",
                HostProductDeviceChatCipherSuite::LegacyV2
            ),
            Err(ProductDeviceChatAuthorityError::InvalidCiphertext)
        );
        assert_eq!(
            open(
                "egui-chat.paseo",
                HostProductDeviceChatCipherSuite::ContextBoundV1 {
                    peer_account_id: sender_account_id,
                    channel_id: [0x56; 32],
                },
            ),
            Err(ProductDeviceChatAuthorityError::InvalidCiphertext)
        );
        assert_eq!(
            open(
                "egui-chat.westend",
                HostProductDeviceChatCipherSuite::ContextBoundV1 {
                    peer_account_id: sender_account_id,
                    channel_id,
                },
            ),
            Err(ProductDeviceChatAuthorityError::InvalidCiphertext)
        );
    }

    #[test]
    fn product_device_rejects_invalid_peer_keys() {
        assert_eq!(
            execute_product_device_chat(
                &[0x11; 32],
                [0x33; 32],
                ProductDeviceChatAuthorityRequest::Seal {
                    calling_product_id: "egui-chat.paseo".to_string(),
                    peer_chat_public_key: [0; 32],
                    cipher_suite: HostProductDeviceChatCipherSuite::LegacyV2,
                    plaintext: Vec::new(),
                },
            ),
            Err(ProductDeviceChatAuthorityError::InvalidPeerKey)
        );

        let mut noncanonical_peer_key =
            x25519_dalek::PublicKey::from(&x25519_dalek::StaticSecret::from([0x22; 32])).to_bytes();
        noncanonical_peer_key[31] |= 0x80;
        assert_eq!(
            execute_product_device_chat(
                &[0x11; 32],
                [0x33; 32],
                ProductDeviceChatAuthorityRequest::Seal {
                    calling_product_id: "egui-chat.paseo".to_string(),
                    peer_chat_public_key: noncanonical_peer_key,
                    cipher_suite: HostProductDeviceChatCipherSuite::LegacyV2,
                    plaintext: Vec::new(),
                },
            ),
            Err(ProductDeviceChatAuthorityError::InvalidPeerKey)
        );
    }
}
