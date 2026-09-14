//! Request dispatcher.
//!
//! Routes incoming frames to the appropriate trait method based on the
//! numeric `(trait, method)` wire discriminant pair. The handler set is
//! registered by the auto-generated
//! [`crate::generated::dispatcher::register`] function; this module provides
//! the framework that owns the registration tables and the routing logic.

use std::collections::{HashMap, HashSet};
use std::sync::Arc;
use std::sync::Mutex;

use futures::future::BoxFuture;
use parity_scale_codec::Encode;
use tracing::{error, instrument};

use crate::frame::{
    MESSAGE_TYPE_INTERRUPT, MESSAGE_TYPE_REQUEST, MESSAGE_TYPE_RESPONSE, MESSAGE_TYPE_START,
    MESSAGE_TYPE_STOP, PROTOCOL_ERROR_KEY, PROTOCOL_ERROR_METHOD_ID, PROTOCOL_ERROR_TRAIT_ID,
    Payload, ProtocolErrorV1, ProtocolMessage, VersionedProtocolError,
};
use crate::generated::wire_table::MethodIds;
use crate::subscription::{Spawner, SubscriptionManager, SubscriptionStream};
use crate::transport::Transport;

/// A handler for a request-response method. TrUAPI service traits require
/// their returned futures to be [`Send`], allowing native dispatch to move
/// across executor threads while WASM remains free to poll the same future on
/// its local executor. The `request_id` is the per-frame identifier; handlers
/// thread it into the `CallContext` so trait methods can correlate
/// logs/cancellation with the originating request. The returned bytes are the
/// complete SCALE-encoded response payload on both the success and error
/// paths, since a method's failure is a `Result` inside that payload rather
/// than a failure to produce one.
pub type RequestHandler = Arc<dyn Fn(String, Vec<u8>) -> BoxFuture<'static, Vec<u8>> + Send + Sync>;

/// A handler for a subscription method. On the error path the handler
/// returns the complete SCALE-encoded `Interrupt` payload.
pub type SubscriptionHandler = Arc<
    dyn Fn(String, Vec<u8>) -> BoxFuture<'static, Result<SubscriptionStream, Vec<u8>>>
        + Send
        + Sync,
>;

/// A registered request handler plus the discriminants it replies on.
pub struct RequestEntry {
    ids: MethodIds,
    handler: RequestHandler,
}

/// A registered subscription handler plus the discriminants its frames carry.
pub struct SubscriptionEntry {
    ids: MethodIds,
    handler: SubscriptionHandler,
}

/// Routes incoming protocol messages to registered handlers, keyed on the
/// numeric `(trait, method)` wire discriminant pair.
pub struct Dispatcher {
    by_request: HashMap<(u8, u8), RequestEntry>,
    by_start: HashMap<(u8, u8), SubscriptionEntry>,
    subscriptions: SubscriptionManager,
    /// Trusted executable kind bound to this connection; `None` leaves the
    /// surface unrestricted for direct dispatcher embeddings.
    execution: Option<truapi_platform::ProductExecutionKind>,
    /// `(trait, method)` pairs already reported on this connection. A peer
    /// whose wire table disagrees with ours is exactly what these reports are
    /// for, and exactly what would repeat them once per frame, so each pair is
    /// reported once and then stays quiet.
    reported_violations: Mutex<HashSet<(u8, u8)>>,
}

impl Dispatcher {
    /// Construct a dispatcher whose subscriptions are driven on `spawner`.
    pub fn new(spawner: Spawner) -> Self {
        Self {
            by_request: HashMap::new(),
            by_start: HashMap::new(),
            subscriptions: SubscriptionManager::new(spawner),
            execution: None,
            reported_violations: Mutex::new(HashSet::new()),
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

    /// Run `report` only the first time `key` violates the protocol on this
    /// connection. The lock is released before `report` runs, so a report can
    /// never be held up by, or hold up, another frame's dispatch.
    fn report_once(&self, key: (u8, u8), report: impl FnOnce()) {
        let first = self
            .reported_violations
            .lock()
            .expect("dispatcher violation set mutex poisoned")
            .insert(key);
        if first {
            report();
        }
    }

    /// Return whether this connection may access a service execution kind.
    pub fn allows_execution(&self, required: truapi_platform::ProductExecutionKind) -> bool {
        self.execution.is_none_or(|actual| actual == required)
    }

    /// Register a request-response handler, keyed on
    /// `(ids.trait_id, ids.method_id)`. Returns the previously registered
    /// entry if any; callers (the generated `dispatcher::register`) should
    /// treat `Some` as a programming error since each discriminant pair must
    /// own exactly one handler.
    pub fn on_request<F>(&mut self, ids: MethodIds, handler: F) -> Option<RequestEntry>
    where
        F: Fn(String, Vec<u8>) -> BoxFuture<'static, Vec<u8>> + Send + Sync + 'static,
    {
        self.by_request.insert(
            (ids.trait_id, ids.method_id),
            RequestEntry {
                ids,
                handler: Arc::new(handler),
            },
        )
    }

    /// Register a subscription handler, keyed on
    /// `(ids.trait_id, ids.method_id)`. A `Stop` frame arrives at this same
    /// address — [`dispatch`](Self::dispatch) checks its `message_type` and
    /// routes it to [`SubscriptionManager::handle_stop`] directly, without
    /// invoking this handler. Returns the previously registered entry if any.
    pub fn on_subscription<F>(&mut self, ids: MethodIds, handler: F) -> Option<SubscriptionEntry>
    where
        F: Fn(String, Vec<u8>) -> BoxFuture<'static, Result<SubscriptionStream, Vec<u8>>>
            + Send
            + Sync
            + 'static,
    {
        self.by_start.insert(
            (ids.trait_id, ids.method_id),
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
            // `Request` is the only leg a request method ever receives. Its
            // `Response` shares this address, so without this guard a peer
            // whose table disagrees with ours, or this side's own outbound
            // response arriving here, would run the handler and be answered
            // with a `Response` to a non-request. Logged because the pair is
            // one we implement: an unknown pair is merely an incompatible
            // peer, but a known method receiving a leg it cannot have is a
            // bug on one side or the other.
            if message.payload.message_type != MESSAGE_TYPE_REQUEST {
                let message_type = message.payload.message_type;
                self.report_once(key, || {
                    error!(
                        trait_id = key.0,
                        method_id = key.1,
                        message_type,
                        "dropping a frame whose message type a request method cannot receive"
                    );
                });
                return;
            }
            let request_id = message.request_id.clone();
            let value = (entry.handler)(request_id, message.payload.value).await;
            transport.send(ProtocolMessage {
                request_id: message.request_id,
                payload: Payload {
                    trait_id: entry.ids.trait_id,
                    method_id: entry.ids.method_id,
                    message_type: MESSAGE_TYPE_RESPONSE,
                    value,
                },
            });
        } else if let Some(entry) = self.by_start.get(&key) {
            if message.payload.message_type == MESSAGE_TYPE_STOP {
                self.subscriptions.handle_stop(&message.request_id);
                return;
            }
            // `Start` and `Stop` are the only legs this side receives; a
            // subscription's `Receive` and `Interrupt` flow the other way and
            // share this address too, so anything else here would otherwise
            // start a subscription off a frame that is not a start.
            if message.payload.message_type != MESSAGE_TYPE_START {
                let message_type = message.payload.message_type;
                self.report_once(key, || {
                    error!(
                        trait_id = key.0,
                        method_id = key.1,
                        message_type,
                        "dropping a frame whose message type a subscription cannot receive"
                    );
                });
                return;
            }
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
                        entry.ids.method_id,
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
                            method_id: entry.ids.method_id,
                            message_type: MESSAGE_TYPE_INTERRUPT,
                            value: err_bytes,
                        },
                    });
                }
            }
        } else {
            // Response / receive / interrupt frames are handled by the client
            // side and are never registered here, so they land in this arm too:
            // answering them is what tells a mismatched peer its frame was not
            // understood.
            let (trait_id, method_id) = key;
            // `ERROR` because this is the whole reason the crate's default
            // floor is `ERROR` (see the `logging` module doc): a host that
            // never calls `setLogLevel` still has to learn that its peer is
            // speaking a wire it does not understand. This is also the string
            // the local e2e docs tell people to grep for.
            self.report_once(key, || {
                error!(trait_id, method_id, "unknown wire discriminant pair");
            });
            // A codec 2 peer that asked for something unimplemented can read
            // the answer, and dropping it would leave the peer waiting forever.
            transport.send(ProtocolMessage {
                request_id: message.request_id,
                payload: Payload {
                    trait_id: PROTOCOL_ERROR_TRAIT_ID,
                    method_id: PROTOCOL_ERROR_METHOD_ID,
                    message_type: MESSAGE_TYPE_RESPONSE,
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
    use crate::frame::MESSAGE_TYPE_RECEIVE;
    use crate::frame::MESSAGE_TYPE_REQUEST;
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

    fn make_frame(
        trait_id: u8,
        method_id: u8,
        message_type: u8,
        value: Vec<u8>,
    ) -> ProtocolMessage {
        ProtocolMessage {
            request_id: "p:1".into(),
            payload: Payload {
                trait_id,
                method_id,
                message_type,
                value,
            },
        }
    }

    #[test]
    fn dispatch_unknown_id_sends_correlated_protocol_error() {
        let dispatcher = Dispatcher::new(test_spawner());
        let transport = Arc::new(RecordingTransport::default());
        let transport_dyn: Arc<dyn Transport> = transport.clone();
        let frame = make_frame(250, 251, MESSAGE_TYPE_REQUEST, Vec::new());
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
                    message_type: MESSAGE_TYPE_RESPONSE,
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
            MESSAGE_TYPE_RESPONSE,
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
    /// dispatcher only routes it back to the same address the request
    /// arrived on — request and response now share one id.
    #[test]
    fn dispatch_request_handler_error_emits_response_payload() {
        let mut dispatcher = Dispatcher::new(test_spawner());
        let ids = MethodIds {
            trait_id: 7,
            method_id: 200,
        };
        dispatcher.on_request(ids, |_request_id, _bytes| {
            // A method's failure is a `Result` inside the response payload, so
            // an error path still hands back bytes to send.
            Box::pin(async move { vec![9, 8, 7] })
        });
        let transport = Arc::new(RecordingTransport::default());
        let frame = make_frame(7, 200, MESSAGE_TYPE_REQUEST, Vec::new());
        futures::executor::block_on(dispatcher.dispatch(frame, transport.clone()));
        let sent = transport.sent();
        assert_eq!(sent.len(), 1, "exactly one response expected");
        assert_eq!(sent[0].payload.trait_id, 7);
        assert_eq!(sent[0].payload.method_id, 200);
        assert_eq!(sent[0].payload.value, vec![9, 8, 7]);
    }

    /// Registering two handlers under the same key must not silently
    /// overwrite. The contract chosen here is "loud": `on_request`
    /// returns the previous handler, so callers can detect collisions.
    #[test]
    fn register_request_twice_returns_previous_handler() {
        let mut dispatcher = Dispatcher::new(test_spawner());
        let ids = MethodIds {
            trait_id: 7,
            method_id: 200,
        };
        let prev = dispatcher.on_request(ids, |_request_id, _bytes| {
            Box::pin(async move { Vec::new() })
        });
        assert!(prev.is_none(), "first registration has no predecessor");
        let prev = dispatcher.on_request(ids, |_request_id, _bytes| {
            Box::pin(async move { Vec::new() })
        });
        assert!(
            prev.is_some(),
            "second registration must return the previous handler"
        );
    }

    /// A `Stop` frame (`message_type == MESSAGE_TYPE_STOP`) arrives at the
    /// same address as `Start` and must route to
    /// `SubscriptionManager::handle_stop` directly — never invoking the
    /// registered handler, which would otherwise try to start a second
    /// subscription instead of cancelling the first.
    #[test]
    fn stop_frame_never_invokes_the_subscription_handler() {
        let mut dispatcher = Dispatcher::new(test_spawner());
        let ids = MethodIds {
            trait_id: 7,
            method_id: 50,
        };
        let invoked = Arc::new(std::sync::atomic::AtomicBool::new(false));
        let invoked_in_handler = invoked.clone();
        dispatcher.on_subscription(ids, move |_request_id, _bytes| {
            invoked_in_handler.store(true, std::sync::atomic::Ordering::SeqCst);
            Box::pin(async move { Ok(Box::pin(futures::stream::empty()) as SubscriptionStream) })
        });
        let transport = Arc::new(RecordingTransport::default());
        let transport_dyn: Arc<dyn Transport> = transport.clone();
        let frame = make_frame(7, 50, MESSAGE_TYPE_STOP, Vec::new());
        futures::executor::block_on(dispatcher.dispatch(frame, transport_dyn));
        assert!(
            !invoked.load(std::sync::atomic::Ordering::SeqCst),
            "a Stop frame must not invoke the subscription handler"
        );
        assert!(
            transport.sent().is_empty(),
            "handle_stop on an unknown request id emits no frame"
        );
    }

    /// A request method's `Response` shares its address. Reading the leg off
    /// `message_type` is the only thing that stops an inbound `Response`, or
    /// any other leg, from being run as a fresh request and answered.
    #[test]
    fn a_request_method_ignores_every_leg_but_request() {
        for message_type in [
            MESSAGE_TYPE_RESPONSE,
            MESSAGE_TYPE_INTERRUPT,
            MESSAGE_TYPE_STOP,
            99,
        ] {
            let mut dispatcher = Dispatcher::new(test_spawner());
            let ids = MethodIds {
                trait_id: 7,
                method_id: 50,
            };
            let invoked = Arc::new(std::sync::atomic::AtomicBool::new(false));
            let invoked_in_handler = invoked.clone();
            dispatcher.on_request(ids, move |_request_id, _bytes| {
                invoked_in_handler.store(true, std::sync::atomic::Ordering::SeqCst);
                Box::pin(async move { Vec::new() })
            });
            let transport = Arc::new(RecordingTransport::default());
            let transport_dyn: Arc<dyn Transport> = transport.clone();
            let frame = make_frame(7, 50, message_type, Vec::new());
            futures::executor::block_on(dispatcher.dispatch(frame, transport_dyn));
            assert!(
                !invoked.load(std::sync::atomic::Ordering::SeqCst),
                "message_type {message_type} must not invoke a request handler"
            );
            assert!(
                transport.sent().is_empty(),
                "message_type {message_type} must not be answered"
            );
        }
    }

    /// `Receive` and `Interrupt` flow host to product and share the start
    /// address, so they must not start a subscription when they arrive here.
    #[test]
    fn a_subscription_starts_only_on_a_start_leg() {
        for message_type in [MESSAGE_TYPE_RECEIVE, MESSAGE_TYPE_INTERRUPT, 99] {
            let mut dispatcher = Dispatcher::new(test_spawner());
            let ids = MethodIds {
                trait_id: 7,
                method_id: 50,
            };
            let invoked = Arc::new(std::sync::atomic::AtomicBool::new(false));
            let invoked_in_handler = invoked.clone();
            dispatcher.on_subscription(ids, move |_request_id, _bytes| {
                invoked_in_handler.store(true, std::sync::atomic::Ordering::SeqCst);
                Box::pin(
                    async move { Ok(Box::pin(futures::stream::empty()) as SubscriptionStream) },
                )
            });
            let transport = Arc::new(RecordingTransport::default());
            let transport_dyn: Arc<dyn Transport> = transport.clone();
            let frame = make_frame(7, 50, message_type, Vec::new());
            futures::executor::block_on(dispatcher.dispatch(frame, transport_dyn));
            assert!(
                !invoked.load(std::sync::atomic::Ordering::SeqCst),
                "message_type {message_type} must not start a subscription"
            );
            assert!(
                transport.sent().is_empty(),
                "message_type {message_type} must not be answered"
            );
        }
    }

    /// A peer whose table is skewed sends the same unroutable pair on every
    /// frame. Each pair is answered every time, so the peer is never left
    /// waiting, but reported once so it cannot flood the log.
    #[test]
    fn an_unroutable_pair_is_answered_every_time_but_reported_once() {
        let dispatcher = Dispatcher::new(test_spawner());
        let transport = Arc::new(RecordingTransport::default());
        let transport_dyn: Arc<dyn Transport> = transport.clone();
        for _ in 0..3 {
            let frame = make_frame(250, 251, MESSAGE_TYPE_REQUEST, Vec::new());
            futures::executor::block_on(dispatcher.dispatch(frame, transport_dyn.clone()));
        }
        assert_eq!(
            transport.sent().len(),
            3,
            "every unroutable frame still earns its own protocol error"
        );
        assert_eq!(
            dispatcher
                .reported_violations
                .lock()
                .expect("violation set")
                .len(),
            1,
            "the pair is recorded once, so it is logged once"
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
