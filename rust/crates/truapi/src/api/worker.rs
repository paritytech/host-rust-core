//! Unified [`Worker`] trait.

use crate::versioned::worker::{
    HostWorkerBeginOperationError, HostWorkerBeginOperationRequest,
    HostWorkerBeginOperationResponse, HostWorkerEndOperationError, HostWorkerEndOperationRequest,
    HostWorkerEndOperationResponse,
};
use crate::wire;
use crate::{CallContext, CallError};

/// Worker background-operation APIs.
///
/// A worker holds itself alive by keeping an operation open. The host keeps
/// the product's worker running while it has at least one open operation.
#[crate::service(required_execution = Worker)]
#[crate::async_trait]
pub trait Worker: Send + Sync {
    /// Begin a pending operation. The worker is kept alive while it has at
    /// least one open operation. Returns an id for `end_operation`.
    ///
    /// ```ts
    /// const result = await truapi.worker.beginOperation({ label: "funding" });
    /// assert(result.isOk(), "beginOperation failed:", result);
    /// console.log("operation started:", result.value.id);
    /// await truapi.worker.endOperation({ id: result.value.id });
    /// ```
    #[wire(request_id = 202)]
    async fn begin_operation(
        &self,
        _cx: &CallContext,
        _request: HostWorkerBeginOperationRequest,
    ) -> Result<HostWorkerBeginOperationResponse, CallError<HostWorkerBeginOperationError>> {
        Err(CallError::unavailable())
    }

    /// End a pending operation. Idempotent: an unknown or already-ended id
    /// returns success.
    ///
    /// ```ts
    /// const begun = await truapi.worker.beginOperation({});
    /// assert(begun.isOk(), "beginOperation failed:", begun);
    /// const result = await truapi.worker.endOperation({ id: begun.value.id });
    /// assert(result.isOk(), "endOperation failed:", result);
    /// console.log("operation ended");
    /// ```
    #[wire(request_id = 204)]
    async fn end_operation(
        &self,
        _cx: &CallContext,
        _request: HostWorkerEndOperationRequest,
    ) -> Result<HostWorkerEndOperationResponse, CallError<HostWorkerEndOperationError>> {
        Err(CallError::unavailable())
    }
}
