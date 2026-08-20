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

use std::fmt;
use std::sync::{Arc, Weak};

use futures::executor::block_on;
use futures::stream::BoxStream;
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
    /// The host's listener failed in a way it did not declare.
    #[error("{reason}")]
    Listener {
        /// Human-readable failure reason.
        reason: String,
    },
}

impl From<uniffi::UnexpectedUniFFICallbackError> for ChainProviderError {
    fn from(err: uniffi::UnexpectedUniFFICallbackError) -> Self {
        // Without this the generic converter panics, and `panic = "abort"` on
        // the shipping profile turns a listener's exception into a process
        // abort rather than an ended stream.
        tracing::warn!(
            reason = %err.reason,
            "chain listener threw an undeclared error; reporting it as a rejection"
        );
        ChainProviderError::Listener {
            reason: bounded_reason(err.reason),
        }
    }
}

/// Why the pump stopped delivering a connection's responses.
///
/// This says what the core observed, not whether a reconnect is wanted. On the
/// light-client path a response stream ends only when the connection is closed,
/// including by this host's own `disconnect()` or by dropping the handle, so
/// `StreamEnded` is usually the host's own teardown coming back to it. A host
/// that reconnects on it without checking its own intent will reconnect to a
/// connection it deliberately closed.
///
/// New variants may be added, so a Swift host should carry an `@unknown
/// default` and a Kotlin host an `else` branch.
///
/// Reconnecting is done from another thread, and a serial one: a listener
/// callback runs on the pump thread, and `ChainProvider::connect` refuses to
/// run there. Hopping to a concurrent queue lets reconnects run in parallel,
/// and each one costs a thread plus a chain-spec parse.
///
/// Do not re-queue work with `send` from `on_closed`. By then the connection
/// is closed either way: `close()` is what ended the stream on `StreamEnded`,
/// and the pump closes it before reporting `ListenerFailed`. `send` on a
/// closed connection is dropped silently, with no error and no frame for the
/// request's id, so a consumer correlating by id would wait forever. From `on_message`, where the
/// connection is still open, `send` behaves normally. `disconnect` is
/// idempotent and safe to call from either callback.
#[derive(Debug, Clone, PartialEq, Eq, uniffi::Enum)]
pub enum ChainCloseReason {
    /// The response stream ended.
    ///
    /// Every connection this crate hands a host runs on the embedded light
    /// client, and that stream ends only when the connection is closed, so in
    /// practice this is your own teardown arriving back: `disconnect()`, or
    /// dropping the handle. It is not a report that the peer went away.
    StreamEnded,
    /// This listener returned an error from `on_message`, so the connection was
    /// closed under it.
    ///
    /// A listener that rejects frames while it is shutting down reports this
    /// even when the host asked for the teardown: `on_message` blocks in
    /// foreign code, so a `disconnect()` can land while a frame is already in
    /// flight, and rejecting that frame is a listener failure like any other.
    ListenerFailed {
        /// What the listener reported, bounded to 256 characters. For logs
        /// and diagnostics: a
        /// host that needs to branch on its own failure modes should track them
        /// where it raised them.
        reason: String,
    },
}

thread_local! {
    /// Set while this thread is pumping a connection's responses, so every
    /// foreign listener callback runs with it true.
    static PUMPING: core::cell::Cell<bool> = const { core::cell::Cell::new(false) };
}

/// Marks the pump thread for the length of one connection's pumping.
struct PumpGuard(bool);

impl PumpGuard {
    fn enter() -> Self {
        Self(PUMPING.replace(true))
    }
}

impl Drop for PumpGuard {
    fn drop(&mut self) {
        // Restore rather than clear: the spawn site and `pump_responses` both
        // hold one, and an inner drop must not clear the outer's flag.
        PUMPING.set(self.0);
    }
}

/// Longest listener-authored reason carried back to a host.
///
/// The string is whatever the foreign listener threw, so it is unbounded at the
/// source and crosses the boundary twice. 256 is the same order the host
/// callback adapters bound their own reasons to, though each counts in its
/// platform's unit: this one counts Unicode scalar values, so it never splits a
/// character.
pub const CLOSE_REASON_MAX_CHARS: usize = 256;

/// Bound a listener-authored reason to [`CLOSE_REASON_MAX_CHARS`] characters.
/// Render `value` into at most [`CLOSE_REASON_MAX_CHARS`] characters without
/// materializing the whole rendering first. A listener's reason is unbounded at
/// the source, so `to_string()` on it peaks far above what we keep.
fn bounded_display(value: &dyn fmt::Display) -> String {
    use fmt::Write as _;

    struct Capped {
        out: String,
        remaining: usize,
    }

    impl fmt::Write for Capped {
        fn write_str(&mut self, text: &str) -> fmt::Result {
            for character in text.chars() {
                if self.remaining == 0 {
                    return Ok(());
                }
                self.out.push(character);
                self.remaining -= 1;
            }
            Ok(())
        }
    }

    let mut capped = Capped {
        out: String::new(),
        remaining: CLOSE_REASON_MAX_CHARS,
    };
    // Writing into a String cannot fail.
    let _ = write!(capped, "{value}");
    capped.out
}

fn bounded_reason(reason: String) -> String {
    match reason.char_indices().nth(CLOSE_REASON_MAX_CHARS) {
        Some((end, _)) => reason[..end].to_string(),
        None => reason,
    }
}

/// Sink for a connection's inbound JSON-RPC responses and notifications,
/// implemented on the foreign (Swift) side.
#[uniffi::export(with_foreign)]
pub trait ChainMessageListener: Send + Sync {
    /// Called for each JSON-RPC response or notification string.
    fn on_message(&self, message: String) -> Result<(), ChainProviderError>;
    /// Called once the connection has closed, whichever way it ended.
    fn on_closed(&self, reason: ChainCloseReason) -> Result<(), ChainProviderError>;
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
        // A listener callback runs on the pump thread, which is already inside
        // `block_on`; blocking again there is a panic the host cannot catch,
        // and an abort on the shipping profile. Refuse it as an error instead,
        // since reconnecting from `on_closed` is the flow `ChainCloseReason`
        // exists to inform.
        if PUMPING.get() {
            return Err(ChainProviderError::Connect {
                reason: "connect() cannot be called from a listener callback; \
                         call it from another thread"
                    .to_string(),
            });
        }
        let genesis: [u8; 32] = genesis_hash
            .try_into()
            .map_err(|_| ChainProviderError::BadGenesis)?;
        let connection =
            block_on(self.inner.connect(genesis)).map_err(|error| ChainProviderError::Connect {
                reason: error.reason,
            })?;
        let connection: Arc<dyn JsonRpcConnection> = Arc::from(connection);

        let responses = connection.responses();
        // Weak on purpose: a strong handle here would keep the connection alive
        // forever. `Drop` is what calls `close()`, `close()` is what ends the
        // response stream, and the pump parks on that stream -- so holding a
        // strong reference means the drop that would release it can never run.
        let pumped = Arc::downgrade(&connection);
        // Named for crash reports, and fallible: under EAGAIN the unnamed
        // `thread::spawn` panics, which this method has a `Result` to avoid.
        std::thread::Builder::new()
            .name("truapi-pump".to_string())
            .spawn(move || {
                // Entered here, not inside `pump_responses`: the guard must outlive
                // the future, because dropping `listener` releases the foreign object
                // and runs its destructor on this thread, still inside `block_on`.
                let _pumping = PumpGuard::enter();
                block_on(pump_responses(responses, pumped, listener))
            })
            .map_err(|error| ChainProviderError::Connect {
                reason: format!("could not start the response pump: {error}"),
            })?;

        Ok(Arc::new(ChainConnection { inner: connection }))
    }
}

/// Deliver a connection's responses to its listener until the stream ends or
/// the listener fails.
///
/// A failing listener closes the connection: the response stream is take-once,
/// so it cannot be pumped again, and leaving the handle open would queue every
/// later send against a receiver that is gone. `on_closed` fires either way,
/// after the connection is closed, and names which of the two stopped the pump.
/// See [`ChainCloseReason`] for what that does and does not tell a host.
async fn pump_responses(
    mut responses: BoxStream<'static, String>,
    connection: Weak<dyn JsonRpcConnection>,
    listener: Arc<dyn ChainMessageListener>,
) {
    let _pumping = PumpGuard::enter();
    let mut reason = ChainCloseReason::StreamEnded;
    while let Some(message) = responses.next().await {
        if let Err(error) = listener.on_message(message) {
            tracing::warn!(%error, "chain listener failed; closing the connection");
            if let Some(connection) = connection.upgrade() {
                connection.close();
            }
            // Load-bearing, not redundant with the `From` impl: a listener that
            // throws a *declared* `ChainProviderError` is lifted by uniffi directly,
            // never crossing that impl, so this is the only bound on that path.
            reason = ChainCloseReason::ListenerFailed {
                reason: bounded_display(&error),
            };
            break;
        }
    }
    if let Err(error) = listener.on_closed(reason) {
        tracing::warn!(%error, "chain listener failed on close");
    }
}

/// A live JSON-RPC connection: a raw string pipe to one chain.
#[derive(uniffi::Object)]
pub struct ChainConnection {
    inner: Arc<dyn JsonRpcConnection>,
}

#[cfg(all(test, feature = "networks"))]
mod tests {
    use core::future::Future;
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
        closed: Mutex<Option<Sender<ChainCloseReason>>>,
    }

    impl Collector {
        fn new() -> (Arc<Self>, Receiver<String>, Receiver<ChainCloseReason>) {
            let (messages, message_rx) = channel();
            let (closed, closed_rx) = channel();
            let collector = Arc::new(Collector {
                messages,
                closed: Mutex::new(Some(closed)),
            });
            (collector, message_rx, closed_rx)
        }
    }

    /// Fails on the message at `fail_at`, recording what it was asked to do.
    struct FailingListener {
        fail_at: usize,
        delivered: Mutex<Vec<String>>,
        closed: Mutex<Option<ChainCloseReason>>,
        closes: Mutex<usize>,
        reason: String,
    }

    impl ChainMessageListener for FailingListener {
        fn on_message(&self, message: String) -> Result<(), ChainProviderError> {
            let mut delivered = self.delivered.lock().expect("not poisoned");
            delivered.push(message);
            if delivered.len() == self.fail_at {
                return Err(ChainProviderError::Listener {
                    reason: self.reason.clone(),
                });
            }
            Ok(())
        }

        fn on_closed(&self, reason: ChainCloseReason) -> Result<(), ChainProviderError> {
            *self.closed.lock().expect("not poisoned") = Some(reason);
            *self.closes.lock().expect("not poisoned") += 1;
            Ok(())
        }
    }

    /// Reads the connection at the moment it is told the connection closed, so
    /// the ordering is observed rather than inferred from a final flag.
    struct OrderingListener {
        connection: Arc<ClosingConnection>,
        fails: bool,
        closed_while_open: Mutex<Option<bool>>,
        closes: Mutex<usize>,
    }

    impl ChainMessageListener for OrderingListener {
        fn on_message(&self, _message: String) -> Result<(), ChainProviderError> {
            if self.fails {
                return Err(ChainProviderError::Listener {
                    reason: "cannot decode".to_string(),
                });
            }
            Ok(())
        }

        fn on_closed(&self, _reason: ChainCloseReason) -> Result<(), ChainProviderError> {
            let open = !*self.connection.closed.lock().expect("not poisoned");
            *self.closed_while_open.lock().expect("not poisoned") = Some(open);
            *self.closes.lock().expect("not poisoned") += 1;
            Ok(())
        }
    }

    /// Records whether the pump closed it.
    struct ClosingConnection {
        closed: Mutex<bool>,
    }

    impl JsonRpcConnection for ClosingConnection {
        fn send(&self, _request: String) {}

        fn responses(&self) -> BoxStream<'static, String> {
            Box::pin(futures::stream::empty())
        }

        fn close(&self) {
            *self.closed.lock().expect("not poisoned") = true;
        }
    }

    #[test]
    fn the_pump_does_not_keep_its_connection_alive() {
        // The pump parks on a stream that only ends once the connection is
        // dropped and closed. A strong handle here would make that drop
        // unreachable, leaking the chain and the thread that waits on it.
        let connection: Arc<dyn JsonRpcConnection> = Arc::new(ClosingConnection {
            closed: Mutex::new(false),
        });
        let weak = Arc::downgrade(&connection);
        let listener = Arc::new(FailingListener {
            fail_at: usize::MAX,
            delivered: Mutex::new(Vec::new()),
            closed: Mutex::new(None),
            closes: Mutex::new(0),
            reason: "cannot decode".to_string(),
        });

        // Parked on a stream that never yields, which is where the pump spends
        // its life. Polled first so the future is actually running: an async
        // body executes nothing until then, so dropping before the first poll
        // would prove nothing.
        let mut pump = Box::pin(pump_responses(
            Box::pin(futures::stream::pending()),
            weak.clone(),
            listener,
        ));
        let mut cx = core::task::Context::from_waker(futures::task::noop_waker_ref());
        assert!(pump.as_mut().poll(&mut cx).is_pending());

        drop(connection);
        assert!(
            weak.upgrade().is_none(),
            "a parked pump must not hold its connection alive"
        );
    }

    #[test]
    fn a_dropped_connection_still_reports_the_listener_that_failed() {
        // `close()` ends the stream asynchronously, so a host that dropped its
        // handle can still have buffered frames pumped at it. If a listener
        // rejects one of those, the reason must not fall back to the variant a
        // host reads as an ordinary ending.
        let listener = Arc::new(FailingListener {
            fail_at: 1,
            delivered: Mutex::new(Vec::new()),
            closed: Mutex::new(None),
            closes: Mutex::new(0),
            reason: "cannot decode".to_string(),
        });
        let connection: Arc<dyn JsonRpcConnection> = Arc::new(ClosingConnection {
            closed: Mutex::new(false),
        });
        let weak = Arc::downgrade(&connection);
        drop(connection);
        assert!(weak.upgrade().is_none(), "the owner has already dropped it");

        block_on(pump_responses(
            Box::pin(futures::stream::iter(["late".to_string()])),
            weak,
            listener.clone(),
        ));

        assert_eq!(
            *listener.closed.lock().expect("not poisoned"),
            Some(ChainCloseReason::ListenerFailed {
                reason: "cannot decode".to_string()
            })
        );
        // The fixture records the last call, so without this a second
        // `on_closed` on this path would pass unnoticed.
        assert_eq!(*listener.closes.lock().expect("not poisoned"), 1);
    }

    #[test]
    fn a_host_is_told_once_and_after_any_close_the_pump_performs() {
        // Both listeners read the connection at the moment they are told, so an
        // `on_closed` that ran before `close()` fails here rather than passing
        // on the final state of a flag nothing timed.
        let pump = |fails: bool| {
            let connection = Arc::new(ClosingConnection {
                closed: Mutex::new(false),
            });
            let listener = Arc::new(OrderingListener {
                connection: connection.clone(),
                fails,
                closed_while_open: Mutex::new(None),
                closes: Mutex::new(0),
            });
            block_on(pump_responses(
                Box::pin(futures::stream::iter(["first".to_string()])),
                Arc::downgrade(&(connection.clone() as Arc<dyn JsonRpcConnection>)),
                listener.clone(),
            ));
            listener
        };

        let failed = pump(true);
        assert_eq!(
            *failed.closes.lock().expect("not poisoned"),
            1,
            "a host that reconnects on teardown must not be told twice"
        );
        // The pump closed this one, so it must be closed before the host hears
        // about it: a host reconnecting inside `on_closed` would otherwise do
        // it against a handle still accepting sends.
        assert_eq!(
            *failed.closed_while_open.lock().expect("not poisoned"),
            Some(false)
        );

        let ended = pump(false);
        assert_eq!(*ended.closes.lock().expect("not poisoned"), 1);
        // Nothing failed, so the pump closes nothing: the handle is the owner's
        // to drop, and `on_closed` reports the stream ending, not a close the
        // core performed.
        assert_eq!(
            *ended.closed_while_open.lock().expect("not poisoned"),
            Some(true)
        );
    }

    /// The spawn site and `pump_responses` both hold a guard, so an inner drop
    /// must restore rather than clear: the outer one has to survive the drop of
    /// the listener `Arc`, which runs foreign destructor code on this thread
    /// while `block_on` is still entered.
    #[test]
    fn a_nested_pump_guard_does_not_clear_the_outer_flag() {
        assert!(!PUMPING.get());
        let outer = PumpGuard::enter();
        assert!(PUMPING.get());
        {
            let _inner = PumpGuard::enter();
            assert!(PUMPING.get());
        }
        assert!(
            PUMPING.get(),
            "an inner guard's drop must not clear a flag the outer guard still owns"
        );
        drop(outer);
        assert!(!PUMPING.get());
    }

    #[test]
    fn connecting_from_a_listener_callback_is_refused_rather_than_aborting() {
        // The pump thread is already inside `block_on`, and `connect` blocks
        // again; `futures` answers that with a panic, which `panic = "abort"`
        // turns into a dead app. Reconnecting from `on_closed` is exactly what
        // `ChainCloseReason` invites, so it has to be an error a host can read.
        struct ReconnectingListener {
            provider: Arc<ChainProvider>,
            result: Mutex<Option<Result<(), ChainProviderError>>>,
        }

        impl ChainMessageListener for ReconnectingListener {
            fn on_message(&self, _message: String) -> Result<(), ChainProviderError> {
                Ok(())
            }

            fn on_closed(&self, _reason: ChainCloseReason) -> Result<(), ChainProviderError> {
                let reconnected = self
                    .provider
                    .connect(vec![0u8; 32], Arc::new(SilentListener))
                    .map(|_| ());
                *self.result.lock().expect("not poisoned") = Some(reconnected);
                Ok(())
            }
        }

        struct SilentListener;

        impl ChainMessageListener for SilentListener {
            fn on_message(&self, _message: String) -> Result<(), ChainProviderError> {
                Ok(())
            }

            fn on_closed(&self, _reason: ChainCloseReason) -> Result<(), ChainProviderError> {
                Ok(())
            }
        }

        let listener = Arc::new(ReconnectingListener {
            provider: ChainProvider::new(),
            result: Mutex::new(None),
        });
        let connection = Arc::new(ClosingConnection {
            closed: Mutex::new(false),
        });

        block_on(pump_responses(
            Box::pin(futures::stream::iter(["first".to_string()])),
            Arc::downgrade(&(connection as Arc<dyn JsonRpcConnection>)),
            listener.clone(),
        ));

        let reconnected = listener
            .result
            .lock()
            .expect("not poisoned")
            .take()
            .expect("the listener was told the connection closed");
        assert!(
            matches!(reconnected, Err(ChainProviderError::Connect { ref reason }) if reason.contains("listener callback")),
            "got {reconnected:?}"
        );
    }

    #[test]
    fn a_listener_reason_is_bounded_before_it_crosses_back() {
        // The string is foreign-authored and unbounded at the source, and it
        // crosses the boundary twice.
        // Multi-byte on purpose: a bound written in bytes rather than
        // characters splits this mid-character, which panics, and `panic =
        // "abort"` on the shipping profile turns that into a process kill.
        let listener = Arc::new(FailingListener {
            fail_at: 1,
            delivered: Mutex::new(Vec::new()),
            closed: Mutex::new(None),
            closes: Mutex::new(0),
            reason: format!("HEAD{}", "\u{1f600}".repeat(CLOSE_REASON_MAX_CHARS * 2)),
        });
        let connection = Arc::new(ClosingConnection {
            closed: Mutex::new(false),
        });

        block_on(pump_responses(
            Box::pin(futures::stream::iter(["first".to_string()])),
            Arc::downgrade(&(connection.clone() as Arc<dyn JsonRpcConnection>)),
            listener.clone(),
        ));

        let Some(ChainCloseReason::ListenerFailed { reason }) =
            listener.closed.lock().expect("not poisoned").clone()
        else {
            panic!("a failing listener closes with its own failure");
        };
        assert_eq!(reason.chars().count(), CLOSE_REASON_MAX_CHARS);
        assert!(
            reason.len() > CLOSE_REASON_MAX_CHARS,
            "counted in characters, not bytes"
        );
        // The head is what names the failure, so a bound that kept the tail
        // would leave a host with an anonymous string.
        assert!(
            reason.starts_with("HEAD"),
            "the bound keeps the head, not the tail"
        );
        // Astral chars are two UTF-16 code units each, so a bound counted in
        // those would land on half as many scalars.
        assert!(
            reason.encode_utf16().count() > CLOSE_REASON_MAX_CHARS,
            "counted in scalar values, not UTF-16 code units"
        );
        // The number is the contract a host reads in the doc, so pin the value
        // and not only the relationship to itself.
        assert_eq!(CLOSE_REASON_MAX_CHARS, 256);
    }

    /// The impl exists so an undeclared foreign exception becomes a rejection
    /// instead of the generic converter's panic, which `panic = "abort"` would
    /// turn into a process kill. It also bounds the reason on that path.
    #[test]
    fn an_undeclared_foreign_error_converts_and_is_bounded() {
        let thrown = format!("HEAD{}", "\u{1f600}".repeat(CLOSE_REASON_MAX_CHARS * 2));
        let error =
            ChainProviderError::from(uniffi::UnexpectedUniFFICallbackError::new(thrown.clone()));

        let ChainProviderError::Listener { reason } = error else {
            panic!("an undeclared foreign error is reported as a listener rejection");
        };
        assert_eq!(reason.chars().count(), CLOSE_REASON_MAX_CHARS);
        assert!(reason.starts_with("HEAD"), "the bound keeps the head");
        assert!(
            thrown.chars().count() > CLOSE_REASON_MAX_CHARS,
            "the fixture has to exceed the bound for this to mean anything"
        );
    }

    #[test]
    fn a_stream_that_ends_on_its_own_closes_as_such() {
        let listener = Arc::new(FailingListener {
            fail_at: usize::MAX,
            delivered: Mutex::new(Vec::new()),
            closed: Mutex::new(None),
            closes: Mutex::new(0),
            reason: "cannot decode".to_string(),
        });
        let connection = Arc::new(ClosingConnection {
            closed: Mutex::new(false),
        });
        let responses = futures::stream::iter(["first", "second"].map(str::to_string));

        block_on(pump_responses(
            Box::pin(responses),
            Arc::downgrade(&(connection.clone() as Arc<dyn JsonRpcConnection>)),
            listener.clone(),
        ));

        // The ordinary ending, and the one a host may safely reconnect after.
        assert_eq!(
            *listener.closed.lock().expect("not poisoned"),
            Some(ChainCloseReason::StreamEnded)
        );
        // Nothing failed, so the pump has no reason to close the handle: that
        // is the caller's to drop.
        assert!(!*connection.closed.lock().expect("not poisoned"));
    }

    #[test]
    fn a_failing_listener_ends_the_connection_rather_than_going_deaf() {
        let listener = Arc::new(FailingListener {
            fail_at: 2,
            delivered: Mutex::new(Vec::new()),
            closed: Mutex::new(None),
            closes: Mutex::new(0),
            reason: "cannot decode".to_string(),
        });
        let connection = Arc::new(ClosingConnection {
            closed: Mutex::new(false),
        });
        let responses = futures::stream::iter(["first", "second", "third"].map(str::to_string));

        block_on(pump_responses(
            Box::pin(responses),
            Arc::downgrade(&(connection.clone() as Arc<dyn JsonRpcConnection>)),
            listener.clone(),
        ));

        // Pumping stops at the failure rather than calling the listener again
        // for every remaining response.
        assert_eq!(
            listener.delivered.lock().expect("not poisoned").as_slice(),
            &["first".to_string(), "second".to_string()]
        );
        // The host is told the connection closed, and told which way: a host
        // that reconnected on this would walk straight back into the failure
        // that closed it.
        assert_eq!(
            *listener.closed.lock().expect("not poisoned"),
            Some(ChainCloseReason::ListenerFailed {
                reason: "cannot decode".to_string()
            })
        );
        // And the connection is closed, so later sends are refused at the
        // source instead of queueing against a receiver that is gone.
        assert!(*connection.closed.lock().expect("not poisoned"));
    }

    impl ChainMessageListener for Collector {
        fn on_message(&self, message: String) -> Result<(), ChainProviderError> {
            let _ = self.messages.send(message);
            Ok(())
        }

        fn on_closed(&self, reason: ChainCloseReason) -> Result<(), ChainProviderError> {
            if let Some(closed) = self.closed.lock().expect("not poisoned").take() {
                let _ = closed.send(reason);
            }
            Ok(())
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
