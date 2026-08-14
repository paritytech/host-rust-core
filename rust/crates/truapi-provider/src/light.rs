//! Embedded smoldot light-client backend.
//!
//! One smoldot [`Client`] is shared per provider and created lazily on the
//! first light-client connect: the native platform spawns an OS thread pool,
//! while the wasm platform schedules on the JS event loop and dials peers
//! over the browser's `WebSocket`. Each connect adds the chain again: smoldot
//! deduplicates identical chains internally while giving every add its own
//! [`ChainId`], request queue, and response stream, which yields natural
//! per-connection isolation.
//!
//! Warm-start snapshots: take one with
//! [`EmbeddedChainProvider::snapshot`](crate::EmbeddedChainProvider::snapshot),
//! persist the returned string, and feed it back on a later run through
//! [`EmbeddedChainProviderBuilder::database`](crate::EmbeddedChainProviderBuilder::database),
//! which seeds a chain whether it is connected directly or brought up behind
//! one of its parachains.
//!
//! Observability: on native targets smoldot logs through the `log` crate. A
//! host that wants those lines in its `tracing` output should install a
//! `log`->`tracing` bridge (e.g. `tracing_log::LogTracer`); the provider does
//! not install a global logger of its own.

use core::num::{NonZero, NonZeroUsize};
use core::sync::atomic::{AtomicBool, AtomicUsize, Ordering};
use core::time::Duration;
use std::collections::HashMap;
use std::sync::{Arc, Mutex, MutexGuard, OnceLock, PoisonError};

use futures::channel::mpsc;
use futures::stream::{self, BoxStream, StreamExt};
use smoldot_light::{
    AddChainConfig, AddChainConfigJsonRpc, ChainId, Client, HandleRpcError, JsonRpcResponses,
    StatementProtocolConfig,
};
use truapi_platform::JsonRpcConnection;

use crate::config::ChainSource;
use crate::error::{ProviderError, synthetic_error_frame};

/// Lock a mutex, recovering the guard if a previous holder panicked.
///
/// The embedded light client is a single process-wide instance shared by every
/// connection, so one poisoning event must not brick all of them. smoldot's own
/// calls under this lock do not panic; this is defense-in-depth for the shared
/// singleton's blast radius.
fn lock<T>(mutex: &Mutex<T>) -> MutexGuard<'_, T> {
    mutex.lock().unwrap_or_else(PoisonError::into_inner)
}

/// The smoldot platform backing this target.
#[cfg(not(target_arch = "wasm32"))]
type Platform = Arc<smoldot_light::platform::DefaultPlatform>;
#[cfg(target_arch = "wasm32")]
type Platform = crate::light_platform_web::SubxtPlatform;

fn new_platform() -> Platform {
    #[cfg(not(target_arch = "wasm32"))]
    {
        smoldot_light::platform::DefaultPlatform::new(
            env!("CARGO_PKG_NAME").into(),
            env!("CARGO_PKG_VERSION").into(),
        )
    }
    #[cfg(target_arch = "wasm32")]
    {
        crate::light_platform_web::SubxtPlatform::new()
    }
}

/// Statement-store defaults mirroring smoldot's own example configuration.
const STATEMENT_MAX_SEEN: usize = 65_536;
const STATEMENT_FALSE_POSITIVE_RATE: f64 = 0.01;
const STATEMENT_AFFINITY_UPDATE_INTERVAL: Duration = Duration::from_secs(1);

/// JSON-RPC queue budgets declared to smoldot when adding a chain.
///
/// smoldot stores these but does not enforce the pending cap: its request queue
/// is `async_channel::unbounded()` and `queue_rpc_request` only fails when that
/// channel is closed, so `TooManyPendingRequests` never fires for capacity. A
/// caller that sends without draining [`JsonRpcConnection::responses`] therefore
/// grows the queue without limit, because smoldot's response channel is bounded
/// and its service stalls once the consumer stops reading. The bound is applied
/// here instead, by [`MAX_UNDELIVERED_FRAMES`].
const MAX_PENDING_REQUESTS: u32 = 1024;
const MAX_SUBSCRIPTIONS: u32 = 1024;

/// How many response frames may be waiting for the consumer before further
/// requests are refused, mirroring the bounded outbound buffer the WebSocket
/// backend uses.
///
/// Counts frames owed to the consumer, not requests in smoldot: each accepted
/// request and each synthesized error adds one, and every frame the consumer
/// takes removes one. Subscription notifications also decrement without a
/// matching request, so a subscription-heavy connection is allowed more than
/// this many requests in flight. That errs towards accepting traffic, and still
/// bounds the case this exists for, where nothing is drained at all.
const MAX_UNDELIVERED_FRAMES: usize = 1024;

struct LightInner {
    client: Client<Platform, ()>,
    /// Relay chains added implicitly to sync parachain connections, refcounted
    /// by the live parachain connections that named them. A relay is removed
    /// from the client when its last such connection closes.
    relays: HashMap<[u8; 32], RelayEntry>,
}

/// A shared implicit relay chain and how many live parachain connections use it.
struct RelayEntry {
    chain_id: ChainId,
    refcount: usize,
}

/// Lazily-started shared smoldot client owned by a provider.
pub(crate) struct LightState {
    inner: OnceLock<Arc<Mutex<LightInner>>>,
}

impl LightState {
    pub(crate) fn new() -> Self {
        LightState {
            inner: OnceLock::new(),
        }
    }

    fn inner(&self) -> &Arc<Mutex<LightInner>> {
        self.inner.get_or_init(|| {
            Arc::new(Mutex::new(LightInner {
                client: Client::new(new_platform()),
                relays: HashMap::new(),
            }))
        })
    }

    /// Number of implicit relay chains currently held.
    #[cfg(test)]
    pub(crate) fn relay_count(&self) -> usize {
        lock(self.inner()).relays.len()
    }

    /// Add `source` to the shared client as a [`JsonRpcConnection`]. For a
    /// parachain, `relay` carries its relay's genesis hash and resolved source.
    pub(crate) async fn connect(
        &self,
        source: &ChainSource,
        relay: Option<([u8; 32], ChainSource)>,
    ) -> Result<Box<dyn JsonRpcConnection>, ProviderError> {
        // `ChainSource` collapses to a single variant when only the smoldot
        // backend is enabled (e.g. the iOS build), making this match irrefutable.
        #[allow(irrefutable_let_patterns)]
        let ChainSource::LightClient {
            specification,
            database_content,
            statement_protocol,
        } = source
        else {
            return Err(ProviderError::Transport {
                reason: "light backend invoked with a non-light chain source".to_owned(),
            });
        };

        let inner = Arc::clone(self.inner());
        let mut guard = lock(&inner);

        let relay_genesis = relay.as_ref().map(|(genesis, _)| *genesis);
        let relay_id = match &relay {
            None => None,
            Some((genesis, relay_source)) => Some(add_relay(&mut guard, *genesis, relay_source)?),
        };

        let added = guard
            .client
            .add_chain(AddChainConfig {
                user_data: (),
                specification,
                database_content: database_content.as_deref().unwrap_or(""),
                potential_relay_chains: relay_id.into_iter(),
                json_rpc: AddChainConfigJsonRpc::Enabled {
                    max_pending_requests: NonZero::new(MAX_PENDING_REQUESTS)
                        .expect("budget is non-zero"),
                    max_subscriptions: MAX_SUBSCRIPTIONS,
                },
                statement_protocol_config: statement_protocol.then(statement_protocol_config),
            })
            .map_err(|err| ProviderError::AddChain {
                reason: err.to_string(),
            });

        // No connection is constructed on the error path, so nothing would ever
        // release the reference taken on the relay above (smoldot rejects the
        // add when the spec's relay does not match the one supplied).
        let success = match added {
            Ok(success) => success,
            Err(error) => {
                if let Some(genesis) = relay_genesis {
                    release_relay(&mut guard, genesis);
                }
                return Err(error);
            }
        };

        let responses = success
            .json_rpc_responses
            .expect("JSON-RPC was enabled for this chain");
        drop(guard);

        // `send` synthesizes an error onto this channel when smoldot rejects a
        // request, so a full queue fails the caller fast instead of hanging.
        let (errors_tx, errors_rx) = mpsc::unbounded();

        Ok(Box::new(LightConnection {
            inner,
            chain_id: success.chain_id,
            relay: relay_genesis,
            errors_tx,
            responses: Mutex::new(Some((responses, errors_rx))),
            undelivered: Arc::new(AtomicUsize::new(0)),
            closed: AtomicBool::new(false),
        }))
    }
}

/// Add the relay chain for a parachain entry, reusing an already-added one and
/// taking a reference on it for the calling connection.
///
/// The relay is added with JSON-RPC disabled: it exists only so the parachain
/// can sync, and a direct connection to the relay genesis goes through its own
/// registry entry.
fn add_relay(
    guard: &mut LightInner,
    relay_genesis: [u8; 32],
    relay_source: &ChainSource,
) -> Result<ChainId, ProviderError> {
    if let Some(existing) = guard.relays.get_mut(&relay_genesis) {
        existing.refcount += 1;
        return Ok(existing.chain_id);
    }

    // `ChainSource` collapses to a single variant when only the smoldot backend
    // is enabled, making this match irrefutable.
    #[allow(irrefutable_let_patterns)]
    let ChainSource::LightClient {
        specification,
        database_content,
        statement_protocol,
        ..
    } = relay_source
    else {
        return Err(ProviderError::UnknownRelay {
            relay: relay_genesis,
        });
    };

    let success = guard
        .client
        .add_chain(AddChainConfig {
            user_data: (),
            specification,
            database_content: database_content.as_deref().unwrap_or(""),
            potential_relay_chains: core::iter::empty(),
            json_rpc: AddChainConfigJsonRpc::Disabled,
            statement_protocol_config: statement_protocol.then(statement_protocol_config),
        })
        .map_err(|err| ProviderError::AddChain {
            reason: err.to_string(),
        })?;

    guard.relays.insert(
        relay_genesis,
        RelayEntry {
            chain_id: success.chain_id,
            refcount: 1,
        },
    );
    Ok(success.chain_id)
}

/// Drop one reference on the implicit relay `relay_genesis`, removing it from
/// the client once the last parachain connection using it is gone.
///
/// Callers must have already removed (or never added) the parachain chain that
/// held the reference, so no live chain still depends on the relay.
fn release_relay(guard: &mut LightInner, relay_genesis: [u8; 32]) {
    let orphaned = match guard.relays.get_mut(&relay_genesis) {
        Some(entry) => {
            entry.refcount -= 1;
            (entry.refcount == 0).then_some(entry.chain_id)
        }
        None => None,
    };
    if let Some(relay_id) = orphaned {
        guard.relays.remove(&relay_genesis);
        let _: () = guard.client.remove_chain(relay_id);
    }
}

fn statement_protocol_config() -> StatementProtocolConfig {
    StatementProtocolConfig::new(
        NonZeroUsize::new(STATEMENT_MAX_SEEN).expect("budget is non-zero"),
        STATEMENT_FALSE_POSITIVE_RATE,
        statement_seed(),
        STATEMENT_AFFINITY_UPDATE_INTERVAL,
    )
}

/// Random bloom-filter seed from the target's entropy source.
fn statement_seed() -> u128 {
    #[cfg(not(target_arch = "wasm32"))]
    {
        rand::random()
    }
    #[cfg(target_arch = "wasm32")]
    {
        let mut bytes = [0u8; 16];
        getrandom::getrandom(&mut bytes).expect("the browser provides entropy");
        u128::from_le_bytes(bytes)
    }
}

/// One added smoldot chain exposed as a raw JSON-RPC pipe.
struct LightConnection {
    inner: Arc<Mutex<LightInner>>,
    chain_id: ChainId,
    /// Genesis of the implicit relay this connection holds a reference on, if
    /// it is a parachain; released on close.
    relay: Option<[u8; 32]>,
    /// Synthetic JSON-RPC error frames for requests smoldot rejected, merged
    /// into [`responses`](Self::responses) so the caller fails fast.
    errors_tx: mpsc::UnboundedSender<String>,
    /// Taken once by `responses()`: smoldot's response stream paired with the
    /// receiver for `errors_tx`.
    responses: Mutex<Option<(JsonRpcResponses<Platform>, mpsc::UnboundedReceiver<String>)>>,
    /// Frames owed to the consumer, bounded by [`MAX_UNDELIVERED_FRAMES`].
    undelivered: Arc<AtomicUsize>,
    closed: AtomicBool,
}

/// Decrement `counter` unless it is already zero.
///
/// Subscription notifications arrive without a matching request, so a plain
/// `fetch_sub` would wrap past zero and, being a `usize`, land on a value that
/// refuses every later request. Written as a compare-exchange loop because the
/// saturating helper on atomics is nightly-only.
fn decrement_saturating(counter: &AtomicUsize) {
    let mut current = counter.load(Ordering::Acquire);
    while current > 0 {
        match counter.compare_exchange_weak(
            current,
            current - 1,
            Ordering::AcqRel,
            Ordering::Acquire,
        ) {
            Ok(_) => return,
            Err(actual) => current = actual,
        }
    }
}

impl LightConnection {
    /// Refuse `request` with a synthetic error frame, keeping the connection
    /// alive. The consumer correlates by id, so a dropped request without a
    /// frame for its id would leave it waiting forever.
    fn refuse(&self, request: &str, reason: &str) {
        tracing::warn!(reason, "refusing a light-client request");
        if let Some(frame) = synthetic_error_frame(request, reason) {
            self.undelivered.fetch_add(1, Ordering::AcqRel);
            let _ = self.errors_tx.unbounded_send(frame);
        }
    }
}

impl JsonRpcConnection for LightConnection {
    fn send(&self, request: String) {
        // The chain-removal check and the request must happen under the same
        // lock: json_rpc_request panics on a removed ChainId.
        let mut guard = lock(&self.inner);
        if self.closed.load(Ordering::SeqCst) {
            return;
        }

        // smoldot would queue this without limit, so the backpressure is ours to
        // apply: a consumer that stops reading stops being sent work.
        if self.undelivered.load(Ordering::Acquire) >= MAX_UNDELIVERED_FRAMES {
            drop(guard);
            self.refuse(&request, "light client response queue full");
            return;
        }

        self.undelivered.fetch_add(1, Ordering::AcqRel);
        if let Err(HandleRpcError::TooManyPendingRequests { json_rpc_request }) =
            guard.client.json_rpc_request(request, self.chain_id)
        {
            // Not reachable while the chain is live (smoldot's queue is
            // unbounded), but it owes the caller a frame either way.
            drop(guard);
            self.undelivered.fetch_sub(1, Ordering::AcqRel);
            self.refuse(&json_rpc_request, "light client request queue full");
        }
    }

    fn responses(&self) -> BoxStream<'static, String> {
        match lock(&self.responses).take() {
            Some((responses, errors)) => {
                let responses = stream::unfold(responses, |mut responses| async move {
                    responses.next().await.map(|item| (item, responses))
                });
                let undelivered = Arc::clone(&self.undelivered);
                stream::select(responses, errors)
                    .inspect(move |_| decrement_saturating(&undelivered))
                    .boxed()
            }
            None => stream::empty().boxed(),
        }
    }

    fn close(&self) {
        let mut guard = lock(&self.inner);
        if self.closed.swap(true, Ordering::SeqCst) {
            return;
        }
        // Removal makes JsonRpcResponses::next() return None; closing the error
        // channel ends its half of the merged stream, so `responses()`
        // terminates cleanly.
        let _: () = guard.client.remove_chain(self.chain_id);

        // This connection's own chain is already removed above, so no live chain
        // still depends on the relay it held a reference on.
        if let Some(relay_genesis) = self.relay {
            release_relay(&mut guard, relay_genesis);
        }

        self.errors_tx.close_channel();
    }
}

impl Drop for LightConnection {
    fn drop(&mut self) {
        self.close();
    }
}

#[cfg(test)]
mod tests {
    use std::sync::Arc;

    use futures::executor::block_on;
    use futures::stream::StreamExt;
    use truapi_platform::ChainProvider;

    use crate::{ChainSource, EmbeddedChainProvider};

    /// Real relay-chain spec (checkpoint included) vendored from smoldot's
    /// demo specs: `add_chain` and spec-local JSON-RPC queries succeed without
    /// any network access.
    const RELAY_SPEC: &str = include_str!("../tests/fixtures/paseo.json");

    /// Parachain of [`RELAY_SPEC`], used to exercise the relay-add path.
    const PARACHAIN_SPEC: &str = include_str!("../tests/fixtures/paseo_people.json");

    const RELAY_GENESIS: [u8; 32] = [1; 32];
    const PARACHAIN_GENESIS: [u8; 32] = [2; 32];

    fn offline_provider() -> EmbeddedChainProvider {
        EmbeddedChainProvider::builder()
            .chain(RELAY_GENESIS, ChainSource::light_client(RELAY_SPEC).build())
            .build()
    }

    #[test]
    fn garbage_chain_spec_is_an_error() {
        let provider = EmbeddedChainProvider::builder()
            .chain(
                [1; 32],
                ChainSource::light_client("not a chain spec").build(),
            )
            .build();
        let error = block_on(provider.connect([1; 32]))
            .err()
            .expect("a malformed chain spec must fail to connect");
        assert!(error.reason.contains("failed to add a chain"));
    }

    #[test]
    fn unknown_relay_is_an_error() {
        let provider = EmbeddedChainProvider::builder()
            .parachain(
                RELAY_GENESIS,
                ChainSource::light_client(RELAY_SPEC).build(),
                [9; 32],
            )
            .build();
        let error = block_on(provider.connect(RELAY_GENESIS))
            .err()
            .expect("an unregistered relay must fail to connect");
        assert!(error.reason.contains("not a registered light-client chain"));
    }

    #[test]
    fn chain_name_round_trips_without_a_network() {
        let provider = offline_provider();
        let connection =
            block_on(provider.connect(RELAY_GENESIS)).expect("offline add_chain succeeds");
        let mut responses = connection.responses();
        connection.send(
            r#"{"jsonrpc":"2.0","id":1,"method":"chainSpec_v1_chainName","params":[]}"#.to_owned(),
        );
        let response = block_on(responses.next()).expect("smoldot answers spec-local queries");
        assert!(
            response.contains("Paseo Testnet"),
            "unexpected response: {response}"
        );
    }

    #[test]
    fn parachain_reuses_its_registered_relay() {
        let provider = EmbeddedChainProvider::builder()
            .chain(RELAY_GENESIS, ChainSource::light_client(RELAY_SPEC).build())
            .parachain(
                PARACHAIN_GENESIS,
                ChainSource::light_client(PARACHAIN_SPEC).build(),
                RELAY_GENESIS,
            )
            .build();
        // Two connects: the second must reuse the cached relay ChainId.
        for _ in 0..2 {
            let connection = block_on(provider.connect(PARACHAIN_GENESIS))
                .expect("parachain add_chain succeeds with its relay registered");
            let mut responses = connection.responses();
            connection.send(
                r#"{"jsonrpc":"2.0","id":1,"method":"chainSpec_v1_chainName","params":[]}"#
                    .to_owned(),
            );
            let response = block_on(responses.next()).expect("smoldot answers spec-local queries");
            assert!(
                response.contains("Paseo People"),
                "unexpected response: {response}"
            );
        }
    }

    #[test]
    fn relay_is_reclaimed_when_the_last_parachain_closes() {
        let provider = EmbeddedChainProvider::builder()
            .chain(RELAY_GENESIS, ChainSource::light_client(RELAY_SPEC).build())
            .parachain(
                PARACHAIN_GENESIS,
                ChainSource::light_client(PARACHAIN_SPEC).build(),
                RELAY_GENESIS,
            )
            .build();
        let first = block_on(provider.connect(PARACHAIN_GENESIS)).expect("parachain connects");
        let second = block_on(provider.connect(PARACHAIN_GENESIS)).expect("parachain connects");
        assert_eq!(
            provider.relay_count(),
            1,
            "both connections share one relay"
        );
        first.close();
        assert_eq!(
            provider.relay_count(),
            1,
            "the relay stays while a parachain connection is live"
        );
        second.close();
        assert_eq!(
            provider.relay_count(),
            0,
            "the relay is reclaimed after the last parachain connection closes"
        );
    }

    #[test]
    fn a_failed_parachain_add_releases_its_relay() {
        // The relay entry is a chain whose spec id is not the one the parachain
        // declares, so smoldot refuses the parachain with NoRelayChainFound
        // after the relay has already been added and referenced.
        let provider = EmbeddedChainProvider::builder()
            .chain(
                RELAY_GENESIS,
                ChainSource::light_client(PARACHAIN_SPEC).build(),
            )
            .parachain(
                PARACHAIN_GENESIS,
                ChainSource::light_client(PARACHAIN_SPEC).build(),
                RELAY_GENESIS,
            )
            .build();
        block_on(provider.connect(PARACHAIN_GENESIS))
            .err()
            .expect("a parachain whose relay does not match must fail to connect");
        assert_eq!(
            provider.relay_count(),
            0,
            "the relay must not leak when the parachain add fails"
        );
    }

    /// A consumer that never reads must stop being accepted work.
    ///
    /// smoldot would queue these without limit: its request channel is unbounded
    /// and its service stalls once the bounded response channel backs up, so the
    /// only thing standing between a runaway `send()` loop and unbounded memory
    /// is the frame budget this asserts.
    #[test]
    fn sending_without_draining_is_refused_once_the_budget_is_spent() {
        let provider = offline_provider();
        let connection =
            block_on(provider.connect(RELAY_GENESIS)).expect("offline add_chain succeeds");
        // Held but deliberately never polled, which is what makes frames pile up.
        let mut responses = connection.responses();

        let overshoot = 64;
        for id in 0..super::MAX_UNDELIVERED_FRAMES + overshoot {
            connection.send(format!(
                r#"{{"jsonrpc":"2.0","id":{id},"method":"chainSpec_v1_chainName","params":[]}}"#
            ));
        }

        // Drain what is buffered and count the refusals among it.
        let mut refusals = 0;
        while let Some(Some(frame)) = block_on(async { Some(responses.next().await) }) {
            if frame.contains("response queue full") {
                refusals += 1;
            }
            if refusals >= overshoot {
                break;
            }
        }
        assert_eq!(
            refusals, overshoot,
            "every request past the budget must come back as an error frame"
        );
    }

    #[test]
    fn close_is_idempotent_and_ends_the_stream() {
        let provider = offline_provider();
        let connection =
            block_on(provider.connect(RELAY_GENESIS)).expect("offline add_chain succeeds");
        let mut responses = connection.responses();
        connection.close();
        connection.close();
        assert_eq!(block_on(responses.next()), None);
        // A late send must not panic on the removed chain.
        connection.send(
            r#"{"jsonrpc":"2.0","id":2,"method":"chainSpec_v1_chainName","params":[]}"#.to_owned(),
        );
    }

    #[test]
    fn concurrent_parachain_connects_share_and_reclaim_the_relay() {
        // Many threads race the lazy client init and the shared relay refcount;
        // once every connection closes the relay must be fully reclaimed, with
        // no panic and no leak.
        let provider = Arc::new(
            EmbeddedChainProvider::builder()
                .chain(RELAY_GENESIS, ChainSource::light_client(RELAY_SPEC).build())
                .parachain(
                    PARACHAIN_GENESIS,
                    ChainSource::light_client(PARACHAIN_SPEC).build(),
                    RELAY_GENESIS,
                )
                .build(),
        );
        let threads: Vec<_> = (0..8)
            .map(|_| {
                let provider = Arc::clone(&provider);
                std::thread::spawn(move || {
                    let connection =
                        block_on(provider.connect(PARACHAIN_GENESIS)).expect("parachain connects");
                    connection.close();
                })
            })
            .collect();
        for thread in threads {
            thread.join().expect("connect thread does not panic");
        }
        assert_eq!(provider.relay_count(), 0, "no relay leaks under contention");
    }

    #[test]
    fn connections_to_the_same_chain_are_isolated() {
        let provider = offline_provider();
        let first = block_on(provider.connect(RELAY_GENESIS)).expect("offline add_chain succeeds");
        let second = block_on(provider.connect(RELAY_GENESIS)).expect("offline add_chain succeeds");
        let mut second_responses = second.responses();
        first.close();
        second.send(
            r#"{"jsonrpc":"2.0","id":1,"method":"chainSpec_v1_chainName","params":[]}"#.to_owned(),
        );
        let response =
            block_on(second_responses.next()).expect("the second connection stays alive");
        assert!(
            response.contains("Paseo Testnet"),
            "unexpected response: {response}"
        );
    }
}
