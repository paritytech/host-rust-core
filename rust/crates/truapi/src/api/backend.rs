//! Unified [`Backend`] trait.

use crate::versioned::backend::{
    HostBackendError, HostBackendListError, HostBackendListRequest, HostBackendListResponse,
    HostBackendRequest, HostBackendResponse,
};
use crate::{CallContext, CallError};
use crate::{wire, wire_trait};

/// Requests against a backend the host holds a credential for.
///
/// A product cannot hold a server-side API key, so the deployer's backend holds
/// the third-party key and makes the onward call to the provider. The host holds
/// a credential for that backend and nothing else; the core carries the request
/// between them. The product never learns the origin it reached or the
/// credential that authenticated the call.
///
/// Which backends exist is host configuration, not protocol. A host with no
/// tunnel at all answers `Unsupported`; one that has a tunnel but does not
/// serve the named backend answers `UnknownBackend`.
#[wire_trait(id = 19)]
#[crate::async_trait]
pub trait Backend: Send + Sync {
    /// Perform one request against a registered backend.
    ///
    /// `path` is absolute within the backend and cannot leave its origin, so
    /// variable data belongs in `query`. A redirect comes back as its `3xx`
    /// rather than being followed.
    ///
    /// ```ts
    /// const result = await truapi.backend.request({
    ///   backend: "echo",
    ///   method: "Get",
    ///   path: "/ok",
    ///   query: [{ name: "hello", value: "world" }],
    ///   body: undefined,
    /// });
    /// assert(result.isOk(), "backend request failed:", result);
    /// console.log("backend answered:", result.value.status);
    /// ```
    #[wire(id = 0)]
    async fn request(
        &self,
        _cx: &CallContext,
        _request: HostBackendRequest,
    ) -> Result<HostBackendResponse, CallError<HostBackendError>> {
        Err(CallError::unavailable())
    }

    /// Backends this host serves the calling product.
    ///
    /// The identifiers are what [`Self::request`] accepts; a host reports only
    /// what that product may reach, so an empty list means this host serves the
    /// product no backends rather than that it has none. It carries no origins:
    /// where a backend lives stays host-side.
    ///
    /// ```ts
    /// const result = await truapi.backend.list();
    /// assert(result.isOk(), "backend list failed:", result);
    /// console.log("backends available:", result.value.backends);
    /// ```
    #[wire(id = 1)]
    async fn list(
        &self,
        _cx: &CallContext,
        _request: HostBackendListRequest,
    ) -> Result<HostBackendListResponse, CallError<HostBackendListError>> {
        Err(CallError::unavailable())
    }
}
