//! Versioned wrappers for [`StatementStore`](crate::api::StatementStore) methods.

use crate::CallError;
use crate::v01;
use crate::versioned::Request as RequestEnvelope;
use crate::versioned::Subscription as SubscriptionEnvelope;

truapi_macros::versioned_type! {
    pub enum RemoteStatementStoreSubscribeRequest { V1 => v01::RemoteStatementStoreSubscribeRequest }
    pub enum RemoteStatementStoreSubscribeItem { V1 => v01::RemoteStatementStoreSubscribeItem }
    pub enum RemoteStatementStoreSubscribeError { V1 => v01::GenericError }
    pub enum RemoteStatementStoreCreateProofRequest { V1 => v01::RemoteStatementStoreCreateProofRequest }
    pub enum RemoteStatementStoreCreateProofResponse { V1 => v01::RemoteStatementStoreCreateProofResponse }
    pub enum RemoteStatementStoreCreateProofError { V1 => v01::RemoteStatementStoreCreateProofError }
    pub enum RemoteStatementStoreCreateProofAuthorizedRequest { V1 => v01::Statement }
    pub enum RemoteStatementStoreCreateProofAuthorizedResponse { V1 => v01::RemoteStatementStoreCreateProofResponse }
    pub enum RemoteStatementStoreCreateProofAuthorizedError { V1 => v01::RemoteStatementStoreCreateProofError }
    pub enum RemoteStatementStoreSubmitRequest { V1 => v01::SignedStatement }
    pub enum RemoteStatementStoreSubmitError { V1 => v01::GenericError }

    /// Wire-envelope version for
    /// [`StatementStore::subscribe`](crate::api::StatementStore::subscribe).
    /// Used only by the generated dispatcher/client.
    pub enum RemoteStatementStoreSubscribeVersion {
        V1 => SubscriptionEnvelope<v01::RemoteStatementStoreSubscribeRequest, v01::RemoteStatementStoreSubscribeItem, CallError<v01::GenericError>>,
    }

    /// Wire-envelope version for
    /// [`StatementStore::create_proof`](crate::api::StatementStore::create_proof).
    /// Used only by the generated dispatcher/client.
    pub enum RemoteStatementStoreCreateProofVersion {
        V1 => RequestEnvelope<v01::RemoteStatementStoreCreateProofRequest, Result<v01::RemoteStatementStoreCreateProofResponse, CallError<v01::RemoteStatementStoreCreateProofError>>>,
    }

    /// Wire-envelope version for [`StatementStore::submit`](crate::api::StatementStore::submit).
    /// Used only by the generated dispatcher/client.
    pub enum RemoteStatementStoreSubmitVersion {
        V1 => RequestEnvelope<v01::SignedStatement, Result<(), CallError<v01::GenericError>>>,
    }

    /// Wire-envelope version for
    /// [`StatementStore::create_proof_authorized`](crate::api::StatementStore::create_proof_authorized).
    /// Used only by the generated dispatcher/client.
    pub enum RemoteStatementStoreCreateProofAuthorizedVersion {
        V1 => RequestEnvelope<v01::Statement, Result<v01::RemoteStatementStoreCreateProofResponse, CallError<v01::RemoteStatementStoreCreateProofError>>>,
    }
}
