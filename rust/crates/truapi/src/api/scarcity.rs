//! Unified [`Scarcity`] trait: the host-owned NFT pocket for `pallet-scarcity`.

use crate::versioned::scarcity::{
    HostScarcityListError, HostScarcityListRequest, HostScarcityListResponse,
    HostScarcityListSubscribeError, HostScarcityListSubscribeItem,
    HostScarcityListSubscribeRequest, HostScarcityRequestReceiveAddressError,
    HostScarcityRequestReceiveAddressRequest, HostScarcityRequestReceiveAddressResponse,
    HostScarcityTransferError, HostScarcityTransferItem, HostScarcityTransferRequest,
};
use crate::wire;
use crate::{CallContext, CallError, Subscription};

/// NFT pocket operations.
///
/// The pocket is a set of wallet-owned `pallet-scarcity` purses, one per
/// product plus the wallet's own, each holding one NFT per host-derived key.
/// Custody is context: an item belongs to whichever product's purse holds it,
/// and the host signs from a purse only for that product or for the user in
/// trusted wallet UI. Products never see a purse secret, never derive or
/// scan, and never sign a purse transaction themselves. They list their own
/// purse, obtain a fresh empty key to receive an NFT into, and ask the host to
/// move an NFT they hold; the host derives, reads, prompts, signs and watches.
///
/// Wire ids 198–205 and 212–215 belong to this service. 206–211 are taken by
/// the Pocket card modality; 216–219 are reserved for a transfer form that
/// names a destination product rather than a key.
#[crate::async_trait]
pub trait Scarcity: Send + Sync {
    /// List the NFTs in the caller's purse.
    ///
    /// The host asks the user once per product and remembers the answer. The
    /// `collections` filter narrows the response, not the grant. The response
    /// carries chain facts only — products resolve names and artwork themselves
    /// through `chain.*` and the pallet's `metadata_batch` runtime API.
    ///
    /// ```ts
    /// const result = await truapi.scarcity.list({ collections: [7] });
    /// assert(result.isOk(), "list failed:", result);
    /// for (const item of result.value.items) {
    ///   console.log("held instance", item.instance, "in collection", item.collection);
    /// }
    /// ```
    #[wire(request_id = 198)]
    async fn list(
        &self,
        _cx: &CallContext,
        _request: HostScarcityListRequest,
    ) -> Result<HostScarcityListResponse, CallError<HostScarcityListError>> {
        Err(CallError::unavailable())
    }

    /// Obtain a fresh, empty purse key that may receive exactly one NFT.
    ///
    /// With no `target` the key is allocated in the caller's own purse,
    /// promptless once `list` was granted. With a `target` product id the key
    /// is allocated in that product's purse, so a minting surface can place an
    /// item straight into another product's collectibles; the host asks the
    /// user once per caller and target. The same `idempotencyKey` always
    /// returns the same address, so a retried request never strands a key.
    /// Minting surfaces pass the address as the mint destination; a game
    /// publishes it so an opponent can transfer to it.
    ///
    /// ```ts
    /// const result = await truapi.scarcity.requestReceiveAddress({
    ///   idempotencyKey: "match-42-winner",
    ///   target: undefined,
    /// });
    /// assert(result.isOk(), "requestReceiveAddress failed:", result);
    /// console.log("receive into", result.value.address);
    /// ```
    #[wire(request_id = 200)]
    async fn request_receive_address(
        &self,
        _cx: &CallContext,
        _request: HostScarcityRequestReceiveAddressRequest,
    ) -> Result<
        HostScarcityRequestReceiveAddressResponse,
        CallError<HostScarcityRequestReceiveAddressError>,
    > {
        Err(CallError::unavailable())
    }

    /// Move one NFT the caller's purse holds to another purse key.
    ///
    /// Always shows the user a consent sheet naming the item and destination;
    /// when the destination is a purse key the host derived, the sheet names
    /// that product. On approval the host signs `Scarcity.transfer` with the
    /// holding purse key under the pallet's `AsScarcity` extension (feeless,
    /// mortal), broadcasts it, and verifies ownership at the included block.
    /// The stream ends with `Landed` or `Failed`.
    ///
    /// ```ts
    /// import { lastValueFrom, from } from "rxjs";
    ///
    /// const status = await lastValueFrom(
    ///   from(
    ///     truapi.scarcity.transfer({
    ///       instance: 34n,
    ///       to: "0x0000000000000000000000000000000000000000000000000000000000000000",
    ///     }),
    ///   ),
    /// );
    /// console.log("transfer status:", status);
    /// ```
    #[wire(start_id = 202)]
    async fn transfer(
        &self,
        _cx: &CallContext,
        _request: HostScarcityTransferRequest,
    ) -> Result<Subscription<HostScarcityTransferItem>, CallError<HostScarcityTransferError>> {
        Err(CallError::unavailable())
    }

    /// Follow the NFTs in the caller's purse.
    ///
    /// Emits the whole purse on subscribe and again after every change the
    /// host observes: an arrival, a move in or out, a burn, or a
    /// collection-owner force move. Same grant as `list`.
    ///
    /// ```ts
    /// import { firstValueFrom, from } from "rxjs";
    ///
    /// const first = await firstValueFrom(
    ///   from(truapi.scarcity.listSubscribe({ collections: undefined })),
    /// );
    /// console.log("held items:", first.items.length);
    /// ```
    #[wire(start_id = 212)]
    async fn list_subscribe(
        &self,
        _cx: &CallContext,
        _request: HostScarcityListSubscribeRequest,
    ) -> Result<
        Subscription<HostScarcityListSubscribeItem>,
        CallError<HostScarcityListSubscribeError>,
    > {
        Err(CallError::unavailable())
    }
}
