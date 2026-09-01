//! Versioned wrappers for [`CoinPayment`](crate::api::CoinPayment) methods.

use crate::CallError;
use crate::v01;
use crate::versioned::Request as RequestEnvelope;
use crate::versioned::Subscription as SubscriptionEnvelope;

truapi_macros::versioned_type! {
    pub enum HostCoinPaymentCreatePurseRequest { V1 => v01::HostCoinPaymentCreatePurseRequest }
    pub enum HostCoinPaymentCreatePurseResponse { V1 => v01::HostCoinPaymentCreatePurseResponse }
    pub enum HostCoinPaymentCreatePurseError { V1 => v01::CoinPaymentError }
    pub enum HostCoinPaymentQueryPurseRequest { V1 => v01::HostCoinPaymentQueryPurseRequest }
    pub enum HostCoinPaymentQueryPurseResponse { V1 => v01::HostCoinPaymentQueryPurseResponse }
    pub enum HostCoinPaymentQueryPurseError { V1 => v01::CoinPaymentError }
    pub enum HostCoinPaymentRebalancePurseRequest { V1 => v01::HostCoinPaymentRebalancePurseRequest }
    pub enum HostCoinPaymentRebalancePurseItem { V1 => v01::CoinPaymentStatus }
    pub enum HostCoinPaymentRebalancePurseError { V1 => v01::CoinPaymentError }
    pub enum HostCoinPaymentDeletePurseRequest { V1 => v01::HostCoinPaymentDeletePurseRequest }
    pub enum HostCoinPaymentDeletePurseItem { V1 => v01::CoinPaymentStatus }
    pub enum HostCoinPaymentDeletePurseError { V1 => v01::CoinPaymentError }
    pub enum HostCoinPaymentCreateReceivableRequest { V1 => v01::HostCoinPaymentCreateReceivableRequest }
    pub enum HostCoinPaymentCreateReceivableResponse { V1 => v01::HostCoinPaymentCreateReceivableResponse }
    pub enum HostCoinPaymentCreateReceivableError { V1 => v01::CoinPaymentError }
    pub enum HostCoinPaymentCreateChequeRequest { V1 => v01::HostCoinPaymentCreateChequeRequest }
    pub enum HostCoinPaymentCreateChequeResponse { V1 => v01::HostCoinPaymentCreateChequeResponse }
    pub enum HostCoinPaymentCreateChequeError { V1 => v01::CoinPaymentError }
    pub enum HostCoinPaymentDepositRequest { V1 => v01::HostCoinPaymentDepositRequest }
    pub enum HostCoinPaymentDepositItem { V1 => v01::CoinPaymentStatus }
    pub enum HostCoinPaymentDepositError { V1 => v01::CoinPaymentError }
    pub enum HostCoinPaymentRefundRequest { V1 => v01::HostCoinPaymentRefundRequest }
    pub enum HostCoinPaymentRefundItem { V1 => v01::CoinPaymentStatus }
    pub enum HostCoinPaymentRefundError { V1 => v01::CoinPaymentError }
    pub enum HostCoinPaymentListenForRequest { V1 => v01::HostCoinPaymentListenForRequest }
    pub enum HostCoinPaymentListenForItem { V1 => v01::HostCoinPaymentListenForItem }
    pub enum HostCoinPaymentListenForError { V1 => v01::CoinPaymentError }

    /// Wire-envelope version for
    /// [`CoinPayment::create_purse`](crate::api::CoinPayment::create_purse).
    /// Used only by the generated dispatcher/client.
    pub enum HostCoinPaymentCreatePurseVersion {
        V1 => RequestEnvelope<v01::HostCoinPaymentCreatePurseRequest, Result<v01::HostCoinPaymentCreatePurseResponse, CallError<v01::CoinPaymentError>>>,
    }

    /// Wire-envelope version for
    /// [`CoinPayment::query_purse`](crate::api::CoinPayment::query_purse).
    /// Used only by the generated dispatcher/client.
    pub enum HostCoinPaymentQueryPurseVersion {
        V1 => RequestEnvelope<v01::HostCoinPaymentQueryPurseRequest, Result<v01::HostCoinPaymentQueryPurseResponse, CallError<v01::CoinPaymentError>>>,
    }

    /// Wire-envelope version for
    /// [`CoinPayment::rebalance_purse`](crate::api::CoinPayment::rebalance_purse).
    /// Used only by the generated dispatcher/client.
    pub enum HostCoinPaymentRebalancePurseVersion {
        V1 => SubscriptionEnvelope<v01::HostCoinPaymentRebalancePurseRequest, v01::CoinPaymentStatus, CallError<v01::CoinPaymentError>>,
    }

    /// Wire-envelope version for
    /// [`CoinPayment::delete_purse`](crate::api::CoinPayment::delete_purse).
    /// Used only by the generated dispatcher/client.
    pub enum HostCoinPaymentDeletePurseVersion {
        V1 => SubscriptionEnvelope<v01::HostCoinPaymentDeletePurseRequest, v01::CoinPaymentStatus, CallError<v01::CoinPaymentError>>,
    }

    /// Wire-envelope version for
    /// [`CoinPayment::create_receivable`](crate::api::CoinPayment::create_receivable).
    /// Used only by the generated dispatcher/client.
    pub enum HostCoinPaymentCreateReceivableVersion {
        V1 => RequestEnvelope<v01::HostCoinPaymentCreateReceivableRequest, Result<v01::HostCoinPaymentCreateReceivableResponse, CallError<v01::CoinPaymentError>>>,
    }

    /// Wire-envelope version for
    /// [`CoinPayment::create_cheque`](crate::api::CoinPayment::create_cheque).
    /// Used only by the generated dispatcher/client.
    pub enum HostCoinPaymentCreateChequeVersion {
        V1 => RequestEnvelope<v01::HostCoinPaymentCreateChequeRequest, Result<v01::HostCoinPaymentCreateChequeResponse, CallError<v01::CoinPaymentError>>>,
    }

    /// Wire-envelope version for [`CoinPayment::deposit`](crate::api::CoinPayment::deposit).
    /// Used only by the generated dispatcher/client.
    pub enum HostCoinPaymentDepositVersion {
        V1 => SubscriptionEnvelope<v01::HostCoinPaymentDepositRequest, v01::CoinPaymentStatus, CallError<v01::CoinPaymentError>>,
    }

    /// Wire-envelope version for [`CoinPayment::refund`](crate::api::CoinPayment::refund).
    /// Used only by the generated dispatcher/client.
    pub enum HostCoinPaymentRefundVersion {
        V1 => SubscriptionEnvelope<v01::HostCoinPaymentRefundRequest, v01::CoinPaymentStatus, CallError<v01::CoinPaymentError>>,
    }

    /// Wire-envelope version for
    /// [`CoinPayment::listen_for_payment`](crate::api::CoinPayment::listen_for_payment).
    /// Used only by the generated dispatcher/client.
    pub enum HostCoinPaymentListenForVersion {
        V1 => SubscriptionEnvelope<v01::HostCoinPaymentListenForRequest, v01::HostCoinPaymentListenForItem, CallError<v01::CoinPaymentError>>,
    }
}
