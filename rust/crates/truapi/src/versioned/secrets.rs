//! Versioned wrappers for [`Secrets`](crate::api::Secrets) methods.

use crate::v01;

truapi_macros::versioned_type! {
    pub enum HostSecretRequest { V1 => v01::HostSecretRequest }
    pub enum HostSecretResponse { V1 => v01::HostSecretResponse }
    pub enum HostSecretError { V1 => v01::HostSecretError }
}
