//! The handshake that turns a personhood proof into a backend session.
//!
//! Two calls, and the product is party to neither: the core asks the backend
//! for a challenge, proves the person against it, and receives a short-lived
//! token it holds and attaches. Everything here is the wire of those two
//! calls — building the requests and reading the answers — with no state and
//! no chain access, so it can be tested against the shapes a backend actually
//! sends.
//!
//! The shapes are the reference implementation's
//! ([`onramp-adapter-service-community`]): a challenge is 56 opaque bytes in
//! base64url, and a redemption names the challenge it answers, the proof, the
//! ring index the proof opened against, and the product the session is for.
//!
//! [`onramp-adapter-service-community`]: https://github.com/paritytech/onramp-adapter-service-community

use base64::Engine as _;
use base64::engine::general_purpose::URL_SAFE_NO_PAD;
use serde::Deserialize;
use truapi::latest::{BackendBody, BackendHttpMethod, HostBackendRequest};

/// Path that mints a fresh challenge. Unauthenticated, rate-limited by the
/// backend on the only key it has before a proof.
pub const CHALLENGE_PATH: &str = "/api/v1/auth/challenge";

/// Path that exchanges a challenge and a proof for a session token.
pub const REDEEM_PATH: &str = "/api/v1/auth/redeem";

/// Path that renews a session without a fresh proof.
///
/// The session being renewed travels in `Authorization`, so the request itself
/// carries nothing: the backend reads the credential it already issued and
/// answers with a later one. A backend that does not serve this path costs one
/// refused call and the handshake runs instead.
pub const REFRESH_PATH: &str = "/api/v1/auth/refresh";

/// Longest handshake answer the core reads. A challenge and a JWT are small,
/// and the tunnel's own megabyte is far more room than either needs.
const MAX_HANDSHAKE_BODY_BYTES: usize = 8192;

/// A handshake that did not produce a session.
#[derive(Debug, Clone, PartialEq, Eq, thiserror::Error)]
pub enum SessionError {
    /// The backend answered, but not with what this handshake expects. Either
    /// it serves no handshake at this path or it serves a different one.
    #[error("backend handshake answered with {reason}")]
    Malformed {
        /// What was wrong with the answer.
        reason: String,
    },
}

fn malformed(reason: impl Into<String>) -> SessionError {
    SessionError::Malformed {
        reason: reason.into(),
    }
}

/// The context a personhood proof for a backend is bound to: the product id,
/// as its UTF-8 bytes.
///
/// It is the product and not the backend because the backend already knows
/// which backend it is, and it is the alias's namespace: one person reaches
/// two products as two unlinkable aliases, and the same person reaching one
/// product twice is recognisably the same customer. It is not the protocol's
/// 32-byte product-scoped context, because the verifier passes these bytes
/// into the ring-VRF check verbatim and the reference backend computes them
/// this way.
pub fn proof_context(product_id: &str) -> Vec<u8> {
    product_id.as_bytes().to_vec()
}

/// A challenge, as received and as the proof will bind it.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Challenge {
    /// The token exactly as the backend spelled it, to be echoed on redeem.
    pub encoded: String,
    /// Its bytes, which the proof is minted over.
    pub bytes: Vec<u8>,
}

/// A session the core holds until it expires or is refused.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Session {
    /// Bearer credential for the backend's authenticated routes.
    pub token: String,
    /// When the backend says it stops accepting the token, in milliseconds
    /// since the epoch.
    pub expires_at_ms: u64,
}

/// Ask a backend for a fresh challenge.
pub fn challenge_request(backend: &str) -> HostBackendRequest {
    HostBackendRequest {
        backend: backend.to_owned(),
        method: BackendHttpMethod::Post,
        path: CHALLENGE_PATH.to_owned(),
        query: Vec::new(),
        body: None,
    }
}

/// Offer a proof against a challenge, for one product.
pub fn redeem_request(
    backend: &str,
    challenge: &Challenge,
    proof: &[u8],
    ring: u32,
    product_id: &str,
) -> HostBackendRequest {
    let body = serde_json::json!({
        "challenge": challenge.encoded,
        "proof": URL_SAFE_NO_PAD.encode(proof),
        "ring": ring,
        "productId": product_id,
    });
    HostBackendRequest {
        backend: backend.to_owned(),
        method: BackendHttpMethod::Post,
        path: REDEEM_PATH.to_owned(),
        query: Vec::new(),
        body: Some(BackendBody::Json {
            // A `serde_json::Value` of strings and a number always serializes.
            bytes: serde_json::to_vec(&body).unwrap_or_default(),
        }),
    }
}

/// Ask a backend to renew the session it already issued.
///
/// The body is empty because the credential is the request: the backend reads
/// `Authorization`, which the host writes from the session the core passes
/// beside this.
pub fn refresh_request(backend: &str) -> HostBackendRequest {
    HostBackendRequest {
        backend: backend.to_owned(),
        method: BackendHttpMethod::Post,
        path: REFRESH_PATH.to_owned(),
        query: Vec::new(),
        body: None,
    }
}

#[derive(Deserialize)]
struct ChallengeBody {
    challenge: String,
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
struct SessionBody {
    token: String,
    expires_at_ms: u64,
}

/// Read a challenge out of what the backend answered.
pub fn parse_challenge(body: &[u8]) -> Result<Challenge, SessionError> {
    let parsed: ChallengeBody = parse(body)?;
    // Base64url, and padded or not: `Buffer.toString('base64url')` drops the
    // padding and `Buffer.from(_, 'base64url')` accepts it either way, so a
    // backend may send either and both name the same bytes.
    let bytes = URL_SAFE_NO_PAD
        .decode(parsed.challenge.trim_end_matches('='))
        .map_err(|_| malformed("a challenge that is not base64url"))?;
    if bytes.is_empty() {
        return Err(malformed("an empty challenge"));
    }
    Ok(Challenge {
        encoded: parsed.challenge,
        bytes,
    })
}

/// Read a session out of what the backend answered.
pub fn parse_session(body: &[u8]) -> Result<Session, SessionError> {
    let parsed: SessionBody = parse(body)?;
    if parsed.token.is_empty() {
        return Err(malformed("an empty token"));
    }
    Ok(Session {
        token: parsed.token,
        expires_at_ms: parsed.expires_at_ms,
    })
}

fn parse<T: serde::de::DeserializeOwned>(body: &[u8]) -> Result<T, SessionError> {
    if body.len() > MAX_HANDSHAKE_BODY_BYTES {
        return Err(malformed("a body too large to be a handshake answer"));
    }
    serde_json::from_slice(body).map_err(|err| malformed(err.to_string()))
}

#[cfg(test)]
mod tests {
    use super::*;

    /// The reference backend's own encoding: `Buffer.toString('base64url')`
    /// over 56 bytes, unpadded.
    const CHALLENGE: &str =
        "AAECAwQFBgcICQoLDA0ODxAREhMUFRYXGBkaGxwdHh8gISIjJCUmJygpKissLS4vMDEyMw";

    #[test]
    fn a_challenge_round_trips_from_the_shape_the_backend_sends() {
        let body = format!(r#"{{"challenge":"{CHALLENGE}"}}"#);
        let challenge = parse_challenge(body.as_bytes()).expect("a challenge");
        assert_eq!(challenge.encoded, CHALLENGE);
        assert_eq!(challenge.bytes.len(), 52);
        assert_eq!(challenge.bytes[0], 0);
    }

    #[test]
    fn a_padded_challenge_names_the_same_bytes() {
        let unpadded = parse_challenge(br#"{"challenge":"AAEC"}"#).expect("a challenge");
        let padded = parse_challenge(br#"{"challenge":"AAEC="}"#).expect("a challenge");
        assert_eq!(unpadded.bytes, padded.bytes);
    }

    #[test]
    fn an_answer_that_is_not_this_handshake_is_refused_rather_than_guessed_at() {
        for body in [
            &b"not json"[..],
            br#"{}"#,
            br#"{"challenge":""}"#,
            br#"{"challenge":"not base64!"}"#,
            br#"{"challenge":42}"#,
            // A 404 page, which is what a backend serving no handshake sends.
            br#"<!doctype html>"#,
        ] {
            assert!(
                matches!(parse_challenge(body), Err(SessionError::Malformed { .. })),
                "body {:?} was read as a challenge",
                String::from_utf8_lossy(body)
            );
        }
    }

    #[test]
    fn a_redeem_carries_the_four_fields_the_backend_reads() {
        let challenge = Challenge {
            encoded: CHALLENGE.to_owned(),
            bytes: vec![1, 2, 3],
        };
        let request = redeem_request("fiat-onramp", &challenge, &[0xff, 0x00], 7, "onramp.dot");

        assert_eq!(request.path, REDEEM_PATH);
        assert_eq!(request.method, BackendHttpMethod::Post);
        let Some(BackendBody::Json { bytes }) = request.body else {
            panic!("a redeem carries a JSON body");
        };
        let sent: serde_json::Value = serde_json::from_slice(&bytes).expect("valid JSON");
        assert_eq!(sent["challenge"], CHALLENGE);
        // base64url, unpadded: `/w` and not `/w==`, and never `+` or `/`.
        assert_eq!(sent["proof"], "_wA");
        assert_eq!(sent["ring"], 7);
        assert_eq!(sent["productId"], "onramp.dot");
    }

    #[test]
    fn a_session_is_read_from_the_shape_the_backend_sends() {
        let session = parse_session(br#"{"token":"eyJ.a.b","expiresAtMs":1800000000000}"#)
            .expect("a session");
        assert_eq!(session.token, "eyJ.a.b");
        assert_eq!(session.expires_at_ms, 1_800_000_000_000);
    }

    #[test]
    fn a_session_answer_missing_its_token_or_expiry_is_not_a_session() {
        for body in [
            &br#"{"token":"eyJ"}"#[..],
            br#"{"expiresAtMs":1}"#,
            br#"{"token":"","expiresAtMs":1}"#,
            br#"{"token":"eyJ","expiresAtMs":-1}"#,
        ] {
            assert!(
                matches!(parse_session(body), Err(SessionError::Malformed { .. })),
                "body {:?} was read as a session",
                String::from_utf8_lossy(body)
            );
        }
    }

    #[test]
    fn the_proof_context_is_the_product_id_as_the_backend_computes_it() {
        assert_eq!(proof_context("onramp.dot"), b"onramp.dot".to_vec());
    }

    #[test]
    fn a_challenge_request_carries_no_body_and_names_the_backend() {
        let request = challenge_request("fiat-onramp");
        assert_eq!(request.backend, "fiat-onramp");
        assert_eq!(request.path, CHALLENGE_PATH);
        assert!(request.body.is_none());
        assert_eq!(crate::host_logic::backend::screen_request(&request), Ok(()));
    }
}
