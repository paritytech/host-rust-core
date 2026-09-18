//! Localhost WebSocket bridge. Binds to `127.0.0.1:<port>`, gates each
//! connection on a session token, and relays SCALE-encoded
//! [`ProtocolMessage`](crate::frame::ProtocolMessage) frames into a
//! product-scoped runtime.
//!
//! Feature-gated (`ws-bridge`) so wasm32 and no-tokio build paths stay lean.
//!
//! Executions under one host share a [`SharedWsBridge`] listener and the
//! process-wide `tokio` runtime, with independent tokens and connections.
//!
//! Each upgrade requires an execution's random 256-bit token (`?t=<token>`).
//! Token comparisons scan all candidates to avoid revealing which matched.
//! Tokens go only to the host's embedded WebView; its origin is not known in
//! advance, so the `Origin` header is not pinned.
//!
//! Message size, outbound queues, authenticated connections and pending
//! handshakes are bounded to contain a misbehaving local peer.

use std::collections::{HashMap, VecDeque};
use std::io;
use std::net::SocketAddr;
use std::sync::atomic::{AtomicUsize, Ordering};
use std::sync::{Arc, Mutex, OnceLock};

use futures::{FutureExt, SinkExt, StreamExt};
use rand::RngCore;
use tokio::net::TcpListener;
use tokio::runtime::{Handle, Runtime};
use tokio::sync::{mpsc, oneshot};
use tokio_tungstenite::WebSocketStream;
use tokio_tungstenite::tungstenite::Message as WsMessage;
use tokio_tungstenite::tungstenite::handshake::server::{ErrorResponse, Request, Response};
use tokio_tungstenite::tungstenite::http::{Response as HttpResponse, StatusCode};
use tokio_tungstenite::tungstenite::protocol::WebSocketConfig;

use crate::{FrameSink, ProductRuntime};

// Allow reconnect overlap without one execution exhausting the shared limit.
const MAX_WS_CONNECTIONS_PER_EXECUTION: usize = 8;

// Bound resource use even when a peer holds several valid execution tokens.
const MAX_TOTAL_WS_CONNECTIONS: usize = 64;

// Unauthenticated peers do not count against the connection limits.
const MAX_PENDING_HANDSHAKES: usize = 64;

/// Bound on the per-connection outbound frame queue. A peer that stops reading
/// cannot make the core buffer responses without limit; once the queue fills
/// the connection is treated as closed.
const OUTBOUND_QUEUE_CAP: usize = 4096;

/// Ceiling on a single inbound WebSocket message / frame. `ProtocolMessage`
/// frames on this SCALE control channel are small; the cap prevents a
/// memory-amplification DoS well below tungstenite's 64 MiB default.
const MAX_WS_MESSAGE_BYTES: usize = 8 << 20;

// Stalled handshakes must eventually release their sockets.
const HANDSHAKE_TIMEOUT: std::time::Duration = std::time::Duration::from_secs(10);

/// Per-session descriptor returned to the host: product uses `port + token`
/// to build its WebSocket URL (e.g. `ws://127.0.0.1:<port>/?t=<token>`).
#[derive(Clone, Debug, uniffi::Record)]
pub struct WsBridgeEndpoint {
    /// Localhost port the bridge is listening on.
    pub port: u16,
    /// Session token; the connecting client must supply this as the
    /// `?t=<token>` query parameter to be accepted.
    pub token: String,
}

/// Failure modes returned from host-facing `start_ws_bridge` wrappers.
#[derive(Debug, thiserror::Error, uniffi::Error)]
#[uniffi(flat_error)]
pub enum WsBridgeStartError {
    /// This execution already has a registered bridge token.
    #[error("ws bridge already running")]
    AlreadyRunning,
    /// Anything else (bind failure, runtime spin-up failure, ...).
    #[error("ws bridge start failed: {0}")]
    Io(String),
}

impl From<io::Error> for WsBridgeStartError {
    fn from(err: io::Error) -> Self {
        if err.kind() == io::ErrorKind::AlreadyExists {
            WsBridgeStartError::AlreadyRunning
        } else {
            WsBridgeStartError::Io(err.to_string())
        }
    }
}

/// Logger callback shape used by the bridge for lifecycle events. The
/// Android and iOS wrappers adapt their per-platform callback interfaces to
/// this platform-neutral shape.
pub type BridgeLogger = Arc<dyn Fn(&str, &str) + Send + Sync>;

/// Factory used by the bridge to create one product runtime per WebSocket
/// connection.
pub trait WsProductRuntimeFactory: Send + Sync {
    /// Create a runtime that emits outgoing frames into `sink`.
    fn product_runtime(&self, sink: Arc<dyn FrameSink>) -> ProductRuntime;
}

impl<F> WsProductRuntimeFactory for F
where
    F: Fn(Arc<dyn FrameSink>) -> ProductRuntime + Send + Sync,
{
    fn product_runtime(&self, sink: Arc<dyn FrameSink>) -> ProductRuntime {
        self(sink)
    }
}

/// Process-wide executor shared by every native product bridge.
///
/// The runtime intentionally lives until process exit. Native products have
/// independent bridge lifecycles, so shutting the executor down with any one
/// bridge would interrupt the others.
struct SharedNativeExecutor {
    runtime: Runtime,
}

impl SharedNativeExecutor {
    fn new() -> io::Result<Self> {
        let runtime = tokio::runtime::Builder::new_multi_thread()
            .thread_name("truapi-native-worker")
            .enable_all()
            .build()
            .map_err(|err| io::Error::other(err.to_string()))?;
        Ok(Self { runtime })
    }

    fn handle(&self) -> Handle {
        self.runtime.handle().clone()
    }

    fn worker_threads(&self) -> usize {
        self.runtime.metrics().num_workers()
    }
}

static SHARED_NATIVE_EXECUTOR: OnceLock<SharedNativeExecutor> = OnceLock::new();
static SHARED_NATIVE_EXECUTOR_INIT: Mutex<()> = Mutex::new(());

fn shared_native_executor() -> io::Result<(&'static SharedNativeExecutor, bool)> {
    if let Some(executor) = SHARED_NATIVE_EXECUTOR.get() {
        return Ok((executor, false));
    }

    // Serialize fallible initialization without caching a transient thread
    // creation failure for the rest of the process.
    let _guard = SHARED_NATIVE_EXECUTOR_INIT
        .lock()
        .unwrap_or_else(|poisoned| poisoned.into_inner());
    if let Some(executor) = SHARED_NATIVE_EXECUTOR.get() {
        return Ok((executor, false));
    }

    let initialized = SHARED_NATIVE_EXECUTOR
        .set(SharedNativeExecutor::new()?)
        .is_ok();
    let executor = SHARED_NATIVE_EXECUTOR
        .get()
        .ok_or_else(|| io::Error::other("shared native executor initialization failed"))?;
    Ok((executor, initialized))
}

struct RegistryEntry {
    runtime_factory: Arc<dyn WsProductRuntimeFactory>,
    logger: BridgeLogger,
    connection_count: Arc<AtomicUsize>,
    connections: Mutex<EntryConnections>,
}

// One lock prevents a completed handshake from registering past revocation.
#[derive(Default)]
struct EntryConnections {
    revoked: bool,
    handles: Vec<tokio::task::JoinHandle<()>>,
}

impl EntryConnections {
    fn abort_and_take(&mut self) -> Vec<tokio::task::JoinHandle<()>> {
        for handle in self.handles.iter() {
            handle.abort();
        }
        std::mem::take(&mut self.handles)
    }
}

#[derive(Default)]
struct WsBridgeRegistry {
    entries: Mutex<HashMap<String, Arc<RegistryEntry>>>,
    total_connections: Arc<AtomicUsize>,
}

impl WsBridgeRegistry {
    fn insert(
        &self,
        token: String,
        runtime_factory: Arc<dyn WsProductRuntimeFactory>,
        logger: BridgeLogger,
    ) {
        self.entries
            .lock()
            .expect("ws bridge registry mutex poisoned")
            .insert(
                token,
                Arc::new(RegistryEntry {
                    runtime_factory,
                    logger,
                    connection_count: Arc::new(AtomicUsize::new(0)),
                    connections: Mutex::new(EntryConnections::default()),
                }),
            );
    }

    fn revoke(&self, token: &str) -> Vec<tokio::task::JoinHandle<()>> {
        let Some(entry) = self
            .entries
            .lock()
            .expect("ws bridge registry mutex poisoned")
            .remove(token)
        else {
            return Vec::new();
        };
        let mut state = entry
            .connections
            .lock()
            .expect("ws bridge registry entry mutex poisoned");
        state.revoked = true;
        state.abort_and_take()
    }

    // Scan all candidates so an early match cannot reveal token order.
    fn find_matching(&self, path_and_query: Option<&str>) -> Option<Arc<RegistryEntry>> {
        // Peer-supplied query processing must not hold up registry updates.
        let candidates: Vec<(String, Arc<RegistryEntry>)> = self
            .entries
            .lock()
            .expect("ws bridge registry mutex poisoned")
            .iter()
            .map(|(token, entry)| (token.clone(), entry.clone()))
            .collect();
        let mut found = None;
        for (token, entry) in candidates.iter() {
            if path_token_matches(path_and_query, token) {
                found = Some(entry.clone());
            }
        }
        found
    }

    // Revoked entries are already removed; their caller owns the aborted tasks.
    fn take_all_handles(&self) -> Vec<tokio::task::JoinHandle<()>> {
        let entries = self
            .entries
            .lock()
            .expect("ws bridge registry mutex poisoned");
        let mut all = Vec::new();
        for entry in entries.values() {
            let mut state = entry
                .connections
                .lock()
                .expect("ws bridge registry entry mutex poisoned");
            all.append(&mut state.abort_and_take());
        }
        all
    }
}

/// Lazy listener shared by a host runtime and its product executions.
pub struct SharedWsBridge {
    inner: Mutex<Option<WsBridge>>,
    logger: BridgeLogger,
}

impl SharedWsBridge {
    /// Construct a lazy listener with host-owned lifecycle logging.
    pub fn new(logger: BridgeLogger) -> Self {
        Self {
            inner: Mutex::new(None),
            logger,
        }
    }

    /// Register an execution with its own token and connection logger.
    ///
    /// The first registration starts the listener on `bind_port`. Later
    /// registrations reuse that port; conflicting nonzero requests are logged.
    pub fn register(
        &self,
        bind_port: u16,
        runtime_factory: Arc<dyn WsProductRuntimeFactory>,
        logger: BridgeLogger,
    ) -> Result<WsBridgeEndpoint, WsBridgeStartError> {
        // Log after unlocking because host callbacks can re-enter the bridge.
        let mut pending_logs: Vec<(&'static str, String)> = Vec::new();
        let endpoint = {
            let mut guard = self.inner.lock().expect("shared ws bridge mutex poisoned");
            if guard.is_none() {
                let (bridge, logs) = WsBridge::start(bind_port, self.logger.clone())?;
                *guard = Some(bridge);
                pending_logs = logs;
            } else if bind_port != 0 {
                let running_port = guard.as_ref().expect("just checked Some").port;
                if bind_port != running_port {
                    pending_logs.push((
                        "truapi.ws_bridge.bind_port_ignored",
                        format!("requested={bind_port} running={running_port}"),
                    ));
                }
            }
            guard
                .as_ref()
                .expect("shared bridge just inserted")
                .register(runtime_factory, logger)
        };
        for (event, detail) in &pending_logs {
            (self.logger)(event, detail);
        }
        Ok(endpoint)
    }

    /// Revoke one execution's token. No-op if the listener was never
    /// started or the token is unknown.
    ///
    /// Off the shared executor, waits for connection tasks to release their
    /// sockets and capacity. On that executor, cancellation is requested
    /// without waiting to avoid deadlocking a worker.
    pub fn revoke(&self, token: &str) {
        let aborted = {
            let guard = self.inner.lock().expect("shared ws bridge mutex poisoned");
            match guard.as_ref() {
                Some(bridge) => bridge.revoke(token),
                None => return,
            }
        };
        join_aborted_connections(aborted);
    }
}

/// Running listener owned by [`SharedWsBridge`]. Dropping it stops acceptance
/// and cancels its connections without stopping the shared executor.
pub(crate) struct WsBridge {
    shutdown: Option<oneshot::Sender<()>>,
    stopped: Option<std::sync::mpsc::Receiver<()>>,
    accept_task: Option<tokio::task::JoinHandle<()>>,
    runtime_id: tokio::runtime::Id,
    registry: Arc<WsBridgeRegistry>,
    port: u16,
}

impl WsBridge {
    // Return startup logs so the caller can emit them outside its lock.
    fn start(
        bind_port: u16,
        logger: BridgeLogger,
    ) -> io::Result<(Self, Vec<(&'static str, String)>)> {
        // Bind synchronously so we can surface bind errors and discover the
        // actual port before returning.
        let std_listener =
            std::net::TcpListener::bind(SocketAddr::from(([127, 0, 0, 1], bind_port)))?;
        std_listener.set_nonblocking(true)?;
        let port = std_listener.local_addr()?.port();

        let (executor, initialized) = shared_native_executor()?;
        let handle = executor.handle();
        let runtime_id = handle.id();

        // Register the listener with the shared runtime's I/O driver before
        // returning so a successful start always yields a ready endpoint.
        let listener = {
            let _entered = handle.enter();
            TcpListener::from_std(std_listener)?
        };

        // An error return here would lose the executor's one-time startup event.
        let mut pending_logs: Vec<(&'static str, String)> = Vec::new();
        if initialized {
            pending_logs.push((
                "truapi.native.executor.started",
                format!(
                    "runtime_id={runtime_id} worker_threads={}",
                    executor.worker_threads()
                ),
            ));
        }
        let registry = Arc::new(WsBridgeRegistry::default());
        let (shutdown_tx, shutdown_rx) = oneshot::channel::<()>();
        let (stopped_tx, stopped_rx) = std::sync::mpsc::channel::<()>();
        let accept_registry = registry.clone();
        let accept_logger = logger.clone();
        let accept_task = handle.spawn(async move {
            accept_loop(listener, accept_registry, accept_logger, shutdown_rx).await;
            let _ = stopped_tx.send(());
        });

        pending_logs.push((
            "truapi.ws_bridge.started",
            format!("port={port} runtime_id={runtime_id}"),
        ));

        Ok((
            Self {
                shutdown: Some(shutdown_tx),
                stopped: Some(stopped_rx),
                accept_task: Some(accept_task),
                runtime_id,
                registry,
                port,
            },
            pending_logs,
        ))
    }

    fn register(
        &self,
        runtime_factory: Arc<dyn WsProductRuntimeFactory>,
        logger: BridgeLogger,
    ) -> WsBridgeEndpoint {
        let mut token_bytes = [0u8; 32];
        rand::thread_rng().fill_bytes(&mut token_bytes);
        let token = hex::encode(token_bytes);
        self.registry.insert(token.clone(), runtime_factory, logger);
        WsBridgeEndpoint {
            port: self.port,
            token,
        }
    }

    // Joining from this executor could block the worker needed for cancellation.
    fn revoke(&self, token: &str) -> Vec<tokio::task::JoinHandle<()>> {
        let connections = self.registry.revoke(token);
        if Handle::try_current().is_ok_and(|current| current.id() == self.runtime_id) {
            return Vec::new();
        }
        connections
    }

    // Off the shared executor, wait for tracked connection tasks to release
    // their sockets. Dispatch tasks are cancelled but not joined.
    fn stop(&mut self) {
        if let Some(tx) = self.shutdown.take() {
            let _ = tx.send(());
        }

        // The accept loop needs a worker to observe shutdown and cancel tasks.
        let called_from_shared_executor =
            Handle::try_current().is_ok_and(|handle| handle.id() == self.runtime_id);
        let stopped_cleanly = if called_from_shared_executor {
            drop(self.stopped.take());
            true
        } else {
            self.stopped
                .take()
                .is_none_or(|stopped| stopped.recv().is_ok())
        };

        if let Some(task) = self.accept_task.take()
            && !stopped_cleanly
            && !task.is_finished()
        {
            task.abort();
        }
        // Cover the non-blocking path or an accept loop that failed to stop.
        drop(self.registry.take_all_handles());
    }
}

impl Drop for WsBridge {
    fn drop(&mut self) {
        self.stop();
    }
}

// Synchronous host callers need not have an executor. This wait relies on
// connection tasks yielding so cancellation can complete.
fn join_aborted_connections(handles: Vec<tokio::task::JoinHandle<()>>) {
    if handles.is_empty() {
        return;
    }
    let Ok((executor, _)) = shared_native_executor() else {
        return;
    };
    let (done_tx, done_rx) = std::sync::mpsc::channel::<()>();
    executor.handle().spawn(async move {
        for handle in handles {
            let _ = handle.await;
        }
        let _ = done_tx.send(());
    });
    let _ = done_rx.recv();
}

async fn accept_loop(
    listener: TcpListener,
    registry: Arc<WsBridgeRegistry>,
    logger: BridgeLogger,
    mut shutdown: oneshot::Receiver<()>,
) {
    // Independent setup tasks keep a stalled handshake from blocking acceptance.
    let mut setup_tasks: VecDeque<tokio::task::JoinHandle<()>> = VecDeque::new();
    loop {
        tokio::select! {
            _ = &mut shutdown => {
                logger("truapi.ws_bridge.shutdown", "accept loop exiting");
                for task in &setup_tasks {
                    task.abort();
                }
                for task in setup_tasks {
                    let _ = task.await;
                }
                for handle in registry.take_all_handles() {
                    let _ = handle.await;
                }
                break;
            }
            accepted = listener.accept() => {
                let (stream, peer) = match accepted {
                    Ok(pair) => pair,
                    Err(err) => {
                        logger("truapi.ws_bridge.accept_error", &err.to_string());
                        continue;
                    }
                };
                setup_tasks.retain(|task| !task.is_finished());
                // Evict the oldest pending handshake so stalled peers cannot
                // reserve the entire backlog until their timeouts expire.
                if setup_tasks.len() >= MAX_PENDING_HANDSHAKES
                    && let Some(oldest) = setup_tasks.pop_front()
                {
                    oldest.abort();
                    logger("truapi.ws_bridge.handshake_backlog_evicted", &peer.to_string());
                }
                let registry = registry.clone();
                let logger = logger.clone();
                setup_tasks.push_back(tokio::spawn(async move {
                    connection_setup(stream, peer, registry, logger).await;
                }));
            }
        }
    }
}

async fn connection_setup(
    stream: tokio::net::TcpStream,
    peer: SocketAddr,
    registry: Arc<WsBridgeRegistry>,
    logger: BridgeLogger,
) {
    let auth_result = tokio::time::timeout(
        HANDSHAKE_TIMEOUT,
        authenticate_and_upgrade(stream, peer, &registry, logger.clone()),
    )
    .await;
    let Some((ws, entry, guard)) = (match auth_result {
        Ok(resolved) => resolved,
        Err(_) => {
            logger("truapi.ws_bridge.handshake_timeout", &peer.to_string());
            return;
        }
    }) else {
        return;
    };
    let logger = entry.logger.clone();
    let revoked = {
        let mut state = entry
            .connections
            .lock()
            .expect("ws bridge registry entry mutex poisoned");
        state.handles.retain(|h| !h.is_finished());
        if state.revoked {
            true
        } else {
            let conn_entry = entry.clone();
            state.handles.push(tokio::spawn(async move {
                let _guard = guard;
                connection_lifecycle(ws, peer, conn_entry).await;
            }));
            false
        }
    };
    // Host callbacks may re-enter revocation, so logging must stay outside the lock.
    if revoked {
        logger(
            "truapi.ws_bridge.connection_revoked_during_setup",
            &peer.to_string(),
        );
    }
}

struct ConnectionCountGuard {
    total: Arc<AtomicUsize>,
    per_entry: Arc<AtomicUsize>,
}

impl Drop for ConnectionCountGuard {
    fn drop(&mut self) {
        self.total.fetch_sub(1, Ordering::AcqRel);
        self.per_entry.fetch_sub(1, Ordering::AcqRel);
    }
}

// Task cancellation skips explicit cleanup after an await, but still drops guards.
struct DisposeGuard(Arc<ProductRuntime>);

impl Drop for DisposeGuard {
    fn drop(&mut self) {
        self.0.dispose();
    }
}

type AuthenticatedConnection = (
    WebSocketStream<tokio::net::TcpStream>,
    Arc<RegistryEntry>,
    ConnectionCountGuard,
);

type MatchedReservation = Arc<Mutex<Option<(Arc<RegistryEntry>, ConnectionCountGuard)>>>;

// Concurrent handshakes must not both claim the last available slot.
fn try_reserve(counter: &AtomicUsize, limit: usize) -> bool {
    // `fetch_update` is deprecated on nightly; `try_update` is not yet stable.
    let mut current = counter.load(Ordering::Acquire);
    loop {
        if current >= limit {
            return false;
        }
        match counter.compare_exchange_weak(
            current,
            current + 1,
            Ordering::AcqRel,
            Ordering::Acquire,
        ) {
            Ok(_) => return true,
            Err(actual) => current = actual,
        }
    }
}

// The handshake callback's error type is fixed by tokio-tungstenite.
#[allow(clippy::result_large_err)]
async fn authenticate_and_upgrade(
    stream: tokio::net::TcpStream,
    peer: SocketAddr,
    registry: &Arc<WsBridgeRegistry>,
    logger: BridgeLogger,
) -> Option<AuthenticatedConnection> {
    let matched: MatchedReservation = Arc::new(Mutex::new(None));
    let auth_registry = registry.clone();
    let auth_matched = matched.clone();
    let auth_logger = logger.clone();
    let callback = move |req: &Request, resp: Response| -> Result<Response, ErrorResponse> {
        let path_and_query = req.uri().path_and_query().map(|p| p.as_str());
        let Some(entry) = auth_registry.find_matching(path_and_query) else {
            auth_logger("truapi.ws_bridge.reject_unauthorized", &peer.to_string());
            let mut err: ErrorResponse = HttpResponse::new(Some("invalid token".to_string()));
            *err.status_mut() = StatusCode::UNAUTHORIZED;
            return Err(err);
        };

        // Reject over-cap connections before acknowledging the HTTP upgrade.
        if !try_reserve(&entry.connection_count, MAX_WS_CONNECTIONS_PER_EXECUTION) {
            (entry.logger)(
                "truapi.ws_bridge.connection_limit_execution",
                &peer.to_string(),
            );
            let mut err: ErrorResponse =
                HttpResponse::new(Some("execution connection limit reached".to_string()));
            *err.status_mut() = StatusCode::SERVICE_UNAVAILABLE;
            return Err(err);
        }
        if !try_reserve(&auth_registry.total_connections, MAX_TOTAL_WS_CONNECTIONS) {
            entry.connection_count.fetch_sub(1, Ordering::AcqRel);
            (entry.logger)("truapi.ws_bridge.connection_limit_total", &peer.to_string());
            let mut err: ErrorResponse =
                HttpResponse::new(Some("listener at capacity".to_string()));
            *err.status_mut() = StatusCode::SERVICE_UNAVAILABLE;
            return Err(err);
        }
        // Keep the reservation guarded even if the upgrade fails or times out.
        let guard = ConnectionCountGuard {
            total: auth_registry.total_connections.clone(),
            per_entry: entry.connection_count.clone(),
        };

        *auth_matched
            .lock()
            .expect("ws bridge handshake mutex poisoned") = Some((entry, guard));
        Ok(resp)
    };

    // Cap inbound message/frame size so a peer cannot force the runtime to
    // buffer up to tungstenite's 64 MiB default on this small control channel.
    let config = WebSocketConfig {
        max_message_size: Some(MAX_WS_MESSAGE_BYTES),
        max_frame_size: Some(MAX_WS_MESSAGE_BYTES),
        ..Default::default()
    };
    let ws = match tokio_tungstenite::accept_hdr_async_with_config(stream, callback, Some(config))
        .await
    {
        Ok(ws) => ws,
        Err(err) => {
            logger("truapi.ws_bridge.handshake_error", &err.to_string());
            return None;
        }
    };

    let (entry, guard) = matched
        .lock()
        .expect("ws bridge handshake mutex poisoned")
        .take()
        .expect("a successful upgrade always resolved a matching registry entry");
    (entry.logger)("truapi.ws_bridge.connection_open", &peer.to_string());
    Some((ws, entry, guard))
}

async fn connection_lifecycle(
    ws: WebSocketStream<tokio::net::TcpStream>,
    peer: SocketAddr,
    entry: Arc<RegistryEntry>,
) {
    let logger = &entry.logger;
    let (mut sink, mut source) = ws.split();
    let (out_tx, mut out_rx) = mpsc::channel::<Vec<u8>>(OUTBOUND_QUEUE_CAP);
    let frame_sink = Arc::new(WsFrameSink::new(out_tx));
    let product_runtime = Arc::new(entry.runtime_factory.product_runtime(frame_sink));
    let dispose_guard = DisposeGuard(product_runtime.clone());

    // Dispatch each inbound frame on its own `Send` task so a slow request
    // handler cannot stall the read loop and independent frames can run on
    // different executor workers. Responses may interleave; the wire protocol
    // matches them by request id, and `WsFrameSink::emit_frame` is thread-safe.
    let mut in_flight = tokio::task::JoinSet::new();
    {
        let writer = async {
            while let Some(bytes) = out_rx.recv().await {
                if let Err(err) = sink.send(WsMessage::Binary(bytes)).await {
                    logger("truapi.ws_bridge.send_error", &err.to_string());
                    break;
                }
            }
        };
        tokio::pin!(writer);
        loop {
            let frame = tokio::select! {
                _ = &mut writer => break,
                frame = source.next() => frame,
            };
            match frame {
                Some(Ok(WsMessage::Binary(bytes))) => {
                    while in_flight.try_join_next().is_some() {}
                    let product_runtime = product_runtime.clone();
                    let frame_logger = logger.clone();
                    in_flight.spawn(async move {
                        if let Err(err) = product_runtime.receive_frame(bytes.to_vec()).await {
                            frame_logger("truapi.ws_bridge.frame_error", &err.to_string());
                        }
                    });
                }
                Some(Ok(WsMessage::Text(_))) => {
                    logger("truapi.ws_bridge.text_frame_ignored", "");
                }
                None | Some(Ok(WsMessage::Close(_))) => break,
                Some(Ok(_)) => {}
                Some(Err(err)) => {
                    logger("truapi.ws_bridge.read_error", &err.to_string());
                    break;
                }
            }
        }
    }

    // A slow peer must not retain capacity while its close reply waits.
    let _ = sink.close().now_or_never();
    drop(in_flight);
    drop(dispose_guard);
    logger("truapi.ws_bridge.connection_closed", &peer.to_string());
}

// Scan duplicate `t=` parameters too, so their order cannot expose an early match.
fn path_token_matches(path_and_query: Option<&str>, expected: &str) -> bool {
    let Some(raw) = path_and_query else {
        return false;
    };
    let query = match raw.find('?') {
        Some(idx) => &raw[idx + 1..],
        None => return false,
    };
    let mut matched = false;
    for pair in query.split('&') {
        let (key, value) = match pair.split_once('=') {
            Some(kv) => kv,
            None => continue,
        };
        if key == "t" && constant_time_eq(value.as_bytes(), expected.as_bytes()) {
            matched = true;
        }
    }
    matched
}

/// Constant-time byte-slice equality, used for the session-token check so a
/// local peer cannot recover the token via early-exit comparison timing. The
/// token length is fixed and public, so a length mismatch may short-circuit;
/// only the value comparison must be constant time.
fn constant_time_eq(a: &[u8], b: &[u8]) -> bool {
    if a.len() != b.len() {
        return false;
    }
    let mut diff = 0u8;
    for (x, y) in a.iter().zip(b.iter()) {
        diff |= x ^ y;
    }
    diff == 0
}

struct WsFrameSink {
    outbound: mpsc::Sender<Vec<u8>>,
    closed: Mutex<bool>,
}

impl WsFrameSink {
    fn new(outbound: mpsc::Sender<Vec<u8>>) -> Self {
        Self {
            outbound,
            closed: Mutex::new(false),
        }
    }
}

impl FrameSink for WsFrameSink {
    fn emit_frame(&self, frame: Vec<u8>) {
        if *self.closed.lock().unwrap() {
            return;
        }
        // Non-blocking: a full queue means the peer stopped reading, so the
        // connection is treated as closed rather than buffering without bound.
        if self.outbound.try_send(frame).is_err() {
            *self.closed.lock().unwrap() = true;
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use parity_scale_codec::Decode;
    use parity_scale_codec::Encode;
    use truapi::v01;
    use truapi_platform::{HostInfo, PlatformInfo, ProductContext, SigningHostConfig};

    use crate::SigningHostRuntime;
    use crate::frame::{Payload, ProtocolMessage, request_ids};
    use crate::test_support::{StubPlatform, test_spawner};

    fn start_test_bridge() -> WsBridge {
        WsBridge::start(0, no_log()).expect("start bridge").0
    }

    fn test_runtime_factory() -> Arc<dyn WsProductRuntimeFactory> {
        runtime_factory_for(Arc::new(StubPlatform::default()))
    }

    fn runtime_factory_for(platform: Arc<StubPlatform>) -> Arc<dyn WsProductRuntimeFactory> {
        let config = SigningHostConfig::new(
            HostInfo {
                name: "Polkadot Mobile".to_string(),
                icon: Some("https://example.invalid/dotli.png".to_string()),
                version: None,
                platform: truapi::latest::HostPlatform::Unknown,
            },
            PlatformInfo::default(),
            [0; 32],
            [0xbb; 32],
            [0xcc; 32],
            "paseo".to_string(),
        )
        .expect("test signing host config is valid");
        let runtime = Arc::new(SigningHostRuntime::new(platform, config, test_spawner()));
        let product =
            ProductContext::new("dotli.dot".to_string()).expect("test product context is valid");
        Arc::new(move |sink| runtime.product_runtime(product.clone(), sink))
    }

    fn no_log() -> BridgeLogger {
        Arc::new(|_, _| {})
    }

    fn connect(port: u16, token: &str) -> tokio::runtime::Runtime {
        let rt = tokio::runtime::Builder::new_current_thread()
            .enable_all()
            .build()
            .expect("test runtime");
        let url = format!("ws://127.0.0.1:{port}/?t={token}");
        rt.block_on(async { tokio_tungstenite::connect_async(&url).await.expect("dial") });
        rt
    }

    #[test]
    fn path_token_matches_exact() {
        assert!(path_token_matches(Some("/?t=abc"), "abc"));
        assert!(path_token_matches(Some("/?foo=1&t=abc"), "abc"));
        assert!(!path_token_matches(Some("/?t=other"), "abc"));
        assert!(!path_token_matches(Some("/?token=abc"), "abc"));
        assert!(!path_token_matches(Some("/"), "abc"));
        assert!(!path_token_matches(None, "abc"));
    }

    #[test]
    fn path_token_matches_every_duplicated_t_pair_not_just_the_first() {
        assert!(path_token_matches(Some("/?t=wrong&t=abc"), "abc"));
        assert!(path_token_matches(Some("/?t=abc&t=wrong"), "abc"));
        assert!(!path_token_matches(Some("/?t=wrong&t=alsowrong"), "abc"));
    }

    #[test]
    fn shared_executor_uses_multithread_scheduler() {
        let (executor, _) = shared_native_executor().expect("shared native executor");
        let handle = executor.handle();
        assert_eq!(
            handle.runtime_flavor(),
            tokio::runtime::RuntimeFlavor::MultiThread
        );

        // Each task blocks one runtime worker at the barrier. They can only
        // both complete if the executor actually schedules them concurrently
        // on distinct worker threads.
        if executor.worker_threads() < 2 {
            return;
        }
        let barrier = Arc::new(std::sync::Barrier::new(2));
        let first = handle.spawn({
            let barrier = barrier.clone();
            async move {
                let worker = std::thread::current().id();
                barrier.wait();
                worker
            }
        });
        let second = handle.spawn(async move {
            let worker = std::thread::current().id();
            barrier.wait();
            worker
        });

        let client = tokio::runtime::Builder::new_current_thread()
            .enable_all()
            .build()
            .expect("test runtime");
        let (first, second) = client.block_on(async { tokio::join!(first, second) });
        assert_ne!(
            first.expect("first dispatch task"),
            second.expect("second dispatch task"),
        );
    }

    #[test]
    fn shared_executor_is_reused() {
        let (first, _) = shared_native_executor().expect("first executor access");
        let (second, initialized) = shared_native_executor().expect("second executor access");

        assert!(!initialized);
        assert_eq!(first.handle().id(), second.handle().id());
    }

    #[test]
    fn drop_from_shared_executor_does_not_block_worker() {
        let bridge = start_test_bridge();
        let (executor, _) = shared_native_executor().expect("shared native executor");
        let (dropped_tx, dropped_rx) = std::sync::mpsc::channel();

        executor.handle().spawn(async move {
            drop(bridge);
            let _ = dropped_tx.send(());
        });

        dropped_rx
            .recv_timeout(std::time::Duration::from_secs(2))
            .expect("dropping from an executor worker must not deadlock");
    }

    /// Spin the shared listener up on `127.0.0.1:0`, register one execution,
    /// dial it with a real `tokio-tungstenite` client, send a known SCALE
    /// frame, and verify the bridge echoes the SCALE-encoded
    /// `feature_supported` response.
    #[test]
    fn round_trip_feature_supported_through_bridge() {
        let bridge = start_test_bridge();
        let endpoint = bridge.register(test_runtime_factory(), no_log());
        let url = format!("ws://127.0.0.1:{}/?t={}", endpoint.port, endpoint.token);

        // Use a fresh `tokio` runtime on the test thread so the client does
        // not depend on the native executor under test.
        let rt = tokio::runtime::Builder::new_current_thread()
            .enable_all()
            .build()
            .expect("test runtime");

        let ids = request_ids("system_feature_supported").expect("known request method");
        let response_bytes = rt.block_on(async {
            let (mut ws, _) = tokio_tungstenite::connect_async(&url).await.expect("dial");

            let value = truapi::versioned::system::HostFeatureSupportedRequest::V1(
                v01::HostFeatureSupportedRequest::Chain {
                    genesis_hash: vec![0u8; 32],
                },
            )
            .encode();
            let request_frame = ProtocolMessage {
                request_id: "p:1".into(),
                payload: Payload {
                    trait_id: ids.trait_id,
                    method_id: ids.method_id,
                    message_type: crate::frame::MESSAGE_TYPE_REQUEST,
                    value,
                },
            };
            ws.send(WsMessage::Binary(request_frame.encode()))
                .await
                .expect("send");

            // Block until the bridge replies with the response frame.
            loop {
                match ws.next().await {
                    Some(Ok(WsMessage::Binary(bytes))) => break bytes,
                    Some(Ok(_)) => continue,
                    Some(Err(err)) => panic!("ws error: {err}"),
                    None => panic!("connection closed before response"),
                }
            }
        });

        let response = ProtocolMessage::decode(&mut &response_bytes[..]).expect("decode response");
        assert_eq!(response.request_id, "p:1");
        assert_eq!(response.payload.trait_id, ids.trait_id);
        assert_eq!(response.payload.method_id, ids.method_id);
        assert_eq!(
            response.payload.message_type,
            crate::frame::MESSAGE_TYPE_RESPONSE
        );
        let expected: Result<
            truapi::versioned::system::HostFeatureSupportedResponse,
            truapi::CallError<truapi::versioned::system::HostFeatureSupportedError>,
        > = Ok(truapi::versioned::system::HostFeatureSupportedResponse::V1(
            v01::HostFeatureSupportedResponse { supported: true },
        ));
        assert_eq!(response.payload.value, expected.encode());

        drop(bridge);
    }

    #[test]
    fn two_executions_share_one_port_with_isolated_tokens() {
        let bridge = start_test_bridge();
        let first = bridge.register(test_runtime_factory(), no_log());
        let second = bridge.register(test_runtime_factory(), no_log());

        assert_eq!(first.port, second.port);
        assert_ne!(first.token, second.token);

        connect(first.port, &first.token);
        connect(second.port, &second.token);

        drop(bridge);
    }

    #[test]
    fn wrong_or_unknown_token_is_rejected_at_handshake() {
        let bridge = start_test_bridge();
        let endpoint = bridge.register(test_runtime_factory(), no_log());
        let _second = bridge.register(test_runtime_factory(), no_log());

        let rt = tokio::runtime::Builder::new_current_thread()
            .enable_all()
            .build()
            .expect("test runtime");

        let url = format!("ws://127.0.0.1:{}/?t=bogus", endpoint.port);
        let err = rt
            .block_on(async { tokio_tungstenite::connect_async(&url).await })
            .expect_err("connection with an unknown token must be refused");
        let msg = format!("{err}");
        assert!(
            msg.contains("401") || msg.to_lowercase().contains("unauthorized"),
            "expected 401/unauthorized rejection, got: {msg}",
        );

        drop(bridge);
    }

    struct DisposalWatchFactory {
        inner: Arc<dyn WsProductRuntimeFactory>,
        control: Mutex<Option<crate::ProductRuntimeControl>>,
    }

    impl WsProductRuntimeFactory for DisposalWatchFactory {
        fn product_runtime(&self, sink: Arc<dyn FrameSink>) -> ProductRuntime {
            let runtime = self.inner.product_runtime(sink);
            *self.control.lock().expect("disposal watch mutex poisoned") = Some(runtime.control());
            runtime
        }
    }

    #[test]
    fn retained_controls_do_not_keep_ended_connections_alive() {
        fn is_closed(control: &crate::ProductRuntimeControl) -> bool {
            matches!(
                control.publish_chat_action(v01::HostChatActionSubscribeItem {
                    room_id: "support".into(),
                    peer: "dotli.dot".into(),
                    payload: v01::ChatActionPayload::ActionTriggered(v01::ActionTrigger {
                        message_id: "message".into(),
                        action_id: "vote".into(),
                        payload: None,
                    }),
                }),
                Err(crate::ProductRuntimeError::Closed)
            )
        }

        for ending in ["close", "revoke", "shutdown"] {
            let mut bridge = start_test_bridge();
            let watch = Arc::new(DisposalWatchFactory {
                inner: test_runtime_factory(),
                control: Mutex::new(None),
            });
            let endpoint = bridge.register(watch.clone(), no_log());
            let client = tokio::runtime::Builder::new_current_thread()
                .enable_all()
                .build()
                .expect("client runtime");
            let mut socket = client.block_on(async {
                tokio_tungstenite::connect_async(format!(
                    "ws://127.0.0.1:{}/?t={}",
                    endpoint.port, endpoint.token
                ))
                .await
                .expect("connect")
                .0
            });
            crate::test_support::wait_until(
                || {
                    watch
                        .control
                        .lock()
                        .expect("control mutex poisoned")
                        .is_some()
                },
                "connection did not create its runtime",
            );
            let control = watch
                .control
                .lock()
                .expect("control mutex poisoned")
                .clone()
                .expect("connection control");
            assert!(!is_closed(&control), "connection must begin live");

            match ending {
                "close" => client.block_on(socket.close(None)).expect("close client"),
                "revoke" => join_aborted_connections(bridge.revoke(&endpoint.token)),
                "shutdown" => bridge.stop(),
                _ => unreachable!(),
            }
            client.block_on(async {
                tokio::time::timeout(std::time::Duration::from_secs(2), async {
                    if ending == "close" {
                        assert!(
                            matches!(socket.next().await, Some(Ok(WsMessage::Close(_)))),
                            "a healthy peer must receive its close acknowledgement"
                        );
                    }
                    while let Some(Ok(_)) = socket.next().await {}
                })
                .await
                .unwrap_or_else(|_| {
                    panic!("{ending} left the socket open with a retained control")
                });
            });
            crate::test_support::wait_until(
                || bridge.registry.total_connections.load(Ordering::Acquire) == 0,
                "ended connection did not release its capacity",
            );
            assert!(is_closed(&control), "{ending} did not dispose the runtime");
        }
    }

    #[test]
    fn a_full_handshake_backlog_does_not_lock_out_a_new_connection() {
        let bridge = start_test_bridge();
        let endpoint = bridge.register(test_runtime_factory(), no_log());

        // Silent sockets fill the backlog without reaching token authentication.
        let addr = format!("127.0.0.1:{}", endpoint.port);
        let mut stalled = Vec::new();
        for _ in 0..MAX_PENDING_HANDSHAKES {
            stalled.push(std::net::TcpStream::connect(&addr).expect("stall the backlog"));
        }

        let rt = tokio::runtime::Builder::new_current_thread()
            .enable_all()
            .build()
            .expect("test runtime");
        let url = format!("ws://127.0.0.1:{}/?t={}", endpoint.port, endpoint.token);
        rt.block_on(async {
            let (mut ws, _) = tokio::time::timeout(
                std::time::Duration::from_secs(10),
                tokio_tungstenite::connect_async(&url),
            )
            .await
            .expect("a full backlog must not stall a new connection")
            .expect("dial past a full backlog");
            ws.close(None).await.expect("close client");
        });

        drop(stalled);
        drop(bridge);
    }

    #[test]
    fn revoking_one_token_leaves_another_operational() {
        let bridge = start_test_bridge();
        let revoked = bridge.register(test_runtime_factory(), no_log());
        let survives = bridge.register(test_runtime_factory(), no_log());

        let rt = tokio::runtime::Builder::new_current_thread()
            .enable_all()
            .build()
            .expect("test runtime");
        let revoked_url = format!("ws://127.0.0.1:{}/?t={}", revoked.port, revoked.token);
        let mut revoked_ws = rt.block_on(async {
            tokio_tungstenite::connect_async(&revoked_url)
                .await
                .expect("dial revoked execution")
                .0
        });

        bridge.revoke(&revoked.token);

        // Cancellation need not complete a WebSocket close handshake.
        rt.block_on(async {
            let deadline = tokio::time::sleep(std::time::Duration::from_secs(2));
            tokio::pin!(deadline);
            loop {
                tokio::select! {
                    _ = &mut deadline => panic!("revoked connection was not closed"),
                    frame = revoked_ws.next() => {
                        match frame {
                            None => break,
                            Some(Err(_)) => break,
                            Some(Ok(WsMessage::Close(_))) => continue,
                            Some(Ok(_)) => continue,
                        }
                    }
                }
            }
        });

        let err = rt
            .block_on(async { tokio_tungstenite::connect_async(&revoked_url).await })
            .expect_err("revoked token must be rejected");
        assert!(format!("{err}").to_lowercase().contains("unauthorized"));

        let survives_url = format!("ws://127.0.0.1:{}/?t={}", survives.port, survives.token);
        rt.block_on(async {
            let (mut ws, _) = tokio_tungstenite::connect_async(&survives_url)
                .await
                .expect("surviving execution remains reachable");
            ws.close(None).await.expect("close client");
        });

        drop(bridge);
    }

    #[test]
    fn reconnecting_after_revoke_gets_a_fresh_token() {
        let bridge = start_test_bridge();
        let first = bridge.register(test_runtime_factory(), no_log());
        bridge.revoke(&first.token);

        let second = bridge.register(test_runtime_factory(), no_log());
        assert_ne!(first.token, second.token);
        assert_eq!(first.port, second.port);

        connect(second.port, &second.token);

        let rt = tokio::runtime::Builder::new_current_thread()
            .enable_all()
            .build()
            .expect("test runtime");
        let first_url = format!("ws://127.0.0.1:{}/?t={}", first.port, first.token);
        let err = rt
            .block_on(async { tokio_tungstenite::connect_async(&first_url).await })
            .expect_err("the revoked token must stay rejected");
        assert!(format!("{err}").to_lowercase().contains("unauthorized"));

        drop(bridge);
    }

    #[test]
    fn host_shutdown_closes_every_registered_execution() {
        let bridge = start_test_bridge();
        let first = bridge.register(test_runtime_factory(), no_log());
        let second = bridge.register(test_runtime_factory(), no_log());

        let rt = tokio::runtime::Builder::new_current_thread()
            .enable_all()
            .build()
            .expect("test runtime");
        let (mut first_ws, mut second_ws) = rt.block_on(async {
            let (first_ws, _) = tokio_tungstenite::connect_async(format!(
                "ws://127.0.0.1:{}/?t={}",
                first.port, first.token
            ))
            .await
            .expect("dial first");
            let (second_ws, _) = tokio_tungstenite::connect_async(format!(
                "ws://127.0.0.1:{}/?t={}",
                second.port, second.token
            ))
            .await
            .expect("dial second");
            (first_ws, second_ws)
        });

        drop(bridge);

        rt.block_on(async {
            let deadline = tokio::time::sleep(std::time::Duration::from_secs(2));
            tokio::pin!(deadline);
            tokio::select! {
                _ = &mut deadline => panic!("connections were not closed on host shutdown"),
                _ = async {
                    while first_ws.next().await.is_some() {}
                    while second_ws.next().await.is_some() {}
                } => {}
            }
        });
    }

    #[test]
    fn shared_ws_bridge_lazily_starts_and_reuses_its_port() {
        let shared = SharedWsBridge::new(no_log());
        let first = shared
            .register(0, test_runtime_factory(), no_log())
            .expect("first registration starts the listener");
        let second = shared
            .register(0, test_runtime_factory(), no_log())
            .expect("second registration reuses it");

        assert_eq!(first.port, second.port);
        assert_ne!(first.token, second.token);

        connect(first.port, &first.token);
        connect(second.port, &second.token);

        shared.revoke(&first.token);
        connect(second.port, &second.token);
    }

    #[test]
    fn per_execution_cap_rejects_the_connection_past_the_limit() {
        let bridge = start_test_bridge();
        let endpoint = bridge.register(test_runtime_factory(), no_log());
        let url = format!("ws://127.0.0.1:{}/?t={}", endpoint.port, endpoint.token);

        let rt = tokio::runtime::Builder::new_current_thread()
            .enable_all()
            .build()
            .expect("test runtime");
        let _sockets = rt.block_on(async {
            let mut sockets = Vec::new();
            for _ in 0..MAX_WS_CONNECTIONS_PER_EXECUTION {
                let (ws, _) = tokio_tungstenite::connect_async(&url)
                    .await
                    .expect("dial under the per-execution cap");
                sockets.push(ws);
            }
            sockets
        });

        let err = rt
            .block_on(async { tokio_tungstenite::connect_async(&url).await })
            .expect_err("the connection past the per-execution cap must be refused");
        let msg = format!("{err}").to_lowercase();
        assert!(
            msg.contains("503") || msg.contains("service unavailable"),
            "expected a 503 rejection past the per-execution cap, got: {err}",
        );

        drop(bridge);
    }

    #[test]
    fn total_capacity_is_reusable_after_a_retained_connection_closes() {
        let bridge = start_test_bridge();
        let extra = bridge.register(test_runtime_factory(), no_log());
        let controls = Arc::new(Mutex::new(Vec::new()));
        let inner = test_runtime_factory();
        let factory: Arc<dyn WsProductRuntimeFactory> = Arc::new({
            let controls = controls.clone();
            move |sink| {
                let runtime = inner.product_runtime(sink);
                controls
                    .lock()
                    .expect("controls mutex poisoned")
                    .push(runtime.control());
                runtime
            }
        });

        let rt = tokio::runtime::Builder::new_current_thread()
            .enable_all()
            .build()
            .expect("test runtime");

        let extra_url = format!("ws://127.0.0.1:{}/?t={}", extra.port, extra.token);
        let mut sockets = rt.block_on(async {
            let mut sockets = Vec::new();
            for _ in 0..MAX_TOTAL_WS_CONNECTIONS / MAX_WS_CONNECTIONS_PER_EXECUTION {
                let endpoint = bridge.register(factory.clone(), no_log());
                for _ in 0..MAX_WS_CONNECTIONS_PER_EXECUTION {
                    let (socket, _) = tokio_tungstenite::connect_async(format!(
                        "ws://127.0.0.1:{}/?t={}",
                        endpoint.port, endpoint.token
                    ))
                    .await
                    .expect("connect within capacity");
                    sockets.push(socket);
                }
            }
            sockets
        });
        crate::test_support::wait_until(
            || controls.lock().expect("controls mutex poisoned").len() == MAX_TOTAL_WS_CONNECTIONS,
            "connections did not create their controls",
        );
        let err = rt
            .block_on(async { tokio_tungstenite::connect_async(&extra_url).await })
            .expect_err("a fresh execution must still be refused once the shared listener is full");
        let msg = format!("{err}").to_lowercase();
        assert!(
            msg.contains("503") || msg.contains("service unavailable"),
            "expected a 503 rejection past the total cap, got: {err}",
        );

        rt.block_on(async {
            sockets[0].close(None).await.expect("close one client");
            tokio::time::timeout(std::time::Duration::from_secs(2), async {
                loop {
                    if let Ok((socket, _)) = tokio_tungstenite::connect_async(&extra_url).await {
                        break socket;
                    }
                    tokio::time::sleep(std::time::Duration::from_millis(5)).await;
                }
            })
            .await
            .expect("a disconnected execution must release capacity for another product");
        });

        drop(bridge);
    }

    // Tokio contains task panics in test builds. Release builds use panic=abort,
    // so this test cannot promise panic isolation in a production host.
    #[test]
    fn a_panicking_execution_does_not_affect_a_sibling() {
        let panicking_factory: Arc<dyn WsProductRuntimeFactory> =
            Arc::new(|_sink: Arc<dyn FrameSink>| -> ProductRuntime {
                panic!("intentional test panic: simulating a failing product execution")
            });

        let bridge = start_test_bridge();
        let failing = bridge.register(panicking_factory, no_log());
        let healthy = bridge.register(test_runtime_factory(), no_log());

        let rt = tokio::runtime::Builder::new_current_thread()
            .enable_all()
            .build()
            .expect("test runtime");

        rt.block_on(async {
            let failing_url = format!("ws://127.0.0.1:{}/?t={}", failing.port, failing.token);
            let (mut ws, _) = tokio_tungstenite::connect_async(&failing_url)
                .await
                .expect("handshake succeeds; the token itself is valid");
            let deadline = tokio::time::sleep(std::time::Duration::from_secs(2));
            tokio::pin!(deadline);
            loop {
                tokio::select! {
                    _ = &mut deadline => panic!("the panicking execution's connection was never closed"),
                    frame = ws.next() => match frame {
                        None | Some(Err(_)) => break,
                        Some(Ok(_)) => continue,
                    }
                }
            }
        });

        let healthy_url = format!("ws://127.0.0.1:{}/?t={}", healthy.port, healthy.token);
        rt.block_on(async {
            let (mut ws, _) = tokio_tungstenite::connect_async(&healthy_url)
                .await
                .expect("sibling execution remains reachable");
            ws.close(None).await.expect("close client");
        });

        drop(bridge);
    }

    #[test]
    fn a_stalled_handshake_does_not_block_a_sibling_connection() {
        let bridge = start_test_bridge();
        let stalled = bridge.register(test_runtime_factory(), no_log());
        let healthy = bridge.register(test_runtime_factory(), no_log());

        let rt = tokio::runtime::Builder::new_current_thread()
            .enable_all()
            .build()
            .expect("test runtime");

        rt.block_on(async {
            let _stalled_stream = tokio::net::TcpStream::connect(("127.0.0.1", stalled.port))
                .await
                .expect("open a raw stream to the shared port");

            let healthy_url = format!("ws://127.0.0.1:{}/?t={}", healthy.port, healthy.token);
            let deadline = tokio::time::sleep(std::time::Duration::from_secs(2));
            tokio::pin!(deadline);
            tokio::select! {
                _ = &mut deadline => panic!(
                    "sibling connection was blocked by another connection's stalled handshake"
                ),
                result = tokio_tungstenite::connect_async(&healthy_url) => {
                    let (mut ws, _) = result.expect("sibling handshake must succeed promptly");
                    ws.close(None).await.expect("close client");
                }
            }
        });

        drop(bridge);
    }

    #[test]
    fn three_tokens_route_to_their_own_factory_only() {
        fn tracked_factory(called: Arc<AtomicUsize>) -> Arc<dyn WsProductRuntimeFactory> {
            let inner = test_runtime_factory();
            Arc::new(move |sink| {
                called.fetch_add(1, Ordering::SeqCst);
                inner.product_runtime(sink)
            })
        }

        let bridge = start_test_bridge();
        let calls: Vec<Arc<AtomicUsize>> = (0..3).map(|_| Arc::new(AtomicUsize::new(0))).collect();
        let endpoints: Vec<WsBridgeEndpoint> = calls
            .iter()
            .map(|called| bridge.register(tracked_factory(called.clone()), no_log()))
            .collect();

        // A response proves the factory ran; the HTTP upgrade alone does not.
        let rt = tokio::runtime::Builder::new_current_thread()
            .enable_all()
            .build()
            .expect("test runtime");
        let url = format!(
            "ws://127.0.0.1:{}/?t={}",
            endpoints[1].port, endpoints[1].token
        );
        let ids = request_ids("system_feature_supported").expect("known request method");
        rt.block_on(async {
            let (mut ws, _) = tokio_tungstenite::connect_async(&url).await.expect("dial");
            let request_frame = ProtocolMessage {
                request_id: "p:1".into(),
                payload: Payload {
                    trait_id: ids.trait_id,
                    method_id: ids.method_id,
                    message_type: crate::frame::MESSAGE_TYPE_REQUEST,
                    value: truapi::versioned::system::HostFeatureSupportedRequest::V1(
                        v01::HostFeatureSupportedRequest::Chain {
                            genesis_hash: vec![0u8; 32],
                        },
                    )
                    .encode(),
                },
            };
            ws.send(WsMessage::Binary(request_frame.encode()))
                .await
                .expect("send");
            loop {
                match ws.next().await {
                    Some(Ok(WsMessage::Binary(_))) => break,
                    Some(Ok(_)) => continue,
                    Some(Err(err)) => panic!("ws error: {err}"),
                    None => panic!("connection closed before response"),
                }
            }
        });

        assert_eq!(
            calls[0].load(Ordering::SeqCst),
            0,
            "a sibling's factory must not be invoked"
        );
        assert_eq!(
            calls[1].load(Ordering::SeqCst),
            1,
            "the matching token's own factory must be invoked exactly once"
        );
        assert_eq!(
            calls[2].load(Ordering::SeqCst),
            0,
            "a sibling's factory must not be invoked"
        );

        drop(bridge);
    }
}
