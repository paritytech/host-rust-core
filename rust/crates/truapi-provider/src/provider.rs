//! Genesis-hash registry dispatching each connection to its backend.
//!
//! A parachain's relay is provider topology (see `relays`), not part of
//! [`ChainSource`]; the light backend brings the relay up behind the parachain.

use std::collections::HashMap;
#[cfg(feature = "ws")]
use std::pin::Pin;
#[cfg(feature = "ws")]
use std::sync::{Arc, Mutex};
#[cfg(feature = "ws")]
use std::task::{Context, Poll};

#[cfg(feature = "ws")]
use futures::stream::{BoxStream, Stream, StreamExt};

use truapi::latest::GenericError;
use truapi_platform::{ChainProvider, JsonRpcConnection};

use crate::config::ChainSource;
use crate::error::ProviderError;

/// Builder collecting genesis-hash to [`ChainSource`] registrations.
#[derive(Debug, Default)]
pub struct EmbeddedChainProviderBuilder {
    chains: HashMap<[u8; 32], ChainSource>,
    /// Optional remote node used only for extrinsic submission traffic, keyed
    /// by chain genesis hash.
    #[cfg(feature = "ws")]
    submit_nodes: HashMap<[u8; 32], url::Url>,
    /// The relay each parachain syncs through, keyed by parachain genesis hash
    /// (exactly one per parachain).
    #[cfg(feature = "smoldot")]
    relays: HashMap<[u8; 32], [u8; 32]>,
    /// Warm-start database blobs keyed by genesis hash, applied to a
    /// light-client chain at connect time if it has no explicit blob.
    #[cfg(feature = "smoldot")]
    databases: HashMap<[u8; 32], String>,
}

impl EmbeddedChainProviderBuilder {
    /// Create an empty builder.
    pub fn new() -> Self {
        Self::default()
    }

    /// Register `source` as the backend for the chain identified by
    /// `genesis_hash`. A later registration for the same hash replaces the
    /// earlier one.
    pub fn chain(mut self, genesis_hash: [u8; 32], source: ChainSource) -> Self {
        self.chains.insert(genesis_hash, source);
        self
    }
    /// Route extrinsic submission and matching unwatch requests for
    /// `genesis_hash` through `url`, while all other JSON-RPC remains on the
    /// chain's registered backend. A later registration for the same hash
    /// replaces the earlier one.
    #[cfg(feature = "ws")]
    pub fn submit_rpc(mut self, genesis_hash: [u8; 32], url: url::Url) -> Self {
        self.submit_nodes.insert(genesis_hash, url);
        self
    }

    /// Register `source` as a parachain syncing through the relay registered
    /// under `relay_genesis`. A later registration for `genesis_hash` wins.
    #[cfg(feature = "smoldot")]
    pub(crate) fn parachain(
        mut self,
        genesis_hash: [u8; 32],
        source: ChainSource,
        relay_genesis: [u8; 32],
    ) -> Self {
        self.chains.insert(genesis_hash, source);
        self.relays.insert(genesis_hash, relay_genesis);
        self
    }

    /// Seed a warm-start database blob (previously produced by
    /// [`EmbeddedChainProvider::snapshot`]) for `genesis_hash`, so its light
    /// client resumes from that finalized state instead of syncing from the
    /// chain-spec checkpoint. Applies to catalog-resolved chains too, and is
    /// ignored for a chain that already carries an explicit blob.
    #[cfg(feature = "smoldot")]
    pub fn database(mut self, genesis_hash: [u8; 32], blob: String) -> Self {
        self.databases.insert(genesis_hash, blob);
        self
    }

    /// Build the provider. Light-client resources start lazily on the first
    /// light-client connect.
    pub fn build(self) -> EmbeddedChainProvider {
        EmbeddedChainProvider {
            chains: self.chains,
            #[cfg(feature = "ws")]
            submit_nodes: self.submit_nodes,
            #[cfg(feature = "smoldot")]
            relays: self.relays,
            #[cfg(feature = "smoldot")]
            databases: self.databases,
            #[cfg(feature = "smoldot")]
            light: crate::light::LightState::new(),
        }
    }
}

/// In-process [`ChainProvider`] whose per-chain backend is a remote WebSocket
/// JSON-RPC node (all targets) or an embedded smoldot light client (native
/// targets).
///
/// Construct **one provider per host process** and share it (behind an `Arc`)
/// with every consumer: the provider owns the single light-client instance,
/// so host-internal flows (domain resolution, statement store) and product
/// connections share sync, peers, and warm state, while each connection keeps
/// its own isolated JSON-RPC queue and response stream.
///
/// The `responses()` stream of returned connections is take-once: the first
/// call yields the live stream, later calls yield an ended stream.
pub struct EmbeddedChainProvider {
    chains: HashMap<[u8; 32], ChainSource>,
    #[cfg(feature = "ws")]
    submit_nodes: HashMap<[u8; 32], url::Url>,
    /// The relay each explicitly-registered parachain syncs through; catalog
    /// parachains carry theirs in the catalog entry.
    #[cfg(feature = "smoldot")]
    relays: HashMap<[u8; 32], [u8; 32]>,
    #[cfg(feature = "smoldot")]
    databases: HashMap<[u8; 32], String>,
    #[cfg(feature = "smoldot")]
    light: crate::light::LightState,
}

impl EmbeddedChainProvider {
    /// Start building a provider.
    pub fn builder() -> EmbeddedChainProviderBuilder {
        EmbeddedChainProviderBuilder::new()
    }

    /// Open a connection for `source`; for a parachain, `relay`/`chains` give
    /// the light backend the relay to sync it through.
    ///
    /// The relay's source is resolved and warm-start-seeded here, so a blob
    /// registered for a relay applies whether it is connected directly or
    /// brought up implicitly behind one of its parachains.
    #[cfg_attr(not(feature = "smoldot"), allow(unused_variables))]
    async fn connect_source(
        &self,
        source: &ChainSource,
        chains: &HashMap<[u8; 32], ChainSource>,
        relay: Option<[u8; 32]>,
    ) -> Result<Box<dyn JsonRpcConnection>, ProviderError> {
        match source {
            #[cfg(feature = "ws")]
            ChainSource::RpcNode { url } => crate::ws::connect(url.clone()).await,
            #[cfg(feature = "smoldot")]
            ChainSource::LightClient { .. } => {
                let relay = match relay {
                    None => None,
                    Some(relay_genesis) => Some(self.resolve_relay(chains, relay_genesis)?),
                };
                self.light.connect(source, relay).await
            }
        }
    }

    /// Resolve a parachain's relay to the source the light backend should add
    /// it under, carrying any warm-start blob registered for the relay.
    #[cfg(feature = "smoldot")]
    fn resolve_relay(
        &self,
        chains: &HashMap<[u8; 32], ChainSource>,
        relay_genesis: [u8; 32],
    ) -> Result<([u8; 32], ChainSource), ProviderError> {
        let source = chains
            .get(&relay_genesis)
            .ok_or(ProviderError::UnknownRelay {
                relay: relay_genesis,
            })?;
        Ok((
            relay_genesis,
            self.with_seeded_database(relay_genesis, source.clone()),
        ))
    }

    /// Apply a seeded warm-start database blob to `source` if one exists for
    /// `genesis_hash` and the source is a light client with no explicit blob.
    #[cfg(feature = "smoldot")]
    fn with_seeded_database(&self, genesis_hash: [u8; 32], mut source: ChainSource) -> ChainSource {
        if let Some(blob) = self.databases.get(&genesis_hash)
            && let ChainSource::LightClient {
                database_content, ..
            } = &mut source
            && database_content.is_none()
        {
            *database_content = Some(blob.clone());
        }
        source
    }

    #[cfg(not(feature = "smoldot"))]
    fn with_seeded_database(&self, _genesis_hash: [u8; 32], source: ChainSource) -> ChainSource {
        source
    }
    #[cfg(feature = "ws")]
    async fn with_submit_node(
        &self,
        genesis_hash: [u8; 32],
        primary: Box<dyn JsonRpcConnection>,
    ) -> Result<Box<dyn JsonRpcConnection>, ProviderError> {
        let Some(url) = self.submit_nodes.get(&genesis_hash) else {
            return Ok(primary);
        };
        let submit = crate::ws::connect(url.clone()).await?;
        Ok(Box::new(HybridConnection::new(primary, submit)))
    }

    #[cfg(not(feature = "ws"))]
    async fn with_submit_node(
        &self,
        _genesis_hash: [u8; 32],
        primary: Box<dyn JsonRpcConnection>,
    ) -> Result<Box<dyn JsonRpcConnection>, ProviderError> {
        Ok(primary)
    }
}

/// One logical connection whose ordinary traffic remains on the primary
/// backend while author submission traffic uses a configured remote node.
///
/// Both transports share one response stream and one lifecycle. If either
/// transport dies, the logical stream ends and both transports close, so a
/// caller can never wait forever for a response on the dead half.
#[cfg(feature = "ws")]
struct HybridConnection {
    primary: Arc<dyn JsonRpcConnection>,
    submit: Arc<dyn JsonRpcConnection>,
    responses: Mutex<Option<BoxStream<'static, String>>>,
}

#[cfg(feature = "ws")]
impl HybridConnection {
    fn new(primary: Box<dyn JsonRpcConnection>, submit: Box<dyn JsonRpcConnection>) -> Self {
        let primary: Arc<dyn JsonRpcConnection> = Arc::from(primary);
        let submit: Arc<dyn JsonRpcConnection> = Arc::from(submit);
        let responses = HybridResponses {
            primary: primary.responses(),
            submit: submit.responses(),
            primary_connection: Arc::clone(&primary),
            submit_connection: Arc::clone(&submit),
            poll_submit_first: false,
            closed: false,
        }
        .boxed();
        Self {
            primary,
            submit,
            responses: Mutex::new(Some(responses)),
        }
    }

    fn uses_submit_node(request: &str) -> bool {
        let Ok(request) = serde_json::from_str::<serde_json::Value>(request) else {
            return false;
        };
        request
            .get("method")
            .and_then(serde_json::Value::as_str)
            .is_some_and(|method| {
                method.starts_with("author_submit") || method == "author_unwatchExtrinsic"
            })
    }
}

#[cfg(feature = "ws")]
impl JsonRpcConnection for HybridConnection {
    fn send(&self, request: String) {
        if Self::uses_submit_node(&request) {
            self.submit.send(request);
        } else {
            self.primary.send(request);
        }
    }

    fn responses(&self) -> BoxStream<'static, String> {
        self.responses
            .lock()
            .expect("responses mutex poisoned")
            .take()
            .unwrap_or_else(|| futures::stream::empty().boxed())
    }

    fn close(&self) {
        self.primary.close();
        self.submit.close();
        self.responses
            .lock()
            .expect("responses mutex poisoned")
            .take();
    }
}

#[cfg(feature = "ws")]
impl Drop for HybridConnection {
    fn drop(&mut self) {
        self.close();
    }
}

#[cfg(feature = "ws")]
struct HybridResponses {
    primary: BoxStream<'static, String>,
    submit: BoxStream<'static, String>,
    primary_connection: Arc<dyn JsonRpcConnection>,
    submit_connection: Arc<dyn JsonRpcConnection>,
    poll_submit_first: bool,
    closed: bool,
}

#[cfg(feature = "ws")]
impl HybridResponses {
    fn finish(&mut self) {
        if self.closed {
            return;
        }
        self.closed = true;
        self.primary_connection.close();
        self.submit_connection.close();
    }
}

#[cfg(feature = "ws")]
impl Stream for HybridResponses {
    type Item = String;

    fn poll_next(self: Pin<&mut Self>, cx: &mut Context<'_>) -> Poll<Option<Self::Item>> {
        let this = self.get_mut();
        if this.closed {
            return Poll::Ready(None);
        }
        let first_submit = this.poll_submit_first;
        for poll_submit in [first_submit, !first_submit] {
            let result = if poll_submit {
                this.submit.as_mut().poll_next(cx)
            } else {
                this.primary.as_mut().poll_next(cx)
            };
            match result {
                Poll::Ready(Some(response)) => {
                    this.poll_submit_first = !poll_submit;
                    return Poll::Ready(Some(response));
                }
                Poll::Ready(None) => {
                    this.finish();
                    return Poll::Ready(None);
                }
                Poll::Pending => {}
            }
        }
        Poll::Pending
    }
}

/// Max size for a [`snapshot`](EmbeddedChainProvider::snapshot) database blob.
#[cfg(feature = "smoldot")]
const SNAPSHOT_MAX_BYTES: usize = 8_000_000;

#[cfg(feature = "smoldot")]
impl EmbeddedChainProvider {
    /// Produce a warm-start database blob for `genesis_hash` by asking the
    /// embedded light client for its finalized-database snapshot.
    ///
    /// Persist the returned string and feed it back on a later run via
    /// [`EmbeddedChainProviderBuilder::database`] so the chain resumes from
    /// finalized state instead of re-syncing from the checkpoint.
    ///
    /// Meaningful only for light-client chains. A remote node has no local
    /// database to snapshot and answers the request with a JSON-RPC error,
    /// which surfaces here as an error rather than a wait.
    pub async fn snapshot(&self, genesis_hash: [u8; 32]) -> Result<String, GenericError> {
        use futures::stream::StreamExt;

        use crate::error::FrameForId;

        let connection = self.connect(genesis_hash).await?;
        let mut responses = connection.responses();
        let id = "truapi-provider:finalizedDatabase";
        connection.send(format!(
            concat!(
                r#"{{"jsonrpc":"2.0","id":"{}","#,
                r#""method":"chainHead_unstable_finalizedDatabase","params":[{}]}}"#
            ),
            id, SNAPSHOT_MAX_BYTES,
        ));
        while let Some(frame) = responses.next().await {
            match crate::error::frame_for_id(&frame, id) {
                Some(FrameForId::Result(result)) => {
                    connection.close();
                    return Ok(result);
                }
                Some(FrameForId::Failure(reason)) => {
                    connection.close();
                    return Err(ProviderError::Transport {
                        reason: format!("finalized-database snapshot failed: {reason}"),
                    }
                    .into());
                }
                None => {}
            }
        }
        connection.close();
        Err(ProviderError::Transport {
            reason: "connection ended before the finalized-database snapshot".to_owned(),
        }
        .into())
    }
}

#[cfg(all(test, feature = "smoldot"))]
impl EmbeddedChainProvider {
    /// Number of implicit relay chains the shared light client currently holds.
    pub(crate) fn relay_count(&self) -> usize {
        self.light.relay_count()
    }
}

#[truapi_platform::async_trait]
impl ChainProvider for EmbeddedChainProvider {
    #[tracing::instrument(skip_all, fields(genesis = %hex::encode(genesis_hash)))]
    async fn connect(
        &self,
        genesis_hash: [u8; 32],
    ) -> Result<Box<dyn JsonRpcConnection>, GenericError> {
        // Explicit registrations win; otherwise the catalog resolves the whole
        // network from the genesis hash alone.
        if let Some(source) = self.chains.get(&genesis_hash) {
            let source = self.with_seeded_database(genesis_hash, source.clone());
            #[cfg(feature = "smoldot")]
            let relay = self.relays.get(&genesis_hash).copied();
            #[cfg(not(feature = "smoldot"))]
            let relay = None;
            let primary = self.connect_source(&source, &self.chains, relay).await?;
            return Ok(self.with_submit_node(genesis_hash, primary).await?);
        }
        #[cfg(feature = "networks")]
        if let Some((catalog, relay)) = crate::networks::catalog_network_chains(genesis_hash) {
            if let Some((network, service)) = crate::networks::catalog_service(genesis_hash) {
                tracing::info!(network, service, "connecting via light client");
            }
            let source = catalog
                .get(&genesis_hash)
                .expect("catalog_network_chains includes the queried genesis")
                .clone();
            let source = self.with_seeded_database(genesis_hash, source);
            let primary = self.connect_source(&source, &catalog, relay).await?;
            return Ok(self.with_submit_node(genesis_hash, primary).await?);
        }
        Err(ProviderError::UnknownGenesis {
            genesis: genesis_hash,
        }
        .into())
    }
}

#[cfg(test)]
mod tests {
    use truapi_platform::ChainProvider;

    use super::EmbeddedChainProvider;
    use crate::config::ChainSource;

    #[test]
    fn unknown_genesis_is_an_error_naming_the_hash() {
        let provider = EmbeddedChainProvider::builder().build();
        let error = futures::executor::block_on(provider.connect([0xab; 32]))
            .err()
            .expect("connect must fail for an unregistered genesis");
        assert!(error.reason.contains(&"ab".repeat(32)));
    }

    #[cfg(feature = "ws")]
    #[test]
    fn hybrid_routing_is_limited_to_submission_and_matching_unwatch() {
        use super::HybridConnection;

        for method in [
            "author_submitExtrinsic",
            "author_submitAndWatchExtrinsic",
            "author_unwatchExtrinsic",
        ] {
            assert!(HybridConnection::uses_submit_node(&format!(
                r#"{{"jsonrpc":"2.0","id":1,"method":"{method}","params":[]}}"#
            )));
        }
        for method in [
            "chain_getHeader",
            "chainHead_v1_follow",
            "statement_submit",
            "author_pendingExtrinsics",
        ] {
            assert!(!HybridConnection::uses_submit_node(&format!(
                r#"{{"jsonrpc":"2.0","id":1,"method":"{method}","params":[]}}"#
            )));
        }
        assert!(!HybridConnection::uses_submit_node("not json"));
    }

    /// A blob registered for a relay reaches it even when the relay is never
    /// connected directly, only brought up behind one of its parachains.
    #[cfg(feature = "smoldot")]
    #[test]
    // Without the `ws` backend the enum has a single variant, making the
    // let-else below irrefutable there.
    #[allow(irrefutable_let_patterns)]
    fn a_relay_blob_seeds_the_relay_brought_up_behind_a_parachain() {
        use std::collections::HashMap;

        const RELAY: [u8; 32] = [1; 32];
        let mut chains = HashMap::new();
        chains.insert(RELAY, ChainSource::light_client("{}").build());
        let provider = EmbeddedChainProvider::builder()
            .database(RELAY, "relay-blob".to_owned())
            .build();

        let (genesis, source) = provider
            .resolve_relay(&chains, RELAY)
            .expect("the relay is registered");
        assert_eq!(genesis, RELAY);
        let ChainSource::LightClient {
            database_content, ..
        } = source
        else {
            panic!("expected a LightClient source");
        };
        assert_eq!(database_content.as_deref(), Some("relay-blob"));
    }

    /// The snapshot round trip resolves against a live light client, and the
    /// blob it returns is accepted back as a warm-start seed.
    #[cfg(feature = "smoldot")]
    #[test]
    fn snapshot_round_trips_into_a_warm_start_seed() {
        const GENESIS: [u8; 32] = [1; 32];
        const SPEC: &str = include_str!("../tests/fixtures/paseo.json");
        let provider = EmbeddedChainProvider::builder()
            .chain(GENESIS, ChainSource::light_client(SPEC).build())
            .build();
        let blob = futures::executor::block_on(provider.snapshot(GENESIS))
            .expect("the light client answers the finalized-database request");
        assert!(blob.contains("genesisHash"), "unexpected blob: {blob}");

        let seeded = EmbeddedChainProvider::builder()
            .chain(GENESIS, ChainSource::light_client(SPEC).build())
            .database(GENESIS, blob)
            .build();
        futures::executor::block_on(seeded.connect(GENESIS))
            .expect("a chain seeded with its own snapshot connects");
    }

    #[cfg(feature = "ws")]
    #[test]
    // On wasm32 without the smoldot backend the enum has a single variant,
    // making the let-else irrefutable there.
    #[allow(irrefutable_let_patterns)]
    fn later_registration_wins() {
        let first = url::Url::parse("ws://first.example").expect("static URL parses");
        let second = url::Url::parse("ws://second.example").expect("static URL parses");
        let provider = EmbeddedChainProvider::builder()
            .chain([1; 32], ChainSource::rpc_node(first))
            .chain([1; 32], ChainSource::rpc_node(second.clone()))
            .build();
        let ChainSource::RpcNode { url } = &provider.chains[&[1; 32]] else {
            panic!("expected an RpcNode source");
        };
        assert_eq!(*url, second);
    }
}
