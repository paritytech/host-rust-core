//! Unified [`Renderer`] trait.

use crate::latest::GenericError;
use crate::versioned::renderer::{
    HostRendererActionSubscribeItem, ProductRendererRenderItem, ProductRendererRenderRequest,
};
use crate::{CallContext, CallError, Subscription};
use crate::{wire, wire_trait};

/// Product-rendered bodies and the actions triggered inside them.
#[wire_trait(id = 17)]
#[crate::service(required_execution = Worker)]
#[crate::async_trait]
pub trait Renderer: Send + Sync {
    /// Streams renderer trees for one product-rendered body. Each item
    /// replaces the previous tree. The stream stays open while the body is
    /// displayed so the product can redraw in place.
    ///
    /// ```ts
    /// truapi.renderer.onRender(({ context, payload }, send) => {
    ///   send({ tag: "String", value: { text: `${context.tag}: ${payload}` } });
    /// });
    /// ```
    #[wire(host_initiated, id = 0)]
    fn render(
        &self,
        _cx: &CallContext,
        _request: ProductRendererRenderRequest,
    ) -> Subscription<ProductRendererRenderItem, CallError<GenericError>> {
        Subscription::interrupted(CallError::unavailable())
    }

    /// Subscribe to actions triggered inside this product's rendered bodies.
    ///
    /// ```ts
    /// import { firstValueFrom, from } from "rxjs";
    ///
    /// const action = await firstValueFrom(
    ///   from(truapi.renderer.actionSubscribe()),
    /// );
    /// console.log("action received:", action.context, action.actionId);
    /// ```
    #[wire(id = 1)]
    async fn action_subscribe(
        &self,
        _cx: &CallContext,
    ) -> Subscription<HostRendererActionSubscribeItem, CallError<GenericError>> {
        Subscription::interrupted(CallError::unavailable())
    }
}
