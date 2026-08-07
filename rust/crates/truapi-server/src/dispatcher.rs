//! Request dispatcher.
//!
//! Routes incoming frames to the appropriate trait method based on the
//! numeric `(trait, method)` wire discriminant pair. The handler set is
//! registered by the auto-generated
//! [`crate::generated::dispatcher::register`] function; this module provides
//! the framework that owns the registration tables and the routing logic.

use std::collections::{HashMap, HashSet};
use std::sync::Arc;

use futures::future::BoxFuture;
use parity_scale_codec::Encode;
use tracing::instrument;

use crate::frame::{
    PROTOCOL_ERROR_KEY, PROTOCOL_ERROR_METHOD_ID, PROTOCOL_ERROR_TRAIT_ID, Payload, ProtocolErrorV1,
    ProtocolMessage, VersionedProtocolError,
};
use crate::generated::wire_table::{RequestFrameIds, SubscriptionFrameIds};
use crate::subscription::{Spawner, SubscriptionManager, SubscriptionStream};
use crate::transport::Transport;

/// A handler for a request-response method. TrUAPI service traits require
/// their returned futures to be [`Send`], allowing native dispatch to move
/// across executor threads while WASM remains free to poll the same future on
/// its local executor. The `request_id` is the per-frame identifier; handlers
/// thread it into the `CallContext` so trait methods can correlate
/// logs/cancellation with the originating request. On the error path handlers
/// return the complete SCALE-encoded response payload.
pub type RequestHandler =
    Arc<dyn Fn(String, Vec<u8>) -> BoxFuture<'static, Result<Vec<u8>, Vec<u8>>> + Send + Sync>;

/// A handler for a subscription method. On the error path the handler returns
/// the complete SCALE-encoded `_interrupt` payload.
pub type SubscriptionHandler = Arc<
    dyn Fn(String, Vec<u8>) -> BoxFuture<'static, Result<SubscriptionStream, Vec<u8>>>
        + Send
        + Sync,
>;

/// A registered request handler plus the discriminants it replies on.
pub struct RequestEntry {
    ids: RequestFrameIds,
    handler: RequestHandler,
}

/// A registered subscription handler plus the discriminants its frames carry.
pub struct SubscriptionEntry {
    ids: SubscriptionFrameIds,
    handler: SubscriptionHandler,
}

/// Routes incoming protocol messages to registered handlers, keyed on the
/// numeric `(trait, method)` wire discriminant pair.
pub struct Dispatcher {
    by_request: HashMap<(u8, u8), RequestEntry>,
    by_start: HashMap<(u8, u8), SubscriptionEntry>,
    stop_ids: HashSet<(u8, u8)>,
    subscriptions: SubscriptionManager,
    /// Trusted executable kind bound to this connection; `None` leaves the
    /// surface unrestricted for direct dispatcher embeddings.
    execution: Option<truapi_platform::ProductExecutionKind>,
}

impl Dispatcher {
    /// Construct a dispatcher whose subscriptions are driven on `spawner`.
    pub fn new(spawner: Spawner) -> Self {
        Self {
            by_request: HashMap::new(),
            by_start: HashMap::new(),
            stop_ids: HashSet::new(),
            subscriptions: SubscriptionManager::new(spawner),
            execution: None,
        }
    }

    /// Construct a dispatcher bound to a trusted executable kind.
    pub fn for_execution(
        spawner: Spawner,
        execution: truapi_platform::ProductExecutionKind,
    ) -> Self {
        Self {
            execution: Some(execution),
            ..Self::new(spawner)
        }
    }

    /// Return whether this connection may access a service execution kind.
    pub fn allows_execution(&self, required: truapi_platform::ProductExecutionKind) -> bool {
        self.execution.is_none_or(|actual| actual == required)
    }

    /// Register a request-response handler, keyed on
    /// `(ids.trait_id, ids.request_id)`. Returns the previously registered
    /// entry if any; callers (the generated `dispatcher::register`) should
    /// treat `Some` as a programming error since each discriminant pair must
    /// own exactly one handler.
    pub fn on_request<F>(&mut self, ids: RequestFrameIds, handler: F) -> Option<RequestEntry>
    where
        F: Fn(String, Vec<u8>) -> BoxFuture<'static, Result<Vec<u8>, Vec<u8>>>
            + Send
            + Sync
            + 'static,
    {
        self.by_request.insert(
            (ids.trait_id, ids.request_id),
            RequestEntry {
                ids,
                handler: Arc::new(handler),
            },
        )
    }

    /// Register a subscription handler, keyed on
    /// `(ids.trait_id, ids.start_id)`, and record the stop pair so a matching
    /// `_stop` frame tears the subscription down. Returns the previously
    /// registered entry if any.
    pub fn on_subscription<F>(
        &mut self,
        ids: SubscriptionFrameIds,
        handler: F,
    ) -> Option<SubscriptionEntry>
    where
        F: Fn(String, Vec<u8>) -> BoxFuture<'static, Result<SubscriptionStream, Vec<u8>>>
            + Send
            + Sync
            + 'static,
    {
        self.stop_ids.insert((ids.trait_id, ids.stop_id));
        self.by_start.insert(
            (ids.trait_id, ids.start_id),
            SubscriptionEntry {
                ids,
                handler: Arc::new(handler),
            },
        )
    }

    /// Process an incoming protocol message, sending any responses or
    /// subscription frames through `transport`. A `(trait, method)` pair with
    /// no registered handler is answered with a correlated protocol error
    /// rather than dropped, so a peer learns its frame went unhandled instead
    /// of waiting on a reply that never comes.
    #[instrument(skip_all, fields(runtime.method = "dispatcher.dispatch"))]
    pub async fn dispatch(&self, message: ProtocolMessage, transport: Arc<dyn Transport>) {
        let key = (message.payload.trait_id, message.payload.method_id);

        // Never answer a protocol error with a protocol error: two peers that
        // disagree would otherwise trade frames forever.
        if key == PROTOCOL_ERROR_KEY {
            return;
        }

        if let Some(entry) = self.by_request.get(&key) {
            let request_id = message.request_id.clone();
            let value = (entry.handler)(request_id, message.payload.value)
                .await
                .unwrap_or_else(|value| value);
            transport.send(ProtocolMessage {
                request_id: message.request_id,
                payload: Payload {
                    trait_id: entry.ids.trait_id,
                    method_id: entry.ids.response_id,
                    value,
                },
            });
        } else if let Some(entry) = self.by_start.get(&key) {
            // Reserve the slot before awaiting the handler so a `_stop`
            // arriving while the handler resolves cancels the pending
            // subscription instead of racing the registration.
            let request_id = message.request_id.clone();
            let token = self.subscriptions.reserve(request_id.clone());
            let result = (entry.handler)(request_id, message.payload.value).await;
            match result {
                Ok(stream) => {
                    self.subscriptions.activate(
                        token,
                        entry.ids.trait_id,
                        entry.ids.receive_id,
                        entry.ids.interrupt_id,
                        stream,
                        transport,
                    );
                }
                Err(err_bytes) => {
                    self.subscriptions.cancel_reservation(token);
                    transport.send(ProtocolMessage {
                        request_id: message.request_id,
                        payload: Payload {
                            trait_id: entry.ids.trait_id,
                            method_id: entry.ids.interrupt_id,
                            value: err_bytes,
                        },
                    });
                }
            }
        } else if self.stop_ids.contains(&key) {
            self.subscriptions.handle_stop(&message.request_id);
        } else {
            // Response / receive / interrupt frames are handled by the client
            // side and are never registered here, so they land in this arm too:
            // answering them is what tells a mismatched peer its frame was not
            // understood. No log - a peer speaking a wire we do not know could
            // otherwise flood the host's logs one frame at a time.
            let (trait_id, method_id) = key;
            transport.send(ProtocolMessage {
                request_id: message.request_id,
                payload: Payload {
                    trait_id: PROTOCOL_ERROR_TRAIT_ID,
                    method_id: PROTOCOL_ERROR_METHOD_ID,
                    value: VersionedProtocolError::V1(ProtocolErrorV1::UnsupportedMessage {
                        trait_id,
                        method_id,
                    })
                    .encode(),
                },
            });
        }
    }

    /// Cancel every subscription currently owned by this dispatcher.
    pub fn cancel_subscriptions(&self) {
        self.subscriptions.cancel_all();
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::sync::Mutex;

    fn test_spawner() -> Spawner {
        #[cfg(not(target_arch = "wasm32"))]
        {
            crate::subscription::thread_per_subscription_spawner()
        }
        #[cfg(target_arch = "wasm32")]
        {
            Arc::new(futures::executor::block_on)
        }
    }

    #[derive(Default)]
    struct RecordingTransport {
        sent: Mutex<Vec<ProtocolMessage>>,
    }

    impl RecordingTransport {
        fn sent(&self) -> Vec<ProtocolMessage> {
            self.sent.lock().unwrap().clone()
        }
    }

    impl Transport for RecordingTransport {
        fn send(&self, message: ProtocolMessage) {
            self.sent.lock().unwrap().push(message);
        }
        fn on_message(
            &self,
            _handler: Box<dyn Fn(ProtocolMessage) + Send + Sync>,
        ) -> Box<dyn FnOnce()> {
            Box::new(|| {})
        }
    }

    fn make_frame(trait_id: u8, method_id: u8, value: Vec<u8>) -> ProtocolMessage {
        ProtocolMessage {
            request_id: "p:1".into(),
            payload: Payload {
                trait_id,
                method_id,
                value,
            },
        }
    }

    #[test]
    fn dispatch_unknown_id_sends_correlated_protocol_error() {
        let dispatcher = Dispatcher::new(test_spawner());
        let transport = Arc::new(RecordingTransport::default());
        let transport_dyn: Arc<dyn Transport> = transport.clone();
        let frame = make_frame(250, 251, Vec::new());
        futures::executor::block_on(dispatcher.dispatch(frame, transport_dyn));
        // 250 != 251 on purpose: the reply must echo the pair in the order it
        // arrived, and equal values would let a transposition pass.
        assert_eq!(
            transport.sent(),
            vec![ProtocolMessage {
                request_id: "p:1".into(),
                payload: Payload {
                    trait_id: PROTOCOL_ERROR_TRAIT_ID,
                    method_id: PROTOCOL_ERROR_METHOD_ID,
                    value: VersionedProtocolError::V1(ProtocolErrorV1::UnsupportedMessage {
                        trait_id: 250,
                        method_id: 251,
                    })
                    .encode(),
                },
            }]
        );
    }

    #[test]
    fn dispatch_protocol_error_does_not_send_another_error() {
        let dispatcher = Dispatcher::new(test_spawner());
        let transport = Arc::new(RecordingTransport::default());
        let frame = make_frame(
            PROTOCOL_ERROR_TRAIT_ID,
            PROTOCOL_ERROR_METHOD_ID,
            VersionedProtocolError::V1(ProtocolErrorV1::UnsupportedMessage {
                trait_id: 250,
                method_id: 251,
            })
            .encode(),
        );
        futures::executor::block_on(dispatcher.dispatch(frame, transport.clone()));
        assert_eq!(transport.sent(), Vec::<ProtocolMessage>::new());
    }

    /// A handler error already owns the complete response payload. The
    /// dispatcher only routes it to the registered response id.
    #[test]
    fn dispatch_request_handler_error_emits_response_payload() {
        let mut dispatcher = Dispatcher::new(test_spawner());
        let ids = RequestFrameIds {
            trait_id: 7,
            request_id: 200,
            response_id: 201,
        };
        dispatcher.on_request(ids, |_request_id, _bytes| {
            Box::pin(async move { Err(vec![9, 8, 7]) })
        });
        let transport = Arc::new(RecordingTransport::default());
        let frame = make_frame(7, 200, Vec::new());
        futures::executor::block_on(dispatcher.dispatch(frame, transport.clone()));
        let sent = transport.sent();
        assert_eq!(sent.len(), 1, "exactly one response expected");
        assert_eq!(sent[0].payload.trait_id, 7);
        assert_eq!(sent[0].payload.method_id, 201);
        assert_eq!(sent[0].payload.value, vec![9, 8, 7]);
    }

    /// Registering two handlers under the same key must not silently
    /// overwrite. The contract chosen here is "loud": `on_request`
    /// returns the previous handler, so callers can detect collisions.
    #[test]
    fn register_request_twice_returns_previous_handler() {
        let mut dispatcher = Dispatcher::new(test_spawner());
        let ids = RequestFrameIds {
            trait_id: 7,
            request_id: 200,
            response_id: 201,
        };
        let prev = dispatcher.on_request(ids, |_request_id, _bytes| {
            Box::pin(async move { Ok(Vec::new()) })
        });
        assert!(prev.is_none(), "first registration has no predecessor");
        let prev = dispatcher.on_request(ids, |_request_id, _bytes| {
            Box::pin(async move { Ok(Vec::new()) })
        });
        assert!(
            prev.is_some(),
            "second registration must return the previous handler"
        );
    }

    #[test]
    fn execution_filter_is_bound_to_the_connection() {
        let app =
            Dispatcher::for_execution(test_spawner(), truapi_platform::ProductExecutionKind::App);
        let widget = Dispatcher::for_execution(
            test_spawner(),
            truapi_platform::ProductExecutionKind::Widget,
        );
        let worker = Dispatcher::for_execution(
            test_spawner(),
            truapi_platform::ProductExecutionKind::Worker,
        );

        assert!(!app.allows_execution(truapi_platform::ProductExecutionKind::Worker));
        assert!(!widget.allows_execution(truapi_platform::ProductExecutionKind::Worker));
        assert!(worker.allows_execution(truapi_platform::ProductExecutionKind::Worker));
    }
}
