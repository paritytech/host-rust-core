//! iOS-compatible wallet chat-request discovery and acceptance.
//!
//! A contact request is not part of the product-facing [`truapi::api::Chat`]
//! surface. The wallet publishes it as an encrypted statement on the
//! recipient identity's `chat-request` topic. Acceptance is a regular
//! MessageExchange `chatAccepted` message on the pair's identity session.

use aes_gcm::aead::{Aead, KeyInit};
use aes_gcm::{Aes256Gcm, Nonce};
use hkdf::Hkdf;
use p256::ecdh::diffie_hellman;
use p256::elliptic_curve::sec1::ToEncodedPoint;
use p256::{PublicKey as P256PublicKey, SecretKey as P256SecretKey};
use parity_scale_codec::{Decode, Encode, Error as CodecError, Input, Output};
use schnorrkel::{PublicKey as Sr25519PublicKey, Signature as Sr25519Signature};
use sha2::Sha256;
use thiserror::Error;

use super::product_account::{ProductAccountError, derive_sr25519_hard_path};
use super::sso::pairing::{
    AES_GCM_NONCE_LEN, PairingBootstrapError, ResponderIdentity, SsoStatementData,
    derive_p256_keypair_from_entropy, encrypt_session_statement_data,
    establish_responder_session_info,
};
use super::statement_store::{StatementProof, build_signed_statement};

const CLI_CHAT_ENCRYPTION_KEY_LABEL: &[u8] = b"chat-encryption";
const CHAT_REQUEST_CONTEXT: &[u8] = b"chat-request";
const MULTI_DEVICE_IDENTITY_CONTEXT: &str = "mds-chat-request";
const STATEMENT_SIGNING_CONTEXT: &[u8] = b"substrate";
const CHAT_PRIORITY_EPOCH: u64 = 1_763_164_800;
const CHAT_PRIORITY_PREFIX: u64 = 0xffff_ffff_0000_0000;

/// Persistent identity keys used by a CLI Lite user for wallet chat.
pub struct ChatIdentity {
    statement_secret: [u8; 64],
    /// `//wallet//sso` account targeted by incoming discovery statements.
    pub statement_account_id: [u8; 32],
    encryption_secret: [u8; 32],
    /// P-256 identifier key stored in `Resources.Consumers`.
    pub encryption_public_key: [u8; 65],
}

/// Identity derivations supported by the CLI.
///
/// CLI-managed Lite users use the SSO identity introduced by the headless
/// host. Existing iOS users use their main wallet identity and the
/// `//wallet//chat` encryption key.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ChatIdentityDerivation {
    /// iOS main identity: `//wallet` signer and `//wallet//chat` P-256 key.
    Main,
    /// CLI identity: `//wallet//sso` signer and the headless chat key.
    Sso,
}

/// A cryptographically valid request whose peer People identity must still be
/// resolved and, for V2, checked against the included identity proof.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct IncomingChatRequest {
    /// Sender-chosen request/message identifier.
    pub request_id: String,
    /// Millisecond Unix timestamp from the request.
    pub timestamp_ms: u64,
    /// People identity account to resolve for username and identifier key.
    pub peer_account_id: [u8; 32],
    /// sr25519 account that signed the request proof.
    pub peer_statement_account_id: [u8; 32],
    identity_proof: Option<[u8; 32]>,
}

/// Chat-request codec or cryptographic validation failure.
#[derive(Debug, Error)]
pub enum ChatRequestError {
    /// SCALE payload does not match the iOS chat-request shape.
    #[error("invalid chat request payload: {0}")]
    InvalidPayload(String),
    /// A required key has the wrong representation.
    #[error("invalid chat request key: {0}")]
    InvalidKey(String),
    /// The inner request proof is not sr25519 or does not verify.
    #[error("invalid chat request signature")]
    InvalidSignature,
    /// The V2 device-to-identity binding does not verify.
    #[error("invalid chat request identity proof")]
    InvalidIdentityProof,
    /// Local account derivation failed.
    #[error("chat identity derivation failed: {0}")]
    IdentityDerivation(#[from] ProductAccountError),
    /// Local P-256 derivation failed.
    #[error("chat encryption-key derivation failed: {0}")]
    EncryptionDerivation(#[from] PairingBootstrapError),
    /// Encryption or statement construction failed.
    #[error("chat acceptance construction failed: {0}")]
    Acceptance(String),
}

/// Derive a supported People/chat identity from root entropy.
pub fn derive_chat_identity(
    entropy: &[u8],
    derivation: ChatIdentityDerivation,
) -> Result<ChatIdentity, ChatRequestError> {
    let (statement, encryption_secret, encryption_public_key) = match derivation {
        ChatIdentityDerivation::Main => {
            let statement = derive_sr25519_hard_path(entropy, &["wallet"])?;
            let (secret, public) = derive_ios_main_chat_keypair(entropy)?;
            (statement, secret, public)
        }
        ChatIdentityDerivation::Sso => {
            let statement = derive_sr25519_hard_path(entropy, &["wallet", "sso"])?;
            let (secret, public) =
                derive_p256_keypair_from_entropy(entropy, CLI_CHAT_ENCRYPTION_KEY_LABEL)?;
            (statement, secret, public)
        }
    };
    Ok(ChatIdentity {
        statement_secret: statement.secret.to_bytes(),
        statement_account_id: statement.public.to_bytes(),
        encryption_secret,
        encryption_public_key,
    })
}

/// Derive identities in preference order for an active CLI signer.
pub fn derive_chat_identities(entropy: &[u8]) -> Result<[ChatIdentity; 2], ChatRequestError> {
    Ok([
        derive_chat_identity(entropy, ChatIdentityDerivation::Sso)?,
        derive_chat_identity(entropy, ChatIdentityDerivation::Main)?,
    ])
}

/// Topic carrying every current contact request addressed to `account_id`.
///
/// Mirrors iOS `ChatRequest.allPeerStatementsTopic`: BLAKE2b-256 over SCALE
/// `(Data("chat-request"), Data(account id))`. Both values are SCALE byte
/// vectors, so the fixed-size account still carries its compact length prefix.
pub fn chat_request_discovery_topic(account_id: [u8; 32]) -> [u8; 32] {
    let mut encoded = CHAT_REQUEST_CONTEXT.encode();
    encoded.extend(account_id.to_vec().encode());
    sp_crypto_hashing::blake2_256(&encoded)
}

/// Decode, decrypt, and verify the request's inner sr25519 proof.
///
/// The outer statement proof is deliberately not trusted by iOS either; the
/// encrypted model carries its own proof over `(request, acceptor account)`.
pub fn decode_incoming_chat_request(
    scale_encoded_statement_data: &[u8],
    own: &ChatIdentity,
) -> Result<IncomingChatRequest, ChatRequestError> {
    // iOS passes a SCALE-encoded `Data` into `addScaleEncodedPayload`. The
    // statement builder unwraps that outer `Data` while constructing the
    // statement field, so `decode_statement_data` returns the envelope itself.
    let encrypted: EncryptedRemoteModel =
        decode_complete(scale_encoded_statement_data, "encrypted request envelope")?;
    let ephemeral_public_key: [u8; 65] =
        encrypted
            .encryption_public_key
            .try_into()
            .map_err(|key: Vec<u8>| {
                ChatRequestError::InvalidKey(format!(
                    "ephemeral P-256 key must be 65 bytes, got {}",
                    key.len()
                ))
            })?;
    let decrypted = decrypt_p256(
        own.encryption_secret,
        ephemeral_public_key,
        &encrypted.encrypted_data,
    )?;
    let remote: RemoteModel = decode_complete(&decrypted, "decrypted request")?;

    let StatementProof::Sr25519 { signature, signer } = remote.proof else {
        return Err(ChatRequestError::InvalidSignature);
    };
    let public =
        Sr25519PublicKey::from_bytes(&signer).map_err(|_| ChatRequestError::InvalidSignature)?;
    let signature =
        Sr25519Signature::from_bytes(&signature).map_err(|_| ChatRequestError::InvalidSignature)?;
    let proof_payload = ProofPayload {
        message: remote.message.clone(),
        request_acceptor_id: own.statement_account_id.to_vec(),
    }
    .encode();
    public
        .verify_simple(STATEMENT_SIGNING_CONTEXT, &proof_payload, &signature)
        .map_err(|_| ChatRequestError::InvalidSignature)?;

    let (peer_account_id, identity_proof) = match remote.message.content {
        VersionedRequestContent::V1(_) => (signer, None),
        VersionedRequestContent::V2(content) => (
            content.identity_proof.identity_account_id,
            Some(content.identity_proof.proof),
        ),
    };
    Ok(IncomingChatRequest {
        request_id: remote.message.message_id,
        timestamp_ms: remote.message.timestamp,
        peer_account_id,
        peer_statement_account_id: signer,
        identity_proof,
    })
}

/// Validate the V2 device signer against the peer identity's People-chain
/// identifier key. V1 requests are already identity-signed and need no extra
/// binding proof.
pub fn validate_peer_identity(
    request: &IncomingChatRequest,
    own: &ChatIdentity,
    peer_identifier_key: [u8; 65],
) -> Result<(), ChatRequestError> {
    let Some(actual_proof) = request.identity_proof else {
        return Ok(());
    };
    let shared_secret = p256_shared_secret(own.encryption_secret, peer_identifier_key)?;
    let mut payload = Vec::with_capacity(64 + MULTI_DEVICE_IDENTITY_CONTEXT.len() + 1);
    payload.extend(request.peer_account_id);
    payload.extend(request.peer_statement_account_id);
    payload.extend(MULTI_DEVICE_IDENTITY_CONTEXT.encode());
    let expected = keyed_blake2b256(&payload, &shared_secret);
    if expected != actual_proof {
        return Err(ChatRequestError::InvalidIdentityProof);
    }
    Ok(())
}

/// Build the signed statement that tells iOS its request was accepted.
pub fn build_chat_acceptance_statement(
    own: &ChatIdentity,
    request: &IncomingChatRequest,
    peer_identifier_key: [u8; 65],
    message_id: String,
    transport_request_id: String,
    timestamp_ms: u64,
    priority: u64,
) -> Result<Vec<u8>, ChatRequestError> {
    let identity = ResponderIdentity {
        statement_secret: own.statement_secret,
        statement_public_key: own.statement_account_id,
        encryption_secret_key: own.encryption_secret,
        encryption_public_key: own.encryption_public_key,
    };
    let session =
        establish_responder_session_info(&identity, request.peer_account_id, peer_identifier_key)
            .map_err(ChatRequestError::Acceptance)?;
    let message = RemoteMessage {
        message_id,
        timestamp: timestamp_ms,
        content: VersionedRemoteMessage::V1(RemoteMessageV1 {
            content: RemoteMessageContent::ChatAccepted(ChatAccepted {
                message_id: request.request_id.clone(),
            }),
        }),
    }
    .encode();
    let encrypted = encrypt_session_statement_data(
        &session,
        &SsoStatementData::Request {
            request_id: transport_request_id,
            data: vec![message],
        },
    )
    .map_err(ChatRequestError::Acceptance)?;
    build_signed_statement(
        &session,
        session.request_channel,
        session.session_id_own,
        encrypted,
        priority,
    )
    .map_err(ChatRequestError::Acceptance)
}

/// iOS timestamp-based statement priority.
pub fn chat_statement_priority(now_unix_secs: u64) -> u64 {
    CHAT_PRIORITY_PREFIX | now_unix_secs.saturating_sub(CHAT_PRIORITY_EPOCH)
}

fn decode_complete<T: Decode>(input: &[u8], label: &str) -> Result<T, ChatRequestError> {
    let mut remaining = input;
    let value = T::decode(&mut remaining)
        .map_err(|error| ChatRequestError::InvalidPayload(format!("{label}: {error}")))?;
    if !remaining.is_empty() {
        return Err(ChatRequestError::InvalidPayload(format!(
            "{label}: trailing bytes"
        )));
    }
    Ok(value)
}

fn p256_shared_secret(
    own_secret_key: [u8; 32],
    peer_public_key: [u8; 65],
) -> Result<[u8; 32], ChatRequestError> {
    let secret = P256SecretKey::from_slice(&own_secret_key)
        .map_err(|error| ChatRequestError::InvalidKey(error.to_string()))?;
    let peer = P256PublicKey::from_sec1_bytes(&peer_public_key)
        .map_err(|error| ChatRequestError::InvalidKey(error.to_string()))?;
    Ok((*diffie_hellman(secret.to_nonzero_scalar(), peer.as_affine()).raw_secret_bytes()).into())
}

fn derive_ios_main_chat_keypair(entropy: &[u8]) -> Result<([u8; 32], [u8; 65]), ChatRequestError> {
    // Mirrors iOS ChatPrivateKeyFactory for `//wallet//chat`: derive the
    // sr25519 keypair, hash the first 32 private-key bytes, then interpret the
    // digest as a P-256 agreement key.
    let chat = derive_sr25519_hard_path(entropy, &["wallet", "chat"])?;
    let secret = sp_crypto_hashing::blake2_256(&chat.secret.to_bytes()[..32]);
    let key = P256SecretKey::from_slice(&secret)
        .map_err(|error| ChatRequestError::InvalidKey(error.to_string()))?;
    let encoded = key.public_key().to_encoded_point(false);
    let public: [u8; 65] = encoded.as_bytes().try_into().map_err(|_| {
        ChatRequestError::InvalidKey(format!(
            "derived P-256 public key must be 65 bytes, got {}",
            encoded.as_bytes().len()
        ))
    })?;
    Ok((secret, public))
}

fn decrypt_p256(
    own_secret_key: [u8; 32],
    peer_public_key: [u8; 65],
    encrypted: &[u8],
) -> Result<Vec<u8>, ChatRequestError> {
    if encrypted.len() < AES_GCM_NONCE_LEN + 16 {
        return Err(ChatRequestError::InvalidPayload(
            "encrypted request is too short".to_string(),
        ));
    }
    let shared_secret = p256_shared_secret(own_secret_key, peer_public_key)?;
    let key = aes_key(shared_secret)?;
    let (nonce, ciphertext) = encrypted.split_at(AES_GCM_NONCE_LEN);
    Aes256Gcm::new_from_slice(&key)
        .map_err(|error| ChatRequestError::InvalidKey(error.to_string()))?
        .decrypt(Nonce::from_slice(nonce), ciphertext)
        .map_err(|_| ChatRequestError::InvalidPayload("request decryption failed".to_string()))
}

fn aes_key(shared_secret: [u8; 32]) -> Result<[u8; 32], ChatRequestError> {
    let hkdf = Hkdf::<Sha256>::new(None, &shared_secret);
    let mut key = [0u8; 32];
    hkdf.expand(&[], &mut key)
        .map_err(|error| ChatRequestError::InvalidKey(error.to_string()))?;
    Ok(key)
}

fn keyed_blake2b256(message: &[u8], key: &[u8]) -> [u8; 32] {
    blake2b_simd::Params::new()
        .hash_length(32)
        .key(key)
        .hash(message)
        .as_bytes()
        .try_into()
        .expect("32-byte BLAKE2b output")
}

#[derive(Clone, Encode, Decode)]
struct RequestMessage {
    message_id: String,
    timestamp: u64,
    content: VersionedRequestContent,
}

#[derive(Clone, Encode, Decode)]
enum VersionedRequestContent {
    #[codec(index = 0)]
    V1(RequestContentV1),
    #[codec(index = 1)]
    V2(RequestContentV2),
}

#[derive(Clone, Encode, Decode)]
struct RequestContentV1 {
    push_token: Option<RemoteTokenContent>,
    welcome_message: Option<RequestRichText>,
}

#[derive(Clone, Encode, Decode)]
struct RequestContentV2 {
    identity_proof: IdentityProof,
    device_encryption_public_key: [u8; 65],
    push_token: Option<RemoteTokenContent>,
    welcome_message: Option<RequestRichText>,
}

#[derive(Clone, Encode, Decode)]
struct IdentityProof {
    identity_account_id: [u8; 32],
    proof: [u8; 32],
}

#[derive(Clone, Encode, Decode)]
struct RemoteTokenContent {
    token: Vec<u8>,
    push_type: u8,
}

/// Current iOS request creation accepts text only and always encodes
/// `attachments` as `None`. Reject a future attachment-bearing request
/// explicitly instead of guessing its nested file layout.
#[derive(Clone)]
struct RequestRichText {
    text: Option<String>,
}

impl Encode for RequestRichText {
    fn size_hint(&self) -> usize {
        self.text.size_hint() + 1
    }

    fn encode_to<T: Output + ?Sized>(&self, output: &mut T) {
        self.text.encode_to(output);
        Option::<()>::None.encode_to(output);
    }
}

impl Decode for RequestRichText {
    fn decode<I: Input>(input: &mut I) -> Result<Self, CodecError> {
        let text = Option::<String>::decode(input)?;
        let attachment_option = u8::decode(input)?;
        if attachment_option != 0 {
            return Err("chat-request attachments are unsupported".into());
        }
        Ok(Self { text })
    }
}

#[derive(Encode, Decode)]
struct EncryptedRemoteModel {
    encryption_public_key: Vec<u8>,
    encrypted_data: Vec<u8>,
}

#[derive(Encode, Decode)]
struct RemoteModel {
    message: RequestMessage,
    proof: StatementProof,
}

#[derive(Encode)]
struct ProofPayload {
    message: RequestMessage,
    request_acceptor_id: Vec<u8>,
}

#[derive(Encode, Decode)]
struct RemoteMessage {
    message_id: String,
    timestamp: u64,
    content: VersionedRemoteMessage,
}

#[derive(Encode, Decode)]
enum VersionedRemoteMessage {
    #[codec(index = 0)]
    V1(RemoteMessageV1),
}

#[derive(Encode, Decode)]
struct RemoteMessageV1 {
    content: RemoteMessageContent,
}

#[derive(Encode, Decode)]
enum RemoteMessageContent {
    #[codec(index = 14)]
    ChatAccepted(ChatAccepted),
}

#[derive(Encode, Decode)]
struct ChatAccepted {
    message_id: String,
}

#[cfg(test)]
mod tests {
    use super::super::sso::pairing::{
        decrypt_session_statement_data, encrypt_session_statement_data_with_nonce,
    };
    use super::super::statement_store::decode_verified_statement_data;
    use super::*;

    const OWN_ENTROPY: [u8; 16] = [0x11; 16];
    const PEER_ENTROPY: [u8; 16] = [0x22; 16];

    fn encrypt_request(
        own: &ChatIdentity,
        peer: &ChatIdentity,
        peer_device: &schnorrkel::Keypair,
        request_id: &str,
    ) -> Vec<u8> {
        let shared_secret =
            p256_shared_secret(peer.encryption_secret, own.encryption_public_key).unwrap();
        let mut identity_payload = Vec::new();
        identity_payload.extend(peer.statement_account_id);
        identity_payload.extend(peer_device.public.to_bytes());
        identity_payload.extend(MULTI_DEVICE_IDENTITY_CONTEXT.encode());
        let identity_proof = keyed_blake2b256(&identity_payload, &shared_secret);
        let message = RequestMessage {
            message_id: request_id.to_string(),
            timestamp: 1_800_000_000_123,
            content: VersionedRequestContent::V2(RequestContentV2 {
                identity_proof: IdentityProof {
                    identity_account_id: peer.statement_account_id,
                    proof: identity_proof,
                },
                device_encryption_public_key: peer.encryption_public_key,
                push_token: Some(RemoteTokenContent {
                    token: vec![1, 2, 3],
                    push_type: 1,
                }),
                welcome_message: Some(RequestRichText {
                    text: Some("hello from iOS".to_string()),
                }),
            }),
        };
        let proof_payload = ProofPayload {
            message: message.clone(),
            request_acceptor_id: own.statement_account_id.to_vec(),
        }
        .encode();
        let signature = peer_device
            .secret
            .sign_simple(
                STATEMENT_SIGNING_CONTEXT,
                &proof_payload,
                &peer_device.public,
            )
            .to_bytes();
        let remote = RemoteModel {
            message,
            proof: StatementProof::Sr25519 {
                signature,
                signer: peer_device.public.to_bytes(),
            },
        }
        .encode();
        let nonce = [0x33; AES_GCM_NONCE_LEN];
        let key = aes_key(shared_secret).unwrap();
        let mut encrypted = nonce.to_vec();
        encrypted.extend(
            Aes256Gcm::new_from_slice(&key)
                .unwrap()
                .encrypt(Nonce::from_slice(&nonce), remote.as_slice())
                .unwrap(),
        );
        EncryptedRemoteModel {
            encryption_public_key: peer.encryption_public_key.to_vec(),
            encrypted_data: encrypted,
        }
        .encode()
    }

    #[test]
    fn decodes_and_validates_ios_v2_chat_request() {
        let own = derive_chat_identity(&OWN_ENTROPY, ChatIdentityDerivation::Sso).unwrap();
        let peer = derive_chat_identity(&PEER_ENTROPY, ChatIdentityDerivation::Sso).unwrap();
        let peer_device = derive_sr25519_hard_path(&PEER_ENTROPY, &["wallet", "device"]).unwrap();
        let encoded = encrypt_request(&own, &peer, &peer_device, "request-123");

        let request = decode_incoming_chat_request(&encoded, &own).unwrap();
        validate_peer_identity(&request, &own, peer.encryption_public_key).unwrap();

        assert_eq!(request.request_id, "request-123");
        assert_eq!(request.peer_account_id, peer.statement_account_id);
        assert_eq!(
            request.peer_statement_account_id,
            peer_device.public.to_bytes()
        );
    }

    #[test]
    fn builds_identity_lane_chat_accepted_message() {
        let own = derive_chat_identity(&OWN_ENTROPY, ChatIdentityDerivation::Sso).unwrap();
        let peer = derive_chat_identity(&PEER_ENTROPY, ChatIdentityDerivation::Sso).unwrap();
        let request = IncomingChatRequest {
            request_id: "request-123".to_string(),
            timestamp_ms: 1_800_000_000_123,
            peer_account_id: peer.statement_account_id,
            peer_statement_account_id: peer.statement_account_id,
            identity_proof: None,
        };
        let statement = build_chat_acceptance_statement(
            &own,
            &request,
            peer.encryption_public_key,
            "message-456".to_string(),
            "transport-789".to_string(),
            1_800_000_001_000,
            chat_statement_priority(1_800_000_001),
        )
        .unwrap();
        let verified =
            decode_verified_statement_data(&statement, Some(own.statement_account_id)).unwrap();
        let peer_identity = ResponderIdentity {
            statement_secret: peer.statement_secret,
            statement_public_key: peer.statement_account_id,
            encryption_secret_key: peer.encryption_secret,
            encryption_public_key: peer.encryption_public_key,
        };
        let peer_session = establish_responder_session_info(
            &peer_identity,
            own.statement_account_id,
            own.encryption_public_key,
        )
        .unwrap();
        // iOS `StatementDataCoder` receives the statement field's SCALE
        // `Data` bytes and decodes that prefix exactly once. Rust's
        // `StatementField::Data(Vec<u8>)` supplies that prefix, so the
        // extracted field value must already be the ciphertext rather than
        // another SCALE-wrapped `Vec`.
        let decoded = decrypt_session_statement_data(&peer_session, &verified.data).unwrap();
        let SsoStatementData::Request { request_id, data } = decoded else {
            panic!("acceptance should be a MessageExchange request");
        };
        assert_eq!(request_id, "transport-789");
        let message: RemoteMessage = decode_complete(&data[0], "accepted message").unwrap();
        let VersionedRemoteMessage::V1(RemoteMessageV1 {
            content: RemoteMessageContent::ChatAccepted(accepted),
        }) = message.content;
        assert_eq!(accepted.message_id, "request-123");
        assert_eq!(message.message_id, "message-456");
    }

    #[test]
    fn rejects_v2_request_with_wrong_people_identifier_key() {
        let own = derive_chat_identity(&OWN_ENTROPY, ChatIdentityDerivation::Sso).unwrap();
        let peer = derive_chat_identity(&PEER_ENTROPY, ChatIdentityDerivation::Sso).unwrap();
        let other = derive_chat_identity(&[0x44; 16], ChatIdentityDerivation::Sso).unwrap();
        let peer_device = derive_sr25519_hard_path(&PEER_ENTROPY, &["wallet", "device"]).unwrap();
        let encoded = encrypt_request(&own, &peer, &peer_device, "request-123");
        let request = decode_incoming_chat_request(&encoded, &own).unwrap();

        assert!(matches!(
            validate_peer_identity(&request, &own, other.encryption_public_key),
            Err(ChatRequestError::InvalidIdentityProof)
        ));
    }

    #[test]
    fn chat_priority_matches_ios_epoch_layout() {
        assert_eq!(
            chat_statement_priority(CHAT_PRIORITY_EPOCH + 42),
            0xffff_ffff_0000_002a
        );
    }

    #[test]
    fn chat_request_topic_is_account_scoped() {
        assert_ne!(
            chat_request_discovery_topic([1; 32]),
            chat_request_discovery_topic([2; 32])
        );
        assert_eq!(
            hex::encode(chat_request_discovery_topic([1; 32])),
            "2eff37d3b7fde15ba550f0fc8bc131cc3b12aefafda3e7a614a2cdb3b6df88d0"
        );
    }

    #[test]
    fn request_proof_payload_scale_encodes_account_id_as_data() {
        let payload = ProofPayload {
            message: RequestMessage {
                message_id: "request".to_string(),
                timestamp: 42,
                content: VersionedRequestContent::V1(RequestContentV1 {
                    push_token: None,
                    welcome_message: None,
                }),
            },
            request_acceptor_id: vec![0x55; 32],
        }
        .encode();
        let expected_suffix = [vec![0x80], vec![0x55; 32]].concat();

        assert!(payload.ends_with(&expected_suffix));
    }

    #[test]
    fn main_and_sso_chat_identities_use_distinct_ios_compatible_keys() {
        let main = derive_chat_identity(&OWN_ENTROPY, ChatIdentityDerivation::Main).unwrap();
        let sso = derive_chat_identity(&OWN_ENTROPY, ChatIdentityDerivation::Sso).unwrap();

        assert_ne!(main.statement_account_id, sso.statement_account_id);
        assert_ne!(main.encryption_public_key, sso.encryption_public_key);
        assert_eq!(main.encryption_public_key[0], 0x04);
    }

    #[test]
    fn sso_message_encryption_remains_nonce_compatible() {
        let own = derive_chat_identity(&OWN_ENTROPY, ChatIdentityDerivation::Sso).unwrap();
        let peer = derive_chat_identity(&PEER_ENTROPY, ChatIdentityDerivation::Sso).unwrap();
        let own_identity = ResponderIdentity {
            statement_secret: own.statement_secret,
            statement_public_key: own.statement_account_id,
            encryption_secret_key: own.encryption_secret,
            encryption_public_key: own.encryption_public_key,
        };
        let session = establish_responder_session_info(
            &own_identity,
            peer.statement_account_id,
            peer.encryption_public_key,
        )
        .unwrap();
        let data = SsoStatementData::Request {
            request_id: "request".to_string(),
            data: vec![vec![1, 2, 3]],
        };
        let encrypted =
            encrypt_session_statement_data_with_nonce(&session, &data, [7; AES_GCM_NONCE_LEN])
                .unwrap();
        assert_eq!(&encrypted[..AES_GCM_NONCE_LEN], &[7; AES_GCM_NONCE_LEN]);
    }
}
