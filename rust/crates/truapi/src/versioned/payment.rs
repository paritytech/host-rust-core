//! Versioned wrappers for [`Payment`](crate::api::Payment) methods.

use crate::CallError;
use crate::v01;
use crate::versioned::Request as RequestEnvelope;
use crate::versioned::Subscription as SubscriptionEnvelope;

truapi_macros::versioned_type! {
    pub enum HostPaymentBalanceSubscribeRequest { V1 => v01::HostPaymentBalanceSubscribeRequest }
    pub enum HostPaymentBalanceSubscribeItem { V1 => v01::HostPaymentBalanceSubscribeItem }
    pub enum HostPaymentBalanceSubscribeError { V1 => v01::HostPaymentBalanceSubscribeError }
    pub enum HostPaymentTopUpRequest { V1 => v01::HostPaymentTopUpRequest }
    pub enum HostPaymentTopUpResponse { V1 }
    pub enum HostPaymentTopUpError { V1 => v01::HostPaymentTopUpError }
    pub enum HostPaymentRequest { V1 => v01::HostPaymentRequest }
    pub enum HostPaymentResponse { V1 => v01::HostPaymentResponse }
    pub enum HostPaymentError { V1 => v01::HostPaymentError }
    pub enum HostPaymentStatusSubscribeRequest { V1 => v01::HostPaymentStatusSubscribeRequest }
    pub enum HostPaymentStatusSubscribeItem { V1 => v01::HostPaymentStatusSubscribeItem }
    pub enum HostPaymentStatusSubscribeError { V1 => v01::HostPaymentStatusSubscribeError }

    /// Wire-envelope version for
    /// [`Payment::balance_subscribe`](crate::api::Payment::balance_subscribe).
    /// Used only by the generated dispatcher/client.
    pub enum HostPaymentBalanceSubscribeVersion {
        V1 => SubscriptionEnvelope<v01::HostPaymentBalanceSubscribeRequest, v01::HostPaymentBalanceSubscribeItem, CallError<v01::HostPaymentBalanceSubscribeError>>,
    }

    /// Wire-envelope version for [`Payment::top_up`](crate::api::Payment::top_up).
    /// Used only by the generated dispatcher/client.
    pub enum HostPaymentTopUpVersion {
        V1 => RequestEnvelope<v01::HostPaymentTopUpRequest, Result<(), CallError<v01::HostPaymentTopUpError>>>,
    }

    /// Wire-envelope version for [`Payment::request`](crate::api::Payment::request).
    /// Used only by the generated dispatcher/client.
    pub enum HostPaymentVersion {
        V1 => RequestEnvelope<v01::HostPaymentRequest, Result<v01::HostPaymentResponse, CallError<v01::HostPaymentError>>>,
    }

    /// Wire-envelope version for
    /// [`Payment::status_subscribe`](crate::api::Payment::status_subscribe).
    /// Used only by the generated dispatcher/client.
    pub enum HostPaymentStatusSubscribeVersion {
        V1 => SubscriptionEnvelope<v01::HostPaymentStatusSubscribeRequest, v01::HostPaymentStatusSubscribeItem, CallError<v01::HostPaymentStatusSubscribeError>>,
    }
}
