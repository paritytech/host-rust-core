//! Lite-person username registration parameters (signing host, native only).
//!
//! Builds the client-side proofs the identity backend needs to
//! attest a lite username for an account: an sr25519 proof-of-ownership, a
//! bandersnatch ring-VRF member key + plain-VRF proof, and an sr25519
//! consumer-registration signature. The backend submits the on-chain
//! `register_lite_person` extrinsic; the host never signs a chain extrinsic.
//!
//! Byte layout mirrors signing-bot `src/core/attestation.ts` for backend
//! parity. The registered account is the account whose secret signs here; the
//! paired host resolves the username from the dotNS contracts on Asset Hub
//! (`host_logic::dotns_gateway`), where the backend's `reserve_name` records it.

use parity_scale_codec::{Decode, Encode};
use sha2::{Digest, Sha256};
use thiserror::Error;
use verifiable::Error as VerifiableError;
use verifiable::GenerateVerifiable;
use verifiable::ring::bandersnatch::BandersnatchVrfVerifiable;

use crate::host_logic::dotns_gateway::build_reservation_message;
use crate::host_logic::product_account::{
    ProductAccountError, SR25519_SIGNING_CONTEXT, derive_identity_keypair,
    derive_lite_person_ring_vrf_entropy, product_public_key_to_address,
};

/// sr25519 proof-of-ownership message prefix (exact bytes; one space).
///
/// Canonical People Lite runtime source:
/// <https://github.com/paritytech/individuality/blob/c3ec60ab934d1a64e4f27d1776a598e839819720/pallets/people-lite/src/lib.rs#L69>
///
/// The pallet verifies `MSG_PREFIX || candidate || ring_vrf_key`.
const REGISTER_PREFIX: &[u8] = b"pop:people-lite:register using";
/// SHA-256 digest of the UTF-8 encoding of `'{}'`, used as the auth-stamp
/// component of the identity-auth proof message. This is a fixed value
/// computed once so the digest does not need to be repeated at call time.
const AUTH_STAMP_HASH: [u8; 32] = [
    0x44, 0x13, 0x6f, 0xa3, 0x55, 0xb3, 0x67, 0x8a, 0x11, 0x46, 0xad, 0x16, 0xf7, 0xe8, 0x64, 0x9e,
    0x94, 0xfb, 0x4f, 0xc2, 0x1f, 0xe7, 0x7e, 0x83, 0x10, 0xc0, 0x60, 0xf6, 0x1c, 0xaa, 0xff, 0x8a,
];

/// SCALE payload signed for a lite consumer registration.
///
/// This mirrors the People runtime's tuple of account, verifier, identifier
/// key, username base, and optional reserved username.
#[derive(Debug, Clone, PartialEq, Eq, Encode, Decode)]
struct ConsumerRegistrationSigningPayload {
    account: [u8; 32],
    verifier: [u8; 32],
    identifier_key: [u8; 65],
    username: Vec<u8>,
    reserved_username: Option<Vec<u8>>,
}

/// Client-computed parameters for `POST /usernames`.
pub struct LiteRegistration {
    /// SS58 (prefix 42) of the candidate account.
    pub candidate_account_id: String,
    /// Raw 32-byte candidate public key (the account the username is recorded for).
    pub candidate_public_key: [u8; 32],
    /// sr25519 signature over `prefix ‖ candidate_pub ‖ ring_vrf_key`.
    pub candidate_signature: [u8; 64],
    /// Bandersnatch ring-VRF member key.
    pub ring_vrf_key: [u8; 32],
    /// Plain bandersnatch VRF proof over the same proof message.
    pub proof_of_ownership: [u8; 64],
    /// 65-byte uncompressed P-256 identifier key. It doubles as the dotNS chat
    /// key.
    pub identifier_key: [u8; 65],
    /// sr25519 signature over the SCALE consumer-registration tuple.
    pub consumer_registration_signature: [u8; 64],
    /// sr25519 signature over the dotNS gateway reservation message. It
    /// authorizes `pallet_dotns_gateway::reserve_name` on Asset Hub.
    pub dotns_signature: [u8; 64],
}

/// Error while building lite-person registration parameters.
#[derive(Debug, Error)]
pub enum LiteRegistrationError {
    /// RFC-0022 `uid.<suffix>` identity-account derivation failed.
    #[error("uid identity derivation failed: {0}")]
    CandidateDerivation(#[from] ProductAccountError),
    /// Ring-VRF proof-of-ownership failed.
    #[error("ring-VRF proof-of-ownership failed: {0:?}")]
    ProofOfOwnership(VerifiableError),
    /// P-256 identifier key derivation failed.
    #[error("identifier key derivation failed")]
    IdentifierKey,
}

/// Build the lite-person registration parameters for `username_base`
/// (6+ lowercase letters, no digit suffix) against the backend `verifier`.
///
/// `network_suffix` is the dotNS TLD of the network being registered on
/// (`paseo`, `testnet`): the candidate account is `uid.<suffix>` and the member
/// key `peopl.<suffix>`, the same person every other host derives there.
/// `reserved_username` optionally queues a base name for a later full-person
/// claim on dotNS. `dotns_signed_at_secs` must be Asset Hub chain time, meaning
/// `Timestamp.Now` in seconds. The local wall clock will not do: the gateway
/// rejects signatures more than 30 seconds in the chain's future.
pub fn build_lite_registration(
    entropy: &[u8],
    network_suffix: &str,
    verifier_account_id: [u8; 32],
    username_base: &str,
    reserved_username: Option<&str>,
    dotns_signed_at_secs: u64,
) -> Result<LiteRegistration, LiteRegistrationError> {
    // Registration, local activation, and the SSO responder all use the
    // RFC-0022 `uid.<suffix>` default product account.
    let candidate = derive_identity_keypair(entropy, network_suffix)?;
    let candidate_public_key = candidate.public.to_bytes();

    let vrf_entropy = derive_lite_person_ring_vrf_entropy(entropy, network_suffix);
    let vrf_secret = BandersnatchVrfVerifiable::new_secret(vrf_entropy);
    let ring_vrf_key = BandersnatchVrfVerifiable::member_from_secret(&vrf_secret);

    let mut proof_message = Vec::with_capacity(REGISTER_PREFIX.len() + 64);
    proof_message.extend_from_slice(REGISTER_PREFIX);
    proof_message.extend_from_slice(&candidate_public_key);
    proof_message.extend_from_slice(&ring_vrf_key);

    let candidate_signature = candidate
        .secret
        .sign_simple(SR25519_SIGNING_CONTEXT, &proof_message, &candidate.public)
        .to_bytes();
    let proof_of_ownership = BandersnatchVrfVerifiable::sign(&vrf_secret, &proof_message)
        .map_err(LiteRegistrationError::ProofOfOwnership)?;

    let identity_secret = candidate.secret.to_bytes();
    let identifier_key = derive_identifier_key(&identity_secret)?;

    let consumer_message = ConsumerRegistrationSigningPayload {
        account: candidate_public_key,
        verifier: verifier_account_id,
        identifier_key,
        username: username_base.as_bytes().to_vec(),
        reserved_username: reserved_username.map(|name| name.as_bytes().to_vec()),
    }
    .encode();
    let consumer_registration_signature = candidate
        .secret
        .sign_simple(
            SR25519_SIGNING_CONTEXT,
            &consumer_message,
            &candidate.public,
        )
        .to_bytes();

    let reservation_message = build_reservation_message(
        &candidate_public_key,
        &verifier_account_id,
        username_base.as_bytes(),
        &identifier_key,
        reserved_username.map(str::as_bytes),
        dotns_signed_at_secs,
    );
    let dotns_signature = candidate
        .secret
        .sign_simple(
            SR25519_SIGNING_CONTEXT,
            &reservation_message,
            &candidate.public,
        )
        .to_bytes();

    Ok(LiteRegistration {
        candidate_account_id: product_public_key_to_address(candidate_public_key),
        candidate_public_key,
        candidate_signature,
        ring_vrf_key,
        proof_of_ownership,
        identifier_key,
        consumer_registration_signature,
        dotns_signature,
    })
}

/// Build an identity-auth proof for `challenge`.
///
/// The proof signs `SHA-256(challenge || identityPublicKey || AUTH_STAMP_HASH)` where
/// `AUTH_STAMP_HASH = SHA-256(UTF8('{}'))`. This is the byte-for-byte equivalent of the
/// signing-bot attestation flow used by the People-chain identity backend.
///
/// `entropy` is the wallet's BIP-39 root entropy; the identity key is derived as
/// `//product//uid.<network_suffix>/index_bytes(0)`, the same account the
/// registration and the SSO responder use on that network.
pub fn build_identity_auth_proof(
    entropy: &[u8],
    network_suffix: &str,
    challenge: &[u8],
) -> Result<[u8; 64], LiteRegistrationError> {
    let candidate = derive_identity_keypair(entropy, network_suffix)?;
    let identity_public_key = candidate.public.to_bytes();

    let mut message = Vec::with_capacity(challenge.len() + 64);
    message.extend_from_slice(challenge);
    message.extend_from_slice(&identity_public_key);
    message.extend_from_slice(&AUTH_STAMP_HASH);
    let digest = Sha256::digest(&message);

    Ok(candidate
        .secret
        .sign_simple(SR25519_SIGNING_CONTEXT, &digest, &candidate.public)
        .to_bytes())
}

fn derive_identifier_key(identity_secret: &[u8]) -> Result<[u8; 65], LiteRegistrationError> {
    use k256::SecretKey;
    use k256::elliptic_curve::sec1::ToEncodedPoint;

    let scalar = blake2b_simd::Params::new()
        .hash_length(32)
        .hash(identity_secret);
    let secret = SecretKey::from_slice(scalar.as_bytes())
        .map_err(|_| LiteRegistrationError::IdentifierKey)?;
    secret
        .public_key()
        .to_encoded_point(false)
        .as_bytes()
        .try_into()
        .map_err(|_| LiteRegistrationError::IdentifierKey)
}

#[cfg(test)]
mod tests {
    use super::*;
    use schnorrkel::{PublicKey, Signature};

    const ENTROPY: [u8; 16] = [0xAB; 16];
    const NETWORK_SUFFIX: &str = "paseo";

    #[test]
    fn registration_params_have_expected_shapes_and_verify() {
        let verifier = [0x11u8; 32];
        let reg = build_lite_registration(
            &ENTROPY,
            NETWORK_SUFFIX,
            verifier,
            "headlesstester",
            None,
            1_749_573_123,
        )
        .unwrap();
        assert_eq!(
            reg.candidate_public_key,
            derive_identity_keypair(&ENTROPY, NETWORK_SUFFIX)
                .unwrap()
                .public
                .to_bytes(),
            "registration uses the network's uid.paseo identity account"
        );
        let lite_entropy = derive_lite_person_ring_vrf_entropy(&ENTROPY, NETWORK_SUFFIX);
        assert_eq!(
            reg.ring_vrf_key,
            BandersnatchVrfVerifiable::member_from_secret(&BandersnatchVrfVerifiable::new_secret(
                lite_entropy
            )),
            "registration uses the network's peopl.paseo index-1 member"
        );
        assert_ne!(
            reg.ring_vrf_key,
            BandersnatchVrfVerifiable::member_from_secret(&BandersnatchVrfVerifiable::new_secret(
                derive_lite_person_ring_vrf_entropy(&ENTROPY, "dot")
            )),
            "a person registered on paseo-next-v2 is not the seed's .dot person"
        );

        assert_eq!(reg.identifier_key[0], 0x04, "secp256k1 uncompressed prefix");
        assert!(
            reg.candidate_account_id
                .chars()
                .all(|c| c.is_alphanumeric())
        );

        // candidateSignature verifies over prefix ‖ candidate_pub ‖ ring_vrf_key.
        let mut proof_message = Vec::new();
        proof_message.extend_from_slice(REGISTER_PREFIX);
        proof_message.extend_from_slice(&reg.candidate_public_key);
        assert!(
            k256::PublicKey::from_sec1_bytes(&reg.identifier_key).is_ok(),
            "identifier key is a valid secp256k1 public key"
        );
        assert!(
            p256::PublicKey::from_sec1_bytes(&reg.identifier_key).is_err(),
            "identifier key must not be emitted on the previous P-256 curve"
        );
        proof_message.extend_from_slice(&reg.ring_vrf_key);
        let public = PublicKey::from_bytes(&reg.candidate_public_key).unwrap();
        let sig = Signature::from_bytes(&reg.candidate_signature).unwrap();
        assert!(
            public
                .verify_simple(SR25519_SIGNING_CONTEXT, &proof_message, &sig)
                .is_ok(),
            "candidate signature verifies"
        );

        // proofOfOwnership verifies as a plain VRF signature for the member key.
        assert!(
            BandersnatchVrfVerifiable::verify_signature(
                &reg.proof_of_ownership,
                &proof_message,
                &reg.ring_vrf_key
            ),
            "ring-VRF proof-of-ownership validates against the member key"
        );

        // Verify against the runtime tuple independently of the production
        // payload struct so field-order or optional-field regressions fail.
        let consumer_message = (
            reg.candidate_public_key,
            verifier,
            reg.identifier_key,
            b"headlesstester".as_slice(),
            None::<Vec<u8>>,
        )
            .encode();
        let sig = Signature::from_bytes(&reg.consumer_registration_signature).unwrap();
        assert!(
            public
                .verify_simple(SR25519_SIGNING_CONTEXT, &consumer_message, &sig)
                .is_ok(),
            "consumer registration signature verifies against the runtime tuple"
        );

        // dotnsSignature verifies over the gateway reservation message. The
        // identifier key doubles as the chat key.
        let reservation_message = build_reservation_message(
            &reg.candidate_public_key,
            &verifier,
            b"headlesstester",
            &reg.identifier_key,
            None,
            1_749_573_123,
        );
        let sig = Signature::from_bytes(&reg.dotns_signature).unwrap();
        assert!(
            public
                .verify_simple(SR25519_SIGNING_CONTEXT, &reservation_message, &sig)
                .is_ok(),
            "dotns reservation signature verifies against the gateway message"
        );
    }

    #[test]
    fn reserved_username_threads_into_both_signed_payloads() {
        let verifier = [0x33u8; 32];
        let reg = build_lite_registration(
            &ENTROPY,
            NETWORK_SUFFIX,
            verifier,
            "headlesstester",
            Some("reservedbase"),
            77,
        )
        .unwrap();
        let public = PublicKey::from_bytes(&reg.candidate_public_key).unwrap();

        let consumer_message = (
            reg.candidate_public_key,
            verifier,
            reg.identifier_key,
            b"headlesstester".as_slice(),
            Some(b"reservedbase".to_vec()),
        )
            .encode();
        let sig = Signature::from_bytes(&reg.consumer_registration_signature).unwrap();
        assert!(
            public
                .verify_simple(SR25519_SIGNING_CONTEXT, &consumer_message, &sig)
                .is_ok(),
            "consumer registration signature commits to the reserved username"
        );

        let reservation_message = build_reservation_message(
            &reg.candidate_public_key,
            &verifier,
            b"headlesstester",
            &reg.identifier_key,
            Some(b"reservedbase"),
            77,
        );
        let sig = Signature::from_bytes(&reg.dotns_signature).unwrap();
        assert!(
            public
                .verify_simple(SR25519_SIGNING_CONTEXT, &reservation_message, &sig)
                .is_ok(),
            "dotns signature commits to the reserved username and signed_at"
        );
    }

    #[test]
    fn consumer_registration_payload_matches_runtime_tuple_codec() {
        let payload = ConsumerRegistrationSigningPayload {
            account: [0x11; 32],
            verifier: [0x22; 32],
            identifier_key: [0x04; 65],
            username: b"headlesstester".to_vec(),
            reserved_username: None,
        };
        let encoded = payload.encode();
        let runtime_tuple = (
            payload.account,
            payload.verifier,
            payload.identifier_key,
            payload.username.as_slice(),
            payload.reserved_username.as_ref(),
        )
            .encode();

        assert_eq!(encoded, runtime_tuple);
        assert_eq!(
            ConsumerRegistrationSigningPayload::decode(&mut encoded.as_slice()).unwrap(),
            payload
        );
    }

    #[test]
    fn registration_is_deterministic_per_entropy_and_username() {
        let verifier = [0x22u8; 32];
        let first =
            build_lite_registration(&ENTROPY, NETWORK_SUFFIX, verifier, "aliceheadless", None, 1)
                .unwrap();
        let again =
            build_lite_registration(&ENTROPY, NETWORK_SUFFIX, verifier, "aliceheadless", None, 1)
                .unwrap();
        assert_eq!(first.candidate_public_key, again.candidate_public_key);
        assert_eq!(first.ring_vrf_key, again.ring_vrf_key);
        assert_eq!(first.candidate_account_id, again.candidate_account_id);
    }

    #[test]
    fn auth_proof_signs_the_canonical_sha256_digest() {
        let challenge = b"hello world";
        let proof = build_identity_auth_proof(&ENTROPY, NETWORK_SUFFIX, challenge).unwrap();
        let identity_keypair = derive_identity_keypair(&ENTROPY, NETWORK_SUFFIX).unwrap();
        let identity_public_key = identity_keypair.public.to_bytes();
        let mut message = Vec::new();
        message.extend_from_slice(challenge);
        message.extend_from_slice(&identity_public_key);
        message.extend_from_slice(&AUTH_STAMP_HASH);
        let digest = Sha256::digest(&message);
        let signature = Signature::from_bytes(&proof).unwrap();

        assert!(
            identity_keypair
                .public
                .verify_simple(SR25519_SIGNING_CONTEXT, &digest, &signature)
                .is_ok()
        );
        assert!(
            identity_keypair
                .public
                .verify_simple(SR25519_SIGNING_CONTEXT, &message, &signature)
                .is_err(),
            "the backend contract signs the outer SHA-256 digest, not the concatenated bytes"
        );
    }

    #[test]
    fn auth_proof_differs_for_different_challenges() {
        let proof_a = build_identity_auth_proof(&ENTROPY, NETWORK_SUFFIX, b"challenge A").unwrap();
        let proof_b = build_identity_auth_proof(&ENTROPY, NETWORK_SUFFIX, b"challenge B").unwrap();
        assert_ne!(proof_a, proof_b);
    }

    #[test]
    fn auth_proof_fails_for_invalid_entropy() {
        let bad_entropy = [];
        let result = build_identity_auth_proof(&bad_entropy, NETWORK_SUFFIX, b"challenge");
        assert!(result.is_err(), "auth proof rejects empty entropy");
    }
}
