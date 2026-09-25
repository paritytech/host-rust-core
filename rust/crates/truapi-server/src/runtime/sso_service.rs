//! Context and reply types shared by SSO handlers and generated dispatch.

use core::fmt::Display;

use truapi::{CallContext, RequestId};

use super::authority::AuthoritySession;
use crate::host_internal::sso_messages::{RemoteMessage, RemoteMessageData, Response, v1};
use crate::host_internal::sso_wire::ResponseOutcome;

/// Per-request context handed to every service method.
pub struct SsoRequestContext {
    /// Call context correlated to the request's `message_id`.
    pub call: CallContext,
    /// Signing session resolved once for the request.
    pub session: AuthoritySession,
}

impl SsoRequestContext {
    /// Context for the request sent as `message_id`.
    pub fn new(message_id: &str, session: AuthoritySession) -> Self {
        Self {
            call: CallContext::with_request_id(RequestId::from(message_id)),
            session,
        }
    }
}

/// What the service dispatcher produced for one wire message.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum Dispatch {
    /// Response to post back, with its transcript outcome.
    Response(Box<Answer>),
    /// The peer ended the session.
    Disconnected,
    /// A response variant arrived where only requests are expected.
    NotARequest(&'static str),
}

/// A served request: the response envelope and how the transcript reports it.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Answer {
    /// Response envelope, `message_id` suffixed with `:response`.
    pub message: RemoteMessage,
    /// Transcript classification of the payload.
    pub outcome: ResponseOutcome,
}

/// A handler's payload and optional transcript outcome, before wire wrapping.
pub struct SsoReply<P> {
    payload: P,
    outcome: Option<ResponseOutcome>,
}

impl<P> From<P> for SsoReply<P> {
    fn from(payload: P) -> Self {
        Self {
            payload,
            outcome: None,
        }
    }
}

impl<P> SsoReply<P> {
    /// Supply a transcript outcome when the payload alone does not describe the result.
    pub fn with_outcome(mut self, outcome: ResponseOutcome) -> Self {
        self.outcome = Some(outcome);
        self
    }
}

impl<T, E: Display> SsoReply<Result<T, E>> {
    /// Address the reply and wrap it in the response variant selected by the request.
    pub fn finish(
        self,
        message_id: &str,
        wrap: impl FnOnce(Response<Result<T, E>>) -> v1::RemoteMessage,
    ) -> Answer {
        let outcome = self
            .outcome
            .unwrap_or_else(|| ResponseOutcome::from_payload(&self.payload));
        Answer {
            message: RemoteMessage {
                message_id: format!("{message_id}:response"),
                data: RemoteMessageData::V1(wrap(Response {
                    responding_to: message_id.to_string(),
                    payload: self.payload,
                })),
            },
            outcome,
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::host_internal::sso_messages::{ProductSubtreeRequest, ProductSubtreeResponse};
    use crate::host_internal::sso_wire::SsoRequest;

    #[test]
    fn finish_addresses_the_response_to_the_request() {
        let answer = SsoReply::<ProductSubtreeResponse>::from(Err("nope".to_string()))
            .finish("m-1", ProductSubtreeRequest::response_into_message);

        assert_eq!(answer.message.message_id, "m-1:response");
        let RemoteMessageData::V1(data) = answer.message.data;
        let response = ProductSubtreeRequest::response_from_message(data).unwrap();
        assert_eq!(response.responding_to, "m-1");
        assert_eq!(response.payload, Err("nope".to_string()));
        assert_eq!(answer.outcome.outcome, "error");
        assert_eq!(answer.outcome.reason.as_deref(), Some("nope"));
    }
}
