//! Versioned wrappers for [`System`](crate::api::System) methods.

use crate::CallError;
use crate::v01;
use crate::versioned::Request as RequestEnvelope;

truapi_macros::versioned_type! {
    pub enum HostHandshakeRequest { V1 => v01::HostHandshakeRequest }
    pub enum HostHandshakeResponse { V1 }
    pub enum HostHandshakeError { V1 => v01::HostHandshakeError }
    pub enum HostFeatureSupportedRequest { V1 => v01::HostFeatureSupportedRequest }
    pub enum HostFeatureSupportedResponse { V1 => v01::HostFeatureSupportedResponse }
    pub enum HostFeatureSupportedError { V1 => v01::GenericError }
    pub enum HostNavigateToRequest { V1 => v01::HostNavigateToRequest }
    pub enum HostNavigateToResponse { V1 }
    pub enum HostNavigateToError { V1 => v01::HostNavigateToError }
    pub enum HostInfoRequest { V1 }
    pub enum HostInfoResponse { V1 => v01::HostInfo }
    pub enum HostInfoError { V1 => v01::GenericError }
    pub enum HostGetProductContextRequest { V1 }
    pub enum HostGetProductContextResponse { V1 => v01::HostGetProductContextResponse }
    pub enum HostGetProductContextError { V1 => v01::GenericError }

    /// Wire-envelope version for [`System::handshake`](crate::api::System::handshake).
    /// Used only by the generated dispatcher/client.
    pub enum HostHandshakeVersion {
        V1 => RequestEnvelope<v01::HostHandshakeRequest, Result<(), CallError<v01::HostHandshakeError>>>,
    }

    /// Wire-envelope version for
    /// [`System::feature_supported`](crate::api::System::feature_supported).
    /// Used only by the generated dispatcher/client.
    pub enum HostFeatureSupportedVersion {
        V1 => RequestEnvelope<v01::HostFeatureSupportedRequest, Result<v01::HostFeatureSupportedResponse, CallError<v01::GenericError>>>,
    }

    /// Wire-envelope version for [`System::navigate_to`](crate::api::System::navigate_to).
    /// Used only by the generated dispatcher/client.
    pub enum HostNavigateToVersion {
        V1 => RequestEnvelope<v01::HostNavigateToRequest, Result<(), CallError<v01::HostNavigateToError>>>,
    }

    /// Wire-envelope version for [`System::host_info`](crate::api::System::host_info).
    /// Used only by the generated dispatcher/client.
    pub enum HostInfoVersion {
        V1 => RequestEnvelope<(), Result<v01::HostInfo, CallError<v01::GenericError>>>,
    }

    /// Wire-envelope version for
    /// [`System::get_product_context`](crate::api::System::get_product_context).
    /// Used only by the generated dispatcher/client.
    pub enum HostGetProductContextVersion {
        V1 => RequestEnvelope<(), Result<v01::HostGetProductContextResponse, CallError<v01::GenericError>>>,
    }
}
