//! Unified [`Permissions`] trait.

use crate::versioned::permissions::{
    HostDevicePermissionError, HostDevicePermissionRequest, HostDevicePermissionResponse,
    RemotePermissionError, RemotePermissionRequest, RemotePermissionResponse,
};
use crate::{CallContext, CallError};
use crate::{wire, wire_trait};

/// Permission request methods.
#[wire_trait(id = 202)]
#[crate::async_trait]
pub trait Permissions: Send + Sync {
    /// Request a device-capability permission from the user.
    ///
    /// ```ts
    /// const result = await truapi.permissions.requestDevicePermission("Camera");
    /// assert(result.isOk(), "requestDevicePermission failed:", result);
    /// console.log("device permission result:", result.value);
    /// ```
    #[wire(request_id = 0)]
    async fn request_device_permission(
        &self,
        cx: &CallContext,
        request: HostDevicePermissionRequest,
    ) -> Result<HostDevicePermissionResponse, CallError<HostDevicePermissionError>>;

    /// Request a remote-operation permission.
    ///
    /// ```ts
    /// const result = await truapi.permissions.requestRemotePermission({
    ///   permission: { tag: "Remote", value: { domains: ["api.example.com"] } },
    /// });
    /// assert(result.isOk(), "requestRemotePermission failed:", result);
    /// console.log("remote permission result:", result.value);
    /// ```
    #[wire(request_id = 2)]
    async fn request_remote_permission(
        &self,
        cx: &CallContext,
        request: RemotePermissionRequest,
    ) -> Result<RemotePermissionResponse, CallError<RemotePermissionError>>;
}
