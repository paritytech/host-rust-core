//! Versioned wrappers for [`Pocket`](crate::api::Pocket) methods.

use crate::v01;

truapi_macros::versioned_type! {
    pub enum HostPocketListSubscribeItem { V1 => v01::HostPocketListSubscribeItem }
    pub enum HostPocketRemoveCardRequest { V1 => v01::HostPocketRemoveCardRequest }
    pub enum HostPocketRemoveCardResponse { V1 }
    pub enum HostPocketRemoveCardError { V1 => v01::HostPocketRemoveCardError }
    pub enum HostPocketActionSubscribeItem { V1 => v01::HostPocketActionSubscribeItem }
    pub enum ProductPocketCardRenderRequest { V1 => v01::ProductPocketCardRenderRequest }
    pub enum ProductPocketCardRenderItem { V1 => v01::CustomRendererNode }
}

#[cfg(test)]
mod tests {
    use super::*;
    use parity_scale_codec::{Decode, Encode};

    // A face action must name the card it came from, so one worker handler can
    // serve every card of the product. The fixture pins the field order the
    // host and the generated client agree on.
    #[test]
    fn action_item_carries_card_then_action_then_payload() {
        let item = HostPocketActionSubscribeItem::V1(v01::HostPocketActionSubscribeItem {
            card_id: "loyalty".into(),
            action_id: "redeem".into(),
            payload: None,
        });

        assert_eq!(
            hex::encode(item.encode()),
            "001c6c6f79616c74791872656465656d00"
        );
        assert_eq!(
            HostPocketActionSubscribeItem::decode(&mut item.encode().as_slice()).unwrap(),
            item
        );
    }

    // The face stream reuses the chat renderer tree unchanged, so a host that
    // renders chat custom messages renders Pocket faces with the same decoder.
    #[test]
    fn face_item_encodes_like_a_chat_render_item() {
        let node = v01::CustomRendererNode::String {
            text: "Votes: 1".into(),
        };
        let face = ProductPocketCardRenderItem::V1(node.clone());
        let chat = crate::versioned::chat::ProductChatCustomMessageRenderItem::V1(node);

        assert_eq!(face.encode(), chat.encode());
    }

    // Privileged cards are the only removal the protocol refuses, and its
    // discriminant must stay first so older clients keep decoding it.
    #[test]
    fn privileged_removal_error_is_discriminant_zero() {
        let error = HostPocketRemoveCardError::V1(v01::HostPocketRemoveCardError::Privileged);

        assert_eq!(hex::encode(error.encode()), "0000");
    }
}
