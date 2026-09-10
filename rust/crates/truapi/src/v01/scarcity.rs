//! NFT pocket types for the `Scarcity` service.
//!
//! The pocket is a set of wallet-owned purses for `pallet-scarcity` NFTs, one
//! purse per product plus the wallet's own. The pallet keeps one NFT per
//! account key (`NftsByOwner`), so every item sits in its own host-derived
//! purse key. Custody is context: an item belongs to whichever product's purse
//! holds it. Products see items, never keys: they list their own purse, ask
//! for a fresh empty key to receive into, and ask the host to move an item
//! they hold.

use parity_scale_codec::{Decode, Encode};

/// A 32-byte Substrate account id, the purse key an NFT sits in.
pub type ScarcityAccountId = [u8; 32];

/// Whether an item definition lets its holder move instances.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Encode, Decode)]
#[cfg_attr(feature = "uniffi", derive(uniffi::Enum))]
pub enum ScarcityTransferability {
    /// The holder may transfer the instance to another purse key.
    Transferable,
    /// The instance is bound to the purse key it was minted into; only the
    /// collection owner can move or burn it.
    Soulbound,
}

/// One live NFT held in the pocket, as read from `Scarcity.NftsByOwner`.
#[derive(Debug, Clone, PartialEq, Eq, Encode, Decode)]
#[cfg_attr(feature = "uniffi", derive(uniffi::Record))]
pub struct ScarcityItem {
    /// Globally unique instance id; the stable external handle for the NFT.
    pub instance: u64,
    /// Collection the item definition belongs to.
    pub collection: u32,
    /// Item definition within the collection.
    pub item: u32,
    /// Purse key currently holding the instance.
    pub address: ScarcityAccountId,
    /// Ownership-state revision; increments on every successful move.
    pub state_nonce: u64,
    /// Unix seconds at mint.
    pub minted_at: u64,
    /// Unix seconds of the last move; equals `minted_at` until the first transfer.
    pub last_moved: u64,
    /// Whether the holder may move it; read from the item definition.
    pub transferability: ScarcityTransferability,
}

/// Request to list the NFTs in the caller's purse.
#[derive(Debug, Clone, PartialEq, Eq, Encode, Decode)]
pub struct HostScarcityListRequest {
    /// Restrict the listing to these collections. `None` lists the whole
    /// purse. A convenience filter, not a grant scope: the grant covers the
    /// caller's purse.
    pub collections: Option<Vec<u32>>,
}

/// The NFTs in the caller's purse.
#[derive(Debug, Clone, PartialEq, Eq, Encode, Decode)]
pub struct HostScarcityListResponse {
    /// Live items, in purse derivation order.
    pub items: Vec<ScarcityItem>,
}

/// Request to follow the NFTs in the caller's purse.
#[derive(Debug, Clone, PartialEq, Eq, Encode, Decode)]
pub struct HostScarcityListSubscribeRequest {
    /// Restrict the stream to these collections; `None` follows the whole purse.
    pub collections: Option<Vec<u32>>,
}

/// The caller's purse contents: the whole set on subscribe and after every
/// change the host observes.
#[derive(Debug, Clone, PartialEq, Eq, Encode, Decode)]
pub struct HostScarcityListSubscribeItem {
    /// Live items, in purse derivation order.
    pub items: Vec<ScarcityItem>,
}

/// Request for a fresh, empty purse key to receive one NFT into.
#[derive(Debug, Clone, PartialEq, Eq, Encode, Decode)]
pub struct HostScarcityRequestReceiveAddressRequest {
    /// Caller-chosen key. Repeating a key returns the same address instead of
    /// allocating another purse key, so a retried request never strands one.
    pub idempotency_key: String,
    /// Purse to allocate in. `None` is the caller's own purse. A product id
    /// names that product's purse instead, so a minting surface can place an
    /// item straight into another product's collectibles; the host asks the
    /// user once per caller and target.
    pub target: Option<String>,
}

/// A purse key that holds nothing and may receive one NFT.
#[derive(Debug, Clone, PartialEq, Eq, Encode, Decode)]
pub struct HostScarcityRequestReceiveAddressResponse {
    /// The empty purse key.
    pub address: ScarcityAccountId,
}

/// Request to move one held NFT to another purse key.
#[derive(Debug, Clone, PartialEq, Eq, Encode, Decode)]
pub struct HostScarcityTransferRequest {
    /// Instance to move; the pocket must hold it.
    pub instance: u64,
    /// Destination purse key. It must be empty: the pallet holds one NFT per key.
    pub to: ScarcityAccountId,
}

/// Progress of a transfer the host is executing.
#[derive(Debug, Clone, PartialEq, Eq, Encode, Decode)]
pub enum ScarcityTransferStatus {
    /// The user approved and the signed transaction was broadcast.
    Started,
    /// The transaction was included in a block; ownership not yet verified.
    InBlock {
        /// Hash of the including block.
        block: [u8; 32],
    },
    /// The chain shows the instance under the destination key.
    Landed,
    /// The transaction did not move the instance.
    Failed {
        /// Why the move failed.
        error: ScarcityError,
    },
}

/// Failures from the `Scarcity` service.
#[derive(Debug, Clone, PartialEq, Eq, Encode, Decode)]
pub enum ScarcityError {
    /// The user or host refused the request.
    Rejected,
    /// The pocket does not hold the named instance.
    NotFound,
    /// The destination purse key already holds an NFT.
    AddressOccupied,
    /// The holding purse is locked after a failed dispatch; retry after `until`.
    Locked {
        /// Unix seconds when the lock lifts.
        until: u64,
    },
    /// The instance moved between the read and the signature; refresh and retry.
    StateMismatch,
    /// The host serves no chain carrying the `Scarcity` pallet.
    ChainNotServed,
    /// The item definition binds the instance to its purse key; the holder
    /// cannot move it.
    Soulbound,
    /// The named target purse is not a product this host can allocate for.
    UnknownTarget,
    /// No account-authority session is active, so there is no wallet root to
    /// derive purses from.
    NotConnected,
    /// Catch-all.
    Unknown {
        /// Human-readable failure reason.
        reason: String,
    },
}
