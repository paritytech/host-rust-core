//! Context and reply types shared by SSO handlers and generated dispatch.

use truapi::{CallContext, RequestId};

use super::authority::AuthoritySession;
use crate::host_logic::sso::messages::RemoteMessage;
use crate::host_logic::sso::wire::{ResponseOutcome, ResponsePayload, SsoResponse};

/// Per-request context handed to every service method.
pub(crate) struct SsoRequestContext {
    /// Call context correlated to the request's `message_id`.
    pub(crate) call: CallContext,
    /// Signing session resolved once for the request.
    pub(crate) session: AuthoritySession,
}

impl SsoRequestContext {
    /// Context for the request sent as `message_id`.
    pub(crate) fn new(message_id: &str, session: AuthoritySession) -> Self {
        Self {
            call: CallContext::with_request_id(RequestId::from(message_id)),
            session,
        }
    }
}

/// What the service dispatcher produced for one wire message.
#[derive(Debug, Clone, PartialEq, Eq)]
pub(crate) enum Dispatch {
    /// Response to post back, with its transcript outcome.
    Response(Box<Answer>),
    /// The peer ended the session.
    Disconnected,
    /// A response variant arrived where only requests are expected.
    NotARequest(&'static str),
}

/// A served request: the response envelope and how the transcript reports it.
#[derive(Debug, Clone, PartialEq, Eq)]
pub(crate) struct Answer {
    /// Response envelope, `message_id` suffixed with `:response`.
    pub(crate) message: RemoteMessage,
    /// Transcript classification of the payload.
    pub(crate) outcome: ResponseOutcome,
}

/// A handler's payload and optional transcript outcome, before wire wrapping.
pub(crate) struct SsoReply<R: SsoResponse> {
    payload: ResponsePayload<R>,
    outcome: Option<ResponseOutcome>,
}

impl<R: SsoResponse> From<ResponsePayload<R>> for SsoReply<R> {
    fn from(payload: ResponsePayload<R>) -> Self {
        Self {
            payload,
            outcome: None,
        }
    }
}

impl<R: SsoResponse> SsoReply<R> {
    /// Supply a transcript outcome when the payload alone does not describe the result.
    pub(crate) fn with_outcome(mut self, outcome: ResponseOutcome) -> Self {
        self.outcome = Some(outcome);
        self
    }

    /// Wrap the payload with correlation and use its derived or supplied outcome.
    pub(crate) fn finish(self, message_id: &str) -> Answer {
        let response = R::new(message_id.to_string(), self.payload);
        let outcome = self.outcome.unwrap_or_else(|| response.outcome());
        Answer {
            message: RemoteMessage {
                message_id: format!("{message_id}:response"),
                data: crate::host_logic::sso::messages::RemoteMessageData::V1(
                    response.into_message(),
                ),
            },
            outcome,
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::host_logic::sso::messages::{ProductSubtreeResponse, RemoteMessageData, v1};

    #[test]
    fn finish_addresses_the_response_to_the_request() {
        let answer =
            SsoReply::<ProductSubtreeResponse>::from(Err("nope".to_string())).finish("m-1");

        assert_eq!(
            answer,
            Answer {
                message: RemoteMessage {
                    message_id: "m-1:response".to_string(),
                    data: RemoteMessageData::V1(v1::RemoteMessage::ProductSubtreeResponse(
                        ProductSubtreeResponse {
                            responding_to: "m-1".to_string(),
                            product_public_key: Err("nope".to_string()),
                        },
                    )),
                },
                outcome: ResponseOutcome {
                    outcome: "error",
                    reason: Some("nope".to_string()),
                },
            }
        );
    }

    #[test]
    fn reply_outcome_does_not_change_the_wire_payload() {
        let answer = SsoReply::<ProductSubtreeResponse>::from(Err("denied".to_string()))
            .with_outcome(ResponseOutcome {
                outcome: "rejected",
                reason: Some("local detail".to_string()),
            })
            .finish("m-1");

        assert_eq!(answer.outcome.outcome, "rejected");
        assert_eq!(answer.outcome.reason.as_deref(), Some("local detail"));
        let RemoteMessageData::V1(data) = answer.message.data;
        let response = ProductSubtreeResponse::from_message(data).unwrap();
        assert_eq!(response.product_public_key, Err("denied".to_string()));
    }
}
