//! Unified [`Pocket`] trait.

use crate::versioned::pocket::{
    HostPocketListSubscribeItem, HostPocketRemoveCardError, HostPocketRemoveCardRequest,
    HostPocketRemoveCardResponse,
};
use crate::wire;
use crate::{CallContext, CallError, Subscription};

/// Pocket cards backed by the calling product.
///
/// The host owns the collection: a product observes its own cards and may
/// remove them, but cannot add one.
#[crate::service(required_execution = Worker)]
#[crate::async_trait]
pub trait Pocket: Send + Sync {
    /// Subscribe to the calling product's cards.
    ///
    /// Emits the whole set on subscribe and again after every change.
    ///
    /// ```ts
    /// import { firstValueFrom, from } from "rxjs";
    ///
    /// const item = await firstValueFrom(
    ///   from(truapi.pocket.listSubscribe()),
    /// );
    /// console.log("cards:", item.cards);
    /// ```
    #[wire(start_id = 206)]
    async fn list_subscribe(&self, _cx: &CallContext) -> Subscription<HostPocketListSubscribeItem> {
        Subscription::empty()
    }

    /// Remove one of the calling product's cards.
    ///
    /// Removing a card that is not present succeeds. A privileged card is
    /// refused with `Privileged`.
    ///
    /// ```ts
    /// const result = await truapi.pocket.removeCard({ cardId: "loyalty" });
    /// assert(result.isOk(), "removeCard failed:", result);
    /// console.log("card removed");
    /// ```
    #[wire(request_id = 210)]
    async fn remove_card(
        &self,
        _cx: &CallContext,
        _request: HostPocketRemoveCardRequest,
    ) -> Result<HostPocketRemoveCardResponse, CallError<HostPocketRemoveCardError>> {
        Err(CallError::unavailable())
    }
}
