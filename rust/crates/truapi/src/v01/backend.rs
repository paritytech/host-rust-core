use parity_scale_codec::{Decode, Encode};

/// Request method for a backend call.
///
/// Closed rather than a free string. `TRACE` is absent in particular because it
/// reflects the host's own request headers into a body the product reads, which
/// would hand over the credential the tunnel exists to keep.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Encode, Decode)]
#[cfg_attr(feature = "uniffi", derive(uniffi::Enum))]
pub enum BackendHttpMethod {
    /// `GET`.
    Get,
    /// `HEAD`.
    Head,
    /// `POST`.
    Post,
    /// `PUT`.
    Put,
    /// `PATCH`.
    Patch,
    /// `DELETE`.
    Delete,
}

impl BackendHttpMethod {
    /// Whether this method may carry a request body. A body on one that answers
    /// `false` is refused, since `fetch`, `reqwest` and `URLSession` each treat
    /// it differently.
    pub fn allows_body(self) -> bool {
        matches!(self, Self::Post | Self::Put | Self::Patch)
    }
}

/// One query-string parameter, unencoded. The host percent-encodes both halves
/// when building the URL. Repeating a name is meaningful and preserved.
#[derive(Debug, Clone, PartialEq, Eq, Encode, Decode)]
#[cfg_attr(feature = "uniffi", derive(uniffi::Record))]
pub struct BackendQueryItem {
    /// Parameter name.
    pub name: String,
    /// Parameter value.
    pub value: String,
}

/// One response header the host passed through.
#[derive(Debug, Clone, PartialEq, Eq, Encode, Decode)]
#[cfg_attr(feature = "uniffi", derive(uniffi::Record))]
pub struct BackendHeader {
    /// Header name, lowercased.
    pub name: String,
    /// Header value.
    pub value: String,
}

/// A request body, and with it the content type the host sends.
///
/// The variant fixes the content type rather than the product supplying one,
/// which is what makes a call behave the same on every host: left to guess,
/// `fetch` labels a string body `text/plain` and the native clients label
/// nothing.
#[derive(Debug, Clone, PartialEq, Eq, Encode, Decode)]
#[cfg_attr(feature = "uniffi", derive(uniffi::Enum))]
pub enum BackendBody {
    /// UTF-8 JSON, sent verbatim as `application/json`.
    Json {
        /// The document, as UTF-8 bytes.
        bytes: Vec<u8>,
    },
    /// Fields the host encodes as `application/x-www-form-urlencoded`.
    Form {
        /// Fields, in the order the host encodes them.
        fields: Vec<BackendQueryItem>,
    },
}

/// Request to a backend the host is registered for. The product never names an
/// origin: which base URL `backend` resolves to, and what authenticates the
/// call, is known only to the host.
#[derive(Debug, Clone, PartialEq, Eq, Encode, Decode)]
#[cfg_attr(feature = "uniffi", derive(uniffi::Record))]
pub struct HostBackendRequest {
    /// Backend identifier, resolved by the host to a base URL and credential.
    pub backend: String,
    /// Request method.
    pub method: BackendHttpMethod,
    /// Absolute path within the backend, beginning with `/`. Dot segments,
    /// empty segments, percent escapes and a `//` prefix are refused, so
    /// variable data belongs in `query`.
    pub path: String,
    /// Query parameters, in the order the host appends them.
    pub query: Vec<BackendQueryItem>,
    /// Request body, for the methods that carry one.
    pub body: Option<BackendBody>,
}

/// What a backend answered. Headers are a fixed allowlist rather than whatever
/// the backend sent: enough to parse the body and to back off when asked.
#[derive(Debug, Clone, PartialEq, Eq, Encode, Decode)]
#[cfg_attr(feature = "uniffi", derive(uniffi::Record))]
pub struct HostBackendResponse {
    /// HTTP status the backend returned, including redirect and error statuses.
    pub status: u16,
    /// Allowlisted response headers, lowercased.
    pub headers: Vec<BackendHeader>,
    /// Response body as received.
    pub body: Vec<u8>,
}

/// Backends this host serves for the calling product.
#[derive(Debug, Clone, PartialEq, Eq, Encode, Decode)]
#[cfg_attr(feature = "uniffi", derive(uniffi::Record))]
pub struct HostBackendListResponse {
    /// Identifiers accepted by [`HostBackendRequest::backend`], in the order
    /// the host reports them.
    pub backends: Vec<String>,
}

/// Backend request failure.
#[derive(Debug, Clone, PartialEq, Eq, Encode, Decode)]
#[cfg_attr(feature = "uniffi", derive(uniffi::Enum))]
pub enum HostBackendError {
    /// The host serves no backend under this identifier.
    UnknownBackend,
    /// The request was refused before it was sent.
    InvalidRequest {
        /// Which rule the request broke.
        reason: String,
    },
    /// The request body or query exceeds what the core forwards.
    RequestTooLarge,
    /// The response exceeds what the host reads, and is not truncated to fit.
    ResponseTooLarge,
    /// The request was sent and did not complete.
    Transport {
        /// Human-readable failure reason.
        reason: String,
    },
    /// Catch-all.
    Unknown {
        /// Human-readable failure reason.
        reason: String,
    },
}
