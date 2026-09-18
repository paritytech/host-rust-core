//! Versioned wrappers for [`Backend`](crate::api::Backend) methods.

use crate::v01;

truapi_macros::versioned_type! {
    pub enum HostBackendRequest { V1 => v01::HostBackendRequest }
    pub enum HostBackendResponse { V1 => v01::HostBackendResponse }
    pub enum HostBackendError { V1 => v01::HostBackendError }
    pub enum HostBackendListRequest { V1 }
    pub enum HostBackendListResponse { V1 => v01::HostBackendListResponse }
    pub enum HostBackendListError { V1 => v01::GenericError }
}
