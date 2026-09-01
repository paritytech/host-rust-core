//! Versioned wrappers for [`Theme`](crate::api::Theme) methods.

use crate::CallError;
use crate::v01;
use crate::versioned::Subscription as SubscriptionEnvelope;

truapi_macros::versioned_type! {
    pub enum HostThemeSubscribeItem { V1 => v01::HostThemeSubscribeItem }

    /// Wire-envelope version for [`Theme::subscribe`](crate::api::Theme::subscribe).
    /// Used only by the generated dispatcher/client.
    pub enum HostThemeSubscribeVersion {
        V1 => SubscriptionEnvelope<(), v01::HostThemeSubscribeItem, CallError<crate::latest::GenericError>>,
    }
}
