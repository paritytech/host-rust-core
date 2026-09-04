use parity_scale_codec::{Decode, Encode};

/// One of the calling product's Pocket cards.
#[derive(Debug, Clone, PartialEq, Eq, Encode, Decode)]
#[cfg_attr(feature = "uniffi", derive(uniffi::Record))]
pub struct PocketCard {
    /// Card label declared by the product, unique within the product.
    pub card_id: String,
    /// Placed by the host itself; removable by neither the user nor the product.
    pub privileged: bool,
}

/// The calling product's cards: the whole set on subscribe and after every change.
#[derive(Debug, Clone, PartialEq, Eq, Encode, Decode)]
#[cfg_attr(feature = "uniffi", derive(uniffi::Record))]
pub struct HostPocketListSubscribeItem {
    /// Cards currently in Pocket for the calling product.
    pub cards: Vec<PocketCard>,
}

/// Request to remove one of the calling product's cards.
#[derive(Debug, Clone, PartialEq, Eq, Encode, Decode)]
#[cfg_attr(feature = "uniffi", derive(uniffi::Record))]
pub struct HostPocketRemoveCardRequest {
    /// Card to remove. A card that is not present is already removed.
    pub card_id: String,
}

/// Card removal failure.
#[derive(Debug, Clone, PartialEq, Eq, Encode, Decode)]
#[cfg_attr(feature = "uniffi", derive(uniffi::Enum))]
pub enum HostPocketRemoveCardError {
    /// The card is privileged and stays in Pocket.
    Privileged,
    /// Catch-all.
    Unknown {
        /// Human-readable reason.
        reason: String,
    },
}

/// An action the user triggered on one of the calling product's card faces.
#[derive(Debug, Clone, PartialEq, Eq, Encode, Decode)]
#[cfg_attr(feature = "uniffi", derive(uniffi::Record))]
pub struct HostPocketActionSubscribeItem {
    /// Card whose face carried the action.
    pub card_id: String,
    /// `Button.click_action` or `TextField.value_change_action` from the face tree.
    pub action_id: String,
    /// Optional additional data, such as the new text-field value.
    pub payload: Option<Vec<u8>>,
}

/// Render work sent by the host while a card's face is on screen.
#[derive(Debug, Clone, PartialEq, Eq, Encode, Decode)]
#[cfg_attr(feature = "uniffi", derive(uniffi::Record))]
pub struct ProductPocketCardRenderRequest {
    /// Card whose face to stream.
    pub card_id: String,
}
