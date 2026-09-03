//! Unified [`Locale`] trait.

use crate::versioned::locale::HostLocaleSubscribeItem;
use crate::wire;
use crate::{CallContext, Subscription};

/// Host locale subscription.
#[crate::async_trait]
pub trait Locale: Send + Sync {
    /// Subscribe to the host's selected locale.
    ///
    /// ```ts
    /// import { firstValueFrom, from } from "rxjs";
    ///
    /// const locale = await firstValueFrom(
    ///   from(truapi.locale.subscribe()),
    /// );
    /// console.log("locale received:", locale.languageTag);
    /// ```
    #[wire(start_id = 194)]
    async fn subscribe(&self, _cx: &CallContext) -> Subscription<HostLocaleSubscribeItem> {
        Subscription::empty()
    }
}
