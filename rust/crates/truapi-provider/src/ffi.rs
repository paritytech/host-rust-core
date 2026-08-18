//! Swift/UniFFI bindings (the `uniffi` feature, native targets).
//!
//! Exposes the embedded smoldot [`ChainProvider`](truapi_platform::ChainProvider)
//! to Swift (and other UniFFI targets): build a provider, connect to a chain by
//! genesis hash, and drive the raw JSON-RPC string pipe. Chain specs, relay
//! topology, and statement-store placement come from the bundled network
//! catalog, so the only argument a host supplies is the genesis hash.
//!
//! Inbound responses are delivered to a foreign [`ChainMessageListener`]; a
//! background thread pumps the response stream and invokes it until the
//! connection closes.

use std::sync::Arc;

use futures::executor::block_on;
use futures::stream::StreamExt;
use truapi_platform::{ChainProvider as _, JsonRpcConnection};

use crate::EmbeddedChainProvider;

/// Errors surfaced to the foreign caller.
#[derive(Debug, thiserror::Error, uniffi::Error)]
pub enum ChainProviderError {
    /// The chain could not be connected (unknown genesis, transport failure).
    #[error("{reason}")]
    Connect {
        /// Human-readable failure reason.
        reason: String,
    },
    /// The genesis hash was not exactly 32 bytes.
    #[error("genesis hash must be 32 bytes")]
    BadGenesis,
}

/// Sink for a connection's inbound JSON-RPC responses and notifications,
/// implemented on the foreign (Swift) side.
#[uniffi::export(with_foreign)]
pub trait ChainMessageListener: Send + Sync {
    /// Called for each JSON-RPC response or notification string.
    fn on_message(&self, message: String);
    /// Called once the connection's response stream ends.
    fn on_closed(&self);
}

/// Embedded-smoldot chain provider. Construct one per process and share it;
/// every connection runs on the single embedded light client.
#[derive(uniffi::Object)]
pub struct ChainProvider {
    inner: EmbeddedChainProvider,
}

#[uniffi::export]
impl ChainProvider {
    /// Create a provider backed by the bundled network catalog.
    #[uniffi::constructor]
    pub fn new() -> Arc<Self> {
        Arc::new(Self {
            inner: EmbeddedChainProvider::builder().build(),
        })
    }

    /// Open a connection to the chain identified by `genesis_hash` (32 bytes).
    /// The network is resolved from the catalog; responses are delivered to
    /// `listener` until the connection closes.
    pub fn connect(
        &self,
        genesis_hash: Vec<u8>,
        listener: Arc<dyn ChainMessageListener>,
    ) -> Result<Arc<ChainConnection>, ChainProviderError> {
        let genesis: [u8; 32] = genesis_hash
            .try_into()
            .map_err(|_| ChainProviderError::BadGenesis)?;
        let connection =
            block_on(self.inner.connect(genesis)).map_err(|error| ChainProviderError::Connect {
                reason: error.reason,
            })?;
        let connection: Arc<dyn JsonRpcConnection> = Arc::from(connection);

        let mut responses = connection.responses();
        std::thread::spawn(move || {
            block_on(async move {
                while let Some(message) = responses.next().await {
                    listener.on_message(message);
                }
                listener.on_closed();
            });
        });

        Ok(Arc::new(ChainConnection { inner: connection }))
    }
}

/// A live JSON-RPC connection: a raw string pipe to one chain.
#[derive(uniffi::Object)]
pub struct ChainConnection {
    inner: Arc<dyn JsonRpcConnection>,
}

#[cfg(all(test, feature = "networks"))]
mod tests {
    use std::sync::Mutex;
    use std::sync::mpsc::{Receiver, Sender, channel};
    use std::time::Duration;

    use super::*;

    /// Paseo Next v2's relay, whose spec the catalog bundles. Spec-local queries
    /// are answered from it without any network access.
    const CATALOG_RELAY: [u8; 32] = match const_hex_decode(
        "374057be67b355151f271ff70c3db98308c62c8adc48dc6724b6a009a1a014fd",
    ) {
        Some(bytes) => bytes,
        None => panic!("the constant is 32 bytes of hex"),
    };

    /// `hex::decode` is not const, and a literal byte array here would not be
    /// greppable against the catalog.
    const fn const_hex_decode(hex: &str) -> Option<[u8; 32]> {
        let bytes = hex.as_bytes();
        if bytes.len() != 64 {
            return None;
        }
        let mut out = [0u8; 32];
        let mut i = 0;
        while i < 32 {
            let (high, low) = (nibble(bytes[i * 2]), nibble(bytes[i * 2 + 1]));
            match (high, low) {
                (Some(high), Some(low)) => out[i] = high << 4 | low,
                _ => return None,
            }
            i += 1;
        }
        Some(out)
    }

    const fn nibble(byte: u8) -> Option<u8> {
        match byte {
            b'0'..=b'9' => Some(byte - b'0'),
            b'a'..=b'f' => Some(byte - b'a' + 10),
            _ => None,
        }
    }

    /// Foreign listener stand-in: the real one lives in Swift or Kotlin, so this
    /// exercises the same `with_foreign` trait the bindings implement.
    struct Collector {
        messages: Sender<String>,
        closed: Mutex<Option<Sender<()>>>,
    }

    impl Collector {
        fn new() -> (Arc<Self>, Receiver<String>, Receiver<()>) {
            let (messages, message_rx) = channel();
            let (closed, closed_rx) = channel();
            let collector = Arc::new(Collector {
                messages,
                closed: Mutex::new(Some(closed)),
            });
            (collector, message_rx, closed_rx)
        }
    }

    impl ChainMessageListener for Collector {
        fn on_message(&self, message: String) {
            let _ = self.messages.send(message);
        }

        fn on_closed(&self) {
            if let Some(closed) = self.closed.lock().expect("not poisoned").take() {
                let _ = closed.send(());
            }
        }
    }

    #[test]
    fn a_genesis_hash_of_the_wrong_length_is_rejected() {
        let (listener, _messages, _closed) = Collector::new();
        let error = ChainProvider::new()
            .connect(vec![0u8; 31], listener)
            .err()
            .expect("a 31-byte genesis must be rejected");
        assert!(matches!(error, ChainProviderError::BadGenesis));
    }

    #[test]
    fn a_genesis_hash_outside_the_catalog_is_rejected() {
        let (listener, _messages, _closed) = Collector::new();
        let error = ChainProvider::new()
            .connect(vec![0xab; 32], listener)
            .err()
            .expect("an unbundled genesis must be rejected");
        let ChainProviderError::Connect { reason } = error else {
            panic!("expected a Connect error");
        };
        assert!(reason.contains(&"ab".repeat(32)), "unexpected: {reason}");
    }

    /// The whole foreign contract end to end: connect by catalog genesis, send a
    /// request, receive it on the listener, and see `on_closed` after
    /// `disconnect()`.
    #[test]
    fn a_catalog_chain_answers_on_the_listener_and_closes() {
        let (listener, messages, closed) = Collector::new();
        let connection = ChainProvider::new()
            .connect(CATALOG_RELAY.to_vec(), listener)
            .expect("the catalog resolves its own relay genesis");

        connection.send(
            r#"{"jsonrpc":"2.0","id":1,"method":"chainSpec_v1_chainName","params":[]}"#.to_owned(),
        );
        let response = messages
            .recv_timeout(Duration::from_secs(30))
            .expect("smoldot answers spec-local queries without a network");
        assert!(response.contains("Paseo"), "unexpected: {response}");

        connection.disconnect();
        closed
            .recv_timeout(Duration::from_secs(30))
            .expect("disconnecting ends the stream and fires on_closed");
    }
}

#[uniffi::export]
impl ChainConnection {
    /// Queue a JSON-RPC request string.
    pub fn send(&self, request: String) {
        self.inner.send(request);
    }

    /// Close the connection; the listener's `on_closed` fires once the stream
    /// ends.
    ///
    /// NOT named `close`: uniffi's generated Kotlin object already implements
    /// `AutoCloseable.close()` for handle disposal, so an exported `close`
    /// produces two methods with the same signature and the module does not
    /// compile ("Conflicting overloads").
    pub fn disconnect(&self) {
        self.inner.close();
    }
}
