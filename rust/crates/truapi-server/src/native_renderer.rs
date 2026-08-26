//! Native observation of custom-renderer streams.

use std::sync::{Arc, Mutex};

use futures::StreamExt;
use futures::future::{AbortHandle, Abortable};
use truapi::{Subscription, latest::GenericError, latest::ProductChatCustomMessageRenderItem};

use crate::subscription::Spawner;

/// Observer implemented by a native host to receive renderer tree replacements.
#[uniffi::export(callback_interface)]
pub trait NativeCustomRendererObserver: Send + Sync {
    /// Deliver a complete replacement tree.
    fn on_update(&self, node: ProductChatCustomMessageRenderItem);

    /// Report that the renderer stream ended without drawing further trees.
    /// The last tree delivered stands.
    fn on_complete(&self);

    /// Report that the product could not serve this render. The last tree
    /// delivered, if any, is partial and must not be treated as final.
    fn on_error(&self, reason: String);
}

/// Cancellable native observation of one custom-message render instance.
#[derive(uniffi::Object)]
pub struct NativeCustomRendererSubscription {
    abort: Mutex<Option<AbortHandle>>,
}

#[uniffi::export]
impl NativeCustomRendererSubscription {
    /// Stop delivering renderer updates to the native observer.
    pub fn cancel(&self) {
        if let Some(abort) = self
            .abort
            .lock()
            .expect("native renderer subscription mutex poisoned")
            .take()
        {
            abort.abort();
        }
    }
}

impl Drop for NativeCustomRendererSubscription {
    fn drop(&mut self) {
        self.cancel();
    }
}

#[cfg_attr(not(feature = "ws-bridge"), allow(dead_code))]
pub(crate) fn observe_renderer(
    mut stream: Subscription<Result<ProductChatCustomMessageRenderItem, GenericError>>,
    observer: Arc<dyn NativeCustomRendererObserver>,
    spawner: Spawner,
) -> Arc<NativeCustomRendererSubscription> {
    let (abort, registration) = AbortHandle::new_pair();
    (spawner)(Box::pin(async move {
        let _ = Abortable::new(
            async move {
                while let Some(item) = stream.next().await {
                    match item {
                        Ok(node) => observer.on_update(node),
                        Err(error) => return observer.on_error(error.reason),
                    }
                }
                observer.on_complete();
            },
            registration,
        )
        .await;
    }));
    Arc::new(NativeCustomRendererSubscription {
        abort: Mutex::new(Some(abort)),
    })
}
