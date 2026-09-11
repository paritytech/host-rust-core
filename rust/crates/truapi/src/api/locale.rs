//! Unified [`Locale`] trait.

use crate::latest::GenericError;
use crate::versioned::locale::HostLocaleSubscribeItem;
use crate::{CallContext, CallError, Subscription};
use crate::{wire, wire_trait};

/// Host locale subscription.
#[wire_trait(id = 16)]
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
    #[wire(id = 0)]
    async fn subscribe(
        &self,
        _cx: &CallContext,
    ) -> Subscription<HostLocaleSubscribeItem, CallError<GenericError>> {
        Subscription::interrupted(CallError::unavailable())
    }
}
