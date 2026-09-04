//! Unified [`Pocket`] trait.

use crate::versioned::pocket::{
    HostPocketActionSubscribeItem, HostPocketListSubscribeItem, HostPocketRemoveCardError,
    HostPocketRemoveCardRequest, HostPocketRemoveCardResponse, ProductPocketCardRenderItem,
    ProductPocketCardRenderRequest,
};
use crate::wire;
use crate::{CallContext, CallError, Subscription};

/// Pocket cards backed by the calling product.
///
/// The host owns the collection: a product observes its own cards, streams
/// their faces on request, and may remove them, but cannot add one.
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
    #[wire(start_id = 198)]
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
    #[wire(request_id = 202)]
    async fn remove_card(
        &self,
        _cx: &CallContext,
        _request: HostPocketRemoveCardRequest,
    ) -> Result<HostPocketRemoveCardResponse, CallError<HostPocketRemoveCardError>> {
        Err(CallError::unavailable())
    }

    /// Subscribe to actions the user triggers on any of the calling product's
    /// card faces.
    ///
    /// ```ts
    /// import { firstValueFrom, from } from "rxjs";
    ///
    /// const action = await firstValueFrom(
    ///   from(truapi.pocket.actionSubscribe()),
    /// );
    /// console.log("action received:", action.cardId, action.actionId);
    /// ```
    #[wire(start_id = 204)]
    async fn action_subscribe(
        &self,
        _cx: &CallContext,
    ) -> Subscription<HostPocketActionSubscribeItem> {
        Subscription::empty()
    }

    /// Streams the face of one card while it is on screen.
    ///
    /// Each item is a complete renderer tree that replaces the previous face.
    /// The host keeps the newest tree and shows it while the worker is down.
    ///
    /// ```ts
    /// import { of } from "rxjs";
    /// truapi.pocket.onCardRender(({ cardId }) => {
    ///   return of({ tag: "String", value: { text: `Card ${cardId}` } });
    /// });
    /// ```
    #[wire(host_initiated, start_id = 208)]
    fn card_render(
        &self,
        _cx: &CallContext,
        _request: ProductPocketCardRenderRequest,
    ) -> Subscription<ProductPocketCardRenderItem> {
        Subscription::empty()
    }
}
