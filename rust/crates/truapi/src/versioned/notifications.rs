//! Versioned wrappers for [`Notifications`](crate::api::Notifications) methods.

use crate::versioned::{FromLatest, IntoLatest};
use crate::{v01, v02};

truapi_macros::versioned_type! {
    pub enum HostPushNotificationRequest {
        V1 => v01::HostPushNotificationRequest,
        V2 => v02::HostPushNotificationRequest,
    }
    pub enum HostPushNotificationResponse {
        V1 => v01::HostPushNotificationResponse,
        V2 => v02::HostPushNotificationResponse,
    }
    pub enum HostPushNotificationError {
        V1 => v01::HostPushNotificationError,
        V2 => v01::HostPushNotificationError,
    }
    pub enum HostPushNotificationCancelRequest { V1 => v01::HostPushNotificationCancelRequest }
    pub enum HostPushNotificationCancelResponse { V1 }
    pub enum HostPushNotificationCancelError { V1 => v01::GenericError }
}

impl IntoLatest for HostPushNotificationRequest {
    fn into_latest(self) -> Self::Latest {
        match self {
            Self::V1(v01::HostPushNotificationRequest {
                text,
                deeplink,
                scheduled_at,
            }) => v02::HostPushNotificationRequest {
                text,
                deeplink,
                scheduled_at,
                urgency: v01::HostPushNotificationUrgency::Normal,
            },
            Self::V2(latest) => latest,
        }
    }
}

impl IntoLatest for HostPushNotificationResponse {
    fn into_latest(self) -> Self::Latest {
        match self {
            Self::V1(v01::HostPushNotificationResponse { id }) => {
                v02::HostPushNotificationResponse {
                    id,
                    urgency: v01::HostPushNotificationUrgency::Normal,
                }
            }
            Self::V2(latest) => latest,
        }
    }
}

impl FromLatest for HostPushNotificationResponse {
    fn from_latest(latest: Self::Latest, target: u8) -> Self {
        if target >= 2 {
            return Self::V2(latest);
        }
        Self::V1(v01::HostPushNotificationResponse { id: latest.id })
    }
}

impl IntoLatest for HostPushNotificationError {
    fn into_latest(self) -> Self::Latest {
        match self {
            Self::V1(payload) | Self::V2(payload) => payload,
        }
    }
}

impl FromLatest for HostPushNotificationError {
    fn from_latest(latest: Self::Latest, target: u8) -> Self {
        if target >= 2 {
            Self::V2(latest)
        } else {
            Self::V1(latest)
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn a_v01_request_upgrades_to_the_only_delivery_v01_had() {
        let upgraded = HostPushNotificationRequest::V1(v01::HostPushNotificationRequest {
            text: "hi".to_string(),
            deeplink: None,
            scheduled_at: None,
        })
        .into_latest();
        assert_eq!(
            upgraded,
            v02::HostPushNotificationRequest {
                text: "hi".to_string(),
                deeplink: None,
                scheduled_at: None,
                urgency: v01::HostPushNotificationUrgency::Normal,
            }
        );
    }

    #[test]
    fn a_v02_peer_reads_the_delivered_urgency() {
        let delivered = v02::HostPushNotificationResponse {
            id: 7,
            urgency: v01::HostPushNotificationUrgency::Critical,
        };
        assert_eq!(
            HostPushNotificationResponse::from_latest(delivered.clone(), 2),
            HostPushNotificationResponse::V2(delivered)
        );
    }

    #[test]
    fn a_v01_peer_reads_the_id_alone() {
        // A v0.1 caller could not ask for an urgency, so it has none to read
        // back, and the downgrade still has to be total.
        assert_eq!(
            HostPushNotificationResponse::from_latest(
                v02::HostPushNotificationResponse {
                    id: 7,
                    urgency: v01::HostPushNotificationUrgency::Critical,
                },
                1
            ),
            HostPushNotificationResponse::V1(v01::HostPushNotificationResponse { id: 7 })
        );
    }
}
