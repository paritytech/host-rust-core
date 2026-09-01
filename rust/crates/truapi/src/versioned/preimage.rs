//! Versioned wrappers for [`Preimage`](crate::api::Preimage) methods.

use crate::CallError;
use crate::v01;
use crate::versioned::Request as RequestEnvelope;
use crate::versioned::Subscription as SubscriptionEnvelope;

truapi_macros::versioned_type! {
    pub enum RemotePreimageLookupSubscribeRequest { V1 => v01::RemotePreimageLookupSubscribeRequest }
    pub enum RemotePreimageLookupSubscribeItem { V1 => v01::RemotePreimageLookupSubscribeItem }
    pub enum RemotePreimageSubmitRequest { V1 => Vec<u8> }
    pub enum RemotePreimageSubmitResponse { V1 => Vec<u8> }
    pub enum RemotePreimageSubmitError { V1 => v01::PreimageSubmitError }

    /// Wire-envelope version for
    /// [`Preimage::lookup_subscribe`](crate::api::Preimage::lookup_subscribe).
    /// Used only by the generated dispatcher/client.
    pub enum RemotePreimageLookupSubscribeVersion {
        V1 => SubscriptionEnvelope<v01::RemotePreimageLookupSubscribeRequest, v01::RemotePreimageLookupSubscribeItem, CallError<crate::latest::GenericError>>,
    }

    /// Wire-envelope version for [`Preimage::submit`](crate::api::Preimage::submit).
    /// Used only by the generated dispatcher/client.
    pub enum RemotePreimageSubmitVersion {
        V1 => RequestEnvelope<Vec<u8>, Result<Vec<u8>, CallError<v01::PreimageSubmitError>>>,
    }
}
