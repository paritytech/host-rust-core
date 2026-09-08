//! Genesis-hash registry dispatching each connection to its backend.
//!
//! A parachain's relay is provider topology (see `relays`), not part of
//! [`ChainSource`]; the light backend brings the relay up behind the parachain.

use std::collections::HashMap;
#[cfg(feature = "smoldot")]
use std::sync::Mutex;

use truapi::latest::GenericError;
use truapi_platform::{ChainProvider, JsonRpcConnection};

use crate::config::ChainSource;
use crate::error::ProviderError;

/// Builder collecting genesis-hash to [`ChainSource`] registrations.
#[derive(Default)]
pub struct EmbeddedChainProviderBuilder {
    chains: HashMap<[u8; 32], ChainSource>,
    /// The relay each parachain syncs through, keyed by parachain genesis hash
    /// (exactly one per parachain).
    #[cfg(feature = "smoldot")]
    relays: HashMap<[u8; 32], [u8; 32]>,
    /// Warm-start database blobs keyed by genesis hash, applied to a
    /// light-client chain at connect time if it has no explicit blob.
    #[cfg(feature = "smoldot")]
    databases: HashMap<[u8; 32], String>,
    /// Where warm-start blobs are read from and written back to.
    #[cfg(feature = "smoldot")]
    warm_store: Option<crate::warm_start::SharedWarmStore>,
}

impl core::fmt::Debug for EmbeddedChainProviderBuilder {
    fn fmt(&self, f: &mut core::fmt::Formatter<'_>) -> core::fmt::Result {
        let mut builder = f.debug_struct("EmbeddedChainProviderBuilder");
        builder.field("chains", &self.chains);
        #[cfg(feature = "smoldot")]
        builder
            .field("relays", &self.relays)
            .field("databases", &self.databases)
            .field("warm_store", &self.warm_store.is_some());
        builder.finish()
    }
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

    /// Keep warm-start blobs in `store`, so
    /// [`warm_up`](EmbeddedChainProvider::warm_up) and
    /// [`persist`](EmbeddedChainProvider::persist) have somewhere to read from
    /// and write to. A blob registered with [`database`](Self::database) still
    /// wins over a stored one.
    #[cfg(feature = "smoldot")]
    pub fn warm_store(mut self, store: crate::warm_start::SharedWarmStore) -> Self {
        self.warm_store = Some(store);
        self
    }

    /// Build the provider. Light-client resources start lazily on the first
    /// light-client connect.
    pub fn build(self) -> EmbeddedChainProvider {
        EmbeddedChainProvider {
            chains: self.chains,
            #[cfg(feature = "smoldot")]
            relays: self.relays,
            #[cfg(feature = "smoldot")]
            databases: Mutex::new(self.databases),
            #[cfg(feature = "smoldot")]
            warm_store: self.warm_store,
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
    /// The relay each explicitly-registered parachain syncs through; catalog
    /// parachains carry theirs in the catalog entry.
    #[cfg(feature = "smoldot")]
    relays: HashMap<[u8; 32], [u8; 32]>,
    /// Blobs seeded explicitly or read back from the warm store, kept behind a
    /// lock because `warm_up` fills it after the provider is built.
    #[cfg(feature = "smoldot")]
    databases: Mutex<HashMap<[u8; 32], String>>,
    #[cfg(feature = "smoldot")]
    warm_store: Option<crate::warm_start::SharedWarmStore>,
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
        let databases = self
            .databases
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        if let Some(blob) = databases.get(&genesis_hash)
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
}

/// Max size for a [`snapshot`](EmbeddedChainProvider::snapshot) database blob.
#[cfg(feature = "smoldot")]
const SNAPSHOT_MAX_BYTES: usize = 8_000_000;

/// How long [`EmbeddedChainProvider::snapshot`] waits for the light client to
/// answer. A chain that is still warp syncing has no finalized database to hand
/// over, and the response stream stays open either way, so the call has to end
/// on its own rather than wait on a stream that never yields.
#[cfg(feature = "smoldot")]
const SNAPSHOT_TIMEOUT: core::time::Duration = core::time::Duration::from_secs(60);

#[cfg(feature = "smoldot")]
impl EmbeddedChainProvider {
    /// Whether a blob is already in hand for `genesis_hash`.
    fn has_database(&self, genesis_hash: [u8; 32]) -> bool {
        self.databases
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner)
            .contains_key(&genesis_hash)
    }

    /// Read `genesis_hash`'s stored blob into this provider, so the next
    /// connect to that chain resumes from it instead of warp syncing from the
    /// chain-spec checkpoint. Returns whether a blob is now in hand.
    ///
    /// The store is read at most once per chain. smoldot keys a chain by its
    /// genesis hash, so only the first add of a chain consumes a blob and a
    /// later read could not take effect. A blob registered through
    /// [`EmbeddedChainProviderBuilder::database`] wins and is not overwritten.
    ///
    /// Call this before [`connect`](truapi_platform::ChainProvider::connect),
    /// not from inside a connection callback: on the native bindings `connect`
    /// blocks the calling thread, and a store that needs the main thread would
    /// deadlock underneath it.
    pub async fn warm_up(&self, genesis_hash: [u8; 32]) -> Result<bool, GenericError> {
        if self.has_database(genesis_hash) {
            return Ok(true);
        }
        let Some(store) = self.warm_store.clone() else {
            return Ok(false);
        };
        let Some(blob) = store.load(genesis_hash).await? else {
            return Ok(false);
        };
        self.databases
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner)
            .entry(genesis_hash)
            .or_insert(blob);
        Ok(true)
    }

    /// Snapshot `genesis_hash`'s finalized state and hand it to the warm store.
    /// Returns whether a blob was stored.
    ///
    /// A chain that has finalized nothing yet still answers the snapshot
    /// request, with a blob carrying no chain information that smoldot would
    /// discard on the next run. Storing it would turn a warm start back into a
    /// cold one, so it is skipped instead.
    ///
    /// This is a full round trip against the light client, not a write: call it
    /// while the app is alive, and treat a call from a teardown callback as
    /// best effort, since neither a hidden page nor a backgrounded app is
    /// guaranteed to stay scheduled long enough to finish it.
    pub async fn persist(&self, genesis_hash: [u8; 32]) -> Result<bool, GenericError> {
        let Some(store) = self.warm_store.clone() else {
            return Ok(false);
        };
        let blob = self.snapshot(genesis_hash).await?;
        if !crate::warm_start::carries_chain_information(&blob) {
            tracing::debug!(
                genesis = %hex::encode(genesis_hash),
                "no finalized state to store yet"
            );
            return Ok(false);
        }
        store.save(genesis_hash, blob.clone()).await?;
        self.databases
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner)
            .insert(genesis_hash, blob);
        Ok(true)
    }

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
        use futures::future::{self, Either};
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
        let deadline = futures_timer::Delay::new(SNAPSHOT_TIMEOUT);
        futures::pin_mut!(deadline);

        loop {
            match future::select(responses.next(), deadline.as_mut()).await {
                Either::Left((Some(frame), _)) => match crate::error::frame_for_id(&frame, id) {
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
                },
                Either::Left((None, _)) => {
                    connection.close();
                    return Err(ProviderError::Transport {
                        reason: "connection ended before the finalized-database snapshot"
                            .to_owned(),
                    }
                    .into());
                }
                Either::Right(((), _)) => {
                    connection.close();
                    return Err(ProviderError::Transport {
                        reason: format!(
                            "no finalized-database snapshot within {}s",
                            SNAPSHOT_TIMEOUT.as_secs()
                        ),
                    }
                    .into());
                }
            }
        }
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
            return Ok(self.connect_source(&source, &self.chains, relay).await?);
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
            return Ok(self.connect_source(&source, &catalog, relay).await?);
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

    /// A store answering from memory, recording what it was asked to keep.
    #[cfg(feature = "smoldot")]
    #[derive(Default)]
    struct MemoryWarmStore {
        stored: std::sync::Mutex<std::collections::HashMap<[u8; 32], String>>,
        loads: std::sync::atomic::AtomicUsize,
    }

    #[cfg(feature = "smoldot")]
    #[truapi_platform::async_trait]
    impl crate::warm_start::WarmStore for MemoryWarmStore {
        async fn load(
            &self,
            genesis_hash: [u8; 32],
        ) -> Result<Option<String>, crate::warm_start::WarmStoreError> {
            self.loads
                .fetch_add(1, std::sync::atomic::Ordering::Relaxed);
            Ok(self
                .stored
                .lock()
                .expect("test store")
                .get(&genesis_hash)
                .cloned())
        }

        async fn save(
            &self,
            genesis_hash: [u8; 32],
            blob: String,
        ) -> Result<(), crate::warm_start::WarmStoreError> {
            self.stored
                .lock()
                .expect("test store")
                .insert(genesis_hash, blob);
            Ok(())
        }
    }

    /// A stored blob reaches the chain source the light backend is handed.
    #[cfg(feature = "smoldot")]
    #[test]
    #[allow(irrefutable_let_patterns)]
    fn warm_up_seeds_a_chain_from_the_store() {
        const GENESIS: [u8; 32] = [3; 32];
        let store = std::sync::Arc::new(MemoryWarmStore::default());
        store
            .stored
            .lock()
            .expect("test store")
            .insert(GENESIS, "stored-blob".to_owned());

        let provider = EmbeddedChainProvider::builder()
            .chain(GENESIS, ChainSource::light_client("{}").build())
            .warm_store(store.clone())
            .build();

        assert!(
            futures::executor::block_on(provider.warm_up(GENESIS)).expect("the store answers"),
            "a stored blob is reported as in hand"
        );

        let seeded =
            provider.with_seeded_database(GENESIS, ChainSource::light_client("{}").build());
        let ChainSource::LightClient {
            database_content, ..
        } = seeded
        else {
            panic!("expected a LightClient source");
        };
        assert_eq!(database_content.as_deref(), Some("stored-blob"));

        futures::executor::block_on(provider.warm_up(GENESIS)).expect("the store answers");
        assert_eq!(
            store.loads.load(std::sync::atomic::Ordering::Relaxed),
            1,
            "the store is read once per chain, since only the first add consumes a blob"
        );
    }

    /// An explicitly registered blob is not replaced by the stored one.
    #[cfg(feature = "smoldot")]
    #[test]
    fn an_explicit_blob_wins_over_the_store() {
        const GENESIS: [u8; 32] = [4; 32];
        let store = std::sync::Arc::new(MemoryWarmStore::default());
        store
            .stored
            .lock()
            .expect("test store")
            .insert(GENESIS, "stored-blob".to_owned());

        let provider = EmbeddedChainProvider::builder()
            .chain(GENESIS, ChainSource::light_client("{}").build())
            .database(GENESIS, "explicit-blob".to_owned())
            .warm_store(store.clone())
            .build();

        assert!(futures::executor::block_on(provider.warm_up(GENESIS)).expect("no store read"));
        assert_eq!(
            store.loads.load(std::sync::atomic::Ordering::Relaxed),
            0,
            "an explicit blob means the store is never consulted"
        );
    }

    /// Without a store, warm start is simply off rather than an error.
    #[cfg(feature = "smoldot")]
    #[test]
    fn warm_up_without_a_store_reports_nothing_in_hand() {
        let provider = EmbeddedChainProvider::builder()
            .chain([5; 32], ChainSource::light_client("{}").build())
            .build();
        assert!(!futures::executor::block_on(provider.warm_up([5; 32])).expect("no store"));
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
