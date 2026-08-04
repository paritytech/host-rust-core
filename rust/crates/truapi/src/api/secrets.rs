//! Unified [`Secrets`] trait.

use crate::versioned::secrets::{HostSecretError, HostSecretRequest, HostSecretResponse};
use crate::wire;
use crate::{CallContext, CallError};

/// Calls made with a credential the product never holds.
#[crate::async_trait]
pub trait Secrets: Send + Sync {
    /// Send a request to a backend and return its response.
    ///
    /// The backend is resolved as `secret:<name>` in the dotNS records of
    /// `product_id`. That record fixes the endpoint, path, and method, so the
    /// caller supplies only a query, headers, and a body.
    ///
    /// ```ts
    /// const result = await truapi.secrets.request({
    ///   productId: "onramp.dot",
    ///   name: "meld-session",
    ///   query: [],
    ///   headers: [{ name: "Content-Type", value: "application/json" }],
    ///   body: encoded,
    /// });
    /// assert(result.isOk(), "secrets.request failed:", result);
    /// console.log("backend responded:", result.value.status);
    /// ```
    #[wire(request_id = 166)]
    async fn request(
        &self,
        _cx: &CallContext,
        _request: HostSecretRequest,
    ) -> Result<HostSecretResponse, CallError<HostSecretError>> {
        Err(CallError::unavailable())
    }
}
