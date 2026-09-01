//! Versioned wrappers for [`Notifications`](crate::api::Notifications) methods.

use crate::CallError;
use crate::v01;
use crate::versioned::Request as RequestEnvelope;

truapi_macros::versioned_type! {
    pub enum HostPushNotificationRequest { V1 => v01::HostPushNotificationRequest }
    pub enum HostPushNotificationResponse { V1 => v01::HostPushNotificationResponse }
    pub enum HostPushNotificationError { V1 => v01::HostPushNotificationError }
    pub enum HostPushNotificationCancelRequest { V1 => v01::HostPushNotificationCancelRequest }
    pub enum HostPushNotificationCancelResponse { V1 }
    pub enum HostPushNotificationCancelError { V1 => v01::GenericError }

    /// Wire-envelope version for
    /// [`Notifications::send_push_notification`](crate::api::Notifications::send_push_notification).
    /// Used only by the generated dispatcher/client.
    pub enum HostPushNotificationVersion {
        V1 => RequestEnvelope<v01::HostPushNotificationRequest, Result<v01::HostPushNotificationResponse, CallError<v01::HostPushNotificationError>>>,
    }

    /// Wire-envelope version for
    /// [`Notifications::cancel_push_notification`](crate::api::Notifications::cancel_push_notification).
    /// Used only by the generated dispatcher/client.
    pub enum HostPushNotificationCancelVersion {
        V1 => RequestEnvelope<v01::HostPushNotificationCancelRequest, Result<(), CallError<v01::GenericError>>>,
    }
}
