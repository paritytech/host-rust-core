//! Versioned wrappers for [`LocalStorage`](crate::api::LocalStorage) methods.

use crate::CallError;
use crate::v01;
use crate::versioned::Request as RequestEnvelope;

truapi_macros::versioned_type! {
    pub enum HostLocalStorageReadRequest { V1 => v01::HostLocalStorageReadRequest }
    pub enum HostLocalStorageReadResponse { V1 => v01::HostLocalStorageReadResponse }
    pub enum HostLocalStorageReadError { V1 => v01::HostLocalStorageReadError }
    pub enum HostLocalStorageWriteRequest { V1 => v01::HostLocalStorageWriteRequest }
    pub enum HostLocalStorageWriteResponse { V1 }
    pub enum HostLocalStorageWriteError { V1 => v01::HostLocalStorageReadError }
    pub enum HostLocalStorageClearRequest { V1 => v01::HostLocalStorageClearRequest }
    pub enum HostLocalStorageClearResponse { V1 }
    pub enum HostLocalStorageClearError { V1 => v01::HostLocalStorageReadError }

    /// Wire-envelope version for [`LocalStorage::read`](crate::api::LocalStorage::read).
    /// Used only by the generated dispatcher/client.
    pub enum HostLocalStorageReadVersion {
        V1 => RequestEnvelope<v01::HostLocalStorageReadRequest, Result<v01::HostLocalStorageReadResponse, CallError<v01::HostLocalStorageReadError>>>,
    }

    /// Wire-envelope version for [`LocalStorage::write`](crate::api::LocalStorage::write).
    /// Used only by the generated dispatcher/client.
    pub enum HostLocalStorageWriteVersion {
        V1 => RequestEnvelope<v01::HostLocalStorageWriteRequest, Result<(), CallError<v01::HostLocalStorageReadError>>>,
    }

    /// Wire-envelope version for [`LocalStorage::clear`](crate::api::LocalStorage::clear).
    /// Used only by the generated dispatcher/client.
    pub enum HostLocalStorageClearVersion {
        V1 => RequestEnvelope<v01::HostLocalStorageClearRequest, Result<(), CallError<v01::HostLocalStorageReadError>>>,
    }
}
