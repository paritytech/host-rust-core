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
    use truapi::latest::{
        DerivationIndex, HostAccountGetAliasResponse, LegacyAccountTxPayload, ProductAccountId,
        ProductAccountTxPayload, ProductProofContext, RingLocation,
    };
    use truapi::v01::{HostAccountSignVrfError, HostAccountSignVrfRequest, RingVrfKeyDisclosure};

    use super::*;
    use crate::host_logic::sso::messages::v1::{AnyRequest, Incoming, classify};
    use crate::host_logic::sso::messages::{
        CreateAccountProofRequest, CreateAccountProofResponse, CreateTransactionLegacyPayload,
        CreateTransactionPayload, CreateTransactionRequest, CreateTransactionResponse,
        CreateTransactionWithLegacyAccountRequest, GetAccountAliasRequest, GetAccountAliasResponse,
        ListRingVrfKeysRequest, ListRingVrfKeysResponse, OnExistingAllowancePolicy,
        ProductSubtreeRequest, ProductSubtreeResponse, RegisterRingVrfKeyRequest,
        RegisterRingVrfKeyResponse, ResourceAllocationRequest, ResourceAllocationResponse,
        RingVrfSignRequest, RingVrfSignResponse, SignRawWithLegacyAccountRequest,
        SignRawWithLegacyAccountResponse, SignRequest, SignResponse, SignVrfRequest,
        SignVrfResponse, SigningPayloadResponseData, SigningRawPayload, SigningRawRequest,
        SsoAllocationOutcome,
    };

    fn account() -> ProductAccountId {
        ProductAccountId {
            dot_ns_identifier: "myapp.dot".to_string(),
            derivation_index: DerivationIndex::Index(7),
        }
    }

    fn ring() -> RingLocation {
        RingLocation {
            chain_id: [0x11; 32],
            junctions: vec![],
        }
    }

    fn context() -> ProductProofContext {
        ProductProofContext {
            product_id: "voting.dot".to_string(),
            suffix: DerivationIndex::Index(0),
        }
    }

    fn product_tx() -> ProductAccountTxPayload {
        ProductAccountTxPayload {
            signer: account(),
            genesis_hash: [2; 32],
            call_data: vec![1, 2, 3],
            extensions: vec![],
            tx_ext_version: 0,
        }
    }

    fn legacy_tx() -> LegacyAccountTxPayload {
        LegacyAccountTxPayload {
            signer: [1; 32],
            genesis_hash: [2; 32],
            call_data: vec![4],
            extensions: vec![],
            tx_ext_version: 0,
        }
    }

    fn assert_request_round_trip<R>(request: R)
    where
        R: SsoRequest + Clone + PartialEq + core::fmt::Debug,
    {
        let message = request.clone().into_message();
        assert_eq!(message.name(), R::NAME);
        assert_eq!(R::from_message(message), Some(request));
    }

    fn assert_response_round_trip<Q>(payload: Result<Q::Ok, Q::Err>)
    where
        Q: SsoResponse + Clone + PartialEq + core::fmt::Debug,
        Q::Ok: Clone + PartialEq + core::fmt::Debug,
        Q::Err: Clone + PartialEq + core::fmt::Debug,
    {
        let response = Q::new("m-1".to_string(), payload.clone());
        assert_eq!(response.responding_to(), "m-1");
        assert_eq!(response.clone().into_payload(), payload);
        assert_eq!(
            Q::from_message(response.clone().into_message()),
            Some(response)
        );
    }

    #[test]
    fn request_payloads_round_trip_through_their_variants() {
        assert_request_round_trip(SignRequest::Raw(SigningRawRequest {
            product_account_id: account(),
            data: SigningRawPayload::Bytes(vec![0xde]),
        }));
        assert_request_round_trip(GetAccountAliasRequest {
            calling_product_id: "caller.dot".to_string(),
            key_handle: account(),
            context: context(),
            ring_location: ring(),
        });
        assert_request_round_trip(ResourceAllocationRequest {
            calling_product_id: "caller.dot".to_string(),
            resources: vec![],
            on_existing: OnExistingAllowancePolicy::Increase,
        });
        assert_request_round_trip(CreateTransactionRequest {
            payload: CreateTransactionPayload::V1(product_tx()),
        });
        assert_request_round_trip(CreateTransactionWithLegacyAccountRequest {
            payload: CreateTransactionLegacyPayload::V1(legacy_tx()),
        });
        assert_request_round_trip(SignRawWithLegacyAccountRequest {
            account: [1; 32],
            data: SigningRawPayload::Payload("hi".to_string()),
        });
        assert_request_round_trip(CreateAccountProofRequest {
            calling_product_id: "caller.dot".to_string(),
            key_handle: account(),
            context: context(),
            ring_location: ring(),
            message: b"vote".to_vec(),
        });
        assert_request_round_trip(SignVrfRequest {
            calling_product_id: "caller.dot".to_string(),
            payload: HostAccountSignVrfRequest {
                account: account(),
                transcript_label: b"label".to_vec(),
                items: vec![],
            },
        });
        assert_request_round_trip(ProductSubtreeRequest {
            product_id: "browse.dot".to_string(),
        });
        assert_request_round_trip(RegisterRingVrfKeyRequest {
            calling_product_id: "game.dot".to_string(),
            index: DerivationIndex::Index(4),
            ring: ring(),
        });
        assert_request_round_trip(ListRingVrfKeysRequest {
            calling_product_id: "game.dot".to_string(),
            owner: "peopl.dot".to_string(),
            disclosure: RingVrfKeyDisclosure::PublicKey,
        });
        assert_request_round_trip(RingVrfSignRequest {
            calling_product_id: "game.dot".to_string(),
            key_handle: account(),
            message: vec![9],
        });
    }

    #[test]
    fn response_payloads_round_trip_through_their_variants() {
        assert_response_round_trip::<SignResponse>(Ok(SigningPayloadResponseData {
            signature: vec![1],
            signed_transaction: None,
        }));
        assert_response_round_trip::<SignRawWithLegacyAccountResponse>(Err("nope".to_string()));
        assert_response_round_trip::<SignVrfResponse>(Err(HostAccountSignVrfError::Rejected));
        assert_response_round_trip::<GetAccountAliasResponse>(Ok(HostAccountGetAliasResponse {
            context: [0x22; 32],
            alias: vec![0x33],
        }));
        assert_response_round_trip::<CreateAccountProofResponse>(Err(RingVrfError::NotMember));
        assert_response_round_trip::<RegisterRingVrfKeyResponse>(Ok([1; 32]));
        assert_response_round_trip::<ListRingVrfKeysResponse>(Ok(vec![]));
        assert_response_round_trip::<RingVrfSignResponse>(Ok(vec![5]));
        assert_response_round_trip::<ResourceAllocationResponse>(Ok(vec![
            SsoAllocationOutcome::Rejected,
        ]));
        assert_response_round_trip::<ProductSubtreeResponse>(Ok([7; 32]));
        assert_response_round_trip::<CreateTransactionResponse>(Ok(vec![8]));
    }

    #[test]
    fn each_request_is_answered_by_its_named_response() {
        fn response_name<R: SsoRequest>() -> &'static str {
            let not_connected = <<R::Response as SsoResponse>::Err as SsoError>::not_connected();
            R::Response::new(String::new(), Err(not_connected))
                .into_message()
                .name()
        }
        assert_eq!(response_name::<SignRequest>(), "SignResponse");
        assert_eq!(
            response_name::<GetAccountAliasRequest>(),
            "GetAccountAliasResponse"
        );
        assert_eq!(
            response_name::<ResourceAllocationRequest>(),
            "ResourceAllocationResponse"
        );
        assert_eq!(
            response_name::<CreateTransactionRequest>(),
            "CreateTransactionResponse"
        );
        assert_eq!(
            response_name::<CreateTransactionWithLegacyAccountRequest>(),
            "CreateTransactionResponse"
        );
        assert_eq!(
            response_name::<SignRawWithLegacyAccountRequest>(),
            "SignRawWithLegacyAccountResponse"
        );
        assert_eq!(
            response_name::<CreateAccountProofRequest>(),
            "CreateAccountProofResponse"
        );
        assert_eq!(response_name::<SignVrfRequest>(), "SignVrfResponse");
        assert_eq!(
            response_name::<ProductSubtreeRequest>(),
            "ProductSubtreeResponse"
        );
        assert_eq!(
            response_name::<RegisterRingVrfKeyRequest>(),
            "RegisterRingVrfKeyResponse"
        );
        assert_eq!(
            response_name::<ListRingVrfKeysRequest>(),
            "ListRingVrfKeysResponse"
        );
        assert_eq!(response_name::<RingVrfSignRequest>(), "RingVrfSignResponse");
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
        let boxed = SignRequest::Raw(SigningRawRequest {
            product_account_id: account(),
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

    #[test]
    fn shared_response_and_names_follow_the_enum() {
        fn response_name<R: SsoRequest>(_: &R) -> &'static str {
            core::any::type_name::<R::Response>()
        }
        let legacy = CreateTransactionWithLegacyAccountRequest {
            payload: CreateTransactionLegacyPayload::V1(legacy_tx()),
        };
        assert!(response_name(&legacy).ends_with("CreateTransactionResponse"));
        assert_eq!(
            RemoteMessage::request("m".to_string(), legacy).name(),
            "create_transaction_with_legacy_account"
        );
        assert_eq!(
            <CreateTransactionWithLegacyAccountRequest as SsoRequest>::NAME,
            "create_transaction_with_legacy_account"
        );
        assert_eq!(<SignRequest as SsoRequest>::NAME, "sign");
        assert_eq!(
            <GetAccountAliasRequest as SsoRequest>::NAME,
            "get_account_alias"
        );
    }
}
