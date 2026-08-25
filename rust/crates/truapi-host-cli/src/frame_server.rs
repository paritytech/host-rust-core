//! Product-frame WebSocket bridge for the pairing host.
//!
//! Each WebSocket connection is one product: inbound binary frames are pushed
//! into a [`ProductRuntime`] and its outgoing frames are written back as
//! binary messages. One binary WS message carries exactly one SCALE
//! `ProtocolMessage`, matching the browser transport's framing.

use std::net::{IpAddr, SocketAddr};
use std::sync::{Arc, RwLock};
use std::time::Duration;

use anyhow::{Context, Result};
use futures_util::{SinkExt, StreamExt};
use tokio::io::{AsyncRead, AsyncReadExt, AsyncWrite, AsyncWriteExt};
#[cfg(unix)]
use tokio::net::UnixListener;
use tokio::net::{TcpListener, TcpStream};
use tokio::sync::{mpsc, watch};
#[cfg(test)]
use tokio_tungstenite::accept_async;
use tokio_tungstenite::accept_hdr_async;
use tokio_tungstenite::tungstenite::Message;
use tokio_tungstenite::tungstenite::handshake::server::{ErrorResponse, Request, Response};
use tokio_tungstenite::tungstenite::http::{StatusCode, header};
use tracing::{debug, warn};

use crate::bootstrap;
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

/// Cap on the request head buffered while deciding whether a TCP connection is
/// a WebSocket handshake or a plain HTTP request for the bridge script.
const MAX_REQUEST_HEAD: usize = 8 * 1024;

/// Blank line ending an HTTP request head.
const HEAD_TERMINATOR: &[u8] = b"\r\n\r\n";

/// How long a TCP peer has to finish sending its request head before the
/// connection is dropped, so a peer that connects and says nothing cannot pin a
/// task forever.
const REQUEST_HEAD_TIMEOUT: Duration = Duration::from_secs(10);

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
        FrameListener::Tcp(listener) => accept_tcp_loop(runtime, product, listener, endpoint).await,
        #[cfg(unix)]
        FrameListener::Unix(listener) => accept_unix_loop(runtime, product, listener).await,
    }
}

async fn accept_tcp_loop(
    runtime: Arc<dyn ProductRuntimeFactory>,
    product: Arc<ProductSelection>,
    listener: TcpListener,
    endpoint: String,
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
        let endpoint = endpoint.clone();
        tokio::spawn(async move {
            if let Err(err) = serve_tcp_connection(runtime, product, stream, &endpoint).await {
                debug!(%peer, %err, "frame connection ended");
            }
        });
    }
}

/// Serve one TCP peer, which is either a product opening the frame socket or a
/// browser fetching the bridge script.
///
/// The request head is peeked rather than read so a WebSocket handshake reaches
/// the tungstenite server exactly as the peer sent it.
async fn serve_tcp_connection(
    runtime: Arc<dyn ProductRuntimeFactory>,
    product: Arc<ProductSelection>,
    mut stream: TcpStream,
    endpoint: &str,
) -> Result<()> {
    let head = tokio::time::timeout(REQUEST_HEAD_TIMEOUT, peek_request_head(&stream))
        .await
        .context("timed out reading the request head")??;
    if is_websocket_upgrade(&head) {
        return serve_connection(runtime, product, stream).await;
    }
    serve_bridge_script(&mut stream, &head, endpoint).await
}

/// Buffer the peer's request head without consuming it.
async fn peek_request_head(stream: &TcpStream) -> Result<Vec<u8>> {
    let mut buffer = vec![0u8; MAX_REQUEST_HEAD];
    loop {
        stream.readable().await?;
        let peeked = stream.peek(&mut buffer).await?;
        if peeked == 0 {
            anyhow::bail!("peer closed before sending a request");
        }
        let head = &buffer[..peeked];
        if let Some(end) = find_head_end(head) {
            return Ok(head[..end].to_vec());
        }
        if peeked == buffer.len() {
            anyhow::bail!("request head exceeded {MAX_REQUEST_HEAD} bytes");
        }
    }
}

fn find_head_end(head: &[u8]) -> Option<usize> {
    head.windows(HEAD_TERMINATOR.len())
        .position(|window| window == HEAD_TERMINATOR)
}

fn is_websocket_upgrade(head: &[u8]) -> bool {
    header_value(head, "upgrade").is_some_and(|value| value.eq_ignore_ascii_case("websocket"))
}

/// First value of `name` in a raw request head, if the head is valid UTF-8.
fn header_value<'a>(head: &'a [u8], name: &str) -> Option<&'a str> {
    let head = std::str::from_utf8(head).ok()?;
    head.lines().skip(1).find_map(|line| {
        let (key, value) = line.split_once(':')?;
        key.trim().eq_ignore_ascii_case(name).then(|| value.trim())
    })
}

/// Answer a plain HTTP request with the bridge script, or a 404.
///
/// Products load this from a development-only `<script>` tag, which is a
/// cross-origin request no CORS header can gate, so the script carries no
/// secret. What keeps another page from using the endpoint it names is the
/// origin check on the WebSocket handshake.
async fn serve_bridge_script(stream: &mut TcpStream, head: &[u8], endpoint: &str) -> Result<()> {
    // The head was peeked, not read. Closing with it still buffered would reset
    // the connection and lose the response, so drain it first.
    let mut consumed = vec![0u8; head.len() + HEAD_TERMINATOR.len()];
    stream.read_exact(&mut consumed).await?;

    let response = match request_path(head).as_deref() {
        Some(bootstrap::PATH) => http_response(
            "200 OK",
            "application/javascript; charset=utf-8",
            &bootstrap::script(endpoint),
        ),
        _ => http_response(
            "404 Not Found",
            "text/plain; charset=utf-8",
            &format!("not found; the bridge script is at {}\n", bootstrap::PATH),
        ),
    };
    stream.write_all(response.as_bytes()).await?;
    stream.flush().await?;
    Ok(())
}

fn http_response(status: &str, content_type: &str, body: &str) -> String {
    format!(
        "HTTP/1.1 {status}\r\n\
         Content-Type: {content_type}\r\n\
         Content-Length: {length}\r\n\
         Cache-Control: no-store\r\n\
         Connection: close\r\n\r\n\
         {body}",
        length = body.len()
    )
}

/// Request target from a raw request head, ignoring any query string.
fn request_path(head: &[u8]) -> Option<String> {
    let head = std::str::from_utf8(head).ok()?;
    let target = head.lines().next()?.split_whitespace().nth(1)?;
    Some(target.split(['?', '#']).next()?.to_string())
}

/// Whether a browser-supplied `Origin` may open a frame connection.
///
/// Browsers always send `Origin` on a WebSocket handshake and a page cannot
/// forge its own, so this is what separates the product under development from
/// any other page the developer happens to have open: WebSocket is not subject
/// to CORS, so without this any site could drive a host that auto-approves.
/// It also defeats DNS rebinding, because the origin stays the attacker's
/// however their name resolves. A missing `Origin` is a non-browser client on
/// loopback, which can already read the host's state directory.
fn origin_allowed(origin: Option<&str>) -> bool {
    let Some(origin) = origin else {
        return true;
    };
    origin_host(origin).is_some_and(is_loopback_host)
}

/// Handshake callback that rejects a browser origin outside loopback.
// The signature is tungstenite's `Callback` contract, so the error type is not
// ours to shrink.
#[allow(clippy::result_large_err)]
fn check_origin(request: &Request, response: Response) -> Result<Response, ErrorResponse> {
    let origin = request
        .headers()
        .get(header::ORIGIN)
        .map(|value| value.to_str().unwrap_or_default());
    if origin_allowed(origin) {
        return Ok(response);
    }
    warn!(
        origin = origin.unwrap_or_default(),
        "rejected a frame connection from a non-loopback origin"
    );
    let mut rejection = ErrorResponse::new(Some(
        "frame connections are limited to loopback origins".to_string(),
    ));
    *rejection.status_mut() = StatusCode::FORBIDDEN;
    Err(rejection)
}

fn origin_host(origin: &str) -> Option<&str> {
    let authority = origin.split_once("://")?.1;
    match authority.strip_prefix('[') {
        Some(inner) => inner.split_once(']').map(|(host, _)| host),
        None => authority.split(':').next(),
    }
}

fn is_loopback_host(host: &str) -> bool {
    host.eq_ignore_ascii_case("localhost")
        || host
            .parse::<IpAddr>()
            .is_ok_and(|address| address.is_loopback())
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
    let ws = accept_hdr_async(stream, check_origin).await?;
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

    /// Only a browser sends `Origin`, and it cannot forge it. WebSocket
    /// ignores CORS, so without this any page the developer has open could
    /// drive a host that auto-approves confirmations.
    #[test]
    fn only_loopback_browser_origins_may_open_frame_connections() {
        for allowed in [
            "http://localhost:3000",
            "http://LocalHost:3000",
            "http://127.0.0.1:3000",
            "http://127.0.0.2:8080",
            "http://[::1]:5173",
            "https://localhost",
        ] {
            assert!(origin_allowed(Some(allowed)), "{allowed} should be allowed");
        }
        for rejected in [
            "https://evil.com",
            "http://localhost.evil.com:3000",
            "http://evil.com:3000",
            // A rebinding attacker keeps their own origin however the name
            // resolves, which is exactly what this catches.
            "http://rebind.evil.com",
            "null",
            "file://",
        ] {
            assert!(
                !origin_allowed(Some(rejected)),
                "{rejected} should be rejected"
            );
        }
        // A local process, which can already read the host's state directory.
        assert!(origin_allowed(None));
    }

    #[test]
    fn a_request_head_is_classified_by_its_upgrade_header() {
        let upgrade =
            b"GET / HTTP/1.1\r\nHost: x\r\nUpgrade: WebSocket\r\nOrigin: http://localhost:3000";
        assert!(is_websocket_upgrade(upgrade));
        assert_eq!(request_path(upgrade).as_deref(), Some("/"));

        let script = b"GET /bootstrap.js?v=2 HTTP/1.1\r\nHost: 127.0.0.1:9955";
        assert!(!is_websocket_upgrade(script));
        assert_eq!(request_path(script).as_deref(), Some("/bootstrap.js"));
    }

    /// The bridge and the frame socket share one port, so a plain GET must be
    /// answered as HTTP, and the script must name the endpoint to dial.
    #[tokio::test]
    async fn the_bridge_script_is_served_beside_the_frame_socket() -> Result<()> {
        use tokio::io::{AsyncReadExt, AsyncWriteExt};

        async fn fetch(target: &str, endpoint: &str) -> Result<String> {
            let listener = TcpListener::bind("127.0.0.1:0").await?;
            let address = listener.local_addr()?;
            let endpoint = endpoint.to_string();
            let server = tokio::spawn(async move {
                let (mut stream, _) = listener.accept().await?;
                let head = peek_request_head(&stream).await?;
                assert!(!is_websocket_upgrade(&head));
                serve_bridge_script(&mut stream, &head, &endpoint).await
            });

            let mut client = TcpStream::connect(address).await?;
            client
                .write_all(format!("GET {target} HTTP/1.1\r\nHost: {address}\r\n\r\n").as_bytes())
                .await?;
            let mut response = String::new();
            client.read_to_string(&mut response).await?;
            server.await??;
            Ok(response)
        }

        let endpoint = "ws://127.0.0.1:9955";
        let script = fetch(bootstrap::PATH, endpoint).await?;
        assert!(script.starts_with("HTTP/1.1 200 OK"), "{script}");
        assert!(script.contains("application/javascript"));
        assert!(
            script.contains(&format!(r#"var url = "{endpoint}";"#)),
            "{script}"
        );
        assert!(script.contains("window.__HOST_API_PORT__ = channel.port1;"));

        let missing = fetch("/nope", endpoint).await?;
        assert!(missing.starts_with("HTTP/1.1 404 Not Found"), "{missing}");
        Ok(())
    }

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
