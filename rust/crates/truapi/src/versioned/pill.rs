//! Versioned wrappers for [`Pill`](crate::api::Pill) methods.

use crate::v01;

truapi_macros::versioned_type! {
    pub enum HostPillDeclareRequest { V1 => v01::HostPillDeclareRequest }
    pub enum HostPillDeclareResponse { V1 }
    pub enum HostPillDeclareError { V1 => v01::GenericError }
    pub enum HostPillWithdrawRequest { V1 => v01::HostPillWithdrawRequest }
    pub enum HostPillWithdrawResponse { V1 }
    pub enum HostPillWithdrawError { V1 => v01::GenericError }
}
