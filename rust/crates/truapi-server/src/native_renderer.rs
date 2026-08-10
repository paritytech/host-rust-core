//! Native observation of custom-renderer streams.

use std::sync::{Arc, Mutex};

use futures::StreamExt;
use futures::future::{AbortHandle, Abortable};
use truapi::{Subscription, latest::ProductChatCustomMessageRenderItem};

use crate::subscription::Spawner;

/// Observer implemented by a native host to receive renderer tree replacements.
#[uniffi::export(callback_interface)]
pub trait NativeCustomRendererObserver: Send + Sync {
    /// Deliver a complete replacement tree.
    fn on_update(&self, node: ProductChatCustomMessageRenderItem);

    /// Report that the renderer stream ended.
    fn on_complete(&self);
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
    mut stream: Subscription<ProductChatCustomMessageRenderItem>,
    observer: Arc<dyn NativeCustomRendererObserver>,
    spawner: Spawner,
) -> Arc<NativeCustomRendererSubscription> {
    let (abort, registration) = AbortHandle::new_pair();
    (spawner)(Box::pin(async move {
        let _ = Abortable::new(
            async move {
                while let Some(node) = stream.next().await {
                    observer.on_update(node);
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
