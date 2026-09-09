//! Unified [`Scarcity`] trait: the host-owned NFT pocket for `pallet-scarcity`.

use crate::versioned::scarcity::{
    HostScarcityListError, HostScarcityListRequest, HostScarcityListResponse,
    HostScarcityRequestReceiveAddressError, HostScarcityRequestReceiveAddressRequest,
    HostScarcityRequestReceiveAddressResponse, HostScarcityTransferError, HostScarcityTransferItem,
    HostScarcityTransferRequest,
};
use crate::wire;
use crate::{CallContext, CallError, Subscription};

/// NFT pocket operations.
///
/// The pocket is one wallet-owned keyring of `pallet-scarcity` purses: one
/// NFT per host-derived key. Products never see a purse secret, never derive
/// or scan, and never sign a purse transaction themselves. They list what the
/// user holds, obtain a fresh empty purse to receive an NFT into, and ask the
/// host to move an NFT they name; the host derives, reads, prompts, signs and
/// watches.
#[crate::async_trait]
pub trait Scarcity: Send + Sync {
    /// List the NFTs the pocket holds.
    ///
    /// The host asks the user once per product, scoped to the requested
    /// collections, and remembers the answer; a later request for a collection
    /// outside the grant prompts again. The response carries chain facts only —
    /// products resolve names and artwork themselves through `chain.*` and the
    /// pallet's `metadata_batch` runtime API.
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
    /// Promptless once `list` was granted to the caller. The same
    /// `idempotencyKey` always returns the same address, so a retried request
    /// never strands a purse. Minting surfaces pass the address as the mint
    /// destination; a game publishes it so an opponent can transfer to it.
    ///
    /// ```ts
    /// const result = await truapi.scarcity.requestReceiveAddress({
    ///   idempotencyKey: "match-42-winner",
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

    /// Move one held NFT to another purse key.
    ///
    /// Always shows the user a consent sheet naming the item and destination.
    /// On approval the host signs `Scarcity.transfer` with the holding purse
    /// under the pallet's `AsScarcity` extension (feeless), broadcasts it, and
    /// verifies ownership at the included block. The stream ends with `Landed`
    /// or `Failed`.
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
}
