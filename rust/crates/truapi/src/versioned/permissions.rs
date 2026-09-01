//! Versioned wrappers for [`Permissions`](crate::api::Permissions) methods.

use crate::CallError;
use crate::v01;
use crate::versioned::Request as RequestEnvelope;

truapi_macros::versioned_type! {
    #[derive(derive_more::Display)]
    #[display("{_0}")]
    pub enum HostDevicePermissionRequest { V1 => v01::HostDevicePermissionRequest }
    pub enum HostDevicePermissionResponse { V1 => v01::HostDevicePermissionResponse }
    pub enum HostDevicePermissionError { V1 => v01::GenericError }
    #[derive(derive_more::Display)]
    #[display("{_0}")]
    pub enum RemotePermissionRequest { V1 => v01::RemotePermissionRequest }
    pub enum RemotePermissionResponse { V1 => v01::RemotePermissionResponse }
    pub enum RemotePermissionError { V1 => v01::GenericError }

    /// Wire-envelope version for
    /// [`Permissions::request_device_permission`](crate::api::Permissions::request_device_permission).
    /// Used only by the generated dispatcher/client.
    pub enum HostDevicePermissionVersion {
        V1 => RequestEnvelope<v01::HostDevicePermissionRequest, Result<v01::HostDevicePermissionResponse, CallError<v01::GenericError>>>,
    }

    /// Wire-envelope version for
    /// [`Permissions::request_remote_permission`](crate::api::Permissions::request_remote_permission).
    /// Used only by the generated dispatcher/client.
    pub enum RemotePermissionVersion {
        V1 => RequestEnvelope<v01::RemotePermissionRequest, Result<v01::RemotePermissionResponse, CallError<v01::GenericError>>>,
    }
}
