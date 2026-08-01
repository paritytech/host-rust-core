//! Request dispatcher.
//!
//! Routes incoming frames to the appropriate trait method based on the
//! numeric wire discriminant. The handler set is registered by the
//! auto-generated [`crate::generated::dispatcher::register`] function; this
//! module provides the framework that owns the registration tables and the
//! routing logic.

use std::collections::{HashMap, HashSet};
use std::sync::Arc;

use futures::future::BoxFuture;
use tracing::instrument;

use crate::frame::{Payload, ProtocolMessage};
use crate::generated::wire_table::{RequestFrameIds, SubscriptionFrameIds};
use crate::middleware::execution::ExecutionFilter;
use crate::subscription::{
    Spawner, SubscriptionManager, SubscriptionRequestStream, SubscriptionStream,
};
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

/// Handler for a paired request and response subscription.
pub type StreamPairHandler = Arc<
    dyn Fn(
            String,
            Vec<u8>,
            SubscriptionRequestStream,
        ) -> BoxFuture<'static, Result<SubscriptionStream, Vec<u8>>>
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

/// A registered paired-stream handler plus its frame discriminants.
pub struct StreamPairEntry {
    ids: SubscriptionFrameIds,
    handler: StreamPairHandler,
}

/// Routes incoming protocol messages to registered handlers, keyed on the
/// numeric wire discriminant.
pub struct Dispatcher {
    by_request: HashMap<u8, RequestEntry>,
    by_start: HashMap<u8, SubscriptionEntry>,
    by_pair_start: HashMap<u8, StreamPairEntry>,
    pair_receive_ids: HashSet<u8>,
    stop_ids: HashSet<u8>,
    subscriptions: SubscriptionManager,
    execution: ExecutionFilter,
}

impl Dispatcher {
    /// Construct a dispatcher whose subscriptions are driven on `spawner`.
    pub fn new(spawner: Spawner) -> Self {
        Self::with_execution_filter(spawner, ExecutionFilter::unrestricted())
    }

    /// Construct a dispatcher bound to a trusted executable kind.
    pub fn for_execution(
        spawner: Spawner,
        execution: truapi_platform::ProductExecutionKind,
    ) -> Self {
        Self::with_execution_filter(spawner, ExecutionFilter::for_execution(execution))
    }

    fn with_execution_filter(spawner: Spawner, execution: ExecutionFilter) -> Self {
        Self {
            by_request: HashMap::new(),
            by_start: HashMap::new(),
            by_pair_start: HashMap::new(),
            pair_receive_ids: HashSet::new(),
            stop_ids: HashSet::new(),
            subscriptions: SubscriptionManager::new(spawner),
            execution,
        }
    }

    /// Return whether this connection may access a service execution kind.
    pub fn allows_execution(&self, required: truapi_platform::ProductExecutionKind) -> bool {
        self.execution.allows(required)
    }

    /// Register a paired request/response stream handler.
    pub fn on_stream_pair<F>(
        &mut self,
        ids: SubscriptionFrameIds,
        handler: F,
    ) -> Option<StreamPairEntry>
    where
        F: Fn(
                String,
                Vec<u8>,
                SubscriptionRequestStream,
            ) -> BoxFuture<'static, Result<SubscriptionStream, Vec<u8>>>
            + Send
            + Sync
            + 'static,
    {
        self.stop_ids.insert(ids.stop_id);
        self.pair_receive_ids.insert(ids.receive_id);
        self.by_pair_start.insert(
            ids.start_id,
            StreamPairEntry {
                ids,
                handler: Arc::new(handler),
            },
        )
    }

    /// Register a request-response handler, keyed on `ids.request_id`. Returns
    /// the previously registered entry if any; callers (the generated
    /// `dispatcher::register`) should treat `Some` as a programming error
    /// since each request id must own exactly one handler.
    pub fn on_request<F>(&mut self, ids: RequestFrameIds, handler: F) -> Option<RequestEntry>
    where
        F: Fn(String, Vec<u8>) -> BoxFuture<'static, Result<Vec<u8>, Vec<u8>>>
            + Send
            + Sync
            + 'static,
    {
        self.by_request.insert(
            ids.request_id,
            RequestEntry {
                ids,
                handler: Arc::new(handler),
            },
        )
    }

    /// Register a subscription handler, keyed on `ids.start_id`, and record
    /// `ids.stop_id` so a matching `_stop` frame tears the subscription down.
    /// Returns the previously registered entry if any.
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
        self.stop_ids.insert(ids.stop_id);
        self.by_start.insert(
            ids.start_id,
            SubscriptionEntry {
                ids,
                handler: Arc::new(handler),
            },
        )
    }

    /// Process an incoming protocol message, sending any responses or
    /// subscription frames through `transport`. A discriminant with no
    /// registered handler is dropped.
    #[instrument(skip_all, fields(runtime.method = "dispatcher.dispatch"))]
    pub async fn dispatch(&self, message: ProtocolMessage, transport: Arc<dyn Transport>) {
        let id = message.payload.id;

        if let Some(entry) = self.by_request.get(&id) {
            let request_id = message.request_id.clone();
            let value = (entry.handler)(request_id, message.payload.value)
                .await
                .unwrap_or_else(|value| value);
            transport.send(ProtocolMessage {
                request_id: message.request_id,
                payload: Payload {
                    id: entry.ids.response_id,
                    value,
                },
            });
        } else if let Some(entry) = self.by_pair_start.get(&id) {
            let (token, requests) = self
                .subscriptions
                .reserve_pair(message.request_id.clone(), entry.ids.receive_id);
            let request_id = message.request_id.clone();
            match (entry.handler)(request_id, message.payload.value, requests).await {
                Ok(stream) => {
                    self.subscriptions.activate(
                        token,
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
                            id: entry.ids.interrupt_id,
                            value: err_bytes,
                        },
                    });
                }
            }
        } else if let Some(entry) = self.by_start.get(&id) {
            // Reserve the slot before awaiting the handler so a `_stop`
            // arriving while the handler resolves cancels the pending
            // subscription instead of racing the registration.
            let token = self.subscriptions.reserve(message.request_id.clone());
            let request_id = message.request_id.clone();
            match (entry.handler)(request_id, message.payload.value).await {
                Ok(stream) => {
                    self.subscriptions.activate(
                        token,
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
                            id: entry.ids.interrupt_id,
                            value: err_bytes,
                        },
                    });
                }
            }
        } else if self.pair_receive_ids.contains(&id) {
            self.subscriptions
                .handle_request(&message.request_id, id, message.payload.value);
        } else if self.stop_ids.contains(&id) {
            self.subscriptions.handle_stop(&message.request_id);
        }
        // Unknown discriminant: drop. Response / receive / interrupt frames are
        // handled by the client side and never registered here.
    }

    /// Cancel every subscription currently owned by this dispatcher.
    pub fn cancel_subscriptions(&self) {
        self.subscriptions.cancel_all();
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use futures::StreamExt;
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

    fn make_frame(id: u8, value: Vec<u8>) -> ProtocolMessage {
        ProtocolMessage {
            request_id: "p:1".into(),
            payload: Payload { id, value },
        }
    }

    /// A frame whose discriminant has no registered handler is dropped: no
    /// response, no interrupt. (In production `register` registers every wire
    /// method, so this only happens for malformed or client-bound ids.)
    #[test]
    fn dispatch_unregistered_id_sends_nothing() {
        let dispatcher = Dispatcher::new(test_spawner());
        let transport = Arc::new(RecordingTransport::default());
        let transport_dyn: Arc<dyn Transport> = transport.clone();
        let frame = make_frame(250, Vec::new());
        futures::executor::block_on(dispatcher.dispatch(frame, transport_dyn));
        assert!(
            transport.sent().is_empty(),
            "an unregistered discriminant must produce no frame"
        );
    }

    /// A handler error already owns the complete response payload. The
    /// dispatcher only routes it to the registered response id.
    #[test]
    fn dispatch_request_handler_error_emits_response_payload() {
        let mut dispatcher = Dispatcher::new(test_spawner());
        let ids = RequestFrameIds {
            request_id: 200,
            response_id: 201,
        };
        dispatcher.on_request(ids, |_request_id, _bytes| {
            Box::pin(async move { Err(vec![9, 8, 7]) })
        });
        let transport = Arc::new(RecordingTransport::default());
        let frame = make_frame(200, Vec::new());
        futures::executor::block_on(dispatcher.dispatch(frame, transport.clone()));
        let sent = transport.sent();
        assert_eq!(sent.len(), 1, "exactly one response expected");
        assert_eq!(sent[0].payload.id, 201);
        assert_eq!(sent[0].payload.value, vec![9, 8, 7]);
    }

    /// Registering two handlers under the same key must not silently
    /// overwrite. The contract chosen here is "loud": `on_request`
    /// returns the previous handler, so callers can detect collisions.
    #[test]
    fn register_request_twice_returns_previous_handler() {
        let mut dispatcher = Dispatcher::new(test_spawner());
        let ids = RequestFrameIds {
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
    fn paired_subscription_routes_product_values_to_its_request_stream() {
        let mut dispatcher = Dispatcher::new(test_spawner());
        let ids = SubscriptionFrameIds {
            start_id: 200,
            stop_id: 201,
            interrupt_id: 202,
            receive_id: 203,
        };
        dispatcher.on_stream_pair(ids, |_request_id, _bytes, requests| {
            Box::pin(async move {
                Ok(
                    Box::pin(requests.map(crate::subscription::SubscriptionOutput::Item))
                        as SubscriptionStream,
                )
            })
        });
        let transport = Arc::new(RecordingTransport::default());

        futures::executor::block_on(
            dispatcher.dispatch(make_frame(ids.start_id, Vec::new()), transport.clone()),
        );
        futures::executor::block_on(
            dispatcher.dispatch(make_frame(ids.receive_id, vec![7, 8, 9]), transport.clone()),
        );

        let deadline = std::time::Instant::now() + std::time::Duration::from_secs(2);
        loop {
            let sent = transport.sent();
            if let Some(frame) = sent.first() {
                assert_eq!(frame.request_id, "p:1");
                assert_eq!(frame.payload.id, ids.receive_id);
                assert_eq!(frame.payload.value, vec![7, 8, 9]);
                break;
            }
            assert!(
                std::time::Instant::now() < deadline,
                "paired request was not delivered"
            );
            std::thread::yield_now();
        }
    }

    #[test]
    fn execution_filter_is_bound_to_the_connection() {
        let app =
            Dispatcher::for_execution(test_spawner(), truapi_platform::ProductExecutionKind::App);
        let chat =
            Dispatcher::for_execution(test_spawner(), truapi_platform::ProductExecutionKind::Chat);

        assert!(!app.allows_execution(truapi_platform::ProductExecutionKind::Chat));
        assert!(chat.allows_execution(truapi_platform::ProductExecutionKind::Chat));
    }
}
