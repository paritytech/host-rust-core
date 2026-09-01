//! Versioned wrappers for [`Locale`](crate::api::Locale) methods.

use crate::CallError;
use crate::v01;
use crate::versioned::Subscription as SubscriptionEnvelope;

truapi_macros::versioned_type! {
    pub enum HostLocaleSubscribeItem { V1 => v01::HostLocaleSubscribeItem }
}

truapi_macros::versioned_type! {
    /// Wire-envelope version for [`Locale::subscribe`](crate::api::Locale::subscribe).
    /// Used only by the generated dispatcher/client — trait signatures keep
    /// naming [`HostLocaleSubscribeItem`] directly.
    pub enum HostLocaleSubscribeVersion {
        V1 => SubscriptionEnvelope<(), v01::HostLocaleSubscribeItem, CallError<crate::latest::GenericError>>,
    }
}
