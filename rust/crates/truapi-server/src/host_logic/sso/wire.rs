//! Typed pairing of SSO request and response payloads.
//!
//! [`SsoRequest`] is implemented by `#[sso_service]` from each handler's wire
//! request parameter and wire response return type. `#[derive(SsoWire)]` on
//! [`v1::RemoteMessage`] provides wire classification. [`SsoResponse`] is
//! derived on each response struct and exposes its payload without the
//! correlation id.

use truapi::v01::HostAccountSignVrfError;

use super::messages::{RemoteMessage, RemoteMessageData, RingVrfError, v1};

/// A request payload carried by one `v1::RemoteMessage` variant.
pub trait SsoRequest: Sized {
    /// Method name used for tracing.
    const NAME: &'static str;
    /// Response payload the signing host answers with.
    type Response: SsoResponse;
    /// Wrap into the request variant.
    fn into_message(self) -> v1::RemoteMessage;
    /// Unwrap from the request variant; `None` for any other message.
    fn from_message(message: v1::RemoteMessage) -> Option<Self>;
}

/// A response payload carried by one `v1::RemoteMessage` variant.
pub trait SsoResponse: Sized {
    /// Successful payload.
    type Ok;
    /// Failure payload.
    type Err: SsoError;
    /// Build the response for the request identified by `responding_to`.
    fn new(responding_to: String, payload: Result<Self::Ok, Self::Err>) -> Self;
    /// `message_id` of the request being answered.
    fn responding_to(&self) -> &str;
    /// Strip the correlation id.
    fn into_payload(self) -> Result<Self::Ok, Self::Err>;
    /// Wrap into the response variant.
    fn into_message(self) -> v1::RemoteMessage;
    /// Unwrap from the response variant; `None` for any other message.
    fn from_message(message: v1::RemoteMessage) -> Option<Self>;
    /// Transcript classification of the payload.
    fn outcome(&self) -> ResponseOutcome;
}

/// A wire response's `Result` payload, without its correlation id.
///
/// The typed client returns this result. Server replies carry the same payload
/// alongside local diagnostics; dispatch adds the wire envelope.
pub type ResponsePayload<R> = Result<<R as SsoResponse>::Ok, <R as SsoResponse>::Err>;

/// Failure payload that can express "no signing session".
pub trait SsoError {
    /// The signing host has no active session to serve the request with.
    fn not_connected() -> Self;
    /// Single-line description for transcripts.
    fn reason(&self) -> String;
}

impl SsoError for String {
    fn not_connected() -> Self {
        "signing host session is not active".to_string()
    }

    fn reason(&self) -> String {
        self.clone()
    }
}

impl SsoError for RingVrfError {
    fn not_connected() -> Self {
        RingVrfError::Unknown {
            reason: String::not_connected(),
        }
    }

    fn reason(&self) -> String {
        match self {
            RingVrfError::RingNotFound => "RingNotFound".to_string(),
            RingVrfError::NotMember => "NotMember".to_string(),
            RingVrfError::KeyNotRegistered => "KeyNotRegistered".to_string(),
            RingVrfError::KeyNotInRing => "KeyNotInRing".to_string(),
            RingVrfError::NotAllowlisted => "NotAllowlisted".to_string(),
            RingVrfError::Rejected => "Rejected".to_string(),
            RingVrfError::Unknown { reason } => format!("Unknown: {reason}"),
        }
    }
}

impl SsoError for HostAccountSignVrfError {
    fn not_connected() -> Self {
        HostAccountSignVrfError::NotConnected
    }

    fn reason(&self) -> String {
        match self {
            HostAccountSignVrfError::NotConnected => "NotConnected".to_string(),
            HostAccountSignVrfError::Rejected => "Rejected".to_string(),
            HostAccountSignVrfError::Unknown { reason } => reason.clone(),
        }
    }
}

/// Outcome code and reason recorded in the SSO transcript for one response.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ResponseOutcome {
    /// Stable outcome code such as `ok`, `error`, or `publish_failed`.
    pub outcome: &'static str,
    /// Single-line failure description, when any.
    pub reason: Option<String>,
}

impl ResponseOutcome {
    /// Classify a plain payload: `ok`, or `error` with the failure's reason.
    pub fn from_payload<T, E: SsoError>(payload: &Result<T, E>) -> Self {
        match payload {
            Ok(_) => Self {
                outcome: "ok",
                reason: None,
            },
            Err(err) => Self {
                outcome: "error",
                reason: Some(err.reason()),
            },
        }
    }
}

impl RemoteMessage {
    /// Service method name for requests; variant name for other messages.
    pub(crate) fn name(&self) -> &'static str {
        let RemoteMessageData::V1(message) = &self.data;
        message.name()
    }

    /// Outgoing request carrying `request` under `message_id`.
    pub fn request<R: SsoRequest>(message_id: String, request: R) -> Self {
        Self {
            message_id,
            data: RemoteMessageData::V1(request.into_message()),
        }
    }
}

#[cfg(test)]
mod tests {
    use truapi::latest::{DerivationIndex, ProductAccountId};

    use super::*;
    use crate::host_logic::sso::messages::v1::{AnyRequest, Incoming, classify};
    use crate::host_logic::sso::messages::{
        CreateTransactionResponse, ProductSubtreeRequest, SignRequest, SigningRawPayload,
        SigningRawRequest,
    };

    #[test]
    fn classify_separates_requests_responses_and_disconnect() {
        let request = ProductSubtreeRequest {
            product_id: "browse.dot".to_string(),
        };
        assert_eq!(
            classify(request.clone().into_message()),
            Incoming::Request(AnyRequest::ProductSubtreeRequest(request))
        );
        let boxed = SignRequest::Raw(SigningRawRequest {
            product_account_id: ProductAccountId {
                dot_ns_identifier: "myapp.dot".to_string(),
                derivation_index: DerivationIndex::Index(7),
            },
            data: SigningRawPayload::Bytes(vec![]),
        });
        assert_eq!(
            classify(boxed.clone().into_message()),
            Incoming::Request(AnyRequest::SignRequest(boxed))
        );
        assert_eq!(
            classify(CreateTransactionResponse::new("m".to_string(), Ok(vec![])).into_message()),
            Incoming::Response("CreateTransactionResponse")
        );
        assert_eq!(
            classify(v1::RemoteMessage::Disconnected),
            Incoming::Disconnected
        );
    }
}
