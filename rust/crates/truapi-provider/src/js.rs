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
//! Warm start is opt-in and the crate stores nothing: hand `setStorage` a client
//! to storage the host owns and the blob for a chain is read before its first connect,
//! then written back on a schedule the provider sets. `saveDatabase` forces a write at
//! a moment the host chooses.

use std::sync::Arc;

use futures::lock::Mutex;
use futures::stream::{BoxStream, StreamExt};
use truapi_platform::{ChainProvider as _, JsonRpcConnection};
use wasm_bindgen::prelude::*;

use crate::config::ChainSource;
use crate::provider::{EmbeddedChainProvider, EmbeddedChainProviderBuilder};

/// Lock a mutex, recovering the guard if a previous holder panicked.
#[cfg(feature = "smoldot")]
fn lock<T>(mutex: &std::sync::Mutex<T>) -> std::sync::MutexGuard<'_, T> {
    mutex
        .lock()
        .unwrap_or_else(std::sync::PoisonError::into_inner)
}

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
}

#[wasm_bindgen]
impl ChainProviderBuilder {
    /// Create an empty builder.
    #[wasm_bindgen(constructor)]
    pub fn new() -> Self {
        ChainProviderBuilder {
            inner: Some(EmbeddedChainProviderBuilder::new()),
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

    /// Seed the chain with the `0x`-prefixed genesis hash from a stored
    /// database blob, so its light client resumes from that finalized state
    /// instead of syncing from the chain-spec checkpoint.
    ///
    /// The blob is the string the `chainHead_unstable_finalizedDatabase` function in smoldot
    /// produces. It seeds this run only, and beats anything
    /// [`set_storage`](Self::set_storage) would load for the same chain.
    #[cfg(feature = "smoldot")]
    #[wasm_bindgen(js_name = setDatabaseContent)]
    pub fn set_database_content(
        &mut self,
        genesis_hash: &str,
        blob: String,
    ) -> Result<(), JsError> {
        let genesis = parse_genesis(genesis_hash)?;
        let builder = self
            .inner
            .take()
            .ok_or_else(|| JsError::new("builder was already consumed by build()"))?;
        self.inner = Some(builder.database(genesis, blob));
        Ok(())
    }

    /// Keep database blobs in storage the host owns.
    ///
    /// The crate stores nothing itself, so without this call every chain syncs
    /// from the chain-spec checkpoint on every run. Pass a JS object with
    /// `load(genesisHash)` resolving to the stored string or `null`, and
    /// `save(genesisHash, blob)`. Both are called with a `0x`-prefixed hex
    /// genesis hash and may return a promise. Passing `null` does nothing.
    ///
    /// A blob seeded through
    /// [`set_database_content`](Self::set_database_content) beats one loaded
    /// here for the same chain.
    ///
    /// A store that cannot answer must reject rather than resolve empty: an
    /// empty read is taken as nothing stored yet, and would let a later
    /// snapshot overwrite good state.
    ///
    /// A loaded blob is trusted input: it becomes the finalized state the light
    /// client resumes from, so whatever can write to the store can steer the
    /// view of the chain. Origin-scoped storage satisfies that. A store fed by
    /// another page or a server does not.
    #[cfg(feature = "smoldot")]
    #[wasm_bindgen(js_name = setStorage)]
    pub fn set_storage(&mut self, client: JsValue) -> Result<(), JsError> {
        if client.is_null() || client.is_undefined() {
            return Ok(());
        }
        let store = HostStorageClient::new(client)?;
        let builder = self
            .inner
            .take()
            .ok_or_else(|| JsError::new("builder was already consumed by build()"))?;
        self.inner = Some(builder.storage(std::sync::Arc::new(store)));
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
    pub fn build(&mut self) -> Result<ChainProviderHandle, JsError> {
        let builder = self
            .inner
            .take()
            .ok_or_else(|| JsError::new("builder was already consumed by build()"))?;
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

/// Gap between the first snapshots. Doubles up to [`SNAPSHOT_INTERVAL_MAX`],
/// because the finalized state of a chain stops being newsworthy long before the
/// snapshot stops costing a round trip and a multi-megabyte write.
#[cfg(feature = "smoldot")]
const SNAPSHOT_INTERVAL: core::time::Duration = core::time::Duration::from_secs(60);

/// Longest gap the backoff reaches.
#[cfg(feature = "smoldot")]
const SNAPSHOT_INTERVAL_MAX: core::time::Duration = core::time::Duration::from_secs(600);

/// How long storage gets to answer before a chain gives up and syncs
/// from the chain-spec checkpoint. A host-supplied store is arbitrary JS whose
/// promise may never settle, and a stored blob must not be able to wedge a
/// connection that would otherwise work.
#[cfg(feature = "smoldot")]
const STORAGE_DEADLINE: core::time::Duration = core::time::Duration::from_secs(5);

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
    /// Keep the finalized state for `genesis` in storage from now on, once per
    /// chain. Does nothing when the provider was built without a store.
    ///
    /// The loop holds a weak reference and drops it before each wait, so it
    /// stops on its own once JS releases the provider rather than keeping it
    /// alive for the life of the page.
    fn start_persistence(&self, genesis: [u8; 32]) {
        if !self.inner.has_storage() {
            return;
        }
        if !lock(&self.persisting).insert(genesis) {
            return;
        }

        let provider = Arc::downgrade(&self.inner);
        let persisting = Arc::clone(&self.persisting);
        wasm_bindgen_futures::spawn_local(async move {
            futures_timer::Delay::new(FIRST_SNAPSHOT_DELAY).await;
            let mut interval = SNAPSHOT_INTERVAL;
            loop {
                let Some(strong) = provider.upgrade() else {
                    break;
                };
                // Snapshotting a chain nobody holds open would start one just
                // to photograph it, every tick, for the life of the provider.
                if !strong.is_connected(genesis) {
                    break;
                }
                if let Err(error) = strong.save_database(genesis).await {
                    tracing::warn!(
                        genesis = %hex0x(&genesis),
                        reason = %error.reason,
                        "could not store finalized state"
                    );
                }
                // Before the wait, so an idle loop does not keep the provider
                // alive after JS has let go of it.
                drop(strong);
                // Freed before the wait, so a reconnect arriving mid-sleep can
                // start a fresh loop rather than finding the slot still taken.
                lock(&persisting).remove(&genesis);
                futures_timer::Delay::new(interval).await;
                interval = (interval * 2).min(SNAPSHOT_INTERVAL_MAX);
                if !lock(&persisting).insert(genesis) {
                    // Something else took the chain over while this loop slept.
                    return;
                }
            }
            lock(&persisting).remove(&genesis);
        });
    }
}

#[wasm_bindgen]
impl ChainProviderHandle {
    /// Open a connection to the chain identified by the `0x`-prefixed genesis
    /// hash. Rejects when the chain is not registered or the transport fails.
    pub async fn connect(&self, genesis_hash: &str) -> Result<Connection, JsError> {
        let genesis = parse_genesis(genesis_hash)?;
        // Stored state is an optimisation, so storage that cannot answer leaves
        // the chain to sync from the checkpoint rather than failing the connect.
        // A host that supplied no storage is not asked at all, and neither is
        // a chain that is already up, whose blob smoldot would discard anyway.
        #[cfg(feature = "smoldot")]
        if self.inner.has_storage() && !self.inner.is_connected(genesis) {
            let deadline = futures_timer::Delay::new(STORAGE_DEADLINE);
            futures::pin_mut!(deadline);
            match futures::future::select(
                core::pin::pin!(self.inner.load_database(genesis)),
                deadline,
            )
            .await
            {
                futures::future::Either::Left((Err(error), _)) => tracing::warn!(
                    reason = %error.reason,
                    "storage unavailable, syncing from the chain-spec checkpoint"
                ),
                futures::future::Either::Left((Ok(_), _)) => {}
                futures::future::Either::Right(((), _)) => tracing::warn!(
                    "storage did not answer in {}s, syncing from the chain-spec checkpoint",
                    STORAGE_DEADLINE.as_secs()
                ),
            }
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

    /// Read the stored blob for the `0x`-prefixed genesis hash into this
    /// provider, so the next [`connect`](ChainProviderHandle::connect) to that
    /// chain resumes from it. Resolves with whether a blob is now in hand.
    ///
    /// Call this before connecting. The store is read at most once per chain,
    /// because only the first add of a chain consumes a blob.
    #[cfg(feature = "smoldot")]
    #[wasm_bindgen(js_name = loadDatabase)]
    pub async fn load_database(&self, genesis_hash: &str) -> Result<bool, JsError> {
        let genesis = parse_genesis(genesis_hash)?;
        self.inner
            .load_database(genesis)
            .await
            .map_err(|err| JsError::new(&err.reason))
    }

    /// Snapshot the finalized state of the chain and write it to storage.
    /// Resolves with whether a blob was stored.
    ///
    /// A chain that has finalized nothing yet is skipped rather than stored,
    /// since that blob would be discarded on the next run. This is a full round
    /// trip against the light client, so drive it while the page or worker is
    /// alive. Neither `pagehide` nor a hidden tab is guaranteed to stay
    /// scheduled long enough to finish one, and a Worker sees neither event.
    #[cfg(feature = "smoldot")]
    pub async fn save_database(&self, genesis_hash: &str) -> Result<bool, JsError> {
        let genesis = parse_genesis(genesis_hash)?;
        self.inner
            .save_database(genesis)
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
    /// reaches the budget for the connection further [`send`](Connection::send) calls
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
pub(crate) fn hex0x(bytes: &[u8; 32]) -> String {
    format!("0x{}", hex::encode(bytes))
}

/// A [`StorageClient`](crate::storage::StorageClient) over the `load` and
/// `save` methods.
///
/// The JS values are held in a `SendWrapper` because the trait is `Send`, and
/// every call crosses back to Rust through a oneshot channel rather than
/// awaiting the promise in place: a `JsFuture` is not `Send` and could not be
/// held across the await point in the trait method.
#[cfg(feature = "smoldot")]
struct HostStorageClient {
    inner: send_wrapper::SendWrapper<HostStorageMethods>,
}

/// The JS object and the two functions taken from it at registration time.
#[cfg(feature = "smoldot")]
struct HostStorageMethods {
    store: JsValue,
    load: js_sys::Function,
    save: js_sys::Function,
}

#[cfg(feature = "smoldot")]
impl HostStorageClient {
    /// Take `load` and `save` off `store`, failing if either is missing.
    fn new(store: JsValue) -> Result<Self, JsError> {
        let load = Self::method(&store, "load")?;
        let save = Self::method(&store, "save")?;
        Ok(Self {
            inner: send_wrapper::SendWrapper::new(HostStorageMethods { store, load, save }),
        })
    }

    /// Read one function property off the store object.
    fn method(store: &JsValue, name: &str) -> Result<js_sys::Function, JsError> {
        js_sys::Reflect::get(store, &JsValue::from_str(name))
            .map_err(|_| JsError::new(&format!("the storage client has no `{name}`")))?
            .dyn_into::<js_sys::Function>()
            .map_err(|_| JsError::new(&format!("the storage client `{name}` is not a function")))
    }
}

/// Await the result of `call` on the JS event loop, reporting it through a `Send`
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
impl crate::storage::StorageClient for HostStorageClient {
    async fn load(
        &self,
        genesis_hash: [u8; 32],
    ) -> Result<Option<String>, crate::storage::StorageClientError> {
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
            .map_err(|_| crate::storage::StorageClientError::new("the warm store never answered"))?
            .map_err(crate::storage::StorageClientError::new)?;
        Ok(value.as_string())
    }

    async fn save(
        &self,
        genesis_hash: [u8; 32],
        blob: String,
    ) -> Result<(), crate::storage::StorageClientError> {
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
            .map_err(|_| crate::storage::StorageClientError::new("the warm store never answered"))?
            .map_err(crate::storage::StorageClientError::new)?;
        Ok(())
    }
}

fn parse_genesis(hex_str: &str) -> Result<[u8; 32], JsError> {
    hex::decode(hex_str.trim_start_matches("0x"))
        .map_err(|err| JsError::new(&format!("invalid genesis hash hex: {err}")))?
        .try_into()
        .map_err(|_| JsError::new("genesis hashes are 32 bytes"))
}

#[cfg(test)]
mod tests {
    use wasm_bindgen_test::{wasm_bindgen_test, wasm_bindgen_test_configure};

    use super::*;

    wasm_bindgen_test_configure!(run_in_browser);

    /// A client whose `load` and `save` record what they were called with, so a
    /// test can prove the wasm boundary actually reaches the object the host passed.
    fn recording_client(calls: std::rc::Rc<std::cell::RefCell<Vec<String>>>) -> JsValue {
        let client = js_sys::Object::new();

        let load_calls = std::rc::Rc::clone(&calls);
        let load = Closure::<dyn FnMut(String) -> JsValue>::new(move |genesis: String| {
            load_calls.borrow_mut().push(format!("load {genesis}"));
            JsValue::from_str("stored-blob")
        });
        js_sys::Reflect::set(&client, &JsValue::from_str("load"), load.as_ref()).expect("set load");
        load.forget();

        let save_calls = std::rc::Rc::clone(&calls);
        let save =
            Closure::<dyn FnMut(String, String)>::new(move |genesis: String, blob: String| {
                save_calls
                    .borrow_mut()
                    .push(format!("save {genesis} {}", blob.len()));
            });
        js_sys::Reflect::set(&client, &JsValue::from_str("save"), save.as_ref()).expect("set save");
        save.forget();

        client.into()
    }

    /// The crate stores nothing, so a provider nobody gave storage to must say
    /// so rather than quietly never warming up.
    #[wasm_bindgen_test]
    async fn without_storage_the_database_calls_fail() {
        let mut builder = ChainProviderBuilder::new();
        let provider = builder.build().expect("an empty builder builds");
        let genesis = format!("0x{}", "11".repeat(32));

        assert!(
            provider.load_database(&genesis).await.is_err(),
            "loading needs somewhere to load from"
        );
        assert!(
            provider.save_database(&genesis).await.is_err(),
            "saving needs somewhere to save to"
        );
    }

    /// The client the host passed is reached across the wasm boundary, with the genesis
    /// hash it expects.
    #[wasm_bindgen_test]
    async fn the_host_client_is_called_with_the_genesis_hash() {
        let calls = std::rc::Rc::new(std::cell::RefCell::new(Vec::new()));
        let genesis = format!("0x{}", "22".repeat(32));

        let mut builder = ChainProviderBuilder::new();
        builder
            .set_storage(recording_client(std::rc::Rc::clone(&calls)))
            .expect("the client has load and save");
        let provider = builder.build().expect("builds");

        assert!(
            provider
                .load_database(&genesis)
                .await
                .expect("the client answers"),
            "the client returned a blob, so one is now in hand"
        );
        assert_eq!(calls.borrow().as_slice(), [format!("load {genesis}")]);
    }

    /// A seeded blob is used without consulting the client at all.
    #[wasm_bindgen_test]
    async fn a_seeded_blob_beats_the_client() {
        let calls = std::rc::Rc::new(std::cell::RefCell::new(Vec::new()));
        let genesis = format!("0x{}", "33".repeat(32));

        let mut builder = ChainProviderBuilder::new();
        builder
            .set_storage(recording_client(std::rc::Rc::clone(&calls)))
            .expect("the client has load and save");
        builder
            .set_database_content(&genesis, "seeded-blob".to_owned())
            .expect("the genesis parses");
        let provider = builder.build().expect("builds");

        assert!(provider.load_database(&genesis).await.expect("in hand"));
        assert!(
            calls.borrow().is_empty(),
            "a seeded blob is already in hand, so the client is never asked"
        );
    }
}
