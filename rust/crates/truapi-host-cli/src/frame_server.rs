//! Product-frame WebSocket bridge for the pairing host.
//!
//! Each WebSocket connection is one product: inbound binary frames are pushed
//! into a [`ProductRuntime`] and its outgoing frames are written back as
//! binary messages. One binary WS message carries exactly one SCALE
//! `ProtocolMessage`, matching the browser transport's framing.

use std::net::SocketAddr;
use std::sync::{Arc, RwLock};
use std::time::Duration;

use anyhow::{Context, Result};
use futures_util::{SinkExt, StreamExt};
use tokio::io::{AsyncRead, AsyncWrite};
use tokio::net::TcpListener;
#[cfg(unix)]
use tokio::net::UnixListener;
use tokio::sync::{mpsc, watch};
use tokio_tungstenite::accept_async;
use tokio_tungstenite::tungstenite::Message;
use tracing::{debug, warn};
use truapi_platform::ProductExecutionKind;
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

/// Process-local product selection shared by the command loop and frame server.
pub struct ProductSelection {
    current: watch::Sender<ProductContext>,
    /// Execution kind every selection keeps. A host serves one kind for its
    /// lifetime: the core reads it per connection, and chat is denied to a
    /// connection that opened as `App`.
    execution_kind: ProductExecutionKind,
}

impl ProductSelection {
    /// Validate and normalize the initial product id.
    pub fn new(product_id: String, execution_kind: ProductExecutionKind) -> Result<Arc<Self>> {
        let product = ProductContext::new_with_execution(product_id, execution_kind)
            .map_err(|error| anyhow::anyhow!("invalid product id: {error}"))?;
        let (current, _) = watch::channel(product);
        Ok(Arc::new(Self {
            current,
            execution_kind,
        }))
    }

    /// Return the normalized current product id.
    pub fn current(&self) -> String {
        self.current.borrow().product_id.clone()
    }

    /// Select a validated product, returning whether the selection changed.
    pub fn select(&self, product_id: String) -> Result<bool> {
        let product = ProductContext::new_with_execution(product_id, self.execution_kind)
            .map_err(|error| anyhow::anyhow!("invalid product id: {error}"))?;
        Ok(self.current.send_if_modified(|current| {
            if current == &product {
                false
            } else {
                *current = product;
                true
            }
        }))
    }

    fn subscribe(&self) -> watch::Receiver<ProductContext> {
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
        self.reset_connections();
    }

    /// Disconnect every product currently using the active signing runtime.
    pub fn reset_connections(&self) {
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
/// socket when no TCP address was requested.
pub async fn bind(addr: Option<SocketAddr>) -> Result<BoundFrameServer> {
    if let Some(addr) = addr {
        let listener = TcpListener::bind(addr)
            .await
            .with_context(|| format!("frame server failed to bind {addr}"))?;
        let endpoint = format!("ws://{}", listener.local_addr()?);
        return Ok(BoundFrameServer {
            listener: FrameListener::Tcp(listener),
            endpoint,
            #[cfg(unix)]
            socket_directory: None,
        });
    }
    bind_unix()
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
    let ws = accept_async(stream).await?;
    let (mut write, mut read) = ws.split();
    let (outbound_tx, mut outbound_rx) = mpsc::unbounded_channel::<Message>();

    let writer = tokio::spawn(async move {
        while let Some(message) = outbound_rx.recv().await {
            if write.send(message).await.is_err() {
                break;
            }
        }
    });

    let product = product_updates.borrow().clone();
    let sink = Arc::new(WsFrameSink {
        outbound: outbound_tx.clone(),
    });
    let product_runtime = runtime.product_runtime(product, sink);

    loop {
        let message = tokio::select! {
            _ = connection_reset(&mut reset) => break,
            _ = product_updates.changed() => break,
            message = read.next() => message,
        };
        let Some(message) = message else {
            break;
        };
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
        let product = ProductSelection::new(" Dotli.DOT ".to_string(), ProductExecutionKind::App)?;

        assert_eq!(product.current(), "dotli.dot");
        assert!(product.select("localhost:3000".to_string())?);
        assert_eq!(product.current(), "localhost:3000");
        assert!(!product.select("LOCALHOST:3000".to_string())?);
        assert!(product.select("example.com".to_string()).is_err());
        Ok(())
    }

    #[tokio::test]
    async fn changing_product_notifies_connections() -> Result<()> {
        let product = ProductSelection::new("first.dot".to_string(), ProductExecutionKind::App)?;
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
        let socket_path = server
            .endpoint()
            .strip_prefix("ws+unix:")
            .expect("Unix endpoint prefix");
        let socket_path = std::path::PathBuf::from(socket_path);
        let socket_directory = socket_path
            .parent()
            .expect("socket has a parent directory")
            .to_path_buf();
        assert!(socket_path.exists());

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
            let (mut websocket, _) = client_async("ws://localhost/", stream).await?;
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
}
