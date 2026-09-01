//! Versioned wrappers for [`Chain`](crate::api::Chain) methods.

use crate::CallError;
use crate::v01;
use crate::versioned::Request as RequestEnvelope;
use crate::versioned::Subscription as SubscriptionEnvelope;

truapi_macros::versioned_type! {
    pub enum RemoteChainHeadFollowRequest { V1 => v01::RemoteChainHeadFollowRequest }
    pub enum RemoteChainHeadFollowItem { V1 => v01::RemoteChainHeadFollowItem }
    pub enum RemoteChainHeadHeaderRequest { V1 => v01::RemoteChainHeadHeaderRequest }
    pub enum RemoteChainHeadHeaderResponse { V1 => v01::RemoteChainHeadHeaderResponse }
    pub enum RemoteChainHeadHeaderError { V1 => v01::GenericError }
    pub enum RemoteChainHeadBodyRequest { V1 => v01::RemoteChainHeadBodyRequest }
    pub enum RemoteChainHeadBodyResponse { V1 => v01::RemoteChainHeadBodyResponse }
    pub enum RemoteChainHeadBodyError { V1 => v01::GenericError }
    pub enum RemoteChainHeadStorageRequest { V1 => v01::RemoteChainHeadStorageRequest }
    pub enum RemoteChainHeadStorageResponse { V1 => v01::RemoteChainHeadStorageResponse }
    pub enum RemoteChainHeadStorageError { V1 => v01::GenericError }
    pub enum RemoteChainHeadCallRequest { V1 => v01::RemoteChainHeadCallRequest }
    pub enum RemoteChainHeadCallResponse { V1 => v01::RemoteChainHeadCallResponse }
    pub enum RemoteChainHeadCallError { V1 => v01::GenericError }
    pub enum RemoteChainHeadUnpinRequest { V1 => v01::RemoteChainHeadUnpinRequest }
    pub enum RemoteChainHeadUnpinResponse { V1 }
    pub enum RemoteChainHeadUnpinError { V1 => v01::GenericError }
    pub enum RemoteChainHeadContinueRequest { V1 => v01::RemoteChainHeadContinueRequest }
    pub enum RemoteChainHeadContinueResponse { V1 }
    pub enum RemoteChainHeadContinueError { V1 => v01::GenericError }
    pub enum RemoteChainHeadStopOperationRequest { V1 => v01::RemoteChainHeadStopOperationRequest }
    pub enum RemoteChainHeadStopOperationResponse { V1 }
    pub enum RemoteChainHeadStopOperationError { V1 => v01::GenericError }
    pub enum RemoteChainSpecGenesisHashRequest { V1 => v01::RemoteChainSpecGenesisHashRequest }
    pub enum RemoteChainSpecGenesisHashResponse { V1 => v01::RemoteChainSpecGenesisHashResponse }
    pub enum RemoteChainSpecGenesisHashError { V1 => v01::GenericError }
    pub enum RemoteChainSpecChainNameRequest { V1 => v01::RemoteChainSpecChainNameRequest }
    pub enum RemoteChainSpecChainNameResponse { V1 => v01::RemoteChainSpecChainNameResponse }
    pub enum RemoteChainSpecChainNameError { V1 => v01::GenericError }
    pub enum RemoteChainSpecPropertiesRequest { V1 => v01::RemoteChainSpecPropertiesRequest }
    pub enum RemoteChainSpecPropertiesResponse { V1 => v01::RemoteChainSpecPropertiesResponse }
    pub enum RemoteChainSpecPropertiesError { V1 => v01::GenericError }
    pub enum RemoteChainTransactionBroadcastRequest { V1 => v01::RemoteChainTransactionBroadcastRequest }
    pub enum RemoteChainTransactionBroadcastResponse { V1 => v01::RemoteChainTransactionBroadcastResponse }
    pub enum RemoteChainTransactionBroadcastError { V1 => v01::GenericError }
    pub enum RemoteChainTransactionStopRequest { V1 => v01::RemoteChainTransactionStopRequest }
    pub enum RemoteChainTransactionStopResponse { V1 }
    pub enum RemoteChainTransactionStopError { V1 => v01::GenericError }
    pub enum RemoteChainInfoRequest { V1 => v01::RemoteChainInfoRequest }
    pub enum RemoteChainInfoResponse { V1 => v01::RemoteChainInfoResponse }
    pub enum RemoteChainInfoError { V1 => v01::RemoteChainInfoError }

    /// Wire-envelope version for
    /// [`Chain::follow_head_subscribe`](crate::api::Chain::follow_head_subscribe).
    /// Used only by the generated dispatcher/client.
    pub enum RemoteChainHeadFollowVersion {
        V1 => SubscriptionEnvelope<v01::RemoteChainHeadFollowRequest, v01::RemoteChainHeadFollowItem, CallError<crate::latest::GenericError>>,
    }

    /// Wire-envelope version for [`Chain::get_head_header`](crate::api::Chain::get_head_header).
    /// Used only by the generated dispatcher/client.
    pub enum RemoteChainHeadHeaderVersion {
        V1 => RequestEnvelope<v01::RemoteChainHeadHeaderRequest, Result<v01::RemoteChainHeadHeaderResponse, CallError<v01::GenericError>>>,
    }

    /// Wire-envelope version for [`Chain::get_head_body`](crate::api::Chain::get_head_body).
    /// Used only by the generated dispatcher/client.
    pub enum RemoteChainHeadBodyVersion {
        V1 => RequestEnvelope<v01::RemoteChainHeadBodyRequest, Result<v01::RemoteChainHeadBodyResponse, CallError<v01::GenericError>>>,
    }

    /// Wire-envelope version for [`Chain::get_head_storage`](crate::api::Chain::get_head_storage).
    /// Used only by the generated dispatcher/client.
    pub enum RemoteChainHeadStorageVersion {
        V1 => RequestEnvelope<v01::RemoteChainHeadStorageRequest, Result<v01::RemoteChainHeadStorageResponse, CallError<v01::GenericError>>>,
    }

    /// Wire-envelope version for [`Chain::call_head`](crate::api::Chain::call_head).
    /// Used only by the generated dispatcher/client.
    pub enum RemoteChainHeadCallVersion {
        V1 => RequestEnvelope<v01::RemoteChainHeadCallRequest, Result<v01::RemoteChainHeadCallResponse, CallError<v01::GenericError>>>,
    }

    /// Wire-envelope version for [`Chain::unpin_head`](crate::api::Chain::unpin_head).
    /// Used only by the generated dispatcher/client.
    pub enum RemoteChainHeadUnpinVersion {
        V1 => RequestEnvelope<v01::RemoteChainHeadUnpinRequest, Result<(), CallError<v01::GenericError>>>,
    }

    /// Wire-envelope version for [`Chain::continue_head`](crate::api::Chain::continue_head).
    /// Used only by the generated dispatcher/client.
    pub enum RemoteChainHeadContinueVersion {
        V1 => RequestEnvelope<v01::RemoteChainHeadContinueRequest, Result<(), CallError<v01::GenericError>>>,
    }

    /// Wire-envelope version for
    /// [`Chain::stop_head_operation`](crate::api::Chain::stop_head_operation).
    /// Used only by the generated dispatcher/client.
    pub enum RemoteChainHeadStopOperationVersion {
        V1 => RequestEnvelope<v01::RemoteChainHeadStopOperationRequest, Result<(), CallError<v01::GenericError>>>,
    }

    /// Wire-envelope version for
    /// [`Chain::get_spec_genesis_hash`](crate::api::Chain::get_spec_genesis_hash).
    /// Used only by the generated dispatcher/client.
    pub enum RemoteChainSpecGenesisHashVersion {
        V1 => RequestEnvelope<v01::RemoteChainSpecGenesisHashRequest, Result<v01::RemoteChainSpecGenesisHashResponse, CallError<v01::GenericError>>>,
    }

    /// Wire-envelope version for
    /// [`Chain::get_spec_chain_name`](crate::api::Chain::get_spec_chain_name).
    /// Used only by the generated dispatcher/client.
    pub enum RemoteChainSpecChainNameVersion {
        V1 => RequestEnvelope<v01::RemoteChainSpecChainNameRequest, Result<v01::RemoteChainSpecChainNameResponse, CallError<v01::GenericError>>>,
    }

    /// Wire-envelope version for
    /// [`Chain::get_spec_properties`](crate::api::Chain::get_spec_properties).
    /// Used only by the generated dispatcher/client.
    pub enum RemoteChainSpecPropertiesVersion {
        V1 => RequestEnvelope<v01::RemoteChainSpecPropertiesRequest, Result<v01::RemoteChainSpecPropertiesResponse, CallError<v01::GenericError>>>,
    }

    /// Wire-envelope version for
    /// [`Chain::broadcast_transaction`](crate::api::Chain::broadcast_transaction).
    /// Used only by the generated dispatcher/client.
    pub enum RemoteChainTransactionBroadcastVersion {
        V1 => RequestEnvelope<v01::RemoteChainTransactionBroadcastRequest, Result<v01::RemoteChainTransactionBroadcastResponse, CallError<v01::GenericError>>>,
    }

    /// Wire-envelope version for [`Chain::stop_transaction`](crate::api::Chain::stop_transaction).
    /// Used only by the generated dispatcher/client.
    pub enum RemoteChainTransactionStopVersion {
        V1 => RequestEnvelope<v01::RemoteChainTransactionStopRequest, Result<(), CallError<v01::GenericError>>>,
    }

    /// Wire-envelope version for [`Chain::get_chain_info`](crate::api::Chain::get_chain_info).
    /// Used only by the generated dispatcher/client.
    pub enum RemoteChainInfoVersion {
        V1 => RequestEnvelope<v01::RemoteChainInfoRequest, Result<v01::RemoteChainInfoResponse, CallError<v01::RemoteChainInfoError>>>,
    }
}
