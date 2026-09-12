//! Product-facing payment capability adapters.
//!
//! Payment serves the purse the host installed (`RuntimeServices::payment_purse`)
//! and answers with typed domain errors when there is none; CoinPayment
//! returns Unsupported.

use futures::StreamExt;
use tracing::instrument;
use truapi::api::{CoinPayment, Payment};
use truapi::versioned::coin_payment::{
    HostCoinPaymentCreateChequeError, HostCoinPaymentCreateChequeRequest,
    HostCoinPaymentCreateChequeResponse, HostCoinPaymentCreatePurseError,
    HostCoinPaymentCreatePurseRequest, HostCoinPaymentCreatePurseResponse,
    HostCoinPaymentCreateReceivableError, HostCoinPaymentCreateReceivableRequest,
    HostCoinPaymentCreateReceivableResponse, HostCoinPaymentDeletePurseError,
    HostCoinPaymentDeletePurseItem, HostCoinPaymentDeletePurseRequest, HostCoinPaymentDepositError,
    HostCoinPaymentDepositItem, HostCoinPaymentDepositRequest, HostCoinPaymentListenForError,
    HostCoinPaymentListenForItem, HostCoinPaymentListenForRequest, HostCoinPaymentQueryPurseError,
    HostCoinPaymentQueryPurseRequest, HostCoinPaymentQueryPurseResponse,
    HostCoinPaymentRebalancePurseError, HostCoinPaymentRebalancePurseItem,
    HostCoinPaymentRebalancePurseRequest, HostCoinPaymentRefundError, HostCoinPaymentRefundItem,
    HostCoinPaymentRefundRequest,
};
use truapi::versioned::payment::{
    HostPaymentBalanceSubscribeError, HostPaymentBalanceSubscribeItem,
    HostPaymentBalanceSubscribeRequest, HostPaymentError, HostPaymentRequest, HostPaymentResponse,
    HostPaymentStatusSubscribeError, HostPaymentStatusSubscribeItem,
    HostPaymentStatusSubscribeRequest, HostPaymentTopUpError, HostPaymentTopUpRequest,
    HostPaymentTopUpResponse,
};
use truapi::{CallContext, CallError, Subscription, v01};

use crate::runtime::{PAYMENTS_NOT_IMPLEMENTED, ProductRuntimeHost};

#[truapi::async_trait]
impl CoinPayment for ProductRuntimeHost {
    #[instrument(skip_all, fields(runtime.method = "coin_payment.create_purse"))]
    async fn create_purse(
        &self,
        _cx: &CallContext,
        _request: HostCoinPaymentCreatePurseRequest,
    ) -> Result<HostCoinPaymentCreatePurseResponse, CallError<HostCoinPaymentCreatePurseError>>
    {
        Err(CallError::Unsupported)
    }

    #[instrument(skip_all, fields(runtime.method = "coin_payment.query_purse"))]
    async fn query_purse(
        &self,
        _cx: &CallContext,
        _request: HostCoinPaymentQueryPurseRequest,
    ) -> Result<HostCoinPaymentQueryPurseResponse, CallError<HostCoinPaymentQueryPurseError>> {
        Err(CallError::Unsupported)
    }

    #[instrument(skip_all, fields(runtime.method = "coin_payment.rebalance_purse"))]
    async fn rebalance_purse(
        &self,
        _cx: &CallContext,
        _request: HostCoinPaymentRebalancePurseRequest,
    ) -> Result<
        Subscription<HostCoinPaymentRebalancePurseItem>,
        CallError<HostCoinPaymentRebalancePurseError>,
    > {
        Err(CallError::Unsupported)
    }

    #[instrument(skip_all, fields(runtime.method = "coin_payment.delete_purse"))]
    async fn delete_purse(
        &self,
        _cx: &CallContext,
        _request: HostCoinPaymentDeletePurseRequest,
    ) -> Result<
        Subscription<HostCoinPaymentDeletePurseItem>,
        CallError<HostCoinPaymentDeletePurseError>,
    > {
        Err(CallError::Unsupported)
    }

    #[instrument(skip_all, fields(runtime.method = "coin_payment.create_receivable"))]
    async fn create_receivable(
        &self,
        _cx: &CallContext,
        _request: HostCoinPaymentCreateReceivableRequest,
    ) -> Result<
        HostCoinPaymentCreateReceivableResponse,
        CallError<HostCoinPaymentCreateReceivableError>,
    > {
        Err(CallError::Unsupported)
    }

    #[instrument(skip_all, fields(runtime.method = "coin_payment.create_cheque"))]
    async fn create_cheque(
        &self,
        _cx: &CallContext,
        _request: HostCoinPaymentCreateChequeRequest,
    ) -> Result<HostCoinPaymentCreateChequeResponse, CallError<HostCoinPaymentCreateChequeError>>
    {
        Err(CallError::Unsupported)
    }

    #[instrument(skip_all, fields(runtime.method = "coin_payment.deposit"))]
    async fn deposit(
        &self,
        _cx: &CallContext,
        _request: HostCoinPaymentDepositRequest,
    ) -> Result<Subscription<HostCoinPaymentDepositItem>, CallError<HostCoinPaymentDepositError>>
    {
        Err(CallError::Unsupported)
    }

    #[instrument(skip_all, fields(runtime.method = "coin_payment.refund"))]
    async fn refund(
        &self,
        _cx: &CallContext,
        _request: HostCoinPaymentRefundRequest,
    ) -> Result<Subscription<HostCoinPaymentRefundItem>, CallError<HostCoinPaymentRefundError>>
    {
        Err(CallError::Unsupported)
    }

    #[instrument(skip_all, fields(runtime.method = "coin_payment.listen_for_payment"))]
    async fn listen_for_payment(
        &self,
        _cx: &CallContext,
        _request: HostCoinPaymentListenForRequest,
    ) -> Result<Subscription<HostCoinPaymentListenForItem>, CallError<HostCoinPaymentListenForError>>
    {
        Err(CallError::Unsupported)
    }
}

#[truapi::async_trait]
impl Payment for ProductRuntimeHost {
    #[instrument(skip_all, fields(runtime.method = "payment.balance_subscribe"))]
    async fn balance_subscribe(
        &self,
        _cx: &CallContext,
        request: HostPaymentBalanceSubscribeRequest,
    ) -> Result<
        Subscription<HostPaymentBalanceSubscribeItem>,
        CallError<HostPaymentBalanceSubscribeError>,
    > {
        let Some(purse) = self.services.payment_purse() else {
            return Err(CallError::Domain(HostPaymentBalanceSubscribeError::V1(
                v01::HostPaymentBalanceSubscribeError::PermissionDenied,
            )));
        };
        let HostPaymentBalanceSubscribeRequest::V1(v01::HostPaymentBalanceSubscribeRequest {
            purse: purse_id,
        }) = request;
        let stream = purse.subscribe_balance(purse_id).map(|available| {
            HostPaymentBalanceSubscribeItem::V1(v01::HostPaymentBalanceSubscribeItem { available })
        });
        Ok(Subscription::new(Box::pin(stream)))
    }

    #[instrument(skip_all, fields(runtime.method = "payment.request"))]
    async fn request(
        &self,
        _cx: &CallContext,
        _request: HostPaymentRequest,
    ) -> Result<HostPaymentResponse, CallError<HostPaymentError>> {
        Err(CallError::Domain(HostPaymentError::V1(
            v01::HostPaymentError::Unknown {
                reason: PAYMENTS_NOT_IMPLEMENTED.to_string(),
            },
        )))
    }

    #[instrument(skip_all, fields(runtime.method = "payment.status_subscribe"))]
    async fn status_subscribe(
        &self,
        _cx: &CallContext,
        _request: HostPaymentStatusSubscribeRequest,
    ) -> Result<
        Subscription<HostPaymentStatusSubscribeItem>,
        CallError<HostPaymentStatusSubscribeError>,
    > {
        Err(CallError::Domain(HostPaymentStatusSubscribeError::V1(
            v01::HostPaymentStatusSubscribeError::Unknown {
                reason: PAYMENTS_NOT_IMPLEMENTED.to_string(),
            },
        )))
    }

    #[instrument(skip_all, fields(runtime.method = "payment.top_up"))]
    async fn top_up(
        &self,
        _cx: &CallContext,
        request: HostPaymentTopUpRequest,
    ) -> Result<HostPaymentTopUpResponse, CallError<HostPaymentTopUpError>> {
        let Some(purse) = self.services.payment_purse() else {
            return Err(CallError::Domain(HostPaymentTopUpError::V1(
                v01::HostPaymentTopUpError::Unknown {
                    reason: PAYMENTS_NOT_IMPLEMENTED.to_string(),
                },
            )));
        };
        let HostPaymentTopUpRequest::V1(v01::HostPaymentTopUpRequest {
            into,
            amount,
            source,
        }) = request;
        purse
            .top_up(into, amount, source)
            .await
            .map(|()| HostPaymentTopUpResponse::V1)
            .map_err(|error| CallError::Domain(HostPaymentTopUpError::V1(error)))
    }
}
