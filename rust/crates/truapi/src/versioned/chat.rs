//! Versioned wrappers for [`Chat`](crate::api::Chat) methods.

use crate::CallError;
use crate::v01;
use crate::versioned::Request as RequestEnvelope;
use crate::versioned::Subscription as SubscriptionEnvelope;

truapi_macros::versioned_type! {
    pub enum HostChatCreateRoomRequest { V1 => v01::HostChatCreateRoomRequest }
    pub enum HostChatCreateRoomResponse { V1 => v01::HostChatCreateRoomResponse }
    pub enum HostChatCreateRoomError { V1 => v01::HostChatCreateRoomError }
    pub enum HostChatRegisterBotRequest { V1 => v01::HostChatRegisterBotRequest }
    pub enum HostChatRegisterBotResponse { V1 => v01::HostChatRegisterBotResponse }
    pub enum HostChatRegisterBotError { V1 => v01::HostChatRegisterBotError }
    pub enum HostChatPostMessageRequest { V1 => v01::HostChatPostMessageRequest }
    pub enum HostChatPostMessageResponse { V1 => v01::HostChatPostMessageResponse }
    pub enum HostChatPostMessageError { V1 => v01::HostChatPostMessageError }
    pub enum HostChatListSubscribeItem { V1 => v01::HostChatListSubscribeItem }
    pub enum HostChatActionSubscribeItem { V1 => v01::HostChatActionSubscribeItem }
    pub enum ProductChatCustomMessageRenderRequest { V1 => v01::ProductChatCustomMessageRenderRequest }
    pub enum ProductChatCustomMessageRenderItem { V1 => v01::CustomRendererNode }

    /// Wire-envelope version for [`Chat::create_room`](crate::api::Chat::create_room).
    /// Used only by the generated dispatcher/client.
    pub enum HostChatCreateRoomVersion {
        V1 => RequestEnvelope<v01::HostChatCreateRoomRequest, Result<v01::HostChatCreateRoomResponse, CallError<v01::HostChatCreateRoomError>>>,
    }

    /// Wire-envelope version for [`Chat::register_bot`](crate::api::Chat::register_bot).
    /// Used only by the generated dispatcher/client.
    pub enum HostChatRegisterBotVersion {
        V1 => RequestEnvelope<v01::HostChatRegisterBotRequest, Result<v01::HostChatRegisterBotResponse, CallError<v01::HostChatRegisterBotError>>>,
    }

    /// Wire-envelope version for [`Chat::list_subscribe`](crate::api::Chat::list_subscribe).
    /// Used only by the generated dispatcher/client.
    pub enum HostChatListSubscribeVersion {
        V1 => SubscriptionEnvelope<(), v01::HostChatListSubscribeItem, CallError<crate::latest::GenericError>>,
    }

    /// Wire-envelope version for [`Chat::post_message`](crate::api::Chat::post_message).
    /// Used only by the generated dispatcher/client.
    pub enum HostChatPostMessageVersion {
        V1 => RequestEnvelope<v01::HostChatPostMessageRequest, Result<v01::HostChatPostMessageResponse, CallError<v01::HostChatPostMessageError>>>,
    }

    /// Wire-envelope version for [`Chat::action_subscribe`](crate::api::Chat::action_subscribe).
    /// Used only by the generated dispatcher/client.
    pub enum HostChatActionSubscribeVersion {
        V1 => SubscriptionEnvelope<(), v01::HostChatActionSubscribeItem, CallError<crate::latest::GenericError>>,
    }

    /// Wire-envelope version for
    /// [`Chat::custom_message_render`](crate::api::Chat::custom_message_render).
    /// Used only by the generated dispatcher/client.
    pub enum ProductChatCustomMessageRenderVersion {
        V1 => SubscriptionEnvelope<v01::ProductChatCustomMessageRenderRequest, v01::CustomRendererNode, CallError<crate::latest::GenericError>>,
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use parity_scale_codec::{Decode, Encode};

    // Fixture is `ChatRegisterBotV1_request` output from triangle-js-sdks
    // `packages/host-api`, under an `Enum({ v1: … })` envelope. Requests and
    // success responses match that host; error frames do not, because
    // `CallError` adds a tag and inner version (`TODO(shared-core-wire)`).
    #[test]
    fn register_bot_request_matches_reference_host_wire() {
        let request = HostChatRegisterBotRequest::V1(v01::HostChatRegisterBotRequest {
            bot_id: "flipper".into(),
            name: "Flipper".into(),
            icon: String::new(),
        });

        assert_eq!(
            hex::encode(request.encode()),
            "001c666c69707065721c466c697070657200"
        );

        let decoded = HostChatRegisterBotRequest::decode(&mut request.encode().as_slice()).unwrap();
        assert_eq!(decoded, request);
    }

    // Discriminant order matches the reference host's `Status('New','Exists')`.
    // The dispatcher adds the `Result` byte, so this pins the payload only.
    #[test]
    fn register_bot_response_status_matches_reference_host_wire() {
        let new = HostChatRegisterBotResponse::V1(v01::HostChatRegisterBotResponse {
            status: v01::ChatBotRegistrationStatus::New,
        });
        let exists = HostChatRegisterBotResponse::V1(v01::HostChatRegisterBotResponse {
            status: v01::ChatBotRegistrationStatus::Exists,
        });

        assert_eq!(hex::encode(new.encode()), "0000");
        assert_eq!(hex::encode(exists.encode()), "0001");

        assert_eq!(
            HostChatRegisterBotResponse::decode(&mut new.encode().as_slice()).unwrap(),
            new
        );
    }

    #[test]
    fn custom_render_start_matches_legacy_wire_fixture() {
        let request =
            ProductChatCustomMessageRenderRequest::V1(v01::ProductChatCustomMessageRenderRequest {
                message_id: "message-1".into(),
                message_type: "vote".into(),
                payload: vec![1, 2],
            });

        assert_eq!(
            hex::encode(request.encode()),
            "00246d6573736167652d3110766f7465080102"
        );
    }

    #[test]
    fn custom_render_receive_matches_legacy_wire_fixture() {
        let item = ProductChatCustomMessageRenderItem::V1(v01::CustomRendererNode::String {
            text: "Votes: 1".into(),
        });

        assert_eq!(hex::encode(item.encode()), "000120566f7465733a2031");
    }
}
