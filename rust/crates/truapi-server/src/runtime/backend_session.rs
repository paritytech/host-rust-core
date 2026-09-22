//! Sessions the core holds for backends that authenticate a person.
//!
//! A product asks for a backend call and gets one; whether that backend wants
//! a person proven first is between the core and the backend. The core runs
//! the handshake on first use of a backend, keeps the session it produced,
//! attaches it to every later call, and runs the handshake again once when a
//! backend refuses the one it holds. The same shape the CLI host already uses
//! against the identity backend.
//!
//! There is no consent gate here. Which backends a host serves at all is the
//! host vendor's decision, and the registry is where that decision lives; a
//! prompt would ask the person about a boundary they did not draw. The proof
//! discloses an alias bound to the product and to nothing else.

use std::collections::BTreeMap;
use std::sync::Mutex;

use truapi_platform::{BackendHost, ProductContext};

use crate::host_logic::backend::screen_authorization;
use crate::host_logic::backend::session::{self, Session};

/// How far before its stated expiry a session stops being used, so a call is
/// not sent with a token that expires in flight.
const EXPIRY_MARGIN_MS: u64 = 5_000;

/// How long a backend that refused the handshake with a `4xx` is left alone.
///
/// A refusal in this range is a statement about the request, and the request
/// the core makes is the same every time: the product is not on the backend's
/// allowlist, or the proof does not open against a ring it accepts. Retrying
/// that on the next call re-runs a chain-reading proof to be told the same
/// thing, so the window is long enough that a misconfigured product costs one
/// handshake per window rather than one per call.
const REFUSED_BACKOFF_MS: u64 = 300_000;

/// How long a handshake that could not be completed for any other reason is
/// left alone: a `5xx`, a transport failure, or a proof this host could not
/// make because nobody is connected or the person is in no ring.
///
/// Shorter than [`REFUSED_BACKOFF_MS`], because every cause here can clear
/// without anyone changing configuration.
const UNAVAILABLE_BACKOFF_MS: u64 = 30_000;

/// Ceiling on a `retry-after` the core will honour, so a backend cannot park
/// its own callers for longer than the core is willing to hold state.
const MAX_RETRY_AFTER_MS: u64 = 3_600_000;

/// What to do about credentials on one backend call.
#[derive(Debug, Clone, PartialEq, Eq)]
pub(crate) enum Authorization {
    /// Attach this session.
    Session(String),
    /// This backend authenticates nobody. Call it with no session, which is
    /// what a backend serving no handshake expects.
    Unauthenticated,
    /// This backend authenticates a person and the core holds no session for
    /// it. The call is not sent: the backend has already said it refuses
    /// callers it cannot identify, so forwarding one spends the caller's
    /// budget to be told that again, and reports the backend's own `401`
    /// as though the product had been refused on its merits.
    Unavailable(String),
}

/// What a personhood proof for a backend handshake consists of.
pub(crate) struct PersonProof {
    /// The ring-VRF proof, bound to the context and the challenge.
    pub(crate) proof: Vec<u8>,
    /// Index of the ring the proof opened against, which the backend needs to
    /// read the same commitment off chain.
    pub(crate) ring_index: u32,
}

/// The host role that can prove the connected person.
///
/// A signing host proves with the reserved `peopl.<suffix>` member key it
/// holds; a paired host asks the signer that holds it.
#[truapi::async_trait]
pub(crate) trait PersonhoodProver: Send + Sync {
    /// Prove the connected person against `context` and `message`.
    async fn prove_person(&self, context: &[u8], message: &[u8]) -> Result<PersonProof, ()>;
}

/// What a backend turned out to want, once the core has asked it.
enum Entry {
    /// A session, good until it expires or is refused.
    Held(Session),
    /// This backend answered the challenge path with something that is not
    /// this handshake, so there is no session to be had and no reason to ask
    /// again.
    NoHandshake,
    /// This backend speaks the handshake and the core could not complete one.
    /// Held until `retry_at_ms` so a cause that does not clear between two
    /// calls cannot re-run the proof on each of them.
    Unavailable {
        /// When the handshake may be attempted again.
        retry_at_ms: u64,
        /// What went wrong, for the product's error and the operator's log.
        reason: String,
    },
}

impl Authorization {
    /// The session this decision carries, if it carries one.
    #[cfg(test)]
    fn token(&self) -> Option<&str> {
        match self {
            Self::Session(token) => Some(token),
            Self::Unauthenticated | Self::Unavailable(_) => None,
        }
    }
}

/// Sessions held per backend, for one product execution.
#[derive(Default)]
pub(crate) struct BackendSessions {
    entries: Mutex<BTreeMap<String, Entry>>,
}

impl BackendSessions {
    /// The credential to attach to a call, running the handshake if this is
    /// the first use of the backend, the held session has expired, or an
    /// earlier failure's back-off window has passed.
    pub(crate) async fn authorization(
        &self,
        host: &dyn BackendHost,
        prover: &dyn PersonhoodProver,
        product: &ProductContext,
        backend: &str,
        now_ms: u64,
    ) -> Authorization {
        if let Some(decided) = self.cached(backend, now_ms) {
            return decided;
        }
        self.authenticate(host, prover, product, backend, now_ms)
            .await
    }

    /// Drop a session the backend refused and mint another, once.
    ///
    /// A `401` on a call the core authenticated means the token is stale in a
    /// way its stated expiry did not predict — a rotated signing key, a
    /// revoked product — and the person is still a person.
    pub(crate) async fn reauthenticate(
        &self,
        host: &dyn BackendHost,
        prover: &dyn PersonhoodProver,
        product: &ProductContext,
        backend: &str,
        now_ms: u64,
    ) -> Option<String> {
        self.forget(backend);
        match self
            .authenticate(host, prover, product, backend, now_ms)
            .await
        {
            Authorization::Session(token) => Some(token),
            Authorization::Unauthenticated | Authorization::Unavailable(_) => None,
        }
    }

    fn cached(&self, backend: &str, now_ms: u64) -> Option<Authorization> {
        let entries = self.entries.lock().expect("backend session mutex poisoned");
        match entries.get(backend)? {
            Entry::NoHandshake => Some(Authorization::Unauthenticated),
            Entry::Unavailable {
                retry_at_ms,
                reason,
            } => (*retry_at_ms > now_ms).then(|| Authorization::Unavailable(reason.clone())),
            Entry::Held(session) => (session.expires_at_ms.saturating_sub(EXPIRY_MARGIN_MS)
                > now_ms)
                .then(|| Authorization::Session(session.token.clone())),
        }
    }

    fn forget(&self, backend: &str) {
        self.entries
            .lock()
            .expect("backend session mutex poisoned")
            .remove(backend);
    }

    fn remember(&self, backend: &str, entry: Entry) {
        self.entries
            .lock()
            .expect("backend session mutex poisoned")
            .insert(backend.to_owned(), entry);
    }

    async fn authenticate(
        &self,
        host: &dyn BackendHost,
        prover: &dyn PersonhoodProver,
        product: &ProductContext,
        backend: &str,
        now_ms: u64,
    ) -> Authorization {
        // The handshake rides the same tunnel the product's call will: the
        // core holds no origin of its own, and the host authenticates itself
        // on these two calls exactly as it will on the third.
        let challenged = host
            .backend_request(product, session::challenge_request(backend), None)
            .await;

        let challenge = match challenged {
            // A backend that will not answer the challenge path at all may
            // simply be down, so this is a back-off rather than a verdict
            // about what it serves.
            Err(error) => {
                return self.unavailable(
                    backend,
                    now_ms,
                    format!("challenge call failed: {error:?}"),
                );
            }
            // The route not being there is the backend saying it serves no
            // handshake, which does not change between calls. Any other
            // refusal is about this request or this moment, so it backs off
            // instead of disabling personhood for the rest of the execution.
            Ok(response) if response.status == 404 || response.status == 405 => {
                self.remember(backend, Entry::NoHandshake);
                return Authorization::Unauthenticated;
            }
            Ok(response) if response.status != 200 => {
                return self.unavailable_for_status(
                    backend,
                    now_ms,
                    &response,
                    format!("challenge answered {}", response.status),
                );
            }
            Ok(response) => match session::parse_challenge(&response.body) {
                Ok(challenge) => challenge,
                // A `200` in another shape is this backend serving a different
                // handshake, or none. That does not change between calls, and
                // asking again would put two dead round trips in front of each
                // one.
                Err(_) => {
                    self.remember(backend, Entry::NoHandshake);
                    return Authorization::Unauthenticated;
                }
            },
        };

        let context = session::proof_context(&product.product_id);
        let Ok(proof) = prover.prove_person(&context, &challenge.bytes).await else {
            // Nobody connected, or this person is in no ring the chain serves.
            // Both can clear without anyone changing configuration, and both
            // cost a full ring scan to discover, so the answer is kept.
            return self.unavailable(backend, now_ms, "no personhood proof available".to_owned());
        };

        let redeemed = host
            .backend_request(
                product,
                session::redeem_request(
                    backend,
                    &challenge,
                    &proof.proof,
                    proof.ring_index,
                    &product.product_id,
                ),
                None,
            )
            .await;

        let session = match redeemed {
            Err(error) => {
                return self.unavailable(backend, now_ms, format!("redeem call failed: {error:?}"));
            }
            Ok(response) if response.status != 200 => {
                return self.unavailable_for_status(
                    backend,
                    now_ms,
                    &response,
                    format!("redeem answered {}", response.status),
                );
            }
            Ok(response) => match session::parse_session(&response.body) {
                Ok(session) => session,
                Err(_) => {
                    self.remember(backend, Entry::NoHandshake);
                    return Authorization::Unauthenticated;
                }
            },
        };

        // What a backend hands back becomes a header on the host's own
        // request, so it is held to the same rule as anything else that does.
        if screen_authorization(&session.token).is_err() {
            return self.unavailable(
                backend,
                now_ms,
                "session token is not a usable credential".to_owned(),
            );
        }

        let token = session.token.clone();
        self.remember(backend, Entry::Held(session));
        Authorization::Session(token)
    }

    /// Record a handshake failure and report it, backing off by status.
    ///
    /// A `4xx` is a statement about the request, and the core makes the same
    /// request every time, so it waits longer before asking again. Anything
    /// else may clear on its own. A `retry-after` the backend sent wins over
    /// both, since the backend knows its own outage better than this does.
    fn unavailable_for_status(
        &self,
        backend: &str,
        now_ms: u64,
        response: &truapi::latest::HostBackendResponse,
        reason: String,
    ) -> Authorization {
        let backoff = retry_after_ms(response).unwrap_or({
            if (400..500).contains(&response.status) {
                REFUSED_BACKOFF_MS
            } else {
                UNAVAILABLE_BACKOFF_MS
            }
        });
        self.remember_unavailable(backend, now_ms, backoff, reason.clone());
        Authorization::Unavailable(reason)
    }

    /// Record a handshake failure with no status to reason from.
    fn unavailable(&self, backend: &str, now_ms: u64, reason: String) -> Authorization {
        self.remember_unavailable(backend, now_ms, UNAVAILABLE_BACKOFF_MS, reason.clone());
        Authorization::Unavailable(reason)
    }

    fn remember_unavailable(&self, backend: &str, now_ms: u64, backoff_ms: u64, reason: String) {
        self.remember(
            backend,
            Entry::Unavailable {
                retry_at_ms: now_ms.saturating_add(backoff_ms),
                reason,
            },
        );
    }
}

/// The `retry-after` a backend sent, in milliseconds, when it sent one as a
/// delay in seconds. An HTTP-date form is not read: the core has no clock it
/// can trust against the backend's, and a wrong reading would park a caller.
fn retry_after_ms(response: &truapi::latest::HostBackendResponse) -> Option<u64> {
    let value = response
        .headers
        .iter()
        .find(|header| header.name == "retry-after")?;
    let seconds: u64 = value.value.trim().parse().ok()?;
    Some(seconds.saturating_mul(1_000).min(MAX_RETRY_AFTER_MS))
}

/// Wall clock in milliseconds, for comparing a session's stated expiry.
pub(crate) fn now_ms() -> u64 {
    #[cfg(target_arch = "wasm32")]
    let now = web_time::SystemTime::now().duration_since(web_time::UNIX_EPOCH);
    #[cfg(not(target_arch = "wasm32"))]
    let now = std::time::SystemTime::now().duration_since(std::time::UNIX_EPOCH);
    now.map(|since| u64::try_from(since.as_millis()).unwrap_or(u64::MAX))
        .unwrap_or_default()
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::sync::atomic::{AtomicUsize, Ordering};
    use truapi::latest::{HostBackendError, HostBackendListResponse, HostBackendResponse};

    /// A backend that speaks the handshake, counting what it was asked.
    #[derive(Default)]
    struct StubBackend {
        challenges: AtomicUsize,
        redeems: AtomicUsize,
        plain_calls: AtomicUsize,
        /// Status the challenge path answers with.
        challenge_status: u16,
        /// Status the redeem path answers with.
        redeem_status: u16,
        /// `retry-after` seconds the redeem path sends, when it sends one.
        retry_after: Option<u64>,
        /// Token minted by each redemption, suffixed by the redeem count.
        expires_at_ms: u64,
    }

    impl StubBackend {
        fn serving() -> Self {
            Self {
                challenge_status: 200,
                redeem_status: 200,
                expires_at_ms: 10_000,
                ..Self::default()
            }
        }

        /// Serves the handshake but refuses every redemption, as a backend
        /// does when the product is not on its allowlist.
        fn refusing_redeems(status: u16) -> Self {
            Self {
                redeem_status: status,
                ..Self::serving()
            }
        }

        /// Refuses redemptions and names its own retry window.
        fn refusing_redeems_for(status: u16, retry_after: u64) -> Self {
            Self {
                retry_after: Some(retry_after),
                ..Self::refusing_redeems(status)
            }
        }

        fn without_a_handshake() -> Self {
            Self {
                challenge_status: 404,
                ..Self::default()
            }
        }
    }

    #[truapi::async_trait]
    impl BackendHost for StubBackend {
        async fn backend_request(
            &self,
            _product: &ProductContext,
            request: truapi::latest::HostBackendRequest,
            _authorization: Option<String>,
        ) -> Result<HostBackendResponse, HostBackendError> {
            let (status, body) = match request.path.as_str() {
                session::CHALLENGE_PATH => {
                    self.challenges.fetch_add(1, Ordering::SeqCst);
                    (
                        self.challenge_status,
                        br#"{"challenge":"AAECAwQF"}"#.to_vec(),
                    )
                }
                session::REDEEM_PATH => {
                    let nth = self.redeems.fetch_add(1, Ordering::SeqCst);
                    (
                        self.redeem_status,
                        format!(
                            r#"{{"token":"session-{nth}","expiresAtMs":{}}}"#,
                            self.expires_at_ms
                        )
                        .into_bytes(),
                    )
                }
                _ => {
                    self.plain_calls.fetch_add(1, Ordering::SeqCst);
                    (200, b"{}".to_vec())
                }
            };
            let headers = match self.retry_after {
                Some(seconds) if request.path == session::REDEEM_PATH => {
                    vec![truapi::latest::BackendHeader {
                        name: "retry-after".to_string(),
                        value: seconds.to_string(),
                    }]
                }
                _ => Vec::new(),
            };
            Ok(HostBackendResponse {
                status,
                headers,
                body,
            })
        }

        async fn backends(
            &self,
            _product: &ProductContext,
        ) -> Result<HostBackendListResponse, truapi::latest::GenericError> {
            Ok(HostBackendListResponse {
                backends: vec!["fiat-onramp".to_string()],
            })
        }
    }

    /// A host role that holds the key but cannot produce a proof: nobody
    /// connected, or this person is in no ring the chain serves.
    #[derive(Default)]
    struct UnprovableProver {
        attempts: AtomicUsize,
    }

    #[truapi::async_trait]
    impl PersonhoodProver for UnprovableProver {
        async fn prove_person(&self, _context: &[u8], _message: &[u8]) -> Result<PersonProof, ()> {
            self.attempts.fetch_add(1, Ordering::SeqCst);
            Err(())
        }
    }

    #[derive(Default)]
    struct StubProver {
        proofs: AtomicUsize,
        /// Context of the last proof, to check what it was bound to.
        context: Mutex<Vec<u8>>,
        message: Mutex<Vec<u8>>,
    }

    #[truapi::async_trait]
    impl PersonhoodProver for StubProver {
        async fn prove_person(&self, context: &[u8], message: &[u8]) -> Result<PersonProof, ()> {
            self.proofs.fetch_add(1, Ordering::SeqCst);
            *self.context.lock().expect("context mutex") = context.to_vec();
            *self.message.lock().expect("message mutex") = message.to_vec();
            Ok(PersonProof {
                proof: vec![0xaa, 0xbb],
                ring_index: 3,
            })
        }
    }

    fn product() -> ProductContext {
        ProductContext::new("onramp.dot".to_string()).expect("valid product id")
    }

    #[test]
    fn a_session_is_minted_once_and_then_reused() {
        let backend = StubBackend::serving();
        let prover = StubProver::default();
        let sessions = BackendSessions::default();

        let first = futures::executor::block_on(sessions.authorization(
            &backend,
            &prover,
            &product(),
            "fiat-onramp",
            0,
        ));
        let second = futures::executor::block_on(sessions.authorization(
            &backend,
            &prover,
            &product(),
            "fiat-onramp",
            1_000,
        ));

        assert_eq!(first.token(), Some("session-0"));
        assert_eq!(second.token(), Some("session-0"));
        assert_eq!(backend.challenges.load(Ordering::SeqCst), 1);
        assert_eq!(prover.proofs.load(Ordering::SeqCst), 1);
    }

    #[test]
    fn the_proof_is_bound_to_the_product_and_to_the_challenge() {
        let backend = StubBackend::serving();
        let prover = StubProver::default();
        let sessions = BackendSessions::default();

        futures::executor::block_on(sessions.authorization(
            &backend,
            &prover,
            &product(),
            "fiat-onramp",
            0,
        ));

        assert_eq!(
            *prover.context.lock().expect("context mutex"),
            b"onramp.dot".to_vec()
        );
        assert_eq!(
            *prover.message.lock().expect("message mutex"),
            vec![0, 1, 2, 3, 4, 5]
        );
    }

    #[test]
    fn a_session_close_to_expiry_is_replaced_before_it_is_sent() {
        let backend = StubBackend::serving();
        let prover = StubProver::default();
        let sessions = BackendSessions::default();

        futures::executor::block_on(sessions.authorization(
            &backend,
            &prover,
            &product(),
            "fiat-onramp",
            0,
        ));
        // Inside the margin: the token has not expired, but it would while the
        // call it was going to authenticate is in flight.
        let renewed = futures::executor::block_on(sessions.authorization(
            &backend,
            &prover,
            &product(),
            "fiat-onramp",
            6_000,
        ));

        assert_eq!(renewed.token(), Some("session-1"));
        assert_eq!(backend.challenges.load(Ordering::SeqCst), 2);
    }

    #[test]
    fn a_refused_session_is_replaced_rather_than_reused() {
        let backend = StubBackend::serving();
        let prover = StubProver::default();
        let sessions = BackendSessions::default();

        futures::executor::block_on(sessions.authorization(
            &backend,
            &prover,
            &product(),
            "fiat-onramp",
            0,
        ));
        let refreshed = futures::executor::block_on(sessions.reauthenticate(
            &backend,
            &prover,
            &product(),
            "fiat-onramp",
            0,
        ));

        assert_eq!(refreshed.as_deref(), Some("session-1"));
        assert_eq!(prover.proofs.load(Ordering::SeqCst), 2);
    }

    #[test]
    fn a_backend_without_a_handshake_is_asked_once_and_never_again() {
        let backend = StubBackend::without_a_handshake();
        let prover = StubProver::default();
        let sessions = BackendSessions::default();

        for now in [0, 1_000, 2_000] {
            assert_eq!(
                futures::executor::block_on(sessions.authorization(
                    &backend,
                    &prover,
                    &product(),
                    "echo",
                    now,
                )),
                Authorization::Unauthenticated
            );
        }

        assert_eq!(backend.challenges.load(Ordering::SeqCst), 1);
        assert_eq!(
            prover.proofs.load(Ordering::SeqCst),
            0,
            "a backend that wants no proof must not cost one"
        );
    }

    /// A person who cannot prove is the ordinary state for anyone not
    /// registered, so it must not be the most expensive path in the system.
    ///
    /// Without a remembered answer each call re-ran the challenge round trip
    /// and a chain-reading ring scan to be told the same thing, and then went
    /// out unauthenticated to collect the backend's `401`.
    #[test]
    fn a_person_who_cannot_prove_is_not_re_proved_on_every_call() {
        let backend = StubBackend::serving();
        let prover = UnprovableProver::default();
        let sessions = BackendSessions::default();

        for now in [0, 1_000, 2_000] {
            let decided = futures::executor::block_on(sessions.authorization(
                &backend,
                &prover,
                &product(),
                "fiat-onramp",
                now,
            ));
            assert!(
                matches!(decided, Authorization::Unavailable(_)),
                "a backend that wants a person must not be called without one"
            );
        }

        assert_eq!(prover.attempts.load(Ordering::SeqCst), 1);
        assert_eq!(backend.challenges.load(Ordering::SeqCst), 1);
        assert_eq!(
            backend.redeems.load(Ordering::SeqCst),
            0,
            "no proof means nothing to redeem"
        );
    }

    /// The window ends, and the next call tries again: a person can register,
    /// and a wallet can connect.
    #[test]
    fn a_proof_is_attempted_again_once_the_window_passes() {
        let backend = StubBackend::serving();
        let prover = UnprovableProver::default();
        let sessions = BackendSessions::default();

        for now in [0, UNAVAILABLE_BACKOFF_MS + 1] {
            futures::executor::block_on(sessions.authorization(
                &backend,
                &prover,
                &product(),
                "fiat-onramp",
                now,
            ));
        }

        assert_eq!(prover.attempts.load(Ordering::SeqCst), 2);
    }

    /// `productId` missing from the backend's allowlist is a configuration
    /// fact, not a transient one, and the core sends the same request every
    /// time. Retrying it per call spends a ring proof to be refused again.
    #[test]
    fn a_refused_redemption_backs_off_further_than_an_unavailable_one() {
        let backend = StubBackend::refusing_redeems(401);
        let prover = StubProver::default();
        let sessions = BackendSessions::default();

        futures::executor::block_on(sessions.authorization(
            &backend,
            &prover,
            &product(),
            "fiat-onramp",
            0,
        ));
        // Past the transient window, still inside the refusal one.
        futures::executor::block_on(sessions.authorization(
            &backend,
            &prover,
            &product(),
            "fiat-onramp",
            UNAVAILABLE_BACKOFF_MS + 1,
        ));

        assert_eq!(
            backend.redeems.load(Ordering::SeqCst),
            1,
            "a 4xx refusal is held past the transient window"
        );

        futures::executor::block_on(sessions.authorization(
            &backend,
            &prover,
            &product(),
            "fiat-onramp",
            REFUSED_BACKOFF_MS + 1,
        ));
        assert_eq!(backend.redeems.load(Ordering::SeqCst), 2);
    }

    /// A backend that could not read the chain answers `503`, and says when to
    /// come back. It knows its own outage better than a constant here does.
    #[test]
    fn a_backend_naming_its_own_retry_window_is_honoured() {
        let backend = StubBackend::refusing_redeems_for(503, 2);
        let prover = StubProver::default();
        let sessions = BackendSessions::default();

        futures::executor::block_on(sessions.authorization(
            &backend,
            &prover,
            &product(),
            "fiat-onramp",
            0,
        ));
        // Inside the two seconds the backend asked for.
        futures::executor::block_on(sessions.authorization(
            &backend,
            &prover,
            &product(),
            "fiat-onramp",
            1_500,
        ));
        assert_eq!(backend.redeems.load(Ordering::SeqCst), 1);

        // Past them, and well short of the transient default.
        futures::executor::block_on(sessions.authorization(
            &backend,
            &prover,
            &product(),
            "fiat-onramp",
            2_500,
        ));
        assert_eq!(
            backend.redeems.load(Ordering::SeqCst),
            2,
            "the backend's own window outranks the default"
        );
    }

    /// A refusal must not read as the product being turned away on its merits.
    /// The call the product asked for is never sent, so the reason it gets is
    /// about the handshake rather than the backend's answer to a request it
    /// never saw.
    #[test]
    fn an_unavailable_handshake_names_the_handshake() {
        let backend = StubBackend::refusing_redeems(503);
        let prover = StubProver::default();
        let sessions = BackendSessions::default();

        let decided = futures::executor::block_on(sessions.authorization(
            &backend,
            &prover,
            &product(),
            "fiat-onramp",
            0,
        ));

        let Authorization::Unavailable(reason) = decided else {
            panic!("a backend that refused the redemption owes a reason");
        };
        assert!(reason.contains("503"), "reason was {reason}");
        assert_eq!(
            backend.plain_calls.load(Ordering::SeqCst),
            0,
            "the product's own call is not sent to collect a refusal"
        );
    }
}
