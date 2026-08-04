use parity_scale_codec::{Decode, Encode};

/// Error from [`crate::api::Secrets::request`] (RFC 0025).
#[derive(Debug, Clone, PartialEq, Eq, Encode, Decode)]
pub enum HostSecretError {
    /// No authenticated session (RFC 0009). The host must not auto-prompt login.
    NotConnected,
    /// No record under that name.
    UnknownSecret,
    /// The record resolved but does not parse.
    MalformedRecord,
    /// The user declined consent or the signing confirmation.
    Rejected,
    /// The user is not a people-set member, so no caller proof can be produced.
    NotMember,
    /// The backend could not be reached.
    Transport,
    /// The response exceeded the host's limit and was discarded.
    ResponseTooLarge,
    /// Catch-all.
    Unknown {
        /// Human-readable failure reason.
        reason: String,
    },
}

/// One header on the outbound request.
#[derive(Debug, Clone, PartialEq, Eq, Encode, Decode)]
pub struct SecretHeader {
    /// Header name.
    pub name: String,
    /// Header value.
    pub value: String,
}

/// One query parameter appended to the record's fixed path.
#[derive(Debug, Clone, PartialEq, Eq, Encode, Decode)]
pub struct SecretQueryParam {
    /// Parameter name.
    pub name: String,
    /// Parameter value.
    pub value: String,
}

/// Request to a backend holding a credential the product never sees (RFC 0025).
///
/// The backend is resolved as `secret:<name>` in `product`'s dotNS records.
/// That record fixes the endpoint, path, and method, so the caller supplies
/// only a query, headers, and a body. The host attaches a ring VRF proof over
/// the canonical digest, plus the contextual alias for that backend.
#[derive(Debug, Clone, PartialEq, Eq, Encode, Decode)]
pub struct HostSecretRequest {
    /// dotNS name whose records declare the backend. Often the caller's own,
    /// but naming another is how a product reaches a shared service.
    pub product: String,
    /// Secret name, resolved as `secret:<name>` in that product's records.
    pub name: String,
    /// Appended to the record's fixed path as a query string.
    pub query: Vec<SecretQueryParam>,
    /// Headers to forward. The host strips any in the `X-Polkadot-` namespace.
    pub headers: Vec<SecretHeader>,
    /// Request body, if the record's method takes one.
    pub body: Option<Vec<u8>>,
}

/// Response returned by the backend, unmodified except for hop-by-hop headers.
#[derive(Debug, Clone, PartialEq, Eq, Encode, Decode)]
pub struct HostSecretResponse {
    /// HTTP status the backend returned.
    pub status: u16,
    /// Response headers.
    pub headers: Vec<SecretHeader>,
    /// Response body.
    pub body: Vec<u8>,
}
