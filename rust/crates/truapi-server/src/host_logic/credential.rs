//! Credential-endpoint grants and the caller identity the host attaches to
//! every request one covers (RFC 0025).
//!
//! A grant names one `(domain, path, method)` triple. For each covered request
//! the host derives an sr25519 key scoped to that triple, signs a digest of the
//! request, and attaches the public key and signature. A consuming backend
//! verifies the signature and rate limits on the public key, which is stable
//! for one wallet calling one endpoint of one product and unrelated everywhere
//! else.
//!
//! Everything here is pure. The session secret arrives from the caller and the
//! clock and randomness are inputs, so the digest and the derivation are
//! reproducible from a test vector.

use schnorrkel::{ExpansionMode, Keypair, MiniSecretKey};
use thiserror::Error;
use truapi::latest::RemotePermission;
use url::Url;

use crate::host_logic::entropy::blake2b256_keyed;
use crate::host_logic::product_account::SR25519_SIGNING_CONTEXT;

/// Separates the credential key tree from RFC-0007 product entropy.
///
/// It keys the product-id layer, not the caller-supplied layer, so no argument
/// a product can pass to `host_derive_entropy` reaches this tree. Separating at
/// the caller layer instead would leave the product able to derive its own
/// credential keys and sign covered requests without a grant.
const CREDENTIAL_DOMAIN_SEPARATOR: &[u8] = b"credential-endpoint-derivation";

/// Labels the request digest, so a credential signature cannot be replayed as
/// any other signature this key tree produces.
const REQUEST_DIGEST_LABEL: &[u8] = b"truapi/credential-request/v1";

/// Public key identifying the caller. A backend rate limits on this value.
pub const HEADER_KEY: &str = "X-Polkadot-Key";
/// sr25519 signature over the request digest.
pub const HEADER_SIGNATURE: &str = "X-Polkadot-Signature";
/// Unix seconds the signature was made at.
pub const HEADER_TIMESTAMP: &str = "X-Polkadot-Timestamp";
/// Random bytes, fresh per request.
pub const HEADER_NONCE: &str = "X-Polkadot-Nonce";

/// Prefix the host reserves. A caller-supplied header matching it is stripped
/// before the host attaches its own, so a product cannot present an identity of
/// its choosing.
pub const HEADER_PREFIX: &str = "x-polkadot-";

/// Why a request is not covered by a credential grant.
#[derive(Debug, Error, PartialEq, Eq)]
pub enum CredentialError {
    /// The URL does not parse, or carries no host.
    #[error("request URL is not a valid absolute URL")]
    InvalidUrl,
    /// Covered requests must be `https`: the signature would otherwise travel
    /// in plaintext, and a proxy could lift it onto another request.
    #[error("credential grants cover https only")]
    NotHttps,
    /// A grant names one exact endpoint. A wildcard would ask the user to
    /// reason about a set, which is what domain grants already do badly.
    #[error("credential grants take no wildcards")]
    Wildcard,
    /// A grant is keyed by domain, so a port or userinfo in the URL would be
    /// dropped and two distinct origins would share one grant.
    #[error("credential grants cover the default https port, without userinfo")]
    NotDefaultOrigin,
}

/// Why a host cannot attach an identity to an outbound request.
#[derive(Debug, Error, PartialEq, Eq)]
#[cfg_attr(not(target_arch = "wasm32"), derive(uniffi::Error))]
pub enum CredentialRequestError {
    /// The URL does not parse, carries no host, is not `https`, or names a
    /// wildcard.
    #[error("{reason}")]
    NotCovered {
        /// Which of those it is.
        reason: String,
    },
    /// No credential grant covers this endpoint. The product asks for one
    /// through `request_remote_permission`; the host never prompts mid-request.
    #[error("no credential grant covers this endpoint")]
    NotGranted,
    /// No session, so there is no wallet to derive an identity from.
    #[error("no active session")]
    NotConnected,
    /// The identity could not be derived.
    #[error("{reason}")]
    Unknown {
        /// What went wrong.
        reason: String,
    },
}

impl From<CredentialError> for CredentialRequestError {
    fn from(err: CredentialError) -> Self {
        Self::NotCovered {
            reason: err.to_string(),
        }
    }
}

/// One header the host sets on the outgoing request.
///
/// The core hands hosts finished name/value pairs rather than raw bytes, so
/// every host presents the identity identically. A backend verifies bytes it
/// decodes from these strings; two hosts encoding them differently would make
/// the same wallet verify on one platform and fail on another.
#[derive(Debug, Clone, PartialEq, Eq)]
#[cfg_attr(not(target_arch = "wasm32"), derive(uniffi::Record))]
pub struct CredentialHeader {
    /// Header name.
    pub name: String,
    /// Header value. Byte strings are lower-case hex behind `0x`.
    pub value: String,
}

/// The identity a host attaches to one covered request.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct CredentialRequestHeaders {
    /// `X-Polkadot-Key`: the sr25519 public key a backend rate limits on.
    pub key: Vec<u8>,
    /// `X-Polkadot-Signature`: sr25519 signature over the request digest.
    pub signature: Vec<u8>,
    /// `X-Polkadot-Timestamp`: Unix seconds the signature was made at.
    pub timestamp: u64,
    /// `X-Polkadot-Nonce`: random bytes, fresh per request.
    pub nonce: Vec<u8>,
}

impl CredentialRequestHeaders {
    /// The headers to set on the request, in the one encoding every host uses.
    pub fn to_headers(&self) -> Vec<CredentialHeader> {
        [
            (HEADER_KEY, hex_value(&self.key)),
            (HEADER_SIGNATURE, hex_value(&self.signature)),
            (HEADER_TIMESTAMP, self.timestamp.to_string()),
            (HEADER_NONCE, hex_value(&self.nonce)),
        ]
        .into_iter()
        .map(|(name, value)| CredentialHeader {
            name: name.to_string(),
            value,
        })
        .collect()
    }
}

fn hex_value(bytes: &[u8]) -> String {
    format!("0x{}", hex::encode(bytes))
}

/// One `(domain, path, method)` triple in the canonical form the permission key
/// is built from: domain lower-cased, method upper-cased, path verbatim.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct CredentialGrant {
    /// Domain the grant covers.
    pub domain: String,
    /// Exact path the grant covers.
    pub path: String,
    /// HTTP method the grant covers.
    pub method: String,
}

impl CredentialGrant {
    /// The grant covering an outbound request, and the request's query string.
    ///
    /// The query is not part of the grant — a grant names an endpoint, not one
    /// call to it — but it is covered by the signature, so it is returned
    /// alongside rather than discarded.
    pub fn from_request(method: &str, url: &str) -> Result<(Self, String), CredentialError> {
        Self::from_url(
            &Url::parse(url).map_err(|_| CredentialError::InvalidUrl)?,
            method,
        )
    }

    /// Canonicalize a triple as a product asked for it.
    ///
    /// Goes through the same URL parse a live request does, so a grant and the
    /// request it is meant to cover cannot disagree on spelling: a path is
    /// percent-encoded and dot-resolved on both sides, and a port or userinfo
    /// is refused on both rather than accepted here and refused there.
    pub fn new(domain: &str, path: &str, method: &str) -> Result<Self, CredentialError> {
        if domain.contains('*') || path.contains('*') {
            return Err(CredentialError::Wildcard);
        }
        let separator = if path.starts_with('/') { "" } else { "/" };
        let url = Url::parse(&format!("https://{domain}{separator}{path}"))
            .map_err(|_| CredentialError::InvalidUrl)?;
        Self::from_url(&url, method).map(|(grant, _)| grant)
    }

    /// The grant an `https` URL names, and its query string.
    fn from_url(url: &Url, method: &str) -> Result<(Self, String), CredentialError> {
        if url.scheme() != "https" {
            return Err(CredentialError::NotHttps);
        }
        // A grant is keyed by domain alone. Accepting a port or userinfo here
        // would drop it and let `https://example.com:8443/session` be covered
        // by a grant the user gave for `https://example.com/session`, which is
        // a different origin. Refuse rather than silently widen the grant.
        if url.port().is_some() || !url.username().is_empty() || url.password().is_some() {
            return Err(CredentialError::NotDefaultOrigin);
        }
        let domain = url.host_str().ok_or(CredentialError::InvalidUrl)?;
        let grant = Self {
            domain: domain.to_ascii_lowercase(),
            path: url.path().to_string(),
            method: method.to_ascii_uppercase(),
        };
        Ok((grant, url.query().unwrap_or_default().to_string()))
    }

    /// The permission this grant is stored and prompted under.
    pub fn permission(&self) -> RemotePermission {
        RemotePermission::Credential {
            domain: self.domain.clone(),
            path: self.path.clone(),
            method: self.method.clone(),
        }
    }

    /// The triple as one 32-byte value, keying the endpoint's slot in the
    /// product's credential key tree.
    pub fn digest(&self) -> [u8; 32] {
        let mut preimage = Vec::new();
        push_field(&mut preimage, self.method.as_bytes());
        push_field(&mut preimage, self.domain.as_bytes());
        push_field(&mut preimage, self.path.as_bytes());
        blake2b256_keyed(&preimage, &[])
    }
}

/// The digest a covered request is signed over.
///
/// Query and body are covered so a signature cannot authorize different
/// content, and the timestamp and nonce bound how long a captured signature
/// stays useful. Every field is length-prefixed with a big-endian `u32`, so no
/// two distinct requests share a preimage by running one field into the next.
pub fn request_digest(
    grant: &CredentialGrant,
    query: &str,
    timestamp: u64,
    nonce: &[u8],
    body_hash: &[u8; 32],
) -> [u8; 32] {
    let mut preimage = Vec::new();
    preimage.extend_from_slice(REQUEST_DIGEST_LABEL);
    push_field(&mut preimage, grant.method.as_bytes());
    push_field(&mut preimage, grant.domain.as_bytes());
    push_field(&mut preimage, grant.path.as_bytes());
    push_field(&mut preimage, query.as_bytes());
    preimage.extend_from_slice(&timestamp.to_be_bytes());
    push_field(&mut preimage, nonce);
    preimage.extend_from_slice(body_hash);
    blake2b256_keyed(&preimage, &[])
}

/// Hash of a request body, for [`request_digest`]. An empty body hashes like
/// any other, so a body cannot be added or removed without changing the digest.
pub fn body_hash(body: &[u8]) -> [u8; 32] {
    blake2b256_keyed(body, &[])
}

/// The signing key for one product calling one endpoint.
///
/// Derived from the session's pre-hashed root entropy source, which both a
/// signing host and a paired host hold, so either derives the same key locally
/// without consulting the other. Unreachable through `host_derive_entropy`: see
/// [`CREDENTIAL_DOMAIN_SEPARATOR`].
pub fn credential_keypair(
    root_entropy_source: &[u8; 32],
    product_id: &str,
    grant: &CredentialGrant,
) -> Keypair {
    MiniSecretKey::from_bytes(&credential_seed(root_entropy_source, product_id, grant))
        .expect("blake2b256 yields 32 bytes, which is a valid MiniSecretKey; qed")
        .expand_to_keypair(ExpansionMode::Ed25519)
}

/// The seed [`credential_keypair`] expands.
///
/// Separate from the keypair because this, not the expanded secret, is the
/// value that must stay out of a product's reach: anyone holding it can
/// reproduce the keypair. Tests comparing against product-reachable entropy
/// have to compare against this.
pub fn credential_seed(
    root_entropy_source: &[u8; 32],
    product_id: &str,
    grant: &CredentialGrant,
) -> [u8; 32] {
    let product_id_hash = blake2b256_keyed(product_id.as_bytes(), CREDENTIAL_DOMAIN_SEPARATOR);
    let per_product = blake2b256_keyed(root_entropy_source, &product_id_hash);
    blake2b256_keyed(&per_product, &grant.digest())
}

/// Sign a request digest under a credential key.
pub fn sign_request(keypair: &Keypair, digest: &[u8; 32]) -> [u8; 64] {
    keypair
        .secret
        .sign_simple(SR25519_SIGNING_CONTEXT, digest, &keypair.public)
        .to_bytes()
}

/// Whether the host reserves this header name, and so must drop it from a
/// product's request before attaching its own identity.
///
/// A product that could set `X-Polkadot-Key` itself would present whatever
/// identity it liked to the backend.
pub fn is_reserved_header(name: &str) -> bool {
    name.to_ascii_lowercase().starts_with(HEADER_PREFIX)
}

/// Append a byte string to a preimage, length-prefixed.
///
/// The prefix is what keeps one field from running into the next, so a length
/// that does not fit is a contradiction rather than something to clamp: at
/// `u32::MAX` two different splits would share a preimage.
fn push_field(preimage: &mut Vec<u8>, field: &[u8]) {
    let len =
        u32::try_from(field.len()).expect("a URL component or nonce never reaches 4 GiB; qed");
    preimage.extend_from_slice(&len.to_be_bytes());
    preimage.extend_from_slice(field);
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::host_logic::entropy::derive_product_entropy_from_source;

    const SOURCE: [u8; 32] = [0x11; 32];

    fn grant() -> CredentialGrant {
        CredentialGrant::new("onramp.example.com", "/session", "POST").expect("canonical triple")
    }

    #[test]
    fn a_request_resolves_to_its_grant_and_query() {
        let (grant, query) = CredentialGrant::from_request(
            "post",
            "https://Onramp.Example.com/session?currency=EUR&amount=10",
        )
        .expect("covered request");

        assert_eq!(grant.domain, "onramp.example.com", "domain canonicalizes");
        assert_eq!(grant.method, "POST", "method canonicalizes");
        assert_eq!(grant.path, "/session", "path is verbatim");
        assert_eq!(
            query, "currency=EUR&amount=10",
            "query is kept, not granted"
        );
    }

    #[test]
    fn a_grant_covers_https_only_and_takes_no_wildcards() {
        assert_eq!(
            CredentialGrant::from_request("GET", "http://onramp.example.com/session"),
            Err(CredentialError::NotHttps),
        );
        assert_eq!(
            CredentialGrant::from_request("GET", "onramp.example.com/session"),
            Err(CredentialError::InvalidUrl),
            "a scheme-less URL is not an endpoint"
        );
        assert_eq!(
            CredentialGrant::new("*.example.com", "/session", "GET"),
            Err(CredentialError::Wildcard),
        );
        assert_eq!(
            CredentialGrant::new("onramp.example.com", "/session/*", "GET"),
            Err(CredentialError::Wildcard),
        );
    }

    /// A grant is keyed by domain, so anything else that distinguishes an
    /// origin has to be refused rather than dropped: otherwise a grant for
    /// `example.com/session` would silently cover a different service on
    /// another port.
    #[test]
    fn a_grant_does_not_stretch_across_origins() {
        for url in [
            "https://onramp.example.com:8443/session",
            "https://user@onramp.example.com/session",
            "https://user:pw@onramp.example.com/session",
        ] {
            assert_eq!(
                CredentialGrant::from_request("POST", url),
                Err(CredentialError::NotDefaultOrigin),
                "{url} is not the origin the grant names",
            );
        }
    }

    /// Literal vectors. A backend verifier has to reproduce these bytes
    /// exactly, so a round trip through this module would not be a test:
    /// it would pass just as well if the preimage moved.
    #[test]
    fn request_digest_is_pinned() {
        let digest = request_digest(
            &grant(),
            "currency=EUR",
            1_760_000_000,
            &[0xAA; 16],
            &[0; 32],
        );
        assert_eq!(
            hex::encode(digest),
            "02c47cb7da696d605d9904c8caa93ccad52158b12892a0dd6641579a314b75a9",
        );

        assert_eq!(
            hex::encode(grant().digest()),
            "e35da854a70cf9d44421ab50adbb1fd22cf14184304f210ca9f003a04f0ab3b1",
        );
    }

    #[test]
    fn every_signed_field_changes_the_digest() {
        let base = request_digest(&grant(), "a=1", 100, b"nonce", &body_hash(b"body"));
        let variants = [
            (
                "query",
                request_digest(&grant(), "a=2", 100, b"nonce", &body_hash(b"body")),
            ),
            (
                "timestamp",
                request_digest(&grant(), "a=1", 101, b"nonce", &body_hash(b"body")),
            ),
            (
                "nonce",
                request_digest(&grant(), "a=1", 100, b"nonce2", &body_hash(b"body")),
            ),
            (
                "body",
                request_digest(&grant(), "a=1", 100, b"nonce", &body_hash(b"body2")),
            ),
            (
                "method",
                request_digest(
                    &CredentialGrant::new("onramp.example.com", "/session", "GET").unwrap(),
                    "a=1",
                    100,
                    b"nonce",
                    &body_hash(b"body"),
                ),
            ),
        ];
        for (field, variant) in variants {
            assert_ne!(base, variant, "{field} must be covered by the signature");
        }
    }

    /// The length prefixes exist so no two distinct requests share a preimage
    /// by running one field into the next.
    #[test]
    fn adjacent_fields_cannot_be_confused() {
        let split = CredentialGrant {
            domain: "onramp.example.com".to_string(),
            path: "/session".to_string(),
            method: "POST".to_string(),
        };
        let joined = CredentialGrant {
            domain: "onramp.example.com/session".to_string(),
            path: String::new(),
            method: "POST".to_string(),
        };
        assert_ne!(split.digest(), joined.digest());
    }

    /// A grant and the request it covers are spelled by different callers: the
    /// product names a triple, the host parses a live URL. They have to land on
    /// the same value or the grant silently covers nothing.
    #[test]
    fn a_grant_and_its_request_agree_on_spelling() {
        let cases = [
            (
                "onramp.example.com",
                "/user profile",
                "https://onramp.example.com/user profile",
            ),
            (
                "onramp.example.com",
                "/a/../b",
                "https://onramp.example.com/a/../b",
            ),
            (
                "Onramp.Example.com",
                "/session",
                "https://onramp.example.com/session",
            ),
            ("onramp.example.com", "", "https://onramp.example.com"),
        ];
        for (domain, path, url) in cases {
            let granted = CredentialGrant::new(domain, path, "post").expect("grantable");
            let (requested, _) = CredentialGrant::from_request("POST", url).expect("covered");
            assert_eq!(granted, requested, "{domain}{path} must cover {url}");
        }
    }

    /// A grant naming something no request can produce would prompt the user
    /// for access that could never be exercised.
    #[test]
    fn a_grant_cannot_name_an_origin_no_request_reaches() {
        for (domain, path) in [
            ("onramp.example.com:8443", "/session"),
            ("u@onramp.example.com", "/session"),
        ] {
            assert_eq!(
                CredentialGrant::new(domain, path, "POST"),
                Err(CredentialError::NotDefaultOrigin),
                "{domain} is not an endpoint a request can match",
            );
        }
    }

    #[test]
    fn a_key_is_stable_per_endpoint_and_unrelated_across_them() {
        let other_path = CredentialGrant::new("onramp.example.com", "/quote", "POST").unwrap();
        let other_method = CredentialGrant::new("onramp.example.com", "/session", "GET").unwrap();
        let other_domain = CredentialGrant::new("other.example.com", "/session", "POST").unwrap();

        let key = |product: &str, g: &CredentialGrant| {
            credential_keypair(&SOURCE, product, g).public.to_bytes()
        };

        assert_eq!(
            key("meld.dot", &grant()),
            key("meld.dot", &grant()),
            "the same wallet, product and endpoint yields one key"
        );
        for (name, other) in [
            ("path", &other_path),
            ("method", &other_method),
            ("domain", &other_domain),
        ] {
            assert_ne!(
                key("meld.dot", &grant()),
                key("meld.dot", other),
                "a different {name} is a different endpoint"
            );
        }
        assert_ne!(
            key("meld.dot", &grant()),
            key("other.dot", &grant()),
            "a shared backend sees a different key per product"
        );
        assert_ne!(
            key("meld.dot", &grant()),
            credential_keypair(&[0x22; 32], "meld.dot", &grant())
                .public
                .to_bytes(),
            "a different wallet is a different caller"
        );
    }

    /// The security property the whole mechanism rests on: a product that can
    /// call `host_derive_entropy` with any key must not be able to reach the
    /// credential key for an endpoint it was never granted.
    #[test]
    fn a_product_cannot_derive_its_own_credential_keys() {
        // The seed, not the expanded secret: expansion hashes its input, so
        // comparing against `keypair.secret` would hold even for a seed the
        // product can reach, and the assertion would prove nothing.
        let credential = credential_seed(&SOURCE, "meld.dot", &grant());

        let reachable = [
            CREDENTIAL_DOMAIN_SEPARATOR.to_vec(),
            grant().digest().to_vec(),
            REQUEST_DIGEST_LABEL.to_vec(),
            b"meld.dot".to_vec(),
        ];
        for key in reachable {
            let derived = derive_product_entropy_from_source(&SOURCE, "meld.dot", &key)
                .expect("key is 1..=32 bytes");
            assert_ne!(
                credential, derived,
                "product entropy must not reach the credential key tree"
            );
        }
    }

    /// Guards the guard: the comparison above has to be one that can fail.
    /// It compares seeds because a product holding the seed reproduces the
    /// keypair, and because expansion would mask the match.
    #[test]
    fn the_derivation_test_compares_a_value_that_can_collide() {
        let reachable = derive_product_entropy_from_source(&SOURCE, "meld.dot", b"anything")
            .expect("key is 1..=32 bytes");

        assert_ne!(
            MiniSecretKey::from_bytes(&reachable)
                .expect("32 bytes")
                .expand_to_keypair(ExpansionMode::Ed25519)
                .secret
                .to_bytes()[..32],
            reachable[..],
            "expansion hides a seed match, so the secret is the wrong thing to assert on"
        );
    }

    #[test]
    fn a_signature_verifies_against_the_attached_key() {
        let keypair = credential_keypair(&SOURCE, "meld.dot", &grant());
        let digest = request_digest(&grant(), "", 1_760_000_000, b"nonce", &body_hash(b""));
        let signature = sign_request(&keypair, &digest);

        let parsed = schnorrkel::Signature::from_bytes(&signature).expect("signature parses");
        assert!(
            keypair
                .public
                .verify_simple(SR25519_SIGNING_CONTEXT, &digest, &parsed)
                .is_ok(),
            "a backend verifies with X-Polkadot-Key alone"
        );

        let other = request_digest(&grant(), "a=1", 1_760_000_000, b"nonce", &body_hash(b""));
        assert!(
            keypair
                .public
                .verify_simple(SR25519_SIGNING_CONTEXT, &other, &parsed)
                .is_err(),
            "a signature does not carry to a different request"
        );
    }

    /// Both boundaries hand hosts these exact strings, so a backend sees the
    /// same encoding whichever host the request came from.
    #[test]
    fn headers_carry_one_encoding_for_every_host() {
        let headers = CredentialRequestHeaders {
            key: vec![0x01, 0xAB],
            signature: vec![0xFF, 0x00],
            timestamp: 1_760_000_000,
            nonce: vec![0x7F],
        };

        assert_eq!(
            headers
                .to_headers()
                .into_iter()
                .map(|header| (header.name, header.value))
                .collect::<Vec<_>>(),
            vec![
                ("X-Polkadot-Key".to_string(), "0x01ab".to_string()),
                ("X-Polkadot-Signature".to_string(), "0xff00".to_string()),
                ("X-Polkadot-Timestamp".to_string(), "1760000000".to_string()),
                ("X-Polkadot-Nonce".to_string(), "0x7f".to_string()),
            ],
        );
    }

    /// Hosts drop caller-supplied identity headers by asking this, so it has to
    /// answer for the whole reserved prefix in any casing.
    #[test]
    fn every_reserved_header_spelling_is_recognized() {
        for reserved in [
            "X-Polkadot-Key",
            "x-polkadot-signature",
            "X-POLKADOT-Nonce",
            "x-polkadot-anything",
        ] {
            assert!(is_reserved_header(reserved), "{reserved} is the host's");
        }
        for allowed in [
            "content-type",
            "authorization",
            "x-polkadot",
            "polkadot-key",
        ] {
            assert!(!is_reserved_header(allowed), "{allowed} is the product's");
        }
    }
}
