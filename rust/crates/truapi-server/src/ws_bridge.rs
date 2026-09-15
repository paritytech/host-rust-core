//! Localhost WebSocket bridge. Binds to `127.0.0.1:<port>`, gates each
//! connection on a session token, and relays SCALE-encoded
//! [`ProtocolMessage`](crate::frame::ProtocolMessage) frames into a
//! product-scoped runtime.
//!
//! Feature-gated (`ws-bridge`) so wasm32 and no-tokio build paths stay lean.
//!
//! Every product execution under one host runtime shares a single
//! [`SharedWsBridge`] listener on the process-wide `tokio` runtime.
//! [`SharedWsBridge::register`] hands each execution its own `{port, token}`
//! endpoint on that one port; [`SharedWsBridge::revoke`] tears down only that
//! execution's connections, leaving the listener and its siblings untouched.
//!
//! Security model: the listener binds `127.0.0.1` only, and every connection
//! must present its execution's 256-bit token (`?t=<token>`, from the OS
//! CSPRNG) before the upgrade completes. The handshake scans every registered
//! token with a constant-time comparison and exits early on neither a match
//! nor a duplicated `t=` pair, so timing reveals nothing about which token
//! matched. Revocation removes the token before aborting connections, and the
//! revoked flag is read under the same lock that registers a connection, so a
//! revoked token can never carry a frame. Tokens go only to the host's
//! embedded WebView, whose origin is not known a priori, so the `Origin`
//! header is not pinned.
//!
//! Bounds, all to contain a misbehaving local peer: inbound message size, each
//! connection's outbound queue, admitted connections per execution and
//! listener-wide, and — since a peer that never presents a token reaches none
//! of those — the number of handshakes in flight
//! ([`MAX_PENDING_HANDSHAKES`]). Worst-case sockets is the sum of the last
//! two. A full handshake backlog evicts its oldest entry rather than refusing
//! the newcomer, so one stalled peer cannot lock the listener.

use std::collections::{HashMap, VecDeque};
use std::io;
use std::net::SocketAddr;
use std::sync::atomic::{AtomicUsize, Ordering};
use std::sync::{Arc, Mutex, OnceLock};

use futures::{SinkExt, StreamExt};
use rand::RngCore;
use tokio::net::TcpListener;
use tokio::runtime::{Handle, Runtime};
use tokio::sync::{mpsc, oneshot};
use tokio_tungstenite::WebSocketStream;
use tokio_tungstenite::tungstenite::Message as WsMessage;
use tokio_tungstenite::tungstenite::handshake::server::{ErrorResponse, Request, Response};
use tokio_tungstenite::tungstenite::http::{Response as HttpResponse, StatusCode};
use tokio_tungstenite::tungstenite::protocol::CloseFrame;
use tokio_tungstenite::tungstenite::protocol::WebSocketConfig;
use tokio_tungstenite::tungstenite::protocol::frame::coding::CloseCode;

use crate::{FrameSink, ProductRuntime};

/// Maximum simultaneous connections a single registered execution may hold.
/// An execution uses one connection; the headroom absorbs reconnect churn,
/// and the cap bounds a buggy or hostile local peer opening many sockets
/// against one token.
///
/// Kept low enough that
/// `MAX_TOTAL_WS_CONNECTIONS / MAX_WS_CONNECTIONS_PER_EXECUTION` executions
/// can each hold their full allowance at once. Were the per-execution cap
/// above that share, one execution could take enough of the shared budget to
/// starve its siblings, which a per-execution listener could not do.
const MAX_WS_CONNECTIONS_PER_EXECUTION: usize = 8;

/// Maximum simultaneous connections across every execution sharing the
/// listener. Set well above any realistic concurrent-execution count (App,
/// Widget, Chat/Worker) while still bounding total resource use from a
/// misbehaving peer amplifying across many registered tokens.
const MAX_TOTAL_WS_CONNECTIONS: usize = 64;

/// Maximum handshakes the listener will carry at once, counted separately
/// from [`MAX_TOTAL_WS_CONNECTIONS`]: a connection occupies a slot here only
/// until its handshake resolves, and one there only once a token has
/// matched. Worst-case sockets is therefore the sum of the two, not either
/// alone. The bound exists because a peer that never presents a token is
/// invisible to the connection caps, which are reserved inside the
/// handshake. Reaching it evicts the oldest handshake rather than turning
/// the newcomer away (see [`accept_loop`]).
const MAX_PENDING_HANDSHAKES: usize = 64;

/// Bound on the per-connection outbound frame queue. A peer that stops reading
/// cannot make the core buffer responses without limit; once the queue fills
/// the connection is treated as closed.
const OUTBOUND_QUEUE_CAP: usize = 4096;

/// Ceiling on a single inbound WebSocket message / frame. `ProtocolMessage`
/// frames on this SCALE control channel are small; the cap prevents a
/// memory-amplification DoS well below tungstenite's 64 MiB default.
const MAX_WS_MESSAGE_BYTES: usize = 8 << 20;

/// Ceiling on how long one connection's own setup task will wait for its
/// handshake (`authenticate_and_upgrade`) to resolve. Each connection's setup
/// runs in its own task, so a peer that never completes the handshake cannot
/// stall any other connection — this bound exists so a stalled setup task
/// (and the socket and file descriptor behind it) cannot linger forever, and
/// so the listener's shutdown never has to wait on one indefinitely. Generous
/// relative to a real localhost upgrade (sub-millisecond in practice).
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
    /// This execution already registered a bridge token. The host's shared
    /// listener being up is the normal case and not an error.
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

/// One execution's registered runtime factory and live connection state.
struct RegistryEntry {
    runtime_factory: Arc<dyn WsProductRuntimeFactory>,
    connection_count: Arc<AtomicUsize>,
    connections: Mutex<EntryConnections>,
}

/// A connection can finish its handshake against an entry that is revoked a
/// moment later. The `revoked` flag and the handle list share one lock, and
/// `connection_setup` both reads the flag and spawns the connection under a
/// single acquisition of it, so revocation and registration serialize:
/// whichever happens first is what the other observes. A revocation that
/// wins turns the connection away before any task reads from its socket; one
/// that loses finds the handle already recorded and aborts it.
#[derive(Default)]
struct EntryConnections {
    revoked: bool,
    handles: Vec<tokio::task::JoinHandle<()>>,
}

impl EntryConnections {
    /// Request cancellation of every tracked connection and hand back sole
    /// ownership of their handles, so a caller can join what it aborted.
    fn abort_and_take(&mut self) -> Vec<tokio::task::JoinHandle<()>> {
        for handle in self.handles.iter() {
            handle.abort();
        }
        std::mem::take(&mut self.handles)
    }
}

/// Token registry shared by the listener's accept loop and every
/// [`SharedWsBridge::register`]/[`SharedWsBridge::revoke`] call.
#[derive(Default)]
struct WsBridgeRegistry {
    entries: Mutex<HashMap<String, Arc<RegistryEntry>>>,
    total_connections: Arc<AtomicUsize>,
}

impl WsBridgeRegistry {
    fn insert(&self, token: String, runtime_factory: Arc<dyn WsProductRuntimeFactory>) {
        self.entries
            .lock()
            .expect("ws bridge registry mutex poisoned")
            .insert(
                token,
                Arc::new(RegistryEntry {
                    runtime_factory,
                    connection_count: Arc::new(AtomicUsize::new(0)),
                    connections: Mutex::new(EntryConnections::default()),
                }),
            );
    }

    /// Remove `token`'s entry, mark it revoked, and abort its live
    /// connections, handing their handles back so a caller can choose to
    /// wait for them to actually finish unwinding. A handshake that matched
    /// this token just before the removal, but has not yet registered its
    /// handle, observes the `revoked` flag (set under the same lock as the
    /// abort loop below) and aborts itself instead of registering. No-op
    /// (empty result) for an unknown or already-revoked token.
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

    /// Find the entry whose token matches `path_and_query`'s `?t=` value.
    /// Scans every registered token without exiting early on a match, so
    /// timing does not reveal which one (if any) matched.
    fn find_matching(&self, path_and_query: Option<&str>) -> Option<Arc<RegistryEntry>> {
        // Snapshot first: the scan below runs over peer-supplied request bytes
        // once per registered token, and holding the registry lock across it
        // would stall every concurrent handshake, registration and revocation.
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

    /// Abort and drain every connection under a still-registered execution,
    /// handing back the owned handles so the caller can await them. Idempotent.
    /// A connection revoked moments earlier is not covered: `revoke` removed
    /// its entry and aborted it directly, so this cannot find it to await.
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

/// Host-runtime-owned shared listener. Every product execution under the
/// same host runtime clones the same `Arc<SharedWsBridge>` and registers
/// against it; the underlying listener starts on the first registration and
/// lives for as long as the host runtime does.
#[derive(Default)]
pub struct SharedWsBridge {
    inner: Mutex<Option<WsBridge>>,
}

impl SharedWsBridge {
    /// Construct an unstarted shared bridge. The listener binds lazily on
    /// the first [`Self::register`] call.
    pub fn new() -> Self {
        Self::default()
    }

    /// Ensure the shared listener is running and register a fresh
    /// per-execution token against it.
    ///
    /// `bind_port` only takes effect for the first execution to register;
    /// once the listener is up, every product connects through that same
    /// port regardless of what a later caller requests. A later caller that
    /// requested a specific (non-zero) port different from the one already
    /// running gets a log line noting the request was ignored, rather than
    /// silence.
    pub fn register(
        &self,
        bind_port: u16,
        runtime_factory: Arc<dyn WsProductRuntimeFactory>,
        logger: BridgeLogger,
    ) -> Result<WsBridgeEndpoint, WsBridgeStartError> {
        // Every logger call below is deferred until after this lock is
        // released. A host logger that blocks or calls back into
        // `register`/`revoke` would otherwise stall or deadlock every other
        // execution sharing this bridge, since this lock is the one thing
        // every one of their `register`/`revoke` calls must take too.
        let mut pending_logs: Vec<(&'static str, String)> = Vec::new();
        let endpoint = {
            let mut guard = self.inner.lock().expect("shared ws bridge mutex poisoned");
            if guard.is_none() {
                let (bridge, logs) = WsBridge::start(bind_port, logger.clone())?;
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
                .register(runtime_factory)
        };
        for (event, detail) in &pending_logs {
            logger(event, detail);
        }
        Ok(endpoint)
    }

    /// Revoke one execution's token. No-op if the listener was never
    /// started or the token is unknown.
    ///
    /// Off the shared executor this blocks until that execution's connection
    /// tasks have been joined, the same wait `stop` performs listener-wide.
    /// Joining is not a barrier on the destructors inside those tasks. On the
    /// shared executor the wait is skipped to avoid deadlocking that worker.
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

/// Running listener handle. Drop or call [`WsBridge::stop`] to shut down.
///
/// Crate-internal: hosts reach the bridge through [`SharedWsBridge`], which
/// owns the listener and hands out per-execution endpoints. Deliberately not
/// re-exported by the crate root.
///
/// The listener's tasks run on the process-wide native executor. TrUAPI
/// dispatch futures are `Send`, so connections and independent frames from
/// all registered executions can execute across the shared worker pool.
pub(crate) struct WsBridge {
    shutdown: Option<oneshot::Sender<()>>,
    stopped: Option<std::sync::mpsc::Receiver<()>>,
    accept_task: Option<tokio::task::JoinHandle<()>>,
    runtime_id: tokio::runtime::Id,
    registry: Arc<WsBridgeRegistry>,
    port: u16,
}

impl WsBridge {
    /// Bind a localhost listener and start the accept loop on the shared
    /// native executor.
    ///
    /// `logger` is still used for the accept loop's own ongoing (async,
    /// lock-free) lifecycle events; the one-time startup events below are
    /// instead returned for the caller to emit once it is no longer holding
    /// [`SharedWsBridge::inner`]'s lock.
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

        // Queued only past the last fallible step. The executor is a process
        // -wide `OnceLock`, so `initialized` is true for exactly one caller in
        // the process; dropping its event on an error return would lose it for
        // good rather than delay it.
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

    /// Register one execution's runtime factory, minting a fresh token.
    fn register(&self, runtime_factory: Arc<dyn WsProductRuntimeFactory>) -> WsBridgeEndpoint {
        let mut token_bytes = [0u8; 32];
        rand::thread_rng().fill_bytes(&mut token_bytes);
        let token = hex::encode(token_bytes);
        self.registry.insert(token.clone(), runtime_factory);
        WsBridgeEndpoint {
            port: self.port,
            token,
        }
    }

    /// Revoke one execution's token and abort its live connections, returning
    /// the tasks a caller may join. Empty when there was nothing to abort, or
    /// when the caller is itself running on this bridge's executor and must
    /// not block on it: those connections still unwind on their own.
    fn revoke(&self, token: &str) -> Vec<tokio::task::JoinHandle<()>> {
        let connections = self.registry.revoke(token);
        if Handle::try_current().is_ok_and(|current| current.id() == self.runtime_id) {
            return Vec::new();
        }
        connections
    }

    /// Signal the accept loop to exit and abort every tracked connection
    /// across every registered execution.
    ///
    /// Off the shared executor, this blocks until the accept loop has
    /// actually drained and awaited every connection, so a caller there gets
    /// a real "fully stopped" guarantee. From a task already running on the
    /// shared executor, waiting is skipped instead (see below), so this
    /// specific caller only gets a best-effort sweep, not that guarantee.
    fn stop(&mut self) {
        if let Some(tx) = self.shutdown.take() {
            let _ = tx.send(());
        }

        // Blocking is safe only off the shared executor; on one of its own
        // workers it could deadlock against the task being waited on. Skipping
        // the wait means `stop` can return before the accept loop has even
        // observed the signal, which is what the sweep below is for.
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
        // Finds nothing when the accept loop drained on its own; does real work
        // only on the non-blocking path above or after a force-abort. Aborts
        // without awaiting, `stop` not being async.
        drop(self.registry.take_all_handles());
    }
}

impl Drop for WsBridge {
    fn drop(&mut self) {
        self.stop();
    }
}

/// Block the calling thread until every aborted connection's task has been
/// joined. Spawns a small joiner task on the shared executor and blocks on a
/// synchronous channel rather than awaiting directly, since callers are
/// ordinary host threads with no executor of their own. There is no deadline:
/// a connection wedged in non-yielding work holds the caller until it unwedges.
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
    // Each accepted connection's handshake runs in its own task (see
    // `connection_setup`) so a stalled or hostile peer never blocks another
    // connection's setup, only its own. This loop tracks those setup tasks so
    // shutdown can cancel and await whichever haven't resolved yet, in
    // addition to draining every connection already registered, and so a full
    // backlog can evict its oldest entry. Accept order is insertion order, so
    // the front is the longest-running handshake.
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
                // `take_all_handles` both requests cancellation and hands back
                // sole ownership of every handle still under a registered
                // execution, so every one of them can genuinely be awaited
                // here before this loop (and thus the listener's `stopped`
                // signal) returns. It does not see a connection whose token
                // was revoked (and thus removed from the registry) moments
                // earlier — `revoke` already aborted that one directly.
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
                // A peer that never presents a token holds a task and a file
                // descriptor for up to `HANDSHAKE_TIMEOUT` without ever
                // reaching the connection caps, which are reserved inside the
                // handshake. Bound that backlog by evicting its oldest entry
                // rather than refusing this peer: a real localhost handshake
                // resolves in well under a millisecond, so the oldest of a
                // full backlog is one that has stalled, while refusing the
                // newcomer would let a peer holding every slot lock the whole
                // shared listener out for every execution.
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

/// Authenticate one accepted connection and, if the handshake succeeds,
/// register it and run its lifecycle. Spawned independently per connection
/// (from `accept_loop`) precisely so a stalled or hostile peer's handshake
/// blocks only this task, never another connection's setup, another
/// execution's connections, or the accept loop's ability to keep accepting.
///
/// Handshakes therefore resolve concurrently, which is why the
/// connection-count caps inside `authenticate_and_upgrade`'s handshake
/// callback are reserved with a compare-and-swap loop (`try_reserve`) rather
/// than a plain load-then-increment, and why the `revoked` flag below is read
/// under the same lock that registers the connection: a token revoked while
/// this handshake was resolving must not end up with a task reading from its
/// socket, however many handshakes are in flight.
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
    // Read the revocation flag and spawn the connection under one acquisition
    // of the lock `revoke` takes for its own flag-and-abort pass, so the two
    // serialize: an execution revoked while this handshake was resolving never
    // gets a task reading from the socket, and one still live cannot be
    // revoked between the spawn and the handle landing in its list, where it
    // would be left running with no owner. `tokio::spawn` only queues the
    // task, so nothing host-supplied runs under the lock here.
    let revoked = {
        let mut state = entry
            .connections
            .lock()
            .expect("ws bridge registry entry mutex poisoned");
        state.handles.retain(|h| !h.is_finished());
        if state.revoked {
            true
        } else {
            let conn_logger = logger.clone();
            let conn_entry = entry.clone();
            state.handles.push(tokio::spawn(async move {
                let _guard = guard;
                connection_lifecycle(ws, peer, conn_entry, conn_logger).await;
            }));
            false
        }
    };
    // Logged after the lock is released: the logger is a host callback, and one
    // that blocks or re-enters would otherwise stall every `revoke` and
    // shutdown pass that needs this entry's lock.
    if revoked {
        logger(
            "truapi.ws_bridge.connection_revoked_during_setup",
            &peer.to_string(),
        );
    }
}

/// Decrements the global and per-execution connection counts on drop, which
/// runs whether the connection task ends normally or is aborted (e.g. by a
/// revoke), keeping the caps accurate under both.
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

/// Disposes a connection's `ProductRuntime` when this guard drops, however
/// that happens. `.abort()` — the only mechanism `revoke` and shutdown use to
/// end a connection — drops its task's future at whatever `.await` point it
/// was suspended at (almost always inside the read loop), which skips any
/// code written after that point, including an explicit `dispose()` call at
/// the end of the function. A value still on the stack at that point still
/// gets dropped, though, so holding the runtime here is what actually
/// disposes an aborted connection. `dispose()` is documented as idempotent,
/// so this is safe even alongside a path that also disposes explicitly.
struct DisposeGuard(Arc<ProductRuntime>);

impl Drop for DisposeGuard {
    fn drop(&mut self) {
        self.0.dispose();
    }
}

/// A fully upgraded WebSocket connection, the execution entry its token
/// matched, and the connection-count guard reserved for it.
type AuthenticatedConnection = (
    WebSocketStream<tokio::net::TcpStream>,
    Arc<RegistryEntry>,
    ConnectionCountGuard,
);

/// What the handshake callback found and reserved, shared between the
/// callback and the function's own return path.
type MatchedReservation = Arc<Mutex<Option<(Arc<RegistryEntry>, ConnectionCountGuard)>>>;

/// Atomically reserve one slot by incrementing `counter` unless it is already
/// at `limit`, retrying under contention. One task per accepted connection
/// means setups reserve concurrently, so this cannot be a plain
/// load-then-increment: two handshakes could otherwise both observe room for
/// the last slot and both take it.
fn try_reserve(counter: &AtomicUsize, limit: usize) -> bool {
    counter
        .fetch_update(Ordering::AcqRel, Ordering::Acquire, |current| {
            (current < limit).then_some(current + 1)
        })
        .is_ok()
}

/// Complete the WebSocket handshake, resolving it against the registry to
/// find the matching execution's entry and reserving its connection-count
/// slots for the life of the connection.
///
/// Called from `connection_setup`, one independent task per accepted
/// connection, under [`HANDSHAKE_TIMEOUT`] — so a peer that never completes
/// its handshake only ever stalls that one task, not the accept loop or any
/// other connection's setup.
///
/// The connection-count reservation happens inside the synchronous handshake
/// callback via [`try_reserve`], as soon as a token matches and both caps
/// have room, and a [`ConnectionCountGuard`] for it is constructed
/// immediately and stashed alongside the matched entry. Every way this
/// function can end — a successful upgrade, a post-callback handshake I/O
/// failure, or an outer timeout dropping this whole future — drops `matched`
/// and, with it, any reserved-but-unclaimed guard, so a failure after the
/// callback already committed a slot can never leak it.
// `clippy::result_large_err` fires on the handshake callback because
// tokio-tungstenite's `ErrorResponse` type carries the full HTTP response
// (~136 bytes). The closure signature is dictated by tokio-tungstenite's
// API, so the lint can only be silenced at the call site.
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

        // Reserve both caps' slots here, inside the synchronous handshake
        // callback, so an over-cap peer is rejected at the HTTP upgrade
        // rather than allowed to open a socket that gets dropped right
        // after. Each reservation is a compare-and-swap because one task per
        // connection means concurrent reservations against the same counter.
        if !try_reserve(&entry.connection_count, MAX_WS_CONNECTIONS_PER_EXECUTION) {
            auth_logger(
                "truapi.ws_bridge.connection_limit_execution",
                &peer.to_string(),
            );
            let mut err: ErrorResponse =
                HttpResponse::new(Some("execution connection limit reached".to_string()));
            *err.status_mut() = StatusCode::SERVICE_UNAVAILABLE;
            return Err(err);
        }
        if !try_reserve(&auth_registry.total_connections, MAX_TOTAL_WS_CONNECTIONS) {
            // Roll back the per-execution reservation above: it was never
            // claimed, since the total cap is what ultimately rejected this
            // attempt.
            entry.connection_count.fetch_sub(1, Ordering::AcqRel);
            auth_logger("truapi.ws_bridge.connection_limit_total", &peer.to_string());
            let mut err: ErrorResponse =
                HttpResponse::new(Some("listener at capacity".to_string()));
            *err.status_mut() = StatusCode::SERVICE_UNAVAILABLE;
            return Err(err);
        }
        // Built right after both reservations above, so no return from this
        // function — success, a later I/O failure, or an outer timeout — can
        // drop `matched` without also dropping (and thus balancing) this
        // guard.
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
    logger("truapi.ws_bridge.connection_open", &peer.to_string());
    Some((ws, entry, guard))
}

async fn connection_lifecycle(
    ws: WebSocketStream<tokio::net::TcpStream>,
    peer: SocketAddr,
    entry: Arc<RegistryEntry>,
    logger: BridgeLogger,
) {
    let (mut sink, mut source) = ws.split();
    let (out_tx, mut out_rx) = mpsc::channel::<Vec<u8>>(OUTBOUND_QUEUE_CAP);
    let frame_sink = Arc::new(WsFrameSink::new(out_tx));
    let product_runtime = Arc::new(entry.runtime_factory.product_runtime(frame_sink));
    let dispose_guard = DisposeGuard(product_runtime.clone());

    let pump_logger = logger.clone();
    let pump = tokio::spawn(async move {
        while let Some(bytes) = out_rx.recv().await {
            if let Err(err) = sink.send(WsMessage::Binary(bytes)).await {
                pump_logger("truapi.ws_bridge.send_error", &err.to_string());
                break;
            }
        }
        let _ = sink
            .send(WsMessage::Close(Some(CloseFrame {
                code: CloseCode::Normal,
                reason: "bridge closing".into(),
            })))
            .await;
        let _ = sink.close().await;
    });

    // Dispatch each inbound frame on its own `Send` task so a slow request
    // handler cannot stall the read loop and independent frames can run on
    // different executor workers. Responses may interleave; the wire protocol
    // matches them by request id, and `WsFrameSink::emit_frame` is thread-safe.
    let mut in_flight: Vec<tokio::task::JoinHandle<()>> = Vec::new();
    while let Some(frame) = source.next().await {
        match frame {
            Ok(WsMessage::Binary(bytes)) => {
                in_flight.retain(|task| !task.is_finished());
                let product_runtime = product_runtime.clone();
                let frame_logger = logger.clone();
                in_flight.push(tokio::spawn(async move {
                    // A frame the runtime cannot decode is a wire mismatch on
                    // the peer's side. Report it: dropping it unreported is
                    // indistinguishable from the peer never having sent it,
                    // and the peer is left waiting for a response forever.
                    if let Err(err) = product_runtime.receive_frame(bytes.to_vec()).await {
                        frame_logger("truapi.ws_bridge.frame_error", &err.to_string());
                    }
                }));
            }
            Ok(WsMessage::Text(_)) => {
                logger("truapi.ws_bridge.text_frame_ignored", "");
            }
            Ok(WsMessage::Close(_)) => break,
            Ok(_) => {}
            Err(err) => {
                logger("truapi.ws_bridge.read_error", &err.to_string());
                break;
            }
        }
    }

    // The connection is gone: cancel in-flight dispatches so long-pending
    // handlers unwind instead of outliving the connection.
    for task in &in_flight {
        task.abort();
    }

    // Dispose and release the runtime before awaiting the pump. The pump ends
    // when the last outbound sender drops, and the runtime owns one through its
    // frame sink, so holding the runtime here while waiting for the pump would
    // wait on something only this function's own return can cause.
    drop(dispose_guard);
    drop(product_runtime);

    let _ = pump.await;
    logger("truapi.ws_bridge.connection_closed", &peer.to_string());
}

/// Whether `path_and_query`'s `?t=` value (any occurrence) matches `expected`,
/// compared in constant time. Every `t=` pair present is checked — this does
/// not stop at the first match — so a peer padding the query with several
/// `t=` pairs cannot make a match resolve faster than a non-match and use
/// that timing to test a candidate token. The token length is fixed and
/// public, so a length mismatch may short-circuit; only the value comparison
/// must be constant time.
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

    /// A started bridge with logging discarded, which is all any test here
    /// wants from `WsBridge::start`'s deferred-log return.
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

    /// A query with more than one `t=` pair is matched if ANY of them equals
    /// the expected token, regardless of position — this is what closes the
    /// timing differential a peer could otherwise create by padding the
    /// query with non-matching `t=` pairs before or after the real one.
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
        let endpoint = bridge.register(test_runtime_factory());
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

    /// Two executions registered against the same shared listener land on
    /// the same port with independent tokens, and a token only opens its own
    /// execution's runtime, never the other's.
    #[test]
    fn two_executions_share_one_port_with_isolated_tokens() {
        let bridge = start_test_bridge();
        let first = bridge.register(test_runtime_factory());
        let second = bridge.register(test_runtime_factory());

        assert_eq!(first.port, second.port);
        assert_ne!(first.token, second.token);

        // Each token independently authenticates against the shared port.
        connect(first.port, &first.token);
        connect(second.port, &second.token);

        drop(bridge);
    }

    /// A handshake presenting one execution's token must not be accepted as
    /// belonging to a different execution's entry, and an unknown token is
    /// rejected outright.
    #[test]
    fn wrong_or_unknown_token_is_rejected_at_handshake() {
        let bridge = start_test_bridge();
        let endpoint = bridge.register(test_runtime_factory());
        let _second = bridge.register(test_runtime_factory());

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

    /// Revoking one execution's token closes only its own connections and
    /// rejects future handshakes against it, while a sibling execution on
    /// the same shared listener keeps working.
    /// Hands out the real runtime while keeping the control handle for the
    /// connection it was built for, so a test can ask whether that connection's
    /// runtime has been disposed.
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

    /// Ending a connection disposes the runtime that served it, so the host-core
    /// subscriptions and chat state it held are released rather than left live
    /// for the rest of the listener's life.
    #[test]
    fn ending_a_connection_disposes_its_runtime() {
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

        let bridge = start_test_bridge();
        let watch = Arc::new(DisposalWatchFactory {
            inner: test_runtime_factory(),
            control: Mutex::new(None),
        });
        let endpoint = bridge.register(watch.clone());

        let rt = tokio::runtime::Builder::new_current_thread()
            .enable_all()
            .build()
            .expect("test runtime");
        let url = format!("ws://127.0.0.1:{}/?t={}", endpoint.port, endpoint.token);

        let control = rt.block_on(async {
            let (mut ws, _) = tokio_tungstenite::connect_async(&url).await.expect("dial");
            let control = loop {
                if let Some(control) = watch
                    .control
                    .lock()
                    .expect("disposal watch mutex poisoned")
                    .clone()
                {
                    break control;
                }
                tokio::time::sleep(std::time::Duration::from_millis(5)).await;
            };
            assert!(
                !is_closed(&control),
                "the runtime should be live while the connection is open"
            );
            ws.close(None).await.expect("close client");
            control
        });

        let deadline = std::time::Instant::now() + std::time::Duration::from_secs(5);
        while !is_closed(&control) {
            assert!(
                std::time::Instant::now() < deadline,
                "the connection ended without disposing its runtime"
            );
            std::thread::sleep(std::time::Duration::from_millis(5));
        }

        drop(bridge);
    }

    /// A peer holding every handshake slot open must not be able to lock a
    /// legitimate connection out of the shared listener: a full backlog evicts
    /// its oldest entry instead of refusing the newcomer.
    #[test]
    fn a_full_handshake_backlog_does_not_lock_out_a_new_connection() {
        let bridge = start_test_bridge();
        let endpoint = bridge.register(test_runtime_factory());

        // Raw TCP connections that never send a byte, so each one occupies a
        // handshake slot until it is evicted or times out.
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

    /// Revoking one execution's token tears down that execution's live
    /// connection and stops its token authenticating, while a sibling
    /// execution on the same listener keeps working.
    #[test]
    fn revoking_one_token_leaves_another_operational() {
        let bridge = start_test_bridge();
        let revoked = bridge.register(test_runtime_factory());
        let survives = bridge.register(test_runtime_factory());

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

        // The already-open connection is torn down. Aborting the task drops
        // the socket without a clean close handshake, so the client
        // observes either end-of-stream or a read error, not necessarily a
        // `Close` frame.
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

        // ...and its token no longer authenticates.
        let err = rt
            .block_on(async { tokio_tungstenite::connect_async(&revoked_url).await })
            .expect_err("revoked token must be rejected");
        assert!(format!("{err}").to_lowercase().contains("unauthorized"));

        // The sibling execution is unaffected.
        let survives_url = format!("ws://127.0.0.1:{}/?t={}", survives.port, survives.token);
        rt.block_on(async {
            let (mut ws, _) = tokio_tungstenite::connect_async(&survives_url)
                .await
                .expect("surviving execution remains reachable");
            ws.close(None).await.expect("close client");
        });

        drop(bridge);
    }

    /// After a token is revoked, registering a fresh execution (simulating a
    /// reconnect / restart) gets a brand new token that works independently
    /// of the old one.
    #[test]
    fn reconnecting_after_revoke_gets_a_fresh_token() {
        let bridge = start_test_bridge();
        let first = bridge.register(test_runtime_factory());
        bridge.revoke(&first.token);

        let second = bridge.register(test_runtime_factory());
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

    /// Dropping the shared listener (host runtime shutdown) tears down every
    /// registered execution's connections, not just one.
    #[test]
    fn host_shutdown_closes_every_registered_execution() {
        let bridge = start_test_bridge();
        let first = bridge.register(test_runtime_factory());
        let second = bridge.register(test_runtime_factory());

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

    /// `SharedWsBridge` starts its listener lazily on first registration and
    /// hands every subsequent registration the same port.
    #[test]
    fn shared_ws_bridge_lazily_starts_and_reuses_its_port() {
        let shared = SharedWsBridge::new();
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
        // The second registration is untouched by revoking the first.
        connect(second.port, &second.token);
    }

    /// Once one execution has `MAX_WS_CONNECTIONS_PER_EXECUTION` live
    /// connections, its next connection attempt is refused with a 503 even
    /// though the shared listener's own total cap has plenty of room left.
    #[test]
    fn per_execution_cap_rejects_the_connection_past_the_limit() {
        let bridge = start_test_bridge();
        let endpoint = bridge.register(test_runtime_factory());
        let url = format!("ws://127.0.0.1:{}/?t={}", endpoint.port, endpoint.token);

        let rt = tokio::runtime::Builder::new_current_thread()
            .enable_all()
            .build()
            .expect("test runtime");
        // Keep every socket alive so the execution's connection count never
        // drops back below the cap while the next attempt is made.
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

    /// The shared listener's total connection cap is enforced independently
    /// of any single execution's own cap: a brand-new execution (one that
    /// has never opened a connection before, nowhere near its own
    /// per-execution limit) is still refused once the shared budget is
    /// gone. Simulates the budget already being exhausted by directly
    /// setting the same atomic the real cap check reads, rather than
    /// opening `MAX_TOTAL_WS_CONNECTIONS` real sockets just to reach it —
    /// this exercises the exact same check with far less real I/O.
    #[test]
    fn total_cap_rejects_the_connection_even_for_a_fresh_execution() {
        let bridge = start_test_bridge();
        let extra = bridge.register(test_runtime_factory());
        bridge
            .registry
            .total_connections
            .store(MAX_TOTAL_WS_CONNECTIONS, Ordering::SeqCst);

        let rt = tokio::runtime::Builder::new_current_thread()
            .enable_all()
            .build()
            .expect("test runtime");

        let extra_url = format!("ws://127.0.0.1:{}/?t={}", extra.port, extra.token);
        let err = rt
            .block_on(async { tokio_tungstenite::connect_async(&extra_url).await })
            .expect_err("a fresh execution must still be refused once the shared listener is full");
        let msg = format!("{err}").to_lowercase();
        assert!(
            msg.contains("503") || msg.contains("service unavailable"),
            "expected a 503 rejection past the total cap, got: {err}",
        );

        drop(bridge);
    }

    /// A panic while building one execution's product runtime (e.g. a bug in
    /// its own logic) tears down only that connection, not a sibling's — this
    /// bridge does not, say, hold a lock across the panicking call that a
    /// sibling connection also needs. Tokio's per-task panic containment is
    /// what provides the isolation this test observes, but the release
    /// profile sets `panic = "abort"`, so that containment — and thus this
    /// test's premise — is a property of test builds only; a panic here in
    /// an actual release build aborts the whole host process regardless of
    /// which task it originated in.
    #[test]
    fn a_panicking_execution_does_not_affect_a_sibling() {
        let panicking_factory: Arc<dyn WsProductRuntimeFactory> =
            Arc::new(|_sink: Arc<dyn FrameSink>| -> ProductRuntime {
                panic!("intentional test panic: simulating a failing product execution")
            });

        let bridge = start_test_bridge();
        let failing = bridge.register(panicking_factory);
        let healthy = bridge.register(test_runtime_factory());

        let rt = tokio::runtime::Builder::new_current_thread()
            .enable_all()
            .build()
            .expect("test runtime");

        // The handshake succeeds (the token is valid); the connection is then
        // torn down once its factory panics while building the runtime.
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

        // The healthy sibling execution is unaffected.
        let healthy_url = format!("ws://127.0.0.1:{}/?t={}", healthy.port, healthy.token);
        rt.block_on(async {
            let (mut ws, _) = tokio_tungstenite::connect_async(&healthy_url)
                .await
                .expect("sibling execution remains reachable");
            ws.close(None).await.expect("close client");
        });

        drop(bridge);
    }

    /// A peer that opens a TCP connection and never sends the HTTP upgrade
    /// request — so its handshake never resolves — does not block a
    /// sibling's connection attempt. Each accepted connection's handshake
    /// runs in its own task, and the connection caps are reserved inside it
    /// once a token matches, which is why an unauthenticated socket is bounded
    /// by the handshake backlog rather than by those caps.
    #[test]
    fn a_stalled_handshake_does_not_block_a_sibling_connection() {
        let bridge = start_test_bridge();
        let stalled = bridge.register(test_runtime_factory());
        let healthy = bridge.register(test_runtime_factory());

        let rt = tokio::runtime::Builder::new_current_thread()
            .enable_all()
            .build()
            .expect("test runtime");

        rt.block_on(async {
            // A raw TCP connection that never sends any bytes: the accept
            // loop sees it, but its handshake never resolves.
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

    /// Registers three tokens with distinguishable runtime factories and
    /// confirms connecting through one token invokes only its own factory,
    /// never a sibling's — ruling out a routing bug that only happens to
    /// work by coincidence with exactly two registry entries.
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
            .map(|called| bridge.register(tracked_factory(called.clone())))
            .collect();

        // Connect through the middle token specifically, and wait for a real
        // response: the server cannot answer without having already called
        // `product_runtime()` on the connection task, which is what makes
        // this a reliable synchronization point rather than racing the
        // server's own handling of the just-completed handshake.
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
