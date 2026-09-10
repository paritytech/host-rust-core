//! Product-facing `Scarcity` (NFT pocket) capability adapter.
//!
//! Answered by the signing host's pocket engine once it lands; every host
//! reports the service unsupported until then.

use tracing::instrument;
use truapi::api::Scarcity;
use truapi::versioned::scarcity::{
    HostScarcityListError, HostScarcityListRequest, HostScarcityListResponse,
    HostScarcityListSubscribeError, HostScarcityListSubscribeItem,
    HostScarcityListSubscribeRequest, HostScarcityRequestReceiveAddressError,
    HostScarcityRequestReceiveAddressRequest, HostScarcityRequestReceiveAddressResponse,
    HostScarcityTransferError, HostScarcityTransferItem, HostScarcityTransferRequest,
};
use truapi::{CallContext, CallError, Subscription};

use crate::runtime::ProductRuntimeHost;

#[truapi::async_trait]
impl Scarcity for ProductRuntimeHost {
    #[instrument(skip_all, fields(runtime.method = "scarcity.list"))]
    async fn list(
        &self,
        _cx: &CallContext,
        _request: HostScarcityListRequest,
    ) -> Result<HostScarcityListResponse, CallError<HostScarcityListError>> {
        Err(CallError::Unsupported)
    }

    #[instrument(skip_all, fields(runtime.method = "scarcity.request_receive_address"))]
    async fn request_receive_address(
        &self,
        _cx: &CallContext,
        _request: HostScarcityRequestReceiveAddressRequest,
    ) -> Result<
        HostScarcityRequestReceiveAddressResponse,
        CallError<HostScarcityRequestReceiveAddressError>,
    > {
        Err(CallError::Unsupported)
    }

    #[instrument(skip_all, fields(runtime.method = "scarcity.transfer"))]
    async fn transfer(
        &self,
        _cx: &CallContext,
        _request: HostScarcityTransferRequest,
    ) -> Result<Subscription<HostScarcityTransferItem>, CallError<HostScarcityTransferError>> {
        Err(CallError::Unsupported)
    }

    #[instrument(skip_all, fields(runtime.method = "scarcity.list_subscribe"))]
    async fn list_subscribe(
        &self,
        _cx: &CallContext,
        _request: HostScarcityListSubscribeRequest,
    ) -> Result<
        Subscription<HostScarcityListSubscribeItem>,
        CallError<HostScarcityListSubscribeError>,
    > {
        Err(CallError::Unsupported)
    }
}
