//! NFT pocket types for the `Scarcity` service.
//!
//! The pocket is one wallet-owned keyring for `pallet-scarcity` NFTs. The
//! pallet keeps one NFT per account key (`NftsByOwner`), so every item the
//! pocket holds sits in its own host-derived purse key. Products see items,
//! never keys: they list what the user holds, ask for a fresh empty purse to
//! receive into, and ask the host to move an item they name.

use parity_scale_codec::{Decode, Encode};

/// A 32-byte Substrate account id, the purse key an NFT sits in.
pub type ScarcityAccountId = [u8; 32];

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
}

/// Request to list the NFTs the pocket holds.
#[derive(Debug, Clone, PartialEq, Eq, Encode, Decode)]
pub struct HostScarcityListRequest {
    /// Restrict the listing to these collections. `None` asks for everything
    /// the pocket holds; the consent the host records is scoped the same way.
    pub collections: Option<Vec<u32>>,
}

/// The NFTs the pocket holds that the caller was granted to see.
#[derive(Debug, Clone, PartialEq, Eq, Encode, Decode)]
pub struct HostScarcityListResponse {
    /// Live items, in pocket derivation order.
    pub items: Vec<ScarcityItem>,
}

/// Request for a fresh, empty purse key to receive one NFT into.
#[derive(Debug, Clone, PartialEq, Eq, Encode, Decode)]
pub struct HostScarcityRequestReceiveAddressRequest {
    /// Caller-chosen key. Repeating a key returns the same address instead of
    /// allocating another purse, so a retried request never strands a key.
    pub idempotency_key: String,
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
    /// Catch-all.
    Unknown {
        /// Human-readable failure reason.
        reason: String,
    },
}
