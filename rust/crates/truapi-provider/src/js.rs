//! JavaScript-facing API for browser hosts (`js` feature, wasm32 only).
//!
//! Exposes the provider to JS without a Rust consumer: build a provider from
//! chain registrations, connect per genesis hash, and drive the raw JSON-RPC
//! string pipe. `nextResponse()` is pull-based, mirroring the smoldot npm
//! package's `nextJsonRpcResponse` so existing host code maps 1:1.
//!
//! ```js
//! const builder = new ChainProviderBuilder();
//! builder.addRpcChain("0x3740…", "wss://node.example");
//! const provider = builder.build();
//! const connection = await provider.connect("0x3740…");
//! connection.send('{"jsonrpc":"2.0","id":1,"method":"chainSpec_v1_genesisHash","params":[]}');
//! const response = await connection.nextResponse(); // undefined once closed
//! connection.close();
//! ```
//!
//! Construct one provider per page/worker: connections share the provider's
//! resources, matching the one-provider-per-host-process contract.
//!
//! Warm start needs only `setWarmStore`. A chain's stored blob is read before
//! its first connect, and from then on the provider snapshots that chain into
//! the store on its own schedule. `warmUp` and `persist` stay available for a
//! host that would rather drive both itself.

use std::sync::Arc;

use futures::lock::Mutex;
use futures::stream::{BoxStream, StreamExt};
use truapi_platform::{ChainProvider as _, JsonRpcConnection};
use wasm_bindgen::prelude::*;

use crate::config::ChainSource;
use crate::provider::{EmbeddedChainProvider, EmbeddedChainProviderBuilder};

/// Route the embedded provider's (and smoldot's) `tracing` output to the
/// browser console at `level` (`error`|`warn`|`info`|`debug`|`trace`; anything
/// else disables it). Installs the console subscriber on the first call and is
/// safe to call again at any time to retune verbosity.
#[wasm_bindgen(js_name = setLogLevel)]
pub fn set_log_level(level: &str) {
    crate::logging::set_level_from_str(level);
}

/// Collects genesis-hash to chain-source registrations from JS.
#[wasm_bindgen]
pub struct ChainProviderBuilder {
    inner: Option<EmbeddedChainProviderBuilder>,
    /// Whether the host answered the warm-store question itself, either with a
    /// store of its own or by turning warm start off.
    #[cfg(feature = "smoldot")]
    warm_store_chosen: bool,
}

#[wasm_bindgen]
impl ChainProviderBuilder {
    /// Create an empty builder.
    #[wasm_bindgen(constructor)]
    pub fn new() -> Self {
        ChainProviderBuilder {
            inner: Some(EmbeddedChainProviderBuilder::new()),
            #[cfg(feature = "smoldot")]
            warm_store_chosen: false,
        }
    }

    /// Register a remote JSON-RPC node for the chain identified by the
    /// `0x`-prefixed genesis hash. A later registration for the same hash
    /// replaces the earlier one.
    #[wasm_bindgen(js_name = addRpcChain)]
    pub fn add_rpc_chain(&mut self, genesis_hash: &str, url: &str) -> Result<(), JsError> {
        let genesis = parse_genesis(genesis_hash)?;
        let url =
            url::Url::parse(url).map_err(|err| JsError::new(&format!("invalid URL: {err}")))?;
        let builder = self
            .inner
            .take()
            .ok_or_else(|| JsError::new("builder was already consumed by build()"))?;
        self.inner = Some(builder.chain(genesis, ChainSource::rpc_node(url)));
        Ok(())
    }

    /// Register an embedded light-client chain identified by the
    /// `0x`-prefixed genesis hash. Use this for a relay or standalone chain;
    /// parachains are served through the bundled catalog (`addNetwork`), which
    /// supplies their relay wiring and statement-store placement.
    #[cfg(feature = "smoldot")]
    #[wasm_bindgen(js_name = addLightChain)]
    pub fn add_light_chain(
        &mut self,
        genesis_hash: &str,
        specification: String,
    ) -> Result<(), JsError> {
        let genesis = parse_genesis(genesis_hash)?;
        let source = ChainSource::light_client(specification);
        let builder = self
            .inner
            .take()
            .ok_or_else(|| JsError::new("builder was already consumed by build()"))?;
        self.inner = Some(builder.chain(genesis, source.build()));
        Ok(())
    }

    /// Seed a warm-start database blob (from
    /// [`snapshot`](ChainProviderHandle::snapshot)) for the `0x`-prefixed
    /// genesis hash, so its light client resumes from that finalized state
    /// instead of re-syncing from the checkpoint.
    #[cfg(feature = "smoldot")]
    #[wasm_bindgen(js_name = setDatabase)]
    pub fn set_database(&mut self, genesis_hash: &str, blob: String) -> Result<(), JsError> {
        let genesis = parse_genesis(genesis_hash)?;
        let builder = self
            .inner
            .take()
            .ok_or_else(|| JsError::new("builder was already consumed by build()"))?;
        self.inner = Some(builder.database(genesis, blob));
        Ok(())
    }

    /// Keep warm-start blobs somewhere other than the browser's own database,
    /// or nowhere at all.
    ///
    /// Warm start needs no setup: without this call the provider keeps blobs in
    /// IndexedDB for the origin. Pass a JS object with `load(genesisHash)`
    /// resolving to the stored string or `null` and `save(genesisHash, blob)`
    /// to store them elsewhere, or `null` to turn warm start off and have every
    /// chain sync from the chain-spec checkpoint.
    ///
    /// A store that cannot answer must reject rather than resolve empty: an
    /// empty read is taken as nothing stored yet, and would let a later
    /// snapshot overwrite good state.
    ///
    /// A loaded blob is trusted input: it becomes the finalized state the light
    /// client resumes from, so whatever can write to the store can steer the
    /// client's view of the chain. Origin-scoped storage satisfies that; a
    /// store fed by another page or a server does not.
    #[cfg(feature = "smoldot")]
    #[wasm_bindgen(js_name = setWarmStore)]
    pub fn set_warm_store(&mut self, store: JsValue) -> Result<(), JsError> {
        self.warm_store_chosen = true;
        if store.is_null() || store.is_undefined() {
            return Ok(());
        }
        let store = JsWarmStore::new(store)?;
        let builder = self
            .inner
            .take()
            .ok_or_else(|| JsError::new("builder was already consumed by build()"))?;
        self.inner = Some(builder.warm_store(std::sync::Arc::new(store)));
        Ok(())
    }

    /// Register every chain of the bundled network `name` (relay plus system
    /// parachains, with relay wiring and statement-store placement supplied by
    /// the catalog). Returns the network's genesis hashes.
    #[cfg(feature = "networks")]
    #[wasm_bindgen(js_name = addNetwork)]
    pub fn add_network(&mut self, name: &str) -> Result<NetworkChains, JsError> {
        let builder = self
            .inner
            .take()
            .ok_or_else(|| JsError::new("builder was already consumed by build()"))?;
        let (builder, chains) = builder
            .add_network(name)
            .map_err(|err| JsError::new(&err.reason))?;
        self.inner = Some(builder);
        Ok(NetworkChains {
            relay: hex0x(&chains.relay),
            assethub: hex0x(&chains.assethub),
            bulletin: hex0x(&chains.bulletin),
            people: hex0x(&chains.people),
        })
    }

    /// Build the provider, consuming the builder.
    ///
    /// Unless the host chose otherwise through
    /// [`set_warm_store`](Self::set_warm_store), chains resume from state kept
    /// in the browser's own database.
    pub fn build(&mut self) -> Result<ChainProviderHandle, JsError> {
        #[allow(unused_mut)]
        let mut builder = self
            .inner
            .take()
            .ok_or_else(|| JsError::new("builder was already consumed by build()"))?;
        #[cfg(feature = "smoldot")]
        if !self.warm_store_chosen {
            builder = builder.warm_store(std::sync::Arc::new(
                crate::warm_start_web::IndexedDbWarmStore,
            ));
        }
        Ok(ChainProviderHandle {
            inner: Arc::new(builder.build()),
            #[cfg(feature = "smoldot")]
            persisting: Arc::new(std::sync::Mutex::new(std::collections::HashSet::new())),
        })
    }
}

impl Default for ChainProviderBuilder {
    /// Same as [`ChainProviderBuilder::new`]: an empty builder.
    fn default() -> Self {
        Self::new()
    }
}

/// How long a chain runs before its first snapshot. A chain that has finalized
/// nothing yet has nothing worth storing, and asking costs a round trip.
#[cfg(feature = "smoldot")]
const FIRST_SNAPSHOT_DELAY: core::time::Duration = core::time::Duration::from_secs(30);

/// Gap between snapshots after the first.
#[cfg(feature = "smoldot")]
const SNAPSHOT_INTERVAL: core::time::Duration = core::time::Duration::from_secs(60);

/// A built provider; hand out one per page/worker.
#[wasm_bindgen]
pub struct ChainProviderHandle {
    inner: Arc<EmbeddedChainProvider>,
    /// Chains already being snapshotted, so repeated connects to one chain do
    /// not each start their own loop.
    #[cfg(feature = "smoldot")]
    persisting: Arc<std::sync::Mutex<std::collections::HashSet<[u8; 32]>>>,
}

#[cfg(feature = "smoldot")]
impl ChainProviderHandle {
    /// Keep `genesis`'s finalized state in the warm store from now on, once per
    /// chain. Does nothing when the provider was built without a store.
    ///
    /// The loop holds a weak reference and drops it before each wait, so it
    /// stops on its own once JS releases the provider rather than keeping it
    /// alive for the life of the page.
    fn start_persistence(&self, genesis: [u8; 32]) {
        if !self.inner.has_warm_store() {
            return;
        }
        {
            let mut persisting = self
                .persisting
                .lock()
                .unwrap_or_else(std::sync::PoisonError::into_inner);
            if !persisting.insert(genesis) {
                return;
            }
        }

        let provider = Arc::downgrade(&self.inner);
        let persisting = Arc::clone(&self.persisting);
        wasm_bindgen_futures::spawn_local(async move {
            futures_timer::Delay::new(FIRST_SNAPSHOT_DELAY).await;
            loop {
                let Some(strong) = provider.upgrade() else {
                    break;
                };
                // Snapshotting a chain nobody holds open would start one just
                // to photograph it, every tick, for the life of the provider.
                if !strong.is_connected(genesis) {
                    break;
                }
                if let Err(error) = strong.persist(genesis).await {
                    tracing::warn!(
                        genesis = %hex0x(&genesis),
                        reason = %error.reason,
                        "could not store finalized state"
                    );
                }
                // Before the wait, so an idle loop does not keep the provider
                // alive after JS has let go of it.
                drop(strong);
                futures_timer::Delay::new(SNAPSHOT_INTERVAL).await;
            }
            persisting
                .lock()
                .unwrap_or_else(std::sync::PoisonError::into_inner)
                .remove(&genesis);
        });
    }
}

#[wasm_bindgen]
impl ChainProviderHandle {
    /// Open a connection to the chain identified by the `0x`-prefixed genesis
    /// hash. Rejects when the chain is not registered or the transport fails.
    pub async fn connect(&self, genesis_hash: &str) -> Result<Connection, JsError> {
        let genesis = parse_genesis(genesis_hash)?;
        // Warm start is an optimisation, so a store that cannot answer leaves
        // the chain to sync from the checkpoint rather than failing the connect.
        // A host that turned warm start off is not asked at all, and neither is
        // a chain that is already up, whose blob smoldot would discard anyway.
        #[cfg(feature = "smoldot")]
        if self.inner.has_warm_store()
            && !self.inner.is_connected(genesis)
            && let Err(error) = self.inner.warm_up(genesis).await
        {
            tracing::warn!(
                reason = %error.reason,
                "warm store unavailable; syncing from the chain-spec checkpoint"
            );
        }
        let connection = self
            .inner
            .connect(genesis)
            .await
            .map_err(|err| JsError::new(&err.reason))?;
        #[cfg(feature = "smoldot")]
        {
            // The relay a parachain syncs through is the chain that actually
            // warp syncs, so it is kept warm alongside it.
            if let Some(relay) = self.inner.relay_of(genesis) {
                self.start_persistence(relay);
            }
            self.start_persistence(genesis);
        }
        let responses = connection.responses();
        Ok(Connection {
            inner: Arc::from(connection),
            responses: Arc::new(Mutex::new(responses)),
        })
    }

    /// Read the warm store's blob for the `0x`-prefixed genesis hash into this
    /// provider, so the next [`connect`](ChainProviderHandle::connect) to that
    /// chain resumes from it. Resolves with whether a blob is now in hand.
    ///
    /// Call this before connecting. The store is read at most once per chain,
    /// because only a chain's first add consumes a blob.
    #[cfg(feature = "smoldot")]
    #[wasm_bindgen(js_name = warmUp)]
    pub async fn warm_up(&self, genesis_hash: &str) -> Result<bool, JsError> {
        let genesis = parse_genesis(genesis_hash)?;
        self.inner
            .warm_up(genesis)
            .await
            .map_err(|err| JsError::new(&err.reason))
    }

    /// Snapshot the chain's finalized state and write it to the warm store.
    /// Resolves with whether a blob was stored.
    ///
    /// A chain that has finalized nothing yet is skipped rather than stored,
    /// since that blob would be discarded on the next run. This is a full round
    /// trip against the light client, so drive it while the page or worker is
    /// alive; neither `pagehide` nor a hidden tab is guaranteed to stay
    /// scheduled long enough to finish one, and a Worker sees neither event.
    #[cfg(feature = "smoldot")]
    pub async fn persist(&self, genesis_hash: &str) -> Result<bool, JsError> {
        let genesis = parse_genesis(genesis_hash)?;
        self.inner
            .persist(genesis)
            .await
            .map_err(|err| JsError::new(&err.reason))
    }

    /// Produce a warm-start database blob for the `0x`-prefixed genesis hash.
    /// Persist it and feed it back via
    /// [`setDatabase`](ChainProviderBuilder::set_database) on a later run.
    #[cfg(feature = "smoldot")]
    pub async fn snapshot(&self, genesis_hash: &str) -> Result<String, JsError> {
        let genesis = parse_genesis(genesis_hash)?;
        self.inner
            .snapshot(genesis)
            .await
            .map_err(|err| JsError::new(&err.reason))
    }
}

/// A live JSON-RPC connection: a raw string pipe.
#[wasm_bindgen]
pub struct Connection {
    inner: Arc<dyn JsonRpcConnection>,
    responses: Arc<Mutex<BoxStream<'static, String>>>,
}

#[wasm_bindgen]
impl Connection {
    /// Queue a JSON-RPC request string.
    pub fn send(&self, request: String) {
        self.inner.send(request);
    }

    /// Resolve with the next JSON-RPC response or notification, or
    /// `undefined` once the connection is closed or dead.
    ///
    /// Calling this in a loop is not optional: it is the only thing that drains
    /// the connection. Frames queue until they are taken, and once the backlog
    /// reaches the connection's budget further [`send`](Connection::send) calls
    /// come back as JSON-RPC errors instead of being queued, so a caller that
    /// sends without reading eventually gets nothing but errors.
    #[wasm_bindgen(js_name = nextResponse)]
    pub async fn next_response(&self) -> Option<String> {
        let responses = Arc::clone(&self.responses);
        let mut responses = responses.lock().await;
        responses.next().await
    }

    /// Close the connection; pending `nextResponse()` calls resolve to
    /// `undefined`.
    pub fn close(&self) {
        self.inner.close();
    }
}

/// The genesis hashes of a network registered via
/// [`ChainProviderBuilder::add_network`], as `0x`-prefixed hex strings.
#[cfg(feature = "networks")]
#[wasm_bindgen]
pub struct NetworkChains {
    relay: String,
    assethub: String,
    bulletin: String,
    people: String,
}

#[cfg(feature = "networks")]
#[wasm_bindgen]
impl NetworkChains {
    /// Relay-chain genesis hash.
    #[wasm_bindgen(getter)]
    pub fn relay(&self) -> String {
        self.relay.clone()
    }

    /// Asset Hub genesis hash.
    #[wasm_bindgen(getter)]
    pub fn assethub(&self) -> String {
        self.assethub.clone()
    }

    /// Bulletin-chain genesis hash.
    #[wasm_bindgen(getter)]
    pub fn bulletin(&self) -> String {
        self.bulletin.clone()
    }

    /// People-chain genesis hash.
    #[wasm_bindgen(getter)]
    pub fn people(&self) -> String {
        self.people.clone()
    }
}

#[cfg(any(feature = "networks", feature = "smoldot"))]
fn hex0x(bytes: &[u8; 32]) -> String {
    format!("0x{}", hex::encode(bytes))
}

/// A [`WarmStore`](crate::warm_start::WarmStore) over a JS object's `load` and
/// `save` methods.
///
/// The JS values are held in a `SendWrapper` because the trait is `Send`, and
/// every call crosses back to Rust through a oneshot channel rather than
/// awaiting the promise in place: a `JsFuture` is not `Send` and could not be
/// held across the trait method's await point.
#[cfg(feature = "smoldot")]
struct JsWarmStore {
    inner: send_wrapper::SendWrapper<JsStoreMethods>,
}

/// The JS object and the two functions taken from it at registration time.
#[cfg(feature = "smoldot")]
struct JsStoreMethods {
    store: JsValue,
    load: js_sys::Function,
    save: js_sys::Function,
}

#[cfg(feature = "smoldot")]
impl JsWarmStore {
    /// Take `load` and `save` off `store`, failing if either is missing.
    fn new(store: JsValue) -> Result<Self, JsError> {
        let load = Self::method(&store, "load")?;
        let save = Self::method(&store, "save")?;
        Ok(Self {
            inner: send_wrapper::SendWrapper::new(JsStoreMethods { store, load, save }),
        })
    }

    /// Read one function property off the store object.
    fn method(store: &JsValue, name: &str) -> Result<js_sys::Function, JsError> {
        js_sys::Reflect::get(store, &JsValue::from_str(name))
            .map_err(|_| JsError::new(&format!("warm store has no `{name}`")))?
            .dyn_into::<js_sys::Function>()
            .map_err(|_| JsError::new(&format!("warm store `{name}` is not a function")))
    }
}

/// Await `call`'s result on the JS event loop, reporting it through a `Send`
/// channel the caller can hold across its own await point.
#[cfg(feature = "smoldot")]
fn await_js(
    call: Result<JsValue, JsValue>,
) -> futures::channel::oneshot::Receiver<Result<JsValue, String>> {
    let (sender, receiver) = futures::channel::oneshot::channel();
    match call {
        Ok(value) => {
            let promise = js_sys::Promise::resolve(&value);
            wasm_bindgen_futures::spawn_local(async move {
                let outcome = wasm_bindgen_futures::JsFuture::from(promise)
                    .await
                    .map_err(|error| describe_js(&error));
                let _ = sender.send(outcome);
            });
        }
        Err(error) => {
            let _ = sender.send(Err(describe_js(&error)));
        }
    }
    receiver
}

/// Render a thrown JS value for an error message.
#[cfg(feature = "smoldot")]
fn describe_js(error: &JsValue) -> String {
    error
        .as_string()
        .unwrap_or_else(|| format!("{:?}", js_sys::Object::from(error.clone())))
}

#[cfg(feature = "smoldot")]
#[truapi_platform::async_trait]
impl crate::warm_start::WarmStore for JsWarmStore {
    async fn load(
        &self,
        genesis_hash: [u8; 32],
    ) -> Result<Option<String>, crate::warm_start::WarmStoreError> {
        let receiver = {
            let methods = &*self.inner;
            await_js(
                methods
                    .load
                    .call1(&methods.store, &JsValue::from_str(&hex0x(&genesis_hash))),
            )
        };
        let value = receiver
            .await
            .map_err(|_| crate::warm_start::WarmStoreError::new("the warm store never answered"))?
            .map_err(crate::warm_start::WarmStoreError::new)?;
        Ok(value.as_string())
    }

    async fn save(
        &self,
        genesis_hash: [u8; 32],
        blob: String,
    ) -> Result<(), crate::warm_start::WarmStoreError> {
        let receiver = {
            let methods = &*self.inner;
            await_js(methods.save.call2(
                &methods.store,
                &JsValue::from_str(&hex0x(&genesis_hash)),
                &JsValue::from_str(&blob),
            ))
        };
        receiver
            .await
            .map_err(|_| crate::warm_start::WarmStoreError::new("the warm store never answered"))?
            .map_err(crate::warm_start::WarmStoreError::new)?;
        Ok(())
    }
}

fn parse_genesis(hex_str: &str) -> Result<[u8; 32], JsError> {
    hex::decode(hex_str.trim_start_matches("0x"))
        .map_err(|err| JsError::new(&format!("invalid genesis hash hex: {err}")))?
        .try_into()
        .map_err(|_| JsError::new("genesis hashes are 32 bytes"))
}
