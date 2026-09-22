//! Product-facing backend capability adapter.

use tracing::instrument;
use truapi::api::Backend;
use truapi::versioned::backend::{
    HostBackendError, HostBackendListError, HostBackendListRequest, HostBackendListResponse,
    HostBackendRequest, HostBackendResponse,
};
use truapi::{CallContext, CallError};

use crate::host_logic::backend::{screen_request, screen_response};
use crate::runtime::backend_session::{Authorization, now_ms};

/// The status that means the session the core attached is no longer good.
const UNAUTHORIZED: u16 = 401;
use crate::runtime::ProductRuntimeHost;

#[truapi::async_trait]
impl Backend for ProductRuntimeHost {
    #[instrument(skip_all, fields(runtime.method = "backend.request"))]
    async fn request(
        &self,
        _cx: &CallContext,
        request: HostBackendRequest,
    ) -> Result<HostBackendResponse, CallError<HostBackendError>> {
        let HostBackendRequest::V1(inner) = request;
        let host = self.backend_host()?;

        screen_request(&inner).map_err(domain)?;

        // Authenticating a backend that answers per person is the core's job,
        // not the product's and not the host's: nothing a product sends can
        // reach this argument.
        let authorization = match self.personhood_prover() {
            Some(prover) => {
                match self
                    .backend_sessions()
                    .authorization(
                        host.as_ref(),
                        prover,
                        &self.product,
                        &inner.backend,
                        now_ms(),
                    )
                    .await
                {
                    Authorization::Session(token) => Some(token),
                    Authorization::Unauthenticated => None,
                    // This backend wants a person and the core could not
                    // prove one. Sending the call anyway spends the caller's
                    // budget to collect the backend's `401`, and reports it as
                    // though the product had been refused on its merits.
                    Authorization::Unavailable(reason) => {
                        return Err(CallError::Domain(HostBackendError::V1(
                            truapi::latest::HostBackendError::Unknown { reason },
                        )));
                    }
                }
            }
            None => None,
        };

        let mut response = host
            .backend_request(&self.product, inner.clone(), authorization.clone())
            .await
            .map_err(domain)?;

        // A backend refusing the session the core holds is saying the token is
        // stale in a way its stated expiry did not predict. The person is
        // still a person, so one more handshake settles it; a second refusal
        // is the backend's answer and belongs to the product.
        if response.status == UNAUTHORIZED
            && authorization.is_some()
            && let Some(prover) = self.personhood_prover()
            && let Some(refreshed) = self
                .backend_sessions()
                .reauthenticate(
                    host.as_ref(),
                    prover,
                    &self.product,
                    &inner.backend,
                    now_ms(),
                )
                .await
        {
            response = host
                .backend_request(&self.product, inner, Some(refreshed))
                .await
                .map_err(domain)?;
        }
        // The host owes the allowlist and the cap; this catches one that skips them.
        screen_response(&mut response).map_err(domain)?;
        Ok(HostBackendResponse::V1(response))
    }

    #[instrument(skip_all, fields(runtime.method = "backend.list"))]
    async fn list(
        &self,
        _cx: &CallContext,
        _request: HostBackendListRequest,
    ) -> Result<HostBackendListResponse, CallError<HostBackendListError>> {
        let host = self.backend_host()?;
        host.backends(&self.product)
            .await
            .map(HostBackendListResponse::V1)
            .map_err(|error| CallError::Domain(HostBackendListError::V1(error)))
    }
}

fn domain(error: truapi::latest::HostBackendError) -> CallError<HostBackendError> {
    CallError::Domain(HostBackendError::V1(error))
}
