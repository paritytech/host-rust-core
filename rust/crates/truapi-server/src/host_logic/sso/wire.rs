//! Typed SSO requests and their response variants.
//!
//! `#[sso_service]` generates each request's wire conversions from its handler
//! signature. Responses share the [`Response`] envelope; the request identifies
//! the response variant even when different operations have identical payload types.

use truapi::v01::HostAccountSignVrfError;

use super::messages::{RemoteMessage, RemoteMessageData, Response, RingVrfError, v1};

/// A request payload and the wire response selected by its handler declaration.
pub trait SsoRequest: Sized {
    /// Method name used for tracing.
    const NAME: &'static str;
    /// The handler's result payload, without correlation metadata.
    type Response;
    /// Wrap into the request variant.
    fn into_message(self) -> v1::RemoteMessage;
    /// Wrap an envelope into this request's response variant.
    fn response_into_message(response: Response<Self::Response>) -> v1::RemoteMessage;
    /// Unwrap this request's response variant; `None` for any other message.
    fn response_from_message(message: v1::RemoteMessage) -> Option<Response<Self::Response>>;
}

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
        CreateTransactionRequest, CreateTransactionWithLegacyAccountRequest, ProductSubtreeRequest,
        SignRawWithLegacyAccountRequest, SignRequest,
    };

    #[test]
    fn identical_payloads_keep_their_request_specific_response_variants() {
        let response = Response {
            responding_to: "m-1".to_string(),
            payload: Ok(vec![7]),
        };
        let transaction = CreateTransactionRequest::response_into_message(response.clone());
        assert_eq!(transaction.name(), "CreateTransactionResponse");
        assert_eq!(
            CreateTransactionWithLegacyAccountRequest::response_from_message(transaction.clone()),
            Some(response.clone()),
        );
        assert!(SignRawWithLegacyAccountRequest::response_from_message(transaction).is_none());

        let signature = SignRawWithLegacyAccountRequest::response_into_message(response);
        assert_eq!(signature.name(), "SignRawWithLegacyAccountResponse");
        assert!(CreateTransactionRequest::response_from_message(signature).is_none());
    }

    #[test]
    fn classify_separates_requests_responses_and_disconnect() {
        let request = ProductSubtreeRequest {
            product_id: "browse.dot".to_string(),
        };
        assert_eq!(
            classify(request.clone().into_message()),
            Incoming::Request(AnyRequest::ProductSubtreeRequest(request))
        );
        let boxed = SignRequest::Raw(truapi::latest::HostSignRawRequest {
            account: ProductAccountId {
                dot_ns_identifier: "myapp.dot".to_string(),
                derivation_index: DerivationIndex::Index(7),
            },
            payload: truapi::latest::RawPayload::Bytes { bytes: vec![] },
        });
        assert_eq!(
            classify(boxed.clone().into_message()),
            Incoming::Request(AnyRequest::SignRequest(boxed))
        );
        assert_eq!(
            classify(v1::RemoteMessage::CreateTransactionResponse(Response {
                responding_to: "m".to_string(),
                payload: Ok(vec![]),
            })),
            Incoming::Response("CreateTransactionResponse")
        );
        assert_eq!(
            classify(v1::RemoteMessage::Disconnected),
            Incoming::Disconnected
        );
    }
}
