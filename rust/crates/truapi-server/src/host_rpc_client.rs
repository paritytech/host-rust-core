//! `subxt-rpcs` client adapter for host-provided JSON-RPC pipes.
//!
//! The platform owns the physical chain connection. This module owns only the
//! generic JSON-RPC mechanics needed to expose that pipe as a
//! [`subxt_rpcs::RpcClientT`]: request correlation, subscription routing, and
//! best-effort unsubscribe on subscription drop.

use core::mem;
use core::pin::Pin;
use core::task::{Context, Poll};
use std::collections::HashMap;
use std::sync::atomic::{AtomicBool, AtomicU64, AtomicUsize, Ordering};
use std::sync::{Arc, Mutex};

use futures::channel::{mpsc, oneshot};
use futures::{FutureExt, pin_mut};
use futures::{Stream, StreamExt};
use serde::{Serialize, Serializer};
use serde_json::value::RawValue;
use subxt_rpcs::client::{RawRpcFuture, RawRpcSubscription, RpcClientT};
use subxt_rpcs::{Error as RpcError, UserError};
use tracing::instrument;
use truapi_platform::JsonRpcConnection;

use crate::subscription::Spawner;

const MAX_BUFFERED_SUBSCRIPTIONS: usize = 64;
const MAX_BUFFERED_ITEMS_PER_SUBSCRIPTION: usize = 256;

/// JSON-RPC client backed by a host-owned [`JsonRpcConnection`].
pub(crate) struct HostRpcClient {
    inner: Arc<HostRpcClientInner>,
}

struct HostRpcClientInner {
    connection: Arc<dyn JsonRpcConnection>,
    request_ids: AtomicU64,
    user_handles: AtomicUsize,
    closed: AtomicBool,
    stop_response_loop: Mutex<Option<oneshot::Sender<()>>>,
    pending: Mutex<HashMap<String, PendingRequest>>,
    subscriptions: Mutex<SubscriptionState>,
}

/// One subscription id, in the only two states it can be in.
///
/// A notification can arrive before the task that issued the subscribe call has
/// published its sink, so an id is born `Pending` and holds its own notifications
/// until activation drains them.
enum SubscriptionEntry {
    /// Notifications received before a sink existed, oldest first.
    Pending(Vec<Box<RawValue>>),
    /// The sink the subscriber reads.
    Active(mpsc::UnboundedSender<Result<Box<RawValue>, RpcError>>),
}

/// Every subscription this client routes, under one lock.
///
/// Both states live in one map so that activation, delivery, unsubscribe and
/// connection close are each a single critical section. Ordering then follows
/// from the lock alone: there is no second lock to acquire in the right order,
/// and no window between publishing a sink and replaying what preceded it.
#[derive(Default)]
struct SubscriptionState {
    entries: HashMap<String, SubscriptionEntry>,
}

impl SubscriptionState {
    /// Publish `tx` for `subscription_id` and hand back whatever arrived before
    /// it, oldest first. The caller replays those before releasing the lock, so
    /// nothing delivered later can overtake them.
    fn activate(
        &mut self,
        subscription_id: String,
        tx: mpsc::UnboundedSender<Result<Box<RawValue>, RpcError>>,
    ) -> Vec<Box<RawValue>> {
        match self
            .entries
            .insert(subscription_id, SubscriptionEntry::Active(tx))
        {
            Some(SubscriptionEntry::Pending(items)) => items,
            // Re-activating an id that is already active replaces the sink and
            // has nothing buffered, which is also the never-seen case.
            Some(SubscriptionEntry::Active(_)) | None => Vec::new(),
        }
    }

    /// Route one notification: to the sink when the subscription is active,
    /// into its buffer when it is not.
    ///
    /// Sending happens under the lock on purpose. `unbounded_send` is a
    /// non-blocking queue push and runs no user code, and holding the lock
    /// across it is what makes delivery order total rather than a race between
    /// whoever reacquires first.
    fn deliver_or_buffer(&mut self, subscription_id: String, item: Box<RawValue>) {
        match self.entries.get_mut(&subscription_id) {
            Some(SubscriptionEntry::Active(tx)) => {
                let _ = tx.unbounded_send(Ok(item));
            }
            Some(SubscriptionEntry::Pending(items)) => {
                if items.len() < MAX_BUFFERED_ITEMS_PER_SUBSCRIPTION {
                    items.push(item);
                }
            }
            // The cap counts subscriptions holding a buffer, not active ones:
            // an active subscription costs nothing to remember here.
            None => {
                if self.pending_count() < MAX_BUFFERED_SUBSCRIPTIONS {
                    self.entries
                        .insert(subscription_id, SubscriptionEntry::Pending(vec![item]));
                }
            }
        }
    }

    /// Forget a subscription, whichever state it is in.
    fn remove(&mut self, subscription_id: &str) {
        self.entries.remove(subscription_id);
    }

    /// Take every entry, leaving the state empty.
    fn drain(&mut self) -> HashMap<String, SubscriptionEntry> {
        mem::take(&mut self.entries)
    }

    fn pending_count(&self) -> usize {
        self.entries
            .values()
            .filter(|entry| matches!(entry, SubscriptionEntry::Pending(_)))
            .count()
    }
}

struct HostRpcClientLease {
    inner: Arc<HostRpcClientInner>,
}

struct PendingRequest {
    tx: oneshot::Sender<Result<Box<RawValue>, RpcError>>,
}

#[derive(Debug, derive_more::Display, derive_more::Error)]
#[display("{}", _0)]
struct HostRpcClientError(#[error(not(source))] String);

#[derive(Serialize)]
struct JsonRpcRequest<'a> {
    jsonrpc: &'static str,
    id: &'a str,
    method: &'a str,
    #[serde(serialize_with = "serialize_json_rpc_params")]
    params: Option<&'a RawValue>,
}

fn serialize_json_rpc_params<S>(
    params: &Option<&RawValue>,
    serializer: S,
) -> Result<S::Ok, S::Error>
where
    S: Serializer,
{
    match params {
        Some(params) => params.serialize(serializer),
        None => <[(); 0]>::default().serialize(serializer),
    }
}

impl HostRpcClient {
    /// Wrap `connection` and start the response pump on `spawner`.
    pub(crate) fn new(connection: Arc<dyn JsonRpcConnection>, spawner: Spawner) -> Self {
        let (stop_response_tx, stop_response_rx) = oneshot::channel();
        let client = Self {
            inner: Arc::new(HostRpcClientInner {
                connection,
                request_ids: AtomicU64::new(1),
                user_handles: AtomicUsize::new(1),
                closed: AtomicBool::new(false),
                stop_response_loop: Mutex::new(Some(stop_response_tx)),
                pending: Mutex::new(HashMap::new()),
                subscriptions: Mutex::new(SubscriptionState::default()),
            }),
        };
        client.spawn_response_loop(spawner, stop_response_rx);
        client
    }

    /// Whether the underlying response stream has ended or failed.
    pub(crate) fn is_closed(&self) -> bool {
        self.inner.closed.load(Ordering::Relaxed)
    }

    /// Send a JSON-RPC request without waiting for its response.
    ///
    /// Used by best-effort notifications where the caller must not block on
    /// the remote endpoint acknowledging the request.
    pub(crate) fn send_fire_and_forget(
        &self,
        method: &str,
        params: Option<Box<RawValue>>,
    ) -> Result<(), RpcError> {
        if self.inner.closed.load(Ordering::Relaxed) {
            return Err(client_error("json-rpc connection is closed"));
        }
        let id = self.inner.next_request_id();
        self.inner.send_request(&id, method, params.as_deref())
    }

    fn spawn_response_loop(&self, spawner: Spawner, stop_rx: oneshot::Receiver<()>) {
        let inner = self.inner.clone();
        let fut = async move {
            let mut responses = inner.connection.responses();
            let stop = stop_rx.fuse();
            pin_mut!(stop);
            loop {
                futures::select! {
                    _ = stop => return,
                    frame = responses.next().fuse() => match frame {
                        Some(frame) => {
                            if let Err(error) = inner.handle_frame(&frame) {
                                inner.close_with_error(error);
                                return;
                            }
                        }
                        None => {
                            inner.close_with_error(client_error("json-rpc response stream ended"));
                            return;
                        }
                    }
                }
            }
        };
        (spawner)(fut.boxed());
    }
}

impl Clone for HostRpcClient {
    fn clone(&self) -> Self {
        self.inner.retain_user_handle();
        Self {
            inner: self.inner.clone(),
        }
    }
}

impl Drop for HostRpcClient {
    fn drop(&mut self) {
        self.inner.release_user_handle();
    }
}

impl HostRpcClientInner {
    fn retain_user_handle(&self) {
        self.user_handles.fetch_add(1, Ordering::Relaxed);
    }

    fn acquire_lease(self: &Arc<Self>) -> HostRpcClientLease {
        self.retain_user_handle();
        HostRpcClientLease {
            inner: self.clone(),
        }
    }

    fn release_user_handle(&self) {
        let previous = self.user_handles.fetch_sub(1, Ordering::AcqRel);
        debug_assert!(previous > 0, "host rpc client handle count underflow");
        if previous == 1 {
            self.close_with_error(client_error("json-rpc client dropped"));
        }
    }

    fn next_request_id(&self) -> String {
        format!(
            "truapi:{}",
            self.request_ids.fetch_add(1, Ordering::Relaxed)
        )
    }

    fn send_request(
        &self,
        id: &str,
        method: &str,
        params: Option<&RawValue>,
    ) -> Result<(), RpcError> {
        let normalized_params = normalize_outbound_params(method, params)?;
        let request = JsonRpcRequest {
            jsonrpc: "2.0",
            id,
            method,
            params: normalized_params.as_deref().or(params),
        };
        let encoded = serde_json::to_string(&request).map_err(RpcError::Serialization)?;
        self.connection.send(encoded);
        Ok(())
    }

    async fn request(
        &self,
        method: &str,
        params: Option<Box<RawValue>>,
    ) -> Result<Box<RawValue>, RpcError> {
        let id = self.next_request_id();
        let (tx, rx) = oneshot::channel();
        {
            let mut pending = self.pending.lock().unwrap();
            if self.closed.load(Ordering::Relaxed) {
                return Err(client_error("json-rpc connection is closed"));
            }
            pending.insert(id.clone(), PendingRequest { tx });
        }

        if let Err(error) = self.send_request(&id, method, params.as_deref()) {
            self.pending.lock().unwrap().remove(&id);
            return Err(error);
        }

        rx.await
            .map_err(|_| client_error("json-rpc request was cancelled"))?
    }

    async fn subscribe(
        self: Arc<Self>,
        method: &str,
        params: Option<Box<RawValue>>,
        unsubscribe_method: &str,
        lease: HostRpcClientLease,
    ) -> Result<RawRpcSubscription, RpcError> {
        let raw_id = self.request(method, params).await?;
        let subscription_id = subscription_id_from_raw(raw_id.as_ref())?;
        let (tx, rx) = mpsc::unbounded();
        {
            // Activation and replay are one critical section, so a notification
            // arriving now waits for the lock and lands behind what it follows.
            let mut state = self.subscriptions.lock().unwrap();
            if self.closed.load(Ordering::Relaxed) {
                return Err(client_error("json-rpc connection is closed"));
            }
            for item in state.activate(subscription_id.clone(), tx.clone()) {
                let _ = tx.unbounded_send(Ok(item));
            }
        }

        let stream = SubscriptionStream {
            inner: rx,
            client: self,
            _lease: lease,
            subscription_id: subscription_id.clone(),
            unsubscribe_method: unsubscribe_method.to_string(),
            closed: false,
        };
        Ok(RawRpcSubscription {
            stream: Box::pin(stream),
            id: Some(subscription_id),
        })
    }

    fn unsubscribe(&self, subscription_id: &str, unsubscribe_method: &str) {
        self.subscriptions.lock().unwrap().remove(subscription_id);
        if self.closed.load(Ordering::Relaxed) {
            return;
        }
        let id = self.next_request_id();
        let params = RawValue::from_string(format!(
            "[{}]",
            serde_json::to_string(subscription_id).unwrap_or_else(|_| "\"\"".to_string())
        ));
        if let Ok(params) = params {
            let _ = self.send_request(&id, unsubscribe_method, Some(params.as_ref()));
        }
    }

    #[instrument(skip_all, fields(runtime.method = "host_rpc_client.handle_frame"))]
    fn handle_frame(&self, frame: &str) -> Result<(), RpcError> {
        let value: serde_json::Value =
            serde_json::from_str(frame).map_err(RpcError::Deserialization)?;

        if value.get("method").is_some() && value.get("params").is_some() {
            self.handle_notification(&value)?;
            return Ok(());
        }

        let Some(request_id) = value.get("id").and_then(json_id) else {
            return Ok(());
        };
        let Some(pending) = self.pending.lock().unwrap().remove(&request_id) else {
            return Ok(());
        };

        if let Some(result) = value.get("result") {
            let raw = raw_value_from_json(result)?;
            let _ = pending.tx.send(Ok(raw));
            return Ok(());
        }

        if let Some(error) = value.get("error") {
            let _ = pending.tx.send(Err(user_error_from_json(error)));
            return Ok(());
        }

        let _ = pending.tx.send(Err(client_error(
            "json-rpc response missing result and error",
        )));
        Ok(())
    }

    fn handle_notification(&self, value: &serde_json::Value) -> Result<(), RpcError> {
        let Some(params) = value.get("params") else {
            return Ok(());
        };
        let Some(subscription_id) = params.get("subscription").and_then(json_id) else {
            return Ok(());
        };
        let Some(result) = params.get("result") else {
            return Ok(());
        };
        let raw = raw_value_from_json(result)?;
        self.deliver_or_buffer_subscription_item(subscription_id, raw);
        Ok(())
    }

    fn deliver_or_buffer_subscription_item(&self, subscription_id: String, item: Box<RawValue>) {
        self.subscriptions
            .lock()
            .unwrap()
            .deliver_or_buffer(subscription_id, item);
    }

    fn close_with_error(&self, error: RpcError) {
        if self.closed.swap(true, Ordering::AcqRel) {
            return;
        }
        if let Some(stop) = self.stop_response_loop.lock().unwrap().take() {
            let _ = stop.send(());
        }
        self.connection.close();

        let pending = {
            let mut pending = self.pending.lock().unwrap();
            mem::take(&mut *pending)
        };
        for (_, pending) in pending {
            let _ = pending.tx.send(Err(client_error(format!(
                "json-rpc connection closed: {error}"
            ))));
        }

        // Taken in one step, so a close error cannot land between an activation
        // and the replay it owes. A buffer with no reader is dropped with it.
        let subscriptions = self.subscriptions.lock().unwrap().drain();
        for (_, entry) in subscriptions {
            if let SubscriptionEntry::Active(tx) = entry {
                let _ = tx.unbounded_send(Err(client_error(format!(
                    "json-rpc connection closed: {error}"
                ))));
            }
        }
    }
}

impl Drop for HostRpcClientLease {
    fn drop(&mut self) {
        self.inner.release_user_handle();
    }
}

impl RpcClientT for HostRpcClient {
    fn request_raw<'a>(
        &'a self,
        method: &'a str,
        params: Option<Box<RawValue>>,
    ) -> RawRpcFuture<'a, Box<RawValue>> {
        Box::pin(async move { self.inner.request(method, params).await })
    }

    fn subscribe_raw<'a>(
        &'a self,
        sub: &'a str,
        params: Option<Box<RawValue>>,
        unsub: &'a str,
    ) -> RawRpcFuture<'a, RawRpcSubscription> {
        let lease = self.inner.acquire_lease();
        Box::pin(async move {
            self.inner
                .clone()
                .subscribe(sub, params, unsub, lease)
                .await
        })
    }
}

struct SubscriptionStream {
    inner: mpsc::UnboundedReceiver<Result<Box<RawValue>, RpcError>>,
    client: Arc<HostRpcClientInner>,
    _lease: HostRpcClientLease,
    subscription_id: String,
    unsubscribe_method: String,
    closed: bool,
}

impl Drop for SubscriptionStream {
    fn drop(&mut self) {
        if !self.closed {
            self.closed = true;
            self.client
                .unsubscribe(&self.subscription_id, &self.unsubscribe_method);
        }
    }
}

impl Stream for SubscriptionStream {
    type Item = Result<Box<RawValue>, RpcError>;

    fn poll_next(self: Pin<&mut Self>, cx: &mut Context<'_>) -> Poll<Option<Self::Item>> {
        let this = self.get_mut();
        match Pin::new(&mut this.inner).poll_next(cx) {
            Poll::Ready(None) => {
                this.closed = true;
                Poll::Ready(None)
            }
            other => other,
        }
    }
}

fn raw_value_from_json(value: &serde_json::Value) -> Result<Box<RawValue>, RpcError> {
    RawValue::from_string(value.to_string()).map_err(RpcError::Deserialization)
}

/// PAPI's modern middleware requires the array variant even though Subxt emits
/// the protocol's valid single-hash unpin form.
fn normalize_outbound_params(
    method: &str,
    params: Option<&RawValue>,
) -> Result<Option<Box<RawValue>>, RpcError> {
    if method != "chainHead_v1_unpin" {
        return Ok(None);
    }
    let Some(params) = params else {
        return Ok(None);
    };
    let mut params: Vec<serde_json::Value> =
        serde_json::from_str(params.get()).map_err(RpcError::Serialization)?;
    let Some(hash_slot @ serde_json::Value::String(_)) = params.get_mut(1) else {
        return Ok(None);
    };
    let hash = mem::take(hash_slot);
    *hash_slot = serde_json::Value::Array(vec![hash]);
    let encoded = serde_json::to_string(&params).map_err(RpcError::Serialization)?;
    RawValue::from_string(encoded)
        .map(Some)
        .map_err(RpcError::Serialization)
}

fn subscription_id_from_raw(raw: &RawValue) -> Result<String, RpcError> {
    let value: serde_json::Value =
        serde_json::from_str(raw.get()).map_err(RpcError::Deserialization)?;
    json_id(&value).ok_or_else(|| client_error("json-rpc subscription id is not a string"))
}

fn json_id(value: &serde_json::Value) -> Option<String> {
    match value {
        serde_json::Value::String(value) => Some(value.clone()),
        serde_json::Value::Number(value) => Some(value.to_string()),
        _ => None,
    }
}

fn user_error_from_json(value: &serde_json::Value) -> RpcError {
    match serde_json::from_value::<UserError>(value.clone()) {
        Ok(error) => RpcError::User(error),
        Err(error) => RpcError::Deserialization(error),
    }
}

fn client_error(reason: impl Into<String>) -> RpcError {
    RpcError::Client(Box::new(HostRpcClientError(reason.into())))
}

#[cfg(all(test, not(target_arch = "wasm32")))]
mod tests {
    use super::*;
    use std::sync::atomic::AtomicUsize;

    use futures::executor::block_on;
    use futures::stream::BoxStream;
    use serde_json::{Value, json};
    use subxt_rpcs::RpcClient;
    use subxt_rpcs::client::rpc_params;

    use crate::subscription::thread_per_subscription_spawner;

    struct TrackingConnection {
        sender: Mutex<Option<mpsc::UnboundedSender<String>>>,
        receiver: Mutex<Option<mpsc::UnboundedReceiver<String>>>,
        sent: Mutex<Vec<Value>>,
        close_count: AtomicUsize,
    }

    impl TrackingConnection {
        fn new() -> Arc<Self> {
            let (tx, rx) = mpsc::unbounded();
            Arc::new(Self {
                sender: Mutex::new(Some(tx)),
                receiver: Mutex::new(Some(rx)),
                sent: Mutex::new(Vec::new()),
                close_count: AtomicUsize::new(0),
            })
        }

        fn close_count(&self) -> usize {
            self.close_count.load(Ordering::SeqCst)
        }

        fn sent(&self) -> Vec<Value> {
            self.sent.lock().unwrap().clone()
        }
    }

    impl JsonRpcConnection for TrackingConnection {
        fn send(&self, request: String) {
            let Ok(value) = serde_json::from_str::<Value>(&request) else {
                return;
            };
            self.sent.lock().unwrap().push(value.clone());
            let Some(id) = value.get("id").cloned() else {
                return;
            };
            if value.get("method").and_then(Value::as_str) == Some("sub") {
                let response = json!({
                    "jsonrpc": "2.0",
                    "id": id,
                    "result": "sub-1",
                });
                if let Some(sender) = self.sender.lock().unwrap().as_ref() {
                    let _ = sender.unbounded_send(response.to_string());
                }
            }
        }

        fn responses(&self) -> BoxStream<'static, String> {
            self.receiver
                .lock()
                .unwrap()
                .take()
                .expect("responses called twice")
                .boxed()
        }

        fn close(&self) {
            self.close_count.fetch_add(1, Ordering::SeqCst);
            self.sender.lock().unwrap().take();
        }
    }

    #[test]
    fn dropping_one_shot_client_closes_connection_lease() {
        let connection = TrackingConnection::new();
        let spawner: Spawner = Arc::new(|_| {});

        {
            let client = HostRpcClient::new(connection.clone(), spawner);
            client
                .send_fire_and_forget("statement_submit", None)
                .unwrap();
        }

        assert_eq!(connection.close_count(), 1);
    }

    #[test]
    fn requests_without_arguments_serialize_empty_params() {
        let connection = TrackingConnection::new();
        let spawner: Spawner = Arc::new(|_| {});
        let client = HostRpcClient::new(connection.clone(), spawner);

        client
            .send_fire_and_forget("chainSpec_v1_chainName", None)
            .unwrap();

        assert_eq!(connection.sent()[0]["params"], json!([]));
    }

    #[test]
    fn subxt_single_hash_unpin_is_normalized_for_host_providers() {
        let connection = TrackingConnection::new();
        let spawner: Spawner = Arc::new(|_| {});
        let client = HostRpcClient::new(connection.clone(), spawner);
        let params = RawValue::from_string(r#"["follow-id","0x1234"]"#.to_string()).unwrap();

        client
            .send_fire_and_forget("chainHead_v1_unpin", Some(params))
            .unwrap();

        assert_eq!(
            connection.sent()[0]["params"],
            json!(["follow-id", ["0x1234"]]),
        );
    }

    #[test]
    fn subscription_stream_holds_connection_lease_until_dropped() {
        let connection = TrackingConnection::new();
        let client = HostRpcClient::new(connection.clone(), thread_per_subscription_spawner());
        let rpc_client = RpcClient::new(client.clone());

        let subscription = block_on(rpc_client.subscribe::<Value>("sub", rpc_params![], "unsub"))
            .expect("subscription should start");

        drop(rpc_client);
        drop(client);
        assert_eq!(connection.close_count(), 0);

        drop(subscription);
        assert_eq!(connection.close_count(), 1);
    }

    fn raw(text: &str) -> Box<RawValue> {
        RawValue::from_string(text.to_string()).expect("valid json")
    }

    fn drain(rx: &mut mpsc::UnboundedReceiver<Result<Box<RawValue>, RpcError>>) -> Vec<String> {
        let mut seen = Vec::new();
        while let Ok(item) = rx.try_recv() {
            seen.push(match item {
                Ok(value) => value.get().to_string(),
                Err(error) => format!("error: {error}"),
            });
        }
        seen
    }

    /// The `Stop` before `Initialized` failure: a notification that arrives
    /// before the subscribing task publishes its sink must still be delivered,
    /// and must be delivered first.
    #[test]
    fn buffered_events_precede_notifications_received_after_activation() {
        let client = HostRpcClient::new(TrackingConnection::new(), Arc::new(|_| {}));
        let (tx, mut rx) = mpsc::unbounded();

        client
            .inner
            .deliver_or_buffer_subscription_item("sub-1".to_string(), raw(r#"{"event":"first"}"#));
        client
            .inner
            .deliver_or_buffer_subscription_item("sub-1".to_string(), raw(r#"{"event":"second"}"#));

        let replayed = client
            .inner
            .subscriptions
            .lock()
            .unwrap()
            .activate("sub-1".to_string(), tx.clone());
        for item in replayed {
            tx.unbounded_send(Ok(item)).expect("receiver is alive");
        }

        client
            .inner
            .deliver_or_buffer_subscription_item("sub-1".to_string(), raw(r#"{"event":"live"}"#));

        assert_eq!(
            drain(&mut rx),
            vec![
                r#"{"event":"first"}"#.to_string(),
                r#"{"event":"second"}"#.to_string(),
                r#"{"event":"live"}"#.to_string(),
            ],
            "a live notification overtook the buffer it should follow"
        );
    }

    /// The race itself, with a real second thread: a notification is delivered
    /// while activation is mid-flight. It cannot be observed out of order
    /// because it needs the same lock activation holds across its replay, which
    /// is the property the two-lock version had to arrange by convention.
    #[test]
    fn a_live_notification_cannot_overtake_replay_in_progress() {
        let client = HostRpcClient::new(TrackingConnection::new(), Arc::new(|_| {}));
        let (tx, mut rx) = mpsc::unbounded();

        client.inner.deliver_or_buffer_subscription_item(
            "sub-1".to_string(),
            raw(r#"{"event":"buffered"}"#),
        );

        let (ready_tx, ready_rx) = std::sync::mpsc::channel();
        let deliverer = {
            let inner = Arc::clone(&client.inner);
            std::thread::spawn(move || {
                ready_tx.send(()).expect("main thread is waiting");
                inner.deliver_or_buffer_subscription_item(
                    "sub-1".to_string(),
                    raw(r#"{"event":"live"}"#),
                );
            })
        };

        {
            let mut state = client.inner.subscriptions.lock().unwrap();
            // The other thread is running and wants this lock. Replay happens
            // before it is released, exactly as `subscribe` does it.
            ready_rx.recv().expect("deliverer started");
            for item in state.activate("sub-1".to_string(), tx.clone()) {
                tx.unbounded_send(Ok(item)).expect("receiver is alive");
            }
        }

        deliverer.join().expect("deliverer finished");

        assert_eq!(
            drain(&mut rx),
            vec![
                r#"{"event":"buffered"}"#.to_string(),
                r#"{"event":"live"}"#.to_string(),
            ],
            "the live notification overtook the buffered one"
        );
    }

    /// Closing reports the failure to whoever is reading, but never ahead of
    /// events that were already queued for them.
    #[test]
    fn a_close_error_lands_behind_older_events() {
        let client = HostRpcClient::new(TrackingConnection::new(), Arc::new(|_| {}));
        let (tx, mut rx) = mpsc::unbounded();

        client
            .inner
            .deliver_or_buffer_subscription_item("sub-1".to_string(), raw(r#"{"event":"first"}"#));
        let replayed = client
            .inner
            .subscriptions
            .lock()
            .unwrap()
            .activate("sub-1".to_string(), tx.clone());
        for item in replayed {
            tx.unbounded_send(Ok(item)).expect("receiver is alive");
        }

        client
            .inner
            .close_with_error(client_error("peer went away"));

        let seen = drain(&mut rx);
        assert_eq!(seen.len(), 2, "expected the event and then the close error");
        assert_eq!(seen[0], r#"{"event":"first"}"#);
        assert!(
            seen[1].contains("json-rpc connection closed"),
            "close error should arrive last, got {:?}",
            seen[1]
        );
    }

    /// A subscription nobody ever subscribed to is dropped on close rather than
    /// kept, and an active one is told why it ended.
    #[test]
    fn closing_drops_buffers_that_have_no_reader() {
        let client = HostRpcClient::new(TrackingConnection::new(), Arc::new(|_| {}));
        client
            .inner
            .deliver_or_buffer_subscription_item("orphan".to_string(), raw(r#"{"event":"x"}"#));

        client
            .inner
            .close_with_error(client_error("peer went away"));

        let remaining = client.inner.subscriptions.lock().unwrap().entries.len();
        assert_eq!(
            remaining, 0,
            "close should leave no subscription state behind"
        );
    }

    /// The cap counts subscriptions that hold a buffer. An active subscription
    /// costs nothing to remember, so it must not consume a slot.
    #[test]
    fn the_buffer_cap_counts_only_subscriptions_holding_items() {
        let client = HostRpcClient::new(TrackingConnection::new(), Arc::new(|_| {}));
        let (tx, _rx) = mpsc::unbounded();
        client
            .inner
            .subscriptions
            .lock()
            .unwrap()
            .activate("active".to_string(), tx);

        for index in 0..MAX_BUFFERED_SUBSCRIPTIONS {
            client
                .inner
                .deliver_or_buffer_subscription_item(format!("sub-{index}"), raw("1"));
        }
        client
            .inner
            .deliver_or_buffer_subscription_item("one-too-many".to_string(), raw("1"));

        // Read the state out before asserting: a failed assertion while the
        // guard is alive poisons the lock, and the client's own `Drop` then
        // panics a second time and aborts instead of reporting.
        let (pending, buffered_one_too_many) = {
            let state = client.inner.subscriptions.lock().unwrap();
            (
                state.pending_count(),
                state.entries.contains_key("one-too-many"),
            )
        };
        assert_eq!(pending, MAX_BUFFERED_SUBSCRIPTIONS);
        assert!(
            !buffered_one_too_many,
            "a subscription past the cap must not be buffered"
        );
    }

    #[test]
    fn a_buffer_stops_growing_at_its_item_cap() {
        let client = HostRpcClient::new(TrackingConnection::new(), Arc::new(|_| {}));
        for _ in 0..MAX_BUFFERED_ITEMS_PER_SUBSCRIPTION + 8 {
            client
                .inner
                .deliver_or_buffer_subscription_item("sub-1".to_string(), raw("1"));
        }

        let buffered = {
            let state = client.inner.subscriptions.lock().unwrap();
            match state.entries.get("sub-1") {
                Some(SubscriptionEntry::Pending(items)) => items.len(),
                _ => usize::MAX,
            }
        };
        assert_eq!(buffered, MAX_BUFFERED_ITEMS_PER_SUBSCRIPTION);
    }
}
