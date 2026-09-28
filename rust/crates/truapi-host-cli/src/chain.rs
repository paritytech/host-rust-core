//! Native WebSocket `ChainProvider` / `JsonRpcConnection`.
//!
//! The headless hosts reach the real People-chain statement store over
//! WebSocket JSON-RPC (the same node an iOS/web client uses). Every `connect`
//! opens a fresh socket; the runtime's `HostRpcClient` sits on top and speaks
//! statement-store RPC.

use std::collections::HashMap;
use std::sync::atomic::{AtomicU64, Ordering};
use std::sync::{Arc, Mutex};
use std::time::Duration;

use async_trait::async_trait;
use futures::stream::BoxStream;
use futures_util::{SinkExt, StreamExt};
use tokio::sync::{broadcast, mpsc, watch};
use tokio::time::Instant;
use tokio_stream::wrappers::BroadcastStream;
use tokio_tungstenite::connect_async;
use tokio_tungstenite::tungstenite::Message;
use tracing::{debug, warn};
use truapi::latest as api;
use truapi_platform::{ChainProvider, JsonRpcConnection};

use crate::network::ChainEndpoint;

/// Broadcast backlog for inbound JSON-RPC frames per connection.
const INBOUND_CHANNEL_CAPACITY: usize = 1024;

/// Chain provider that maps a requested genesis hash to a WebSocket endpoint.
///
/// The all-zero genesis (the headless SSO sentinel) and any unmapped genesis
/// fall back to the People-chain statement store. Every role the preset serves —
/// People, Bulletin and Asset Hub — is always routed; the test switch only widens
/// routing to endpoints the preset carries without serving them as a role.
pub struct WsChainProvider {
    fallback_url: String,
    by_genesis: HashMap<[u8; 32], String>,
}

impl WsChainProvider {
    pub fn new(fallback_url: impl Into<String>, live_chain_endpoints: &[ChainEndpoint]) -> Self {
        let live_chain_routing = std::env::var("E2E_LIVE_CHAIN").as_deref() == Ok("1");
        Self::with_live_chain_routing(fallback_url, live_chain_endpoints, live_chain_routing)
    }

    fn with_live_chain_routing(
        fallback_url: impl Into<String>,
        live_chain_endpoints: &[ChainEndpoint],
        live_chain_routing: bool,
    ) -> Self {
        // People remains the fallback for the SSO sentinel. Bulletin backs preimage
        // submission and Asset Hub backs PGAS claims, so all three are host
        // dependencies and must never be gated by the product-facing Chain/* switch.
        let by_genesis = live_chain_endpoints
            .iter()
            .filter(|endpoint| endpoint.required_for_host || live_chain_routing)
            .map(|endpoint| (endpoint.genesis, endpoint.ws.to_string()))
            .collect();
        Self {
            fallback_url: fallback_url.into(),
            by_genesis,
        }
    }

    /// Whether a genesis is mapped rather than answered by the fallback.
    ///
    /// Test-only because production has no reason to care: `url_for` resolves either
    /// way. A test does, since the fallback is the People URL, so asserting on the
    /// resolved URL cannot tell a routed People from a dropped one.
    #[cfg(test)]
    fn routes(&self, genesis_hash: &[u8; 32]) -> bool {
        self.by_genesis.contains_key(genesis_hash)
    }

    /// The URL a genesis routes to. Test-only, so a routing override can be
    /// asserted rather than assumed: an override written to the wrong field
    /// compiles, changes nothing, and is invisible in timings.
    #[cfg(test)]
    pub(crate) fn routed_url(&self, genesis_hash: &[u8; 32]) -> &str {
        self.url_for(genesis_hash)
    }

    fn url_for(&self, genesis_hash: &[u8; 32]) -> &str {
        self.by_genesis
            .get(genesis_hash)
            .map(String::as_str)
            .unwrap_or(&self.fallback_url)
    }
}

#[async_trait]
impl ChainProvider for WsChainProvider {
    async fn connect(
        &self,
        genesis_hash: [u8; 32],
    ) -> Result<Box<dyn JsonRpcConnection>, api::GenericError> {
        let url = self.url_for(&genesis_hash);
        debug!(genesis = %hex::encode(genesis_hash), %url, "chain connect");
        let connection = WsJsonRpcConnection::connect(url)
            .await
            .map_err(|reason| api::GenericError { reason })?;
        Ok(Box::new(connection))
    }
}

/// A Ping every this often keeps a quiet socket from looking dead to the far side and, with
/// [`KEEPALIVE_TIMEOUT`], detects one that is.
const KEEPALIVE_INTERVAL: Duration = Duration::from_secs(15);
/// No inbound frame at all for this long (a Pong counts) means the socket is half-open: the
/// far side went away without a close frame, reads would block for ever and writes would sink
/// into the kernel buffer, so every RPC on it would hang until the caller's own deadline. The
/// connection is closed here instead, which ends its response streams, which is what the
/// runtime watches before it reconnects.
const KEEPALIVE_TIMEOUT: Duration = Duration::from_secs(45);

/// One WebSocket JSON-RPC connection: outbound requests are queued to a writer
/// task, inbound frames are broadcast to every `responses()` stream, and a
/// keepalive task pings the socket and closes it when it falls silent.
pub struct WsJsonRpcConnection {
    outbound: mpsc::UnboundedSender<Message>,
    inbound: broadcast::Sender<String>,
    /// Receiver created before the reader task starts. The first response
    /// stream takes it so an immediate RPC response cannot race subscription
    /// setup and disappear while the broadcast channel has no receivers.
    initial_inbound: Mutex<Option<broadcast::Receiver<String>>>,
    /// True once the socket is gone: set by the reader on a close frame or a
    /// read error, by the keepalive on silence, or by `close`. Every response
    /// stream ends on it, and `send` drops requests after it.
    closed: Arc<watch::Sender<bool>>,
}

/// Resolves once `closed` is true (or the sender is gone).
async fn until_closed(mut closed: watch::Receiver<bool>) {
    while !*closed.borrow_and_update() {
        if closed.changed().await.is_err() {
            return;
        }
    }
}

impl WsJsonRpcConnection {
    async fn connect(url: &str) -> Result<Self, String> {
        Self::connect_with_keepalive(url, KEEPALIVE_INTERVAL, KEEPALIVE_TIMEOUT).await
    }

    async fn connect_with_keepalive(
        url: &str,
        keepalive_interval: Duration,
        keepalive_timeout: Duration,
    ) -> Result<Self, String> {
        let (stream, _response) = connect_async(url)
            .await
            .map_err(|err| format!("statement-store websocket connect failed: {err}"))?;
        let (mut write, mut read) = stream.split();
        let (outbound_tx, mut outbound_rx) = mpsc::unbounded_channel::<Message>();
        let (inbound_tx, initial_inbound) = broadcast::channel(INBOUND_CHANNEL_CAPACITY);
        let closed = Arc::new(watch::channel(false).0);
        // Milliseconds since `started` of the last inbound frame of any kind.
        let started = Instant::now();
        let last_inbound = Arc::new(AtomicU64::new(0));

        let writer_closed = closed.clone();
        let writer_stop = closed.subscribe();
        tokio::spawn(async move {
            loop {
                tokio::select! {
                    message = outbound_rx.recv() => match message {
                        Some(message) => {
                            if write.send(message).await.is_err() {
                                break;
                            }
                        }
                        None => break,
                    },
                    () = until_closed(writer_stop.clone()) => break,
                }
            }
            // A writer that could not send is a dead socket as much as a reader that could not
            // read; without this the connection stayed open until the reader noticed.
            writer_closed.send_replace(true);
            let _ = write.close().await;
        });

        let reader_inbound = inbound_tx.clone();
        let reader_closed = closed.clone();
        let reader_stop = closed.subscribe();
        let reader_last_inbound = last_inbound.clone();
        tokio::spawn(async move {
            loop {
                let message = tokio::select! {
                    message = read.next() => message,
                    () = until_closed(reader_stop.clone()) => break,
                };
                reader_last_inbound.store(started.elapsed().as_millis() as u64, Ordering::Relaxed);
                match message {
                    Some(Ok(Message::Text(text))) => {
                        let _ = reader_inbound.send(text.to_string());
                    }
                    Some(Ok(Message::Binary(bytes))) => {
                        if let Ok(text) = String::from_utf8(bytes.to_vec()) {
                            let _ = reader_inbound.send(text);
                        }
                    }
                    Some(Ok(Message::Close(_))) | Some(Err(_)) | None => break,
                    // Pings are answered by the socket layer while it is read; a Pong is
                    // the keepalive's answer and counts as inbound like any frame.
                    Some(Ok(_)) => {}
                }
            }
            reader_closed.send_replace(true);
        });

        let keepalive_outbound = outbound_tx.clone();
        let keepalive_closed = closed.clone();
        let keepalive_stop = closed.subscribe();
        let keepalive_url = url.to_string();
        tokio::spawn(async move {
            let mut ticker = tokio::time::interval(keepalive_interval);
            ticker.set_missed_tick_behavior(tokio::time::MissedTickBehavior::Delay);
            ticker.tick().await; // the first tick completes at once
            loop {
                tokio::select! {
                    _ = ticker.tick() => {}
                    () = until_closed(keepalive_stop.clone()) => break,
                }
                let silent_for = started
                    .elapsed()
                    .saturating_sub(Duration::from_millis(last_inbound.load(Ordering::Relaxed)));
                if silent_for > keepalive_timeout {
                    warn!(
                        url = %keepalive_url,
                        silent_secs = silent_for.as_secs(),
                        "chain socket answered nothing; closing it so the runtime reconnects"
                    );
                    keepalive_closed.send_replace(true);
                    break;
                }
                if keepalive_outbound.send(Message::Ping(Vec::new())).is_err() {
                    keepalive_closed.send_replace(true);
                    break;
                }
            }
        });

        Ok(Self {
            outbound: outbound_tx,
            inbound: inbound_tx,
            initial_inbound: Mutex::new(Some(initial_inbound)),
            closed,
        })
    }

    #[cfg(test)]
    fn for_test(
        outbound: mpsc::UnboundedSender<Message>,
        inbound: broadcast::Sender<String>,
        initial_inbound: broadcast::Receiver<String>,
    ) -> Self {
        Self {
            outbound,
            inbound,
            initial_inbound: Mutex::new(Some(initial_inbound)),
            closed: Arc::new(watch::channel(false).0),
        }
    }
}

impl JsonRpcConnection for WsJsonRpcConnection {
    fn send(&self, request: String) {
        if *self.closed.borrow() {
            return;
        }
        let _ = self.outbound.send(Message::Text(request));
    }

    fn responses(&self) -> BoxStream<'static, String> {
        let receiver = self
            .initial_inbound
            .lock()
            .expect("initial chain response receiver mutex poisoned")
            .take()
            .unwrap_or_else(|| self.inbound.subscribe());
        let closed = self.closed.subscribe();
        BroadcastStream::new(receiver)
            .filter_map(|item| async move {
                match item {
                    Ok(response) => Some(response),
                    Err(tokio_stream::wrappers::errors::BroadcastStreamRecvError::Lagged(
                        dropped,
                    )) => {
                        warn!(dropped, "chain response subscriber lagged");
                        None
                    }
                }
            })
            .take_until(until_closed(closed))
            .boxed()
    }

    fn close(&self) {
        self.closed.send_replace(true);
    }
}

#[cfg(test)]
mod tests {
    use clap::ValueEnum;

    use super::*;
    use crate::network::Network;

    #[test]
    fn first_response_stream_receives_frames_buffered_during_setup() {
        let (outbound, _outbound_rx) = mpsc::unbounded_channel();
        let (inbound, initial_inbound) = broadcast::channel(INBOUND_CHANNEL_CAPACITY);
        let connection = WsJsonRpcConnection::for_test(outbound, inbound.clone(), initial_inbound);

        inbound
            .send(r#"{"jsonrpc":"2.0","id":1,"result":"ready"}"#.to_string())
            .expect("initial receiver keeps the frame buffered");

        let mut responses = connection.responses();
        let frame = futures::executor::block_on(responses.next()).expect("buffered response");
        assert_eq!(frame, r#"{"jsonrpc":"2.0","id":1,"result":"ready"}"#);
    }

    /// The runtime reconnects only when a connection's response stream has ended; a stream
    /// that outlived its socket kept every later RPC hanging on a dead connection.
    #[tokio::test]
    async fn response_streams_end_once_the_connection_is_closed() {
        let (outbound, _outbound_rx) = mpsc::unbounded_channel();
        let (inbound, initial_inbound) = broadcast::channel(INBOUND_CHANNEL_CAPACITY);
        let connection = WsJsonRpcConnection::for_test(outbound, inbound, initial_inbound);
        let mut responses = connection.responses();
        connection.close();
        assert_eq!(responses.next().await, None);
        connection.send("dropped after close".to_string());
    }

    /// A peer that holds the socket open but never reads it (so never pongs) is what a load
    /// balancer or a node leaves behind; without the keepalive the connection stayed "open"
    /// for good.
    #[tokio::test]
    async fn a_silent_socket_is_closed_by_the_keepalive() {
        let listener = tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
        let address = listener.local_addr().unwrap();
        tokio::spawn(async move {
            let (socket, _) = listener.accept().await.unwrap();
            let _held = tokio_tungstenite::accept_async(socket).await.unwrap();
            tokio::time::sleep(Duration::from_secs(60)).await;
        });
        let connection = WsJsonRpcConnection::connect_with_keepalive(
            &format!("ws://{address}"),
            Duration::from_millis(50),
            Duration::from_millis(200),
        )
        .await
        .unwrap();
        let mut responses = connection.responses();
        let ended = tokio::time::timeout(Duration::from_secs(5), responses.next()).await;
        assert_eq!(ended.expect("the keepalive closes a silent socket"), None);
        assert!(*connection.closed.borrow());
    }

    /// Every role the host says it serves has to route to that role's own chain
    /// without the test switch. `url_for` answers an unmapped genesis with the
    /// fallback URL, so a served role that the routing filter drops would connect
    /// to the People chain while the host claimed to serve something else — and
    /// `ChainContextCache` only warns when the reported genesis diverges.
    #[test]
    fn every_served_role_routes_to_its_own_chain() {
        for network in Network::value_variants() {
            let config = network.config();
            let provider = WsChainProvider::with_live_chain_routing(
                config.people_ws,
                config.live_chain_endpoints,
                false,
            );
            for entry in config.host_chain_set().chains {
                let expected = config.url_for_role(entry.identifier).unwrap_or_else(|| {
                    panic!(
                        "{} serves {:?} with no preset URL",
                        config.id, entry.identifier
                    )
                });
                assert!(
                    provider.routes(&entry.genesis_hash),
                    "{} serves {:?} but does not route it; the fallback would hide this",
                    config.id,
                    entry.identifier
                );
                assert_eq!(
                    provider.url_for(&entry.genesis_hash),
                    expected,
                    "{} serves {:?} but routes it elsewhere",
                    config.id,
                    entry.identifier
                );
            }
        }
    }

    /// The switch exists to widen routing to endpoints the preset carries without
    /// serving them as a role. No preset has one now that Asset Hub is served, so
    /// this uses a synthetic endpoint: without a case the preset cannot express,
    /// `required_for_host` and the switch could both be deleted with a green suite.
    #[test]
    fn the_test_switch_widens_routing_to_endpoints_that_are_not_roles() {
        const FALLBACK: &str = "wss://fallback.invalid";
        let optional = [ChainEndpoint {
            genesis: [0x5a; 32],
            ws: "wss://optional.invalid",
            required_for_host: false,
        }];

        let gated = WsChainProvider::with_live_chain_routing(FALLBACK, &optional, false);
        let widened = WsChainProvider::with_live_chain_routing(FALLBACK, &optional, true);

        assert_eq!(
            gated.url_for(&optional[0].genesis),
            FALLBACK,
            "an endpoint that is not a role is excluded without the switch"
        );
        assert_eq!(
            widened.url_for(&optional[0].genesis),
            optional[0].ws,
            "and included with it"
        );
    }
}
