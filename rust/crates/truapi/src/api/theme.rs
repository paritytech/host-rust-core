//! Unified [`Theme`] trait.

use crate::versioned::theme::HostThemeSubscribeItem;
use crate::{CallContext, Subscription};
use crate::{wire, wire_trait};

/// Host theme subscription.
#[wire_trait(id = 207)]
#[crate::async_trait]
pub trait Theme: Send + Sync {
    /// Subscribe to host theme changes.
    ///
    /// ```ts
    /// import { firstValueFrom, from } from "rxjs";
    ///
    /// const theme = await firstValueFrom(
    ///   from(truapi.theme.subscribe()),
    /// );
    /// console.log("theme received:", theme);
    /// ```
    #[wire(start_id = 0)]
    async fn subscribe(&self, _cx: &CallContext) -> Subscription<HostThemeSubscribeItem> {
        Subscription::empty()
    }
}
