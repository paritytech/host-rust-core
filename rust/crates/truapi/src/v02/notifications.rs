use parity_scale_codec::{Decode, Encode};

/// Push notification payload.
///
/// When `scheduled_at` is `Some`, the notification is deferred to the given
/// wall-clock instant (Unix milliseconds UTC). `None` fires immediately. See
/// [RFC 0019].
///
/// [RFC 0019]: https://github.com/paritytech/host-rust-core/blob/main/docs/rfcs/0019-scheduled-notifications.md
#[derive(Debug, Clone, PartialEq, Eq, Encode, Decode)]
pub struct HostPushNotificationRequest {
    /// Notification text.
    pub text: String,
    /// Optional URL to open on tap.
    pub deeplink: Option<String>,
    /// Optional Unix timestamp in milliseconds (UTC) at which the notification
    /// should fire. `None` fires immediately.
    pub scheduled_at: Option<u64>,
    /// How the host is asked to deliver the notification.
    pub urgency: crate::v01::HostPushNotificationUrgency,
}

/// Successful push notification response.
#[derive(Debug, Clone, PartialEq, Eq, Encode, Decode)]
pub struct HostPushNotificationResponse {
    /// Host-assigned notification identifier.
    pub id: crate::v01::NotificationId,
    /// Urgency the core resolved the request to, which is `Normal` for a
    /// `Critical` request from a product without the `Alarms` grant.
    pub urgency: crate::v01::HostPushNotificationUrgency,
}
