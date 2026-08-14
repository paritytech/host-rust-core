//! Product-frame WebSocket bridge for the pairing host.
//!
//! Each WebSocket connection is one product: inbound binary frames are pushed
//! into a [`ProductRuntime`] and its outgoing frames are written back as
//! binary messages. One binary WS message carries exactly one SCALE
//! `ProtocolMessage`, matching the browser transport's framing.

use std::net::SocketAddr;
use std::sync::{Arc, Mutex, RwLock};
use std::time::Duration;

use anyhow::{Context, Result};
use futures_util::{SinkExt, StreamExt};
use rand::{RngCore, rngs::OsRng};
use tokio::io::{AsyncRead, AsyncWrite};
use tokio::net::TcpListener;
#[cfg(unix)]
use tokio::net::UnixListener;
use tokio::sync::{mpsc, watch};
#[cfg(test)]
use tokio_tungstenite::accept_async;
use tokio_tungstenite::accept_hdr_async;
use tokio_tungstenite::tungstenite::Message;
use tokio_tungstenite::tungstenite::handshake::server::{
    Callback, ErrorResponse, Request, Response,
};
use tokio_tungstenite::tungstenite::http::StatusCode;
use tracing::{debug, warn};
use truapi_platform::normalize_product_identifier;
use truapi_server::{
    FrameSink, PairingHostRuntime, ProductContext, ProductRuntime, SigningHostRuntime,
};

/// Pause after a failed `accept()` before trying again.
///
/// A failed accept leaves the peer in the listener's queue, so the listener stays
/// readable and an immediate retry fails the same way. Without a pause that is a
/// full-CPU loop emitting one warning per iteration. The errors that reach here
/// are either process-wide (`EMFILE`/`ENFILE`) or per-connection and transient
/// (`ECONNABORTED`); neither clears faster for being retried in a tight loop.
const ACCEPT_RETRY_DELAY: Duration = Duration::from_millis(50);

#[derive(Clone, Debug, PartialEq, Eq)]
struct SelectedProduct {
    product_id: String,
    active_execution: Option<AuthorizedExecution>,
}

#[derive(Clone, Debug, PartialEq, Eq)]
struct AuthorizedExecution {
    authorization_path: String,
    context: ProductContext,
}

/// Revocable capability for exactly one measured product execution.
pub struct ProductExecution {
    current: watch::Sender<SelectedProduct>,
    authorization_path: String,
}

impl ProductExecution {
    /// Credential-bearing endpoint supplied only to this product child.
    pub fn frame_url(&self, endpoint: &str) -> String {
        if endpoint.starts_with("ws+unix:") {
            format!("{endpoint}?auth={}", self.authorization_path)
        } else {
            format!("{endpoint}{}", self.authorization_path)
        }
    }
}

impl Drop for ProductExecution {
    fn drop(&mut self) {
        let authorization_path = &self.authorization_path;
        self.current.send_if_modified(|current| {
            if current
                .active_execution
                .as_ref()
                .is_some_and(|execution| &execution.authorization_path == authorization_path)
            {
                current.active_execution = None;
                true
            } else {
                false
            }
        });
    }
}

/// Process-local product selection shared by the command loop and frame server.
pub struct ProductSelection {
    current: watch::Sender<SelectedProduct>,
}

impl ProductSelection {
    /// Validate and normalize the initial product id.
    pub fn new(product_id: String) -> Result<Arc<Self>> {
        let product_id = normalize_product_identifier(&product_id)
            .map_err(|error| anyhow::anyhow!("invalid product id: {error}"))?;
        let (current, _) = watch::channel(SelectedProduct {
            product_id,
            active_execution: None,
        });
        Ok(Arc::new(Self { current }))
    }

    /// Return the normalized current product id.
    pub fn current(&self) -> String {
        self.current.borrow().product_id.clone()
    }

    /// Issue a fresh capability bound to one trusted executable identity.
    pub fn issue_execution(&self, artifact_identity: String) -> Result<ProductExecution> {
        let context = ProductContext::new(self.current(), artifact_identity.clone())
            .map_err(|error| anyhow::anyhow!("invalid product context: {error}"))?;
        let authorization_path = fresh_authorization_path();
        self.current.send_modify(|current| {
            current.active_execution = Some(AuthorizedExecution {
                authorization_path: authorization_path.clone(),
                context,
            });
        });
        Ok(ProductExecution {
            current: self.current.clone(),
            authorization_path,
        })
    }

    /// Return the verified context of the active product execution.
    pub fn context(&self) -> Result<ProductContext> {
        self.current
            .borrow()
            .active_execution
            .as_ref()
            .map(|execution| execution.context.clone())
            .context("no verified product artifact is active; run a script first")
    }

    /// Select a validated product, returning whether the selection changed.
    pub fn select(&self, product_id: String) -> Result<bool> {
        let product_id = normalize_product_identifier(&product_id)
            .map_err(|error| anyhow::anyhow!("invalid product id: {error}"))?;
        Ok(self.current.send_if_modified(|current| {
            if current.product_id == product_id {
                false
            } else {
                current.product_id = product_id.clone();
                current.active_execution = None;
                true
            }
        }))
    }

    fn authorize(&self, authorization_path: &str) -> Option<AuthorizedExecution> {
        self.current
            .borrow()
            .active_execution
            .as_ref()
            .filter(|execution| execution.authorization_path == authorization_path)
            .cloned()
    }

    fn subscribe(&self) -> watch::Receiver<SelectedProduct> {
        self.current.subscribe()
    }
}

pub trait ProductRuntimeFactory: Send + Sync + 'static {
    fn product_runtime(&self, product: ProductContext, sink: Arc<dyn FrameSink>) -> ProductRuntime;

    /// Subscribe to a signal that invalidates existing product connections.
    fn connection_reset(&self) -> Option<watch::Receiver<u64>> {
        None
    }
}

impl ProductRuntimeFactory for PairingHostRuntime {
    fn product_runtime(&self, product: ProductContext, sink: Arc<dyn FrameSink>) -> ProductRuntime {
        PairingHostRuntime::product_runtime(self, product, sink)
    }
}

impl ProductRuntimeFactory for SigningHostRuntime {
    fn product_runtime(&self, product: ProductContext, sink: Arc<dyn FrameSink>) -> ProductRuntime {
        SigningHostRuntime::product_runtime(self, product, sink)
    }
}

/// Signing runtime factory whose active session can be replaced without
/// restarting the frame listener.
pub struct SwitchableSigningRuntime {
    current: RwLock<Arc<SigningHostRuntime>>,
    generation: watch::Sender<u64>,
}

impl SwitchableSigningRuntime {
    pub fn new(runtime: Arc<SigningHostRuntime>) -> Arc<Self> {
        let (generation, _) = watch::channel(0);
        Arc::new(Self {
            current: RwLock::new(runtime),
            generation,
        })
    }

    /// Replace the runtime and disconnect every product using the old one.
    pub fn replace(&self, runtime: Arc<SigningHostRuntime>) {
        *self.current.write().expect("runtime lock poisoned") = runtime;
        self.generation
            .send_modify(|generation| *generation = generation.wrapping_add(1));
    }
}

impl ProductRuntimeFactory for SwitchableSigningRuntime {
    fn product_runtime(&self, product: ProductContext, sink: Arc<dyn FrameSink>) -> ProductRuntime {
        self.current
            .read()
            .expect("runtime lock poisoned")
            .product_runtime(product, sink)
    }

    fn connection_reset(&self) -> Option<watch::Receiver<u64>> {
        Some(self.generation.subscribe())
    }
}

/// Frame sink that writes each outgoing protocol frame as one binary message.
struct WsFrameSink {
    outbound: mpsc::UnboundedSender<Message>,
}

impl FrameSink for WsFrameSink {
    fn emit_frame(&self, frame: Vec<u8>) {
        let _ = self.outbound.send(Message::Binary(frame));
    }
}

/// Bound product-frame endpoint. The temporary-directory guard keeps a Unix
/// socket alive for exactly as long as its listener.
pub struct BoundFrameServer {
    listener: FrameListener,
    endpoint: String,
    #[cfg(unix)]
    socket_directory: Option<tempfile::TempDir>,
}

enum FrameListener {
    Tcp(TcpListener),
    #[cfg(unix)]
    Unix(UnixListener),
}

impl BoundFrameServer {
    /// Endpoint passed to the bundled product runner and shown in the CLI.
    pub fn endpoint(&self) -> &str {
        &self.endpoint
    }
}

/// Bind an explicit TCP WebSocket listener, or a private per-process Unix
/// socket when no TCP address was requested. Per-execution path capabilities
/// are issued only after the trusted launcher measures a product bundle.
pub async fn bind(addr: Option<SocketAddr>) -> Result<BoundFrameServer> {
    if let Some(addr) = addr {
        let listener = TcpListener::bind(addr)
            .await
            .with_context(|| format!("frame server failed to bind {addr}"))?;
        return Ok(BoundFrameServer {
            endpoint: format!("ws://{}", listener.local_addr()?),
            listener: FrameListener::Tcp(listener),
            #[cfg(unix)]
            socket_directory: None,
        });
    }
    bind_unix()
}

fn fresh_authorization_path() -> String {
    let mut token = [0_u8; 32];
    OsRng.fill_bytes(&mut token);
    format!("/{}", hex::encode(token))
}

#[cfg(unix)]
fn bind_unix() -> Result<BoundFrameServer> {
    let socket_directory = tempfile::Builder::new()
        .prefix("truapi-host-")
        .tempdir()
        .context("create temporary product-frame socket directory")?;
    let socket_path = socket_directory.path().join("frames.sock");
    let socket_path_text = socket_path
        .to_str()
        .context("product-frame Unix socket path is not valid UTF-8")?;
    let listener = UnixListener::bind(&socket_path)
        .with_context(|| format!("frame server failed to bind {}", socket_path.display()))?;
    Ok(BoundFrameServer {
        listener: FrameListener::Unix(listener),
        endpoint: format!("ws+unix:{socket_path_text}"),
        socket_directory: Some(socket_directory),
    })
}

#[cfg(not(unix))]
fn bind_unix() -> Result<BoundFrameServer> {
    anyhow::bail!(
        "Unix-domain product sockets are unavailable on this platform; pass --frame-listen <address>"
    )
}

/// Accept product-frame connections on `listener` for `product_id` until
/// cancelled.
///
/// Each connection is driven independently on the Tokio worker pool. The
/// shared dispatcher contract requires `Send` futures, while the WASM adapter
/// may still poll those futures on its single-threaded local executor.
pub async fn accept_loop(
    runtime: Arc<dyn ProductRuntimeFactory>,
    product: Arc<ProductSelection>,
    frame_server: BoundFrameServer,
) -> Result<()> {
    let product_id = product.current();
    let endpoint = frame_server.endpoint.clone();
    debug!(%endpoint, %product_id, "product frame server listening");
    #[cfg(unix)]
    let _socket_directory = frame_server.socket_directory;
    match frame_server.listener {
        FrameListener::Tcp(listener) => accept_tcp_loop(runtime, product, listener).await,
        #[cfg(unix)]
        FrameListener::Unix(listener) => accept_unix_loop(runtime, product, listener).await,
    }
}

async fn accept_tcp_loop(
    runtime: Arc<dyn ProductRuntimeFactory>,
    product: Arc<ProductSelection>,
    listener: TcpListener,
) -> Result<()> {
    loop {
        let (stream, peer) = match listener.accept().await {
            Ok(accepted) => accepted,
            Err(err) => {
                warn!(
                    %err,
                    retry_in = ?ACCEPT_RETRY_DELAY,
                    "product frame accept failed"
                );
                tokio::time::sleep(ACCEPT_RETRY_DELAY).await;
                continue;
            }
        };
        let runtime = runtime.clone();
        let product = product.clone();
        tokio::spawn(async move {
            if let Err(err) = serve_connection(runtime, product, stream).await {
                debug!(%peer, %err, "frame connection ended");
            }
        });
    }
}

#[cfg(unix)]
async fn accept_unix_loop(
    runtime: Arc<dyn ProductRuntimeFactory>,
    product: Arc<ProductSelection>,
    listener: UnixListener,
) -> Result<()> {
    loop {
        let (stream, peer) = match listener.accept().await {
            Ok(accepted) => accepted,
            Err(err) => {
                warn!(%err, "product frame accept failed");
                continue;
            }
        };
        let runtime = runtime.clone();
        let product = product.clone();
        tokio::spawn(async move {
            if let Err(err) = serve_connection(runtime, product, stream).await {
                debug!(?peer, %err, "frame connection ended");
            }
        });
    }
}

async fn serve_connection<S>(
    runtime: Arc<dyn ProductRuntimeFactory>,
    selected_product: Arc<ProductSelection>,
    stream: S,
) -> Result<()>
where
    S: AsyncRead + AsyncWrite + Unpin + Send + 'static,
{
    // Subscribe before resolving the runtime so a concurrent replacement can
    // only cause an extra reconnect, never leave a connection on stale state.
    let mut reset = runtime.connection_reset();
    let mut product_updates = selected_product.subscribe();
    let authenticated = Arc::new(Mutex::new(None));
    let ws = accept_hdr_async(
        stream,
        AuthorizeFrameRequest {
            selected_product: selected_product.clone(),
            authenticated: authenticated.clone(),
        },
    )
    .await?;
    let execution = authenticated
        .lock()
        .unwrap_or_else(|error| error.into_inner())
        .take()
        .context("product-frame authentication did not bind an execution")?;
    let authorization_path = execution.authorization_path.clone();
    if selected_product.authorize(&authorization_path).is_none() {
        anyhow::bail!("product execution capability was revoked");
    }
    let product = execution.context;
    let (mut write, mut read) = ws.split();
    let (outbound_tx, mut outbound_rx) = mpsc::unbounded_channel::<Message>();

    let writer = tokio::spawn(async move {
        while let Some(message) = outbound_rx.recv().await {
            if write.send(message).await.is_err() {
                break;
            }
        }
    });

    let sink = Arc::new(WsFrameSink {
        outbound: outbound_tx.clone(),
    });
    let product_runtime = runtime.product_runtime(product, sink);

    loop {
        let message = tokio::select! {
            biased;
            _ = connection_reset(&mut reset) => break,
            _ = product_updates.changed() => break,
            message = read.next() => message,
        };
        let Some(message) = message else {
            break;
        };
        if selected_product.authorize(&authorization_path).is_none() {
            break;
        }
        match message {
            Ok(Message::Binary(bytes)) => {
                if let Err(err) = product_runtime.receive_frame(bytes.to_vec()).await {
                    debug!(%err, "product runtime rejected frame");
                }
            }
            Ok(Message::Text(text)) => {
                if let Err(err) = product_runtime
                    .receive_frame(text.as_bytes().to_vec())
                    .await
                {
                    debug!(%err, "product runtime rejected text frame");
                }
            }
            Ok(Message::Close(_)) | Err(_) => break,
            Ok(_) => {}
        }
    }

    product_runtime.dispose();
    drop(outbound_tx);
    let _ = writer.await;
    Ok(())
}

struct AuthorizeFrameRequest {
    selected_product: Arc<ProductSelection>,
    authenticated: Arc<Mutex<Option<AuthorizedExecution>>>,
}

impl Callback for AuthorizeFrameRequest {
    fn on_request(self, request: &Request, response: Response) -> Result<Response, ErrorResponse> {
        if let Some(execution) = self.selected_product.authorize(request.uri().path()) {
            *self
                .authenticated
                .lock()
                .unwrap_or_else(|error| error.into_inner()) = Some(execution);
            Ok(response)
        } else {
            let mut rejection =
                ErrorResponse::new(Some("invalid product-frame credential".to_string()));
            *rejection.status_mut() = StatusCode::UNAUTHORIZED;
            Err(rejection)
        }
    }
}

async fn connection_reset(reset: &mut Option<watch::Receiver<u64>>) {
    match reset {
        Some(reset) => {
            let _ = reset.changed().await;
        }
        None => std::future::pending().await,
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use futures_util::{SinkExt, StreamExt};
    use tokio_tungstenite::client_async;

    #[test]
    fn product_selection_validates_and_normalizes_ids() -> Result<()> {
        let product = ProductSelection::new(" Dotli.DOT ".to_string())?;
        assert!(product.context().is_err());
        let _execution = product.issue_execution("sha256:trusted-product-bundle".to_string())?;
        assert_eq!(
            product.context()?.artifact_identity,
            "sha256:trusted-product-bundle"
        );

        assert_eq!(product.current(), "dotli.dot");
        assert!(product.select("localhost:3000".to_string())?);
        assert_eq!(product.current(), "localhost:3000");
        assert!(!product.select("LOCALHOST:3000".to_string())?);
        assert!(product.select("example.com".to_string()).is_err());
        Ok(())
    }

    #[tokio::test]
    async fn changing_product_notifies_connections() -> Result<()> {
        let product = ProductSelection::new("first.dot".to_string())?;
        let mut connection = product.subscribe();

        assert!(product.select("second.dot".to_string())?);
        connection.changed().await?;
        assert_eq!(connection.borrow().product_id, "second.dot");
        assert!(!product.select("SECOND.DOT".to_string())?);
        assert!(!connection.has_changed()?);
        Ok(())
    }

    #[tokio::test]
    async fn explicit_tcp_listener_reports_the_actual_bound_port() -> Result<()> {
        let server = bind(Some("127.0.0.1:0".parse()?)).await?;

        assert!(server.endpoint().starts_with("ws://127.0.0.1:"));
        assert!(!server.endpoint().ends_with(":0"));
        Ok(())
    }

    #[cfg(unix)]
    #[tokio::test]
    async fn default_unix_listener_carries_websocket_frames_and_cleans_up() -> Result<()> {
        use tokio::net::UnixStream;

        let server = bind(None).await?;
        let endpoint = server
            .endpoint()
            .strip_prefix("ws+unix:")
            .expect("Unix endpoint prefix");
        let socket_path = std::path::PathBuf::from(endpoint);
        let socket_directory = socket_path
            .parent()
            .expect("socket has a parent directory")
            .to_path_buf();
        assert!(socket_path.exists());

        let execution = ProductSelection::new("test.dot".to_string())?
            .issue_execution("sha256:test-bundle".to_string())?;
        let FrameListener::Unix(listener) = &server.listener else {
            panic!("default listener must be Unix");
        };
        let server_exchange = async {
            let (stream, _) = listener.accept().await?;
            let mut websocket = accept_async(stream).await?;
            let message = websocket
                .next()
                .await
                .context("client closed before sending")??;
            websocket.send(message).await?;
            Ok::<(), anyhow::Error>(())
        };
        let client_exchange = async {
            let stream = UnixStream::connect(&socket_path).await?;
            let request_url = format!("ws://localhost{}", execution.authorization_path);
            let (mut websocket, _) = client_async(request_url, stream).await?;
            websocket.send(Message::Binary(vec![1, 2, 3, 4])).await?;
            assert_eq!(
                websocket.next().await.context("server did not echo")??,
                Message::Binary(vec![1, 2, 3, 4])
            );
            Ok::<(), anyhow::Error>(())
        };
        tokio::try_join!(server_exchange, client_exchange)?;

        drop(server);
        assert!(!socket_directory.exists());
        Ok(())
    }
    #[test]
    fn frame_request_rejects_an_incorrect_capability() {
        let request = Request::builder()
            .uri("/wrong")
            .body(())
            .expect("request is valid");
        let response = Response::new(());

        let product = ProductSelection::new("test.dot".to_string()).expect("product is valid");
        let _execution = product
            .issue_execution("sha256:test-bundle".to_string())
            .expect("execution is valid");
        let rejection = AuthorizeFrameRequest {
            selected_product: product,
            authenticated: Arc::new(Mutex::new(None)),
        }
        .on_request(&request, response)
        .expect_err("incorrect capability must be rejected");
        assert_eq!(rejection.status(), StatusCode::UNAUTHORIZED);
    }

    #[test]
    fn new_execution_revokes_the_previous_capability() -> Result<()> {
        let product = ProductSelection::new("test.dot".to_string())?;
        let first = product.issue_execution("sha256:first".to_string())?;
        let first_path = first.authorization_path.clone();
        let second = product.issue_execution("sha256:second".to_string())?;

        assert!(product.authorize(&first_path).is_none());
        assert_eq!(
            product
                .authorize(&second.authorization_path)
                .expect("new capability is active")
                .context
                .artifact_identity,
            "sha256:second"
        );
        drop(first);
        assert!(product.authorize(&second.authorization_path).is_some());
        Ok(())
    }
}
