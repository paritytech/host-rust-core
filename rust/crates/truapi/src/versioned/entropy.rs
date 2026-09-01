//! Versioned wrappers for [`Entropy`](crate::api::Entropy) methods.

use crate::CallError;
use crate::v01;
use crate::versioned::Request as RequestEnvelope;

truapi_macros::versioned_type! {
    pub enum HostDeriveEntropyRequest { V1 => v01::HostDeriveEntropyRequest }
    pub enum HostDeriveEntropyResponse { V1 => v01::HostDeriveEntropyResponse }
    pub enum HostDeriveEntropyError { V1 => v01::HostDeriveEntropyError }

    /// Wire-envelope version for [`Entropy::derive`](crate::api::Entropy::derive).
    /// Used only by the generated dispatcher/client.
    pub enum HostDeriveEntropyVersion {
        V1 => RequestEnvelope<v01::HostDeriveEntropyRequest, Result<v01::HostDeriveEntropyResponse, CallError<v01::HostDeriveEntropyError>>>,
    }
}
