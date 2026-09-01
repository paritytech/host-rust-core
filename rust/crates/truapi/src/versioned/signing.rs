//! Versioned wrappers for [`Signing`](crate::api::Signing) methods.

use crate::CallError;
use crate::v01;
use crate::versioned::Request as RequestEnvelope;

truapi_macros::versioned_type! {
    pub enum HostSignPayloadRequest { V1 => v01::HostSignPayloadRequest }
    pub enum HostSignPayloadResponse { V1 => v01::HostSignPayloadResponse }
    pub enum HostSignPayloadError { V1 => v01::HostSignPayloadError }
    pub enum HostSignRawRequest { V1 => v01::HostSignRawRequest }
    pub enum HostSignRawResponse { V1 => v01::HostSignPayloadResponse }
    pub enum HostSignRawError { V1 => v01::HostSignPayloadError }
    pub enum HostSignRawWithLegacyAccountRequest { V1 => v01::HostSignRawWithLegacyAccountRequest }
    pub enum HostSignRawWithLegacyAccountResponse { V1 => v01::HostSignPayloadResponse }
    pub enum HostSignRawWithLegacyAccountError { V1 => v01::HostSignPayloadError }
    pub enum HostSignPayloadWithLegacyAccountRequest { V1 => v01::HostSignPayloadWithLegacyAccountRequest }
    pub enum HostSignPayloadWithLegacyAccountResponse { V1 => v01::HostSignPayloadResponse }
    pub enum HostSignPayloadWithLegacyAccountError { V1 => v01::HostSignPayloadError }
    pub enum HostCreateTransactionRequest { V1 => v01::ProductAccountTxPayload }
    pub enum HostCreateTransactionResponse { V1 => v01::HostCreateTransactionResponse }
    pub enum HostCreateTransactionError { V1 => v01::HostCreateTransactionError }
    pub enum HostCreateTransactionWithLegacyAccountRequest { V1 => v01::LegacyAccountTxPayload }
    pub enum HostCreateTransactionWithLegacyAccountResponse { V1 => v01::HostCreateTransactionWithLegacyAccountResponse }
    pub enum HostCreateTransactionWithLegacyAccountError { V1 => v01::HostCreateTransactionError }

    /// Wire-envelope version for
    /// [`Signing::create_transaction`](crate::api::Signing::create_transaction).
    /// Used only by the generated dispatcher/client.
    pub enum HostCreateTransactionVersion {
        V1 => RequestEnvelope<v01::ProductAccountTxPayload, Result<v01::HostCreateTransactionResponse, CallError<v01::HostCreateTransactionError>>>,
    }

    /// Wire-envelope version for
    /// [`Signing::create_transaction_with_legacy_account`](crate::api::Signing::create_transaction_with_legacy_account).
    /// Used only by the generated dispatcher/client.
    pub enum HostCreateTransactionWithLegacyAccountVersion {
        V1 => RequestEnvelope<v01::LegacyAccountTxPayload, Result<v01::HostCreateTransactionWithLegacyAccountResponse, CallError<v01::HostCreateTransactionError>>>,
    }

    /// Wire-envelope version for
    /// [`Signing::sign_raw_with_legacy_account`](crate::api::Signing::sign_raw_with_legacy_account).
    /// Used only by the generated dispatcher/client.
    pub enum HostSignRawWithLegacyAccountVersion {
        V1 => RequestEnvelope<v01::HostSignRawWithLegacyAccountRequest, Result<v01::HostSignPayloadResponse, CallError<v01::HostSignPayloadError>>>,
    }

    /// Wire-envelope version for
    /// [`Signing::sign_payload_with_legacy_account`](crate::api::Signing::sign_payload_with_legacy_account).
    /// Used only by the generated dispatcher/client.
    pub enum HostSignPayloadWithLegacyAccountVersion {
        V1 => RequestEnvelope<v01::HostSignPayloadWithLegacyAccountRequest, Result<v01::HostSignPayloadResponse, CallError<v01::HostSignPayloadError>>>,
    }

    /// Wire-envelope version for [`Signing::sign_raw`](crate::api::Signing::sign_raw).
    /// Used only by the generated dispatcher/client.
    pub enum HostSignRawVersion {
        V1 => RequestEnvelope<v01::HostSignRawRequest, Result<v01::HostSignPayloadResponse, CallError<v01::HostSignPayloadError>>>,
    }

    /// Wire-envelope version for [`Signing::sign_payload`](crate::api::Signing::sign_payload).
    /// Used only by the generated dispatcher/client.
    pub enum HostSignPayloadVersion {
        V1 => RequestEnvelope<v01::HostSignPayloadRequest, Result<v01::HostSignPayloadResponse, CallError<v01::HostSignPayloadError>>>,
    }
}
