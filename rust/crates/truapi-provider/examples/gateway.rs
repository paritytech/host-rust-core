//! Local WebSocket gateway exposing [`EmbeddedChainProvider`] chains to a
//! browser host: each configured chain is served at `ws://LISTEN/<name>`, and
//! every inbound WebSocket connection is multiplexed onto one provider connection
//! per chain so all clients share one Statement Store gossip view.
//!
//! dotli's `rpc-gateway` backend can point at this process via its
//! `dotli:gateway-rpc-base` setting (e.g. `ws://127.0.0.1:9944`), which routes
//! the host's relay/asset-hub/people traffic here — light-client-verified
//! where a chain runs on the embedded smoldot, proxied where it targets a
//! remote node.
//!
//! Usage:
//!
//! ```text
//! cargo run -p truapi-provider --features networks --example gateway -- CONFIG.json
//! ```
//!
//! Config shape: each chain is a light client resolved from the bundled network
//! catalog by its genesis hash (relay wiring included), or a proxy to a remote
//! node via `url`:
//!
//! ```json
//! {
//!   "listen": "127.0.0.1:9944",
//!   "chains": {
//!     "relay": { "genesis": "0x…" },
//!     "asset-hub": { "genesis": "0x…", "url": "wss://node.example" }
//!   }
//! }
//! ```

// The example is native-only; the wasm build gets a stub main so `cargo test
// --target wasm32-unknown-unknown` can still build every target.
#[cfg(target_arch = "wasm32")]
fn main() {}

#[cfg(not(target_arch = "wasm32"))]
#[tokio::main]
async fn main() {
    imp::run().await;
}

#[cfg(not(target_arch = "wasm32"))]
mod imp {
    use std::collections::HashMap;
    use std::net::SocketAddr;
    use std::sync::atomic::{AtomicU64, Ordering};
    use std::sync::{Arc, Mutex};

    use futures::{SinkExt, StreamExt};
    use serde_json::Value;
    use tokio::net::{TcpListener, TcpStream};
    use tokio::sync::mpsc;
    use tokio_tungstenite::tungstenite::Message;
    use tokio_tungstenite::tungstenite::handshake::server::{Request, Response};
    use truapi_platform::{ChainProvider, JsonRpcConnection};
    use truapi_provider::{ChainSource, EmbeddedChainProvider};

    pub(super) async fn run() {
        let config_path = std::env::args().nth(1).unwrap_or_else(|| usage());
        let config: Value = serde_json::from_str(
            &std::fs::read_to_string(&config_path).expect("the config file must be readable"),
        )
        .expect("the config file must be valid JSON");

        let listen = config["listen"]
            .as_str()
            .unwrap_or("127.0.0.1:9944")
            .to_owned();
        let chains = config["chains"]
            .as_object()
            .expect("config.chains must be an object");

        let mut builder = EmbeddedChainProvider::builder();
        let mut routes = HashMap::new();
        for (name, entry) in chains {
            let genesis = parse_genesis(
                entry["genesis"]
                    .as_str()
                    .expect("chain.genesis is required"),
            );
            // A `url` entry is proxied to a remote node; every other entry is a
            // light client the catalog resolves from its genesis hash — relay
            // wiring for parachains comes from the catalog, not this config.
            if let Some(url) = entry["url"].as_str() {
                println!("[gateway] /{name}: proxy to {url}");
                builder = builder.chain(
                    genesis,
                    ChainSource::rpc_node(url::Url::parse(url).expect("chain.url must parse")),
                );
            } else {
                println!("[gateway] /{name}: catalog light client");
            }
            routes.insert(format!("/{name}"), genesis);
        }

        let provider = builder.build();
        let mut shared_routes = HashMap::new();
        for (path, genesis) in routes {
            let connection = provider.connect(genesis).await.unwrap_or_else(|err| {
                panic!("gateway connection for {path} failed: {}", err.reason)
            });
            let mut responses = connection.responses();
            let shared = Arc::new(SharedChain::new(Arc::from(connection)));
            let response_chain = Arc::clone(&shared);
            tokio::spawn(async move {
                while let Some(text) = responses.next().await {
                    response_chain.dispatch(text);
                }
                response_chain.close_clients();
            });
            shared_routes.insert(path, shared);
        }

        let routes = Arc::new(shared_routes);
        let listener = TcpListener::bind(&listen)
            .await
            .expect("the gateway must bind its listen address");
        println!("[gateway] listening on ws://{listen}");

        loop {
            let (stream, peer) = listener.accept().await.expect("accept must succeed");
            tokio::spawn(serve(stream, peer, Arc::clone(&routes)));
        }
    }

    struct SharedChain {
        connection: Arc<dyn JsonRpcConnection>,
        clients: Mutex<HashMap<u64, mpsc::UnboundedSender<Message>>>,
        pending: Mutex<HashMap<String, (u64, Value)>>,
        next_client: AtomicU64,
        next_request: AtomicU64,
    }

    impl SharedChain {
        fn new(connection: Arc<dyn JsonRpcConnection>) -> Self {
            Self {
                connection,
                clients: Mutex::new(HashMap::new()),
                pending: Mutex::new(HashMap::new()),
                next_client: AtomicU64::new(1),
                next_request: AtomicU64::new(1),
            }
        }

        fn register(&self) -> (u64, mpsc::UnboundedReceiver<Message>) {
            let client = self.next_client.fetch_add(1, Ordering::Relaxed);
            let (sender, receiver) = mpsc::unbounded_channel();
            self.clients.lock().unwrap().insert(client, sender);
            (client, receiver)
        }

        fn unregister(&self, client: u64) {
            self.clients.lock().unwrap().remove(&client);
        }

        fn forward(&self, client: u64, text: String) {
            let Ok(mut request) = serde_json::from_str::<Value>(&text) else {
                self.connection.send(text);
                return;
            };
            self.namespace_ids(client, &mut request);
            self.connection
                .send(serde_json::to_string(&request).expect("JSON-RPC request must serialize"));
        }

        fn namespace_ids(&self, client: u64, value: &mut Value) {
            match value {
                Value::Array(items) => {
                    for item in items {
                        self.namespace_ids(client, item);
                    }
                }
                Value::Object(object) => {
                    if let Some(id) = object.get_mut("id") {
                        let request = self.next_request.fetch_add(1, Ordering::Relaxed);
                        let namespaced = format!("gateway:{client}:{request}");
                        self.pending
                            .lock()
                            .unwrap()
                            .insert(namespaced.clone(), (client, id.clone()));
                        *id = Value::String(namespaced);
                    }
                }
                _ => {}
            }
        }

        fn dispatch(&self, text: String) {
            let Ok(mut response) = serde_json::from_str::<Value>(&text) else {
                self.broadcast(Message::Text(text));
                return;
            };
            if let Some(client) = self.restore_ids(&mut response) {
                self.send_to(
                    client,
                    Message::Text(
                        serde_json::to_string(&response).expect("JSON-RPC response must serialize"),
                    ),
                );
            } else {
                self.broadcast(Message::Text(text));
            }
        }

        fn restore_ids(&self, value: &mut Value) -> Option<u64> {
            match value {
                Value::Array(items) => {
                    let mut client = None;
                    for item in items {
                        let item_client = self.restore_ids(item)?;
                        if client.is_some_and(|current| current != item_client) {
                            return None;
                        }
                        client = Some(item_client);
                    }
                    client
                }
                Value::Object(object) => {
                    let id = object.get_mut("id")?;
                    let namespaced = id.as_str()?;
                    let (client, original) = self.pending.lock().unwrap().remove(namespaced)?;
                    *id = original;
                    Some(client)
                }
                _ => None,
            }
        }

        fn send_to(&self, client: u64, message: Message) {
            if let Some(sender) = self.clients.lock().unwrap().get(&client) {
                let _ = sender.send(message);
            }
        }

        fn broadcast(&self, message: Message) {
            self.clients
                .lock()
                .unwrap()
                .retain(|_, sender| sender.send(message.clone()).is_ok());
        }

        fn close_clients(&self) {
            self.broadcast(Message::Close(None));
            self.clients.lock().unwrap().clear();
        }
    }

    /// Bridge every downstream client onto the route's one live provider
    /// connection. One smoldot chain must own both peers: separately added
    /// chains do not gossip statements to each other inside the process.
    async fn serve(
        stream: TcpStream,
        peer: SocketAddr,
        routes: Arc<HashMap<String, Arc<SharedChain>>>,
    ) {
        let mut path = String::new();
        let websocket = match tokio_tungstenite::accept_hdr_async(
            stream,
            // The callback signature (and its large Err variant) is fixed by
            // tungstenite's accept_hdr_async.
            #[allow(clippy::result_large_err)]
            |request: &Request, response: Response| {
                path = request.uri().path().to_owned();
                Ok(response)
            },
        )
        .await
        {
            Ok(websocket) => websocket,
            Err(err) => {
                eprintln!("[gateway] {peer}: handshake failed: {err}");
                return;
            }
        };

        let Some(chain) = routes.get(&path).cloned() else {
            eprintln!("[gateway] {peer}: unknown route {path}");
            return;
        };
        let (client, mut responses) = chain.register();
        println!("[gateway] {peer}: connected to {path}");

        let (mut outbound, mut inbound) = websocket.split();
        loop {
            tokio::select! {
                frame = inbound.next() => match frame {
                    Some(Ok(Message::Text(text))) => chain.forward(client, text),
                    Some(Ok(Message::Binary(bytes))) => match String::from_utf8(bytes) {
                        Ok(text) => chain.forward(client, text),
                        Err(_) => eprintln!("[gateway] {peer}: dropping non-UTF-8 frame"),
                    },
                    Some(Ok(Message::Close(_))) | None => break,
                    // Ping/pong is answered by tungstenite itself.
                    Some(Ok(_)) => {}
                    Some(Err(err)) => {
                        eprintln!("[gateway] {peer}: receive failed: {err}");
                        break;
                    }
                },
                response = responses.recv() => match response {
                    Some(message) => {
                        if outbound.send(message).await.is_err() {
                            break;
                        }
                    }
                    None => break,
                },
            }
        }

        chain.unregister(client);
        let _ = outbound.close().await;
        println!("[gateway] {peer}: disconnected from {path}");
    }

    fn usage() -> ! {
        eprintln!("usage: gateway CONFIG.json");
        std::process::exit(2);
    }

    fn parse_genesis(hex_str: &str) -> [u8; 32] {
        hex::decode(hex_str.trim_start_matches("0x"))
            .expect("genesis hashes are valid hex")
            .try_into()
            .expect("genesis hashes are 32 bytes")
    }
}
