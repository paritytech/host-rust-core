//! Versioned wrappers for [`ResourceAllocation`](crate::api::ResourceAllocation) methods.

use crate::CallError;
use crate::v01;
use crate::versioned::Request as RequestEnvelope;

truapi_macros::versioned_type! {
    pub enum HostRequestResourceAllocationRequest { V1 => v01::HostRequestResourceAllocationRequest }
    pub enum HostRequestResourceAllocationResponse { V1 => v01::HostRequestResourceAllocationResponse }
    pub enum HostRequestResourceAllocationError { V1 => v01::ResourceAllocationError }

    /// Wire-envelope version for
    /// [`ResourceAllocation::request`](crate::api::ResourceAllocation::request).
    /// Used only by the generated dispatcher/client.
    pub enum HostRequestResourceAllocationVersion {
        V1 => RequestEnvelope<v01::HostRequestResourceAllocationRequest, Result<v01::HostRequestResourceAllocationResponse, CallError<v01::ResourceAllocationError>>>,
    }
}
