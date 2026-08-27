//! Stable host-embedding API for the TrUAPI server runtime.
//!
//! `ProductRuntime` is the target-neutral boundary embedders should use.
//! Platform adapters provide:
//! - a [`truapi_platform::Platform`] implementation for host callbacks,
//! - a task [`Spawner`] for runtime-owned async work,
//! - a [`FrameSink`] for outgoing protocol frames.
//!
//! Target-specific shells such as wasm-bindgen, iOS FFI, or desktop IPC should
//! keep their conversion code outside this module.

use std::collections::HashMap;
use std::sync::atomic::{AtomicBool, AtomicU64, Ordering};
use std::sync::{Arc, Mutex};
use std::time::Duration;

use futures::future::{AbortHandle, Abortable};
use futures::{FutureExt, StreamExt, pin_mut};
use parity_scale_codec::{Decode, Encode};
use thiserror::Error;
use tracing::instrument;
use truapi::v01;
use truapi::{CallContext, CancellationReason};
use truapi_platform::{ChatPlatform, PermissionStatusHost};
use truapi_platform::{
    CoreAdmin, PairingHostAdmin, PairingHostConfig, PermissionAuthorizationRequest,
    PermissionAuthorizationStatus, Platform, ProductContext, SigningHostConfig,
    normalize_product_identifier,
};

use crate::core::TrUApiCore;
use crate::frame::ProtocolMessage;
use crate::host_logic::sso::messages::{RemoteMessage, RemoteMessageData, SsoRequestOutcome, v1};
use crate::runtime::{
    ChatConnection, DEFAULT_REMOTE_AUTHORITY_RESPONSE_TIMEOUT, LocalActivation, PairedSsoPeer,
    PairingHostRole, ProductAuthority, ProductRuntimeHost, ResponderExit, RuntimeServices,
    SigningHostRole, answer_remote_message, establish_pairing, respond_to_pairing, resume_pairing,
};
use crate::subscription::{HostInitiatedSubscriptionManager, Spawner};
use crate::transport::Transport;

/// Outgoing frame sink owned by a host adapter.
///
/// Implementations bridge encoded TrUAPI protocol frames to their target
/// transport: JS callbacks, native callbacks, IPC, channels, or another
/// host-specific mechanism.
pub trait FrameSink: Send + Sync {
    /// Emit one SCALE-encoded [`ProtocolMessage`] frame.
    fn emit_frame(&self, frame: Vec<u8>);
}

/// Dev-only sink that observes host debug events at the core's two frame choke
/// points. A host that does not enable the debugger leaves it unset and the tap
/// is inert. Fire-and-forget by construction: [`DebugSink::emit`] must not block
/// the frame path and must not fail the operation that produced the event, so a
/// slow, absent, or crashed debugger only loses the trace, never a session.
pub trait DebugSink: Send + Sync {
    /// Hand one event to the sink.
    ///
    /// Must not block, and must not panic: `emit` is called from inside the
    /// inbound and outbound frame paths, so a panic here would otherwise unwind
    /// into a live dispatch. The core contains a panic at both tap sites
    /// ([`emit_debug`]) rather than trusting the contract, because the trait is
    /// public and implementable out-of-repo, and because the profiles that can
    /// unwind are exactly the ones a developer runs: the workspace defines no
    /// `[profile.dev]`, so `dev` keeps Cargo's default `panic = "unwind"`, and an
    /// out-of-repo or test sink can be installed under it. (The only in-repo
    /// installer is the wasm host, which cannot unwind at all; `truapi-host-cli`
    /// installs no sink.) Serialize and enqueue only; never do fallible work
    /// that can `unwrap`/panic on the caller's thread.
    ///
    /// The two halves of that contract are NOT equally enforced, and the asymmetry
    /// is deliberate rather than an oversight. Panics are contained: both tap sites
    /// go through [`emit_debug`], which wraps the call in `catch_unwind`. Blocking
    /// is caller-enforced only - nothing here bounds how long `emit` may take.
    ///
    /// It is not enforced HERE, at the trait boundary, and that is a choice worth
    /// stating precisely rather than dressing up. A bounded queue drained by a
    /// spawned task does solve the realistic case: it bounds per-frame work to a
    /// serialize-and-push and converts an overloaded debugger into counted trace
    /// loss. `WsDebugSink` does exactly that, and `services.spawner` is in hand
    /// where the sink transport is built, so the core could impose it.
    ///
    /// What it does not solve is a sink that never yields at all - on wasm32 the
    /// drain needs the same single-threaded event loop the tap is blocking, so a
    /// truly hung `emit` stalls regardless. The trait therefore requires the sink to
    /// own that queue rather than wrapping every sink in one here, which would add a
    /// hop to the frame path for every well-behaved implementation to defend against
    /// a case it still cannot fix.
    ///
    /// So the cost is stated rather than papered over. Whatever thread installs a
    /// sink is the thread a hung one blocks, and it blocks all of that thread's
    /// work: every channel, and the outbound path too, which taps synchronously
    /// inside `Transport::send` while a dispatch is live. Tap ordering buys nothing
    /// against a hang; it only decides whether a corrupt frame is still observed.
    ///
    /// In practice the wasm sink is installed from a Web Worker entry point, so the
    /// blast radius is that worker rather than the page - but that is CONVENTION,
    /// not enforcement: nothing gates sink installation on worker scope, and the
    /// raw wasm glue is publicly exported, so a main-thread consumer can install one
    /// and hang the page. A sink that may be slow must own its own queue and return
    /// immediately.
    fn emit(&self, event: DebugEvent);
}

/// Hand one event to a sink, containing a panic rather than letting it unwind
/// into the frame path that called it.
///
/// `catch_unwind` is a no-op under `panic = "abort"` (the shipping `release`
/// profile, which `codegen` inherits, and `wasm32`, which cannot unwind at all).
/// It is not dead code, because the profiles that *do* unwind are the ones the
/// debugger is used from: the workspace defines no `[profile.dev]`, so `dev`
/// keeps the default `panic = "unwind"`, and the Makefile builds
/// `truapi-host-cli` without `--release`. It also protects any downstream crate
/// that compiles this one under its own unwinding profile.
///
/// No in-process test can prove the protection - Cargo ignores the `panic`
/// setting for test profiles, so a test asserting "the guard saved the dispatch"
/// would pass even with the guard removed. The guard is kept because it costs
/// nothing when nothing panics, not because a test can demonstrate it.
fn emit_debug(sink: Arc<dyn DebugSink>, event: DebugEvent) {
    let result = std::panic::catch_unwind(std::panic::AssertUnwindSafe(move || {
        sink.emit(event);
        // Dropped INSIDE the guard, which is why this takes the `Arc` by value.
        // The frame path holds its own clone, so when `set_debug_sink` has
        // concurrently replaced the sink this binding is the last reference and
        // the out-of-repo destructor runs here - not at the caller's scope end,
        // where it would unwind into a live dispatch.
        drop(sink);
    }));
    if result.is_err() {
        tracing::warn!("debug sink panicked; frame dropped, dispatch unaffected");
    }
}

/// Identifies which product channel on a host a debug event belongs to, so one
/// debugger app can demultiplex several channels.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ChannelId(pub String);

/// Direction of a tapped frame relative to the host core.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum FrameDirection {
    /// Product to core (inbound to the host).
    In,
    /// Core to product (outbound from the host).
    Out,
}

impl FrameDirection {
    /// The wire direction string, from the **product's** vantage - the vantage
    /// the debugger app and the design doc use: `"out"` = the frame left the
    /// product, `"in"` = it arrived at the product. This is the inverse of the
    /// enum's host-vantage variants (`In` = product to core, i.e. it *left* the
    /// product), so every sink serializes the same product-vantage string
    /// instead of re-deriving (and risking inverting) it.
    pub fn wire_str(self) -> &'static str {
        match self {
            FrameDirection::In => "out",
            FrameDirection::Out => "in",
        }
    }
}

/// One observable host debug event. Frame bytes are the untouched
/// `ProtocolMessage`; the debugger decodes them, so the core never does. The
/// enum leaves room for host-internal events (e.g. SSO) that have no wire frame,
/// so it is `#[non_exhaustive]`: adding a variant is not a breaking change.
#[derive(Debug, Clone)]
#[non_exhaustive]
pub enum DebugEvent {
    /// A SCALE wire frame crossing a product channel.
    Frame {
        /// Which product channel on this host.
        channel_id: ChannelId,
        /// Product to core, or core to product.
        dir: FrameDirection,
        /// Untouched encoded `ProtocolMessage` bytes.
        bytes: Vec<u8>,
    },
}

/// Errors returned while routing work through a product runtime.
#[derive(Debug, Clone, Error)]
#[cfg_attr(not(target_arch = "wasm32"), derive(uniffi::Error))]
pub enum ProductRuntimeError {
    /// No connected product runtime is available.
    #[error("product is not connected")]
    NotConnected,
    /// Incoming bytes did not decode as a protocol frame.
    #[error("invalid frame: {reason}")]
    InvalidFrame {
        /// Decode failure reason.
        reason: String,
    },
    /// The connection execution kind does not allow the operation.
    #[error("operation denied for this execution")]
    Denied,
    /// The product connection has already closed.
    #[error("product connection is closed")]
    Closed,
    /// The product or native host did not install the requested surface.
    #[error("operation is unsupported")]
    Unsupported,
    /// The bounded pre-subscription action queue is full.
    #[error("connection action buffer is full")]
    BufferFull,
}

fn product_context(product_id: &str) -> Result<ProductContext, v01::GenericError> {
    ProductContext::new(product_id.to_string()).map_err(|err| v01::GenericError {
        reason: err.to_string(),
    })
}

/// A seedless pairing host: the user's keys live in an external wallet reached
/// over the SSO pairing channel.
///
/// Owns the shared services plus pairing-host state. Local-session activation
/// is a signing-host operation and is not present here.
pub struct PairingHostRuntime {
    services: Arc<RuntimeServices>,
    pairing_host: Arc<PairingHostRole>,
}

impl PairingHostRuntime {
    /// Build a long-lived pairing-host runtime around a platform implementation.
    #[instrument(skip_all, fields(runtime.method = "pairing_host_runtime.new"))]
    pub fn new<P>(platform: Arc<P>, config: PairingHostConfig, spawner: Spawner) -> Self
    where
        P: Platform + 'static,
    {
        Self::with_chat_platform(platform, config, spawner, None)
    }

    /// Same as [`Self::new`], with the host's chat adapter installed. Passing
    /// `None` leaves the host without the Chat capability, so its products'
    /// chat calls resolve as `Unsupported`.
    #[instrument(skip_all, fields(runtime.method = "pairing_host_runtime.with_chat_platform"))]
    pub fn with_chat_platform<P>(
        platform: Arc<P>,
        config: PairingHostConfig,
        spawner: Spawner,
        chat_platform: Option<Arc<dyn ChatPlatform>>,
    ) -> Self
    where
        P: Platform + 'static,
    {
        let platform: Arc<dyn Platform> = platform;
        let services = RuntimeServices::with_chat_platform(
            platform,
            config.host.host_info.clone(),
            config.people_chain_genesis_hash,
            config.bulletin_chain_genesis_hash,
            spawner.clone(),
            chat_platform,
        );
        let pairing_host = PairingHostRole::new(services.clone(), config);
        pairing_host.clone().start_session_store_sync(spawner);
        Self {
            services,
            pairing_host,
        }
    }

    /// Install the host's [`PermissionStatusHost`], which carries the reasoning
    /// for what it changes.
    ///
    /// Set-once, so the capability cannot be swapped under a running product.
    /// Returns whether this call installed it. Call it before serving any
    /// product runtime.
    #[instrument(skip_all, fields(runtime.method = "pairing_host_runtime.set_permission_status_host"))]
    pub fn set_permission_status_host(&self, host: Arc<dyn PermissionStatusHost>) -> bool {
        self.services.install_permission_status_host(host)
    }

    /// Build a product-facing runtime from this pairing host.
    #[instrument(skip_all, fields(runtime.method = "pairing_host_runtime.product_runtime"))]
    pub fn product_runtime(
        &self,
        product: ProductContext,
        sink: Arc<dyn FrameSink>,
    ) -> ProductRuntime {
        ProductRuntime::new(
            self.services.clone(),
            self.pairing_host.clone(),
            product,
            ConnectionAdapters::from_services(&self.services),
            sink,
        )
    }

    /// Build a product-scoped administration handle from this pairing host.
    #[instrument(skip_all, fields(runtime.method = "pairing_host_runtime.product_admin"))]
    pub fn product_admin(&self, product: ProductContext) -> HostAdmin {
        HostAdmin::new(
            self.services.clone(),
            self.pairing_host.clone(),
            product,
            ConnectionAdapters::from_services(&self.services),
        )
    }

    /// Disconnect the active account-authority session.
    #[instrument(skip_all, fields(runtime.method = "pairing_host_runtime.disconnect_session"))]
    pub async fn disconnect_session(&self) {
        self.pairing_host.disconnect().await;
    }

    /// Log out and discard the old pairing keypair.
    ///
    /// The next product login request generates a fresh pairing identity and
    /// presents a new deeplink suitable for another signing host.
    #[instrument(skip_all, fields(runtime.method = "pairing_host_runtime.logout"))]
    pub async fn logout(&self) -> Result<(), v01::GenericError> {
        self.pairing_host
            .logout_and_reset_pairing()
            .await
            .map_err(|reason| v01::GenericError { reason })
    }

    /// Clear one product's capability state while preserving the active
    /// session and unrelated products.
    #[instrument(skip_all, fields(runtime.method = "pairing_host_runtime.clear_product_state", %product_id))]
    pub async fn clear_product_state(&self, product_id: &str) -> Result<(), v01::GenericError> {
        self.pairing_host
            .clear_product_state(product_id)
            .await
            .map_err(|reason| v01::GenericError { reason })
    }

    /// Registered providers available for an internal well-known-ring feature.
    pub async fn ring_vrf_providers(
        &self,
        ring: &v01::RingLocation,
    ) -> Result<Vec<v01::ProductAccountId>, v01::GenericError> {
        self.pairing_host
            .ring_vrf_providers(ring)
            .await
            .map_err(ring_vrf_admin_error)
    }

    /// Current provider selected for an internal well-known-ring feature.
    pub async fn selected_ring_vrf_provider(
        &self,
        ring: &v01::RingLocation,
    ) -> Result<Option<v01::ProductAccountId>, v01::GenericError> {
        self.pairing_host
            .selected_ring_vrf_provider(ring)
            .await
            .map_err(ring_vrf_admin_error)
    }

    /// Select a registered provider for an internal well-known-ring feature.
    pub async fn select_ring_vrf_provider(
        &self,
        ring: v01::RingLocation,
        handle: v01::ProductAccountId,
    ) -> Result<(), v01::GenericError> {
        self.pairing_host
            .select_ring_vrf_provider(ring, handle)
            .await
            .map_err(ring_vrf_admin_error)
    }

    /// Read the active session's X25519 chat identity private key, for hosts
    /// running their own P2P chat channel for the paired identity.
    #[instrument(skip_all, fields(runtime.method = "pairing_host_runtime.session_chat_identity_key"))]
    pub fn session_chat_identity_key(&self) -> Option<[u8; 32]> {
        self.pairing_host
            .session_state()
            .current()?
            .identity_chat_private_key
    }

    /// Read this device's X25519 encryption secret, for hosts running device
    /// sync. Generated and persisted on first read.
    #[instrument(skip_all, fields(runtime.method = "pairing_host_runtime.device_encryption_key"))]
    pub async fn device_encryption_key(&self) -> Result<[u8; 32], v01::GenericError> {
        self.services
            .device_encryption_secret()
            .await
            .map_err(|reason| v01::GenericError { reason })
    }

    /// Resolve `product_id`'s hard-subtree public key from the cache, the
    /// persisted slot, or the Account Holder. `timeout_ms` bounds that wait.
    #[instrument(skip_all, fields(runtime.method = "pairing_host_runtime.product_subtree_public_key"))]
    pub async fn product_subtree_public_key(
        &self,
        product_id: &str,
        timeout_ms: Option<u32>,
    ) -> Result<Option<[u8; 32]>, v01::GenericError> {
        product_subtree_public_key(self.pairing_host.as_ref(), product_id, timeout_ms).await
    }

    /// Clear the canonical paired session and all capability caches/storage
    /// without sending a peer-disconnect notice.
    #[instrument(skip_all, fields(runtime.method = "pairing_host_runtime.reset_session_state"))]
    pub async fn reset_session_state(&self) {
        self.pairing_host.reset_session_state().await;
    }

    /// Start or join the pairing-host login flow for one product.
    #[instrument(skip_all, fields(runtime.method = "pairing_host_runtime.login", %product_id))]
    pub async fn login(
        &self,
        product_id: &str,
    ) -> Result<v01::HostRequestLoginResponse, v01::GenericError> {
        let product = product_context(product_id)?;
        match self.pairing_host.request_login(&product).await {
            Ok(truapi::versioned::account::HostRequestLoginResponse::V1(response)) => Ok(response),
            Err(error) => Err(v01::GenericError {
                reason: pairing_login_error_reason(error),
            }),
        }
    }

    /// Cancel an in-flight SSO pairing request. A no-op when no pairing is
    /// active.
    #[instrument(skip_all, fields(runtime.method = "pairing_host_runtime.cancel_pairing"))]
    pub fn cancel_pairing(&self) {
        self.pairing_host.cancel_login();
    }

    /// Activate a canonical session blob supplied by an external encrypted
    /// session owner without writing the blob to core storage.
    ///
    /// Success means decoding, username resolution, replacement fencing, and
    /// connected-session installation have completed.
    #[instrument(skip_all, fields(runtime.method = "pairing_host_runtime.activate_external_session"))]
    pub async fn activate_external_session(&self, blob: &[u8]) -> Result<(), v01::GenericError> {
        self.pairing_host
            .activate_external_session(blob)
            .await
            .map_err(|reason| v01::GenericError { reason })
    }

    /// Await restoration of the persisted auth-session blob.
    ///
    /// Success means decoding, username resolution, stale-read fencing, and
    /// connected-session installation have completed, so product frames may
    /// immediately use the restored authority session.
    #[instrument(skip_all, fields(runtime.method = "pairing_host_runtime.activate_stored_session"))]
    pub async fn activate_stored_session(&self) -> Result<(), v01::GenericError> {
        self.pairing_host
            .activate_stored_session()
            .await
            .map_err(|reason| v01::GenericError { reason })
    }

    /// Notify the pairing runtime that the persisted auth-session blob may
    /// have changed and should be re-read.
    #[instrument(skip_all, fields(runtime.method = "pairing_host_runtime.notify_session_store_changed"))]
    pub fn notify_session_store_changed(&self) {
        self.pairing_host.notify_session_store_changed();
    }

    /// Read a stored permission authorization status for a product without prompting.
    ///
    /// A device capability also resolves the host application's OS gate, so an
    /// OS refusal reads as `Denied` whatever is stored. Remote,
    /// identity-disclosure and account-access decisions have no OS gate.
    #[instrument(skip_all, fields(runtime.method = "pairing_host_runtime.permission_authorization_status", product_id = %product_id))]
    pub async fn permission_authorization_status(
        &self,
        product_id: &str,
        request: PermissionAuthorizationRequest,
    ) -> Result<PermissionAuthorizationStatus, v01::GenericError> {
        self.product_admin(product_context(product_id)?)
            .permission_authorization_status(request)
            .await
    }

    /// Read stored permission authorization statuses for a product without prompting.
    ///
    /// A device capability also resolves the host application's OS gate, so an
    /// OS refusal reads as `Denied` whatever is stored. Remote,
    /// identity-disclosure and account-access decisions have no OS gate.
    #[instrument(skip_all, fields(runtime.method = "pairing_host_runtime.permission_authorization_statuses", product_id = %product_id))]
    pub async fn permission_authorization_statuses(
        &self,
        product_id: &str,
        requests: Vec<PermissionAuthorizationRequest>,
    ) -> Result<Vec<PermissionAuthorizationStatus>, v01::GenericError> {
        self.product_admin(product_context(product_id)?)
            .permission_authorization_statuses(requests)
            .await
    }

    /// Update a stored permission authorization status for a product.
    #[instrument(skip_all, fields(runtime.method = "pairing_host_runtime.set_permission_authorization_status", product_id = %product_id))]
    pub async fn set_permission_authorization_status(
        &self,
        product_id: &str,
        request: PermissionAuthorizationRequest,
        status: PermissionAuthorizationStatus,
    ) -> Result<(), v01::GenericError> {
        self.product_admin(product_context(product_id)?)
            .set_permission_authorization_status(request, status)
            .await
    }
}

fn pairing_login_error_reason(
    error: truapi::CallError<truapi::versioned::account::HostRequestLoginError>,
) -> String {
    match error {
        truapi::CallError::Domain(truapi::versioned::account::HostRequestLoginError::V1(
            v01::HostRequestLoginError::Unknown { reason },
        ))
        | truapi::CallError::HostFailure { reason }
        | truapi::CallError::MalformedFrame { reason } => reason,
        truapi::CallError::Denied => "login denied".to_string(),
        truapi::CallError::Unsupported => "login unsupported".to_string(),
    }
}

impl PairingHostAdmin for PairingHostRuntime {
    fn cancel_pairing(&self) {
        PairingHostRuntime::cancel_pairing(self);
    }

    fn notify_session_store_changed(&self) {
        PairingHostRuntime::notify_session_store_changed(self);
    }
}

/// A wallet-local signing host: the user's keys are held on this device.
///
/// Owns the shared services plus signing-host state. There is no pairing flow,
/// so pairing cancellation is not present here.
///
/// Raw-bytes and extrinsic-payload signing, v4 transaction construction, and
/// product entropy are implemented; native signing hosts can also serve
/// ring-VRF aliases and on-chain resource allocation.
pub struct SigningHostRuntime {
    services: Arc<RuntimeServices>,
    signing_host: Arc<SigningHostRole>,
}

impl SigningHostRuntime {
    /// Build a long-lived signing-host runtime around a platform implementation.
    /// Chat is answered `Unsupported`; [`Self::with_chat_platform`] serves it.
    #[instrument(skip_all, fields(runtime.method = "signing_host_runtime.new"))]
    pub fn new<P>(platform: Arc<P>, config: SigningHostConfig, spawner: Spawner) -> Self
    where
        P: Platform + 'static,
    {
        Self::with_chat_platform(platform, config, spawner, None)
    }

    /// Build a signing-host runtime that serves Chat through `chat_platform`.
    ///
    /// The pairing host has had this since chat reached the core; a signing
    /// host needs it for the same reason a native host does, and without it no
    /// runnable host in this repo can serve a chat product at all.
    #[instrument(skip_all, fields(runtime.method = "signing_host_runtime.with_chat_platform"))]
    pub fn with_chat_platform<P>(
        platform: Arc<P>,
        config: SigningHostConfig,
        spawner: Spawner,
        chat_platform: Option<Arc<dyn ChatPlatform>>,
    ) -> Self
    where
        P: Platform + 'static,
    {
        let platform: Arc<dyn Platform> = platform;
        let services = RuntimeServices::with_chat_platform(
            platform,
            config.host.host_info.clone(),
            config.people_chain_genesis_hash,
            config.bulletin_chain_genesis_hash,
            spawner,
            chat_platform,
        );
        let signing_host = SigningHostRole::new(services.clone());
        Self {
            services,
            signing_host,
        }
    }

    /// Install the host's [`PermissionStatusHost`], which carries the reasoning
    /// for what it changes.
    ///
    /// Set-once, so the capability cannot be swapped under a running product.
    /// Returns whether this call installed it. Call it before serving any
    /// product runtime.
    #[instrument(skip_all, fields(runtime.method = "signing_host_runtime.set_permission_status_host"))]
    pub fn set_permission_status_host(&self, host: Arc<dyn PermissionStatusHost>) -> bool {
        self.services.install_permission_status_host(host)
    }

    /// Build a product-facing runtime from this signing host.
    #[instrument(skip_all, fields(runtime.method = "signing_host_runtime.product_runtime"))]
    pub fn product_runtime(
        &self,
        product: ProductContext,
        sink: Arc<dyn FrameSink>,
    ) -> ProductRuntime {
        ProductRuntime::new(
            self.services.clone(),
            self.signing_host.clone(),
            product,
            ConnectionAdapters::from_services(&self.services),
            sink,
        )
    }

    /// Build one product connection with adapters scoped to one native
    /// executable while sharing this runtime's authentication and services.
    #[cfg(all(not(target_arch = "wasm32"), feature = "ws-bridge"))]
    pub(crate) fn product_runtime_with(
        &self,
        product: ProductContext,
        adapters: ConnectionAdapters,
        sink: Arc<dyn FrameSink>,
    ) -> ProductRuntime {
        ProductRuntime::new(
            self.services.clone(),
            self.signing_host.clone(),
            product,
            adapters,
            sink,
        )
    }

    /// Build a product-scoped administration handle from this signing host.
    #[instrument(skip_all, fields(runtime.method = "signing_host_runtime.product_admin"))]
    pub fn product_admin(&self, product: ProductContext) -> HostAdmin {
        HostAdmin::new(
            self.services.clone(),
            self.signing_host.clone(),
            product,
            ConnectionAdapters::from_services(&self.services),
        )
    }

    /// Build a product administration handle with adapters scoped to one
    /// native executable connection.
    #[cfg(not(target_arch = "wasm32"))]
    pub(crate) fn product_admin_with(
        &self,
        product: ProductContext,
        adapters: ConnectionAdapters,
    ) -> HostAdmin {
        HostAdmin::new(
            self.services.clone(),
            self.signing_host.clone(),
            product,
            adapters,
        )
    }

    /// Return whether this host currently has an authenticated signing session.
    pub fn has_active_session(&self) -> bool {
        self.signing_host.session_state().current().is_some()
    }

    /// Disconnect the active account-authority session.
    #[instrument(skip_all, fields(runtime.method = "signing_host_runtime.disconnect_session"))]
    pub async fn disconnect_session(&self) {
        self.signing_host.disconnect().await;
    }

    /// Revoke one product's grants from the current local activation while
    /// preserving unrelated products.
    #[instrument(skip_all, fields(runtime.method = "signing_host_runtime.clear_product_state", %product_id))]
    pub async fn clear_product_state(&self, product_id: &str) -> Result<(), v01::GenericError> {
        self.signing_host
            .clear_product_state(product_id)
            .map_err(|error| v01::GenericError {
                reason: error.to_string(),
            })
    }

    /// Registered providers available for an internal well-known-ring feature.
    pub async fn ring_vrf_providers(
        &self,
        ring: &v01::RingLocation,
    ) -> Result<Vec<v01::ProductAccountId>, v01::GenericError> {
        self.signing_host
            .ring_vrf_providers(ring)
            .await
            .map_err(ring_vrf_admin_error)
    }

    /// Current provider selected for an internal well-known-ring feature.
    pub async fn selected_ring_vrf_provider(
        &self,
        ring: &v01::RingLocation,
    ) -> Result<Option<v01::ProductAccountId>, v01::GenericError> {
        self.signing_host
            .selected_ring_vrf_provider(ring)
            .await
            .map_err(ring_vrf_admin_error)
    }

    /// Select a registered provider for an internal well-known-ring feature.
    pub async fn select_ring_vrf_provider(
        &self,
        ring: v01::RingLocation,
        handle: v01::ProductAccountId,
    ) -> Result<(), v01::GenericError> {
        self.signing_host
            .select_ring_vrf_provider(ring, handle)
            .await
            .map_err(ring_vrf_admin_error)
    }

    /// Activate a wallet-local session from host-held secret material (raw
    /// BIP-39 entropy).
    #[instrument(skip_all, fields(runtime.method = "signing_host_runtime.activate_local_session"))]
    pub async fn activate_local_session(&self, secret: Vec<u8>) -> Result<(), v01::GenericError> {
        self.signing_host
            .activate_local_session(secret)
            .await
            .map_err(|err| v01::GenericError {
                reason: err.to_string(),
            })
    }

    /// Activate a wallet-local session from host-held secret material and
    /// attach known identity metadata.
    #[instrument(skip_all, fields(runtime.method = "signing_host_runtime.activate_local_session_with_identity"))]
    pub async fn activate_local_session_with_identity(
        &self,
        secret: Vec<u8>,
        lite_username: Option<String>,
    ) -> Result<(), v01::GenericError> {
        self.signing_host
            .activate_local_session_with_identity(secret, lite_username)
            .await
            .map_err(|err| v01::GenericError {
                reason: err.to_string(),
            })
    }

    /// Answer a pairing host's handshake deeplink and serve the resulting SSO
    /// session until it ends.
    #[instrument(skip_all, fields(runtime.method = "signing_host_runtime.respond_to_pairing"))]
    pub async fn respond_to_pairing(
        &self,
        deeplink: &str,
    ) -> Result<ResponderExit, v01::GenericError> {
        respond_to_pairing(self.services.clone(), self.signing_host.clone(), deeplink)
            .await
            .map_err(|reason| v01::GenericError { reason })
    }

    /// Answer a pairing host's handshake without entering its long-lived serve loop.
    #[instrument(skip_all, fields(runtime.method = "signing_host_runtime.establish_pairing"))]
    pub async fn establish_pairing(&self, deeplink: &str) -> Result<(), v01::GenericError> {
        establish_pairing(self.services.clone(), self.signing_host.clone(), deeplink)
            .await
            .map_err(|reason| v01::GenericError { reason })
    }

    /// Resume a previously paired host from its persisted public peer keys.
    ///
    /// Only [`ResponderExit::PeerDisconnected`] authorizes removing the durable
    /// pairing. Retain it after [`ResponderExit::SubscriptionEnded`] or an error.
    #[instrument(skip_all, fields(runtime.method = "signing_host_runtime.resume_pairing"))]
    pub async fn resume_pairing(
        &self,
        peer: PairedSsoPeer,
    ) -> Result<ResponderExit, v01::GenericError> {
        resume_pairing(self.services.clone(), self.signing_host.clone(), peer)
            .await
            .map_err(|reason| v01::GenericError { reason })
    }

    /// Answer one decrypted SSO remote message with this signing host.
    ///
    /// Session control stays with the caller: `Disconnected` is reported as an
    /// outcome, never handled here.
    #[instrument(skip_all, fields(runtime.method = "signing_host_runtime.answer_sso_request"))]
    pub async fn answer_sso_request(
        &self,
        message: RemoteMessage,
    ) -> SsoRequestOutcome<RemoteMessage> {
        let RemoteMessageData::V1(request) = message.data;
        if matches!(request, v1::RemoteMessage::Disconnected) {
            return SsoRequestOutcome::Disconnected;
        }
        match answer_remote_message(
            &self.services,
            &self.signing_host,
            message.message_id,
            request,
        )
        .await
        {
            Some(answer) => SsoRequestOutcome::Response(answer.response),
            None => SsoRequestOutcome::Ignored,
        }
    }
}

#[cfg(not(target_arch = "wasm32"))]
impl SigningHostRuntime {
    /// Record statement-store accounts the host must keep renewed across
    /// allowance periods.
    #[instrument(skip_all, fields(runtime.method = "signing_host_runtime.track_statement_renewal_targets"))]
    pub async fn track_statement_renewal_targets(
        &self,
        targets: Vec<crate::runtime::StatementRenewalTarget>,
    ) -> Result<(), v01::GenericError> {
        self.signing_host
            .track_statement_renewal_targets(targets)
            .await
            .map_err(|reason| v01::GenericError { reason })
    }

    /// Stop renewing one fixed statement account.
    #[instrument(skip_all, fields(runtime.method = "signing_host_runtime.untrack_statement_renewal_account"))]
    pub async fn untrack_statement_renewal_account(
        &self,
        account_id: &[u8; 32],
    ) -> Result<bool, v01::GenericError> {
        self.signing_host
            .untrack_statement_renewal_account(account_id)
            .await
            .map_err(|reason| v01::GenericError { reason })
    }

    /// Run one statement-store renewal pass now and return per-target
    /// outcomes. This is the primary entry point; hosts whose process cannot
    /// stay alive (mobile) call it from an OS scheduler instead of
    /// [`Self::start_statement_allowance_renewal`].
    #[instrument(skip_all, fields(runtime.method = "signing_host_runtime.renew_statement_allowances"))]
    pub async fn renew_statement_allowances(
        &self,
    ) -> Result<crate::statement_allowance::renewal::StatementRenewalReport, v01::GenericError>
    {
        self.signing_host
            .renew_statement_allowances()
            .await
            .map_err(|reason| v01::GenericError { reason })
    }

    /// Start the periodic statement-store renewal loop (hourly, plus a tick
    /// just after each period boundary). Idempotent; the loop stops when this
    /// runtime is dropped.
    #[instrument(skip_all, fields(runtime.method = "signing_host_runtime.start_statement_allowance_renewal"))]
    pub fn start_statement_allowance_renewal(&self) {
        self.signing_host.start_statement_allowance_renewal();
    }

    /// Delay until the next renewal pass is due, for hosts that schedule
    /// wake-ups through an OS scheduler instead of the in-process loop.
    pub fn next_statement_renewal_delay(&self) -> std::time::Duration {
        std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .map(|now| crate::statement_allowance::renewal::next_tick_delay(now.as_secs()))
            .unwrap_or(std::time::Duration::from_secs(3_600))
    }
    /// The most recent pass the in-process renewal loop ran.
    ///
    /// `None` until a pass has run, which is "not yet" rather than healthy. A host
    /// driving the loop has no return value to inspect, so this is where it learns
    /// that a period was exhausted and an allowance went unrenewed.
    pub fn last_statement_renewal_report(
        &self,
    ) -> Option<crate::statement_allowance::renewal::StatementRenewalReport> {
        self.signing_host.last_statement_renewal_report()
    }
}

/// Adapters scoped to one product connection: the platform serving its
/// syscalls, the optional native Chat adapter, and the connection's Chat
/// stream state. Non-native connections use [`Self::from_services`].
#[derive(Clone)]
pub(crate) struct ConnectionAdapters {
    pub(crate) platform: Arc<dyn Platform>,
    pub(crate) chat_platform: Option<Arc<dyn ChatPlatform>>,
    /// Live OS permission state for this connection. It travels here rather
    /// than on the host runtime because a native host builds one platform per
    /// product execution, so the object that reports OS state has to be the
    /// same one that presents the prompt.
    pub(crate) permission_status: Option<Arc<dyn PermissionStatusHost>>,
    pub(crate) chat: Arc<ChatConnection>,
}

impl ConnectionAdapters {
    /// Default adapters for a connection without native scoping.
    pub(crate) fn from_services(services: &RuntimeServices) -> Self {
        Self {
            platform: services.platform.clone(),
            chat_platform: services.chat_platform.clone(),
            permission_status: services.permission_status_host(),
            chat: Arc::new(ChatConnection::new()),
        }
    }
}

fn ring_vrf_admin_error(
    error: crate::host_logic::sso::messages::RingVrfError,
) -> v01::GenericError {
    v01::GenericError {
        reason: match error {
            crate::host_logic::sso::messages::RingVrfError::Unknown { reason } => reason,
            other => format!("{other:?}"),
        },
    }
}

/// Product-scoped administration handle for host UI.
///
/// Host UI should use this when it needs to inspect or update core-owned state
/// without owning a product frame endpoint.
pub struct HostAdmin {
    authority: Arc<dyn ProductAuthority>,
    product_runtime: Arc<ProductRuntimeHost>,
}

impl HostAdmin {
    /// Build an admin handle from a long-lived host runtime and the adapters
    /// scoped to one product connection.
    #[instrument(skip_all, fields(runtime.method = "host_admin.new"))]
    pub(crate) fn new(
        services: Arc<RuntimeServices>,
        authority: Arc<dyn ProductAuthority>,
        product: ProductContext,
        adapters: ConnectionAdapters,
    ) -> Self {
        let product_runtime = Arc::new(ProductRuntimeHost::from_services(
            services,
            adapters,
            authority.clone(),
            product,
        ));
        Self {
            authority,
            product_runtime,
        }
    }

    /// Core-owned logout/disconnect.
    #[instrument(skip_all, fields(runtime.method = "host_admin.disconnect_session"))]
    pub async fn disconnect_session(&self) {
        self.authority.disconnect().await;
    }

    /// Read a stored permission authorization status without prompting.
    ///
    /// A device capability also resolves the host application's OS gate, so an
    /// OS refusal reads as `Denied` whatever is stored. Remote,
    /// identity-disclosure and account-access decisions have no OS gate.
    #[instrument(skip_all, fields(runtime.method = "host_admin.permission_authorization_status"))]
    pub async fn permission_authorization_status(
        &self,
        request: PermissionAuthorizationRequest,
    ) -> Result<PermissionAuthorizationStatus, v01::GenericError> {
        self.product_runtime
            .permission_authorization_status(request)
            .await
    }

    /// Read stored permission authorization statuses without prompting.
    ///
    /// A device capability also resolves the host application's OS gate, so an
    /// OS refusal reads as `Denied` whatever is stored. Remote,
    /// identity-disclosure and account-access decisions have no OS gate.
    #[instrument(skip_all, fields(runtime.method = "host_admin.permission_authorization_statuses"))]
    pub async fn permission_authorization_statuses(
        &self,
        requests: Vec<PermissionAuthorizationRequest>,
    ) -> Result<Vec<PermissionAuthorizationStatus>, v01::GenericError> {
        self.product_runtime
            .permission_authorization_statuses(requests)
            .await
    }

    /// Update a stored permission authorization status.
    #[instrument(skip_all, fields(runtime.method = "host_admin.set_permission_authorization_status"))]
    pub async fn set_permission_authorization_status(
        &self,
        request: PermissionAuthorizationRequest,
        status: PermissionAuthorizationStatus,
    ) -> Result<(), v01::GenericError> {
        self.product_runtime
            .set_permission_authorization_status(request, status)
            .await
    }
}

#[truapi_platform::async_trait]
impl CoreAdmin for HostAdmin {
    async fn disconnect_session(&self) -> Result<(), v01::GenericError> {
        HostAdmin::disconnect_session(self).await;
        Ok(())
    }

    async fn get_permission_authorization_status(
        &self,
        request: PermissionAuthorizationRequest,
    ) -> Result<PermissionAuthorizationStatus, v01::GenericError> {
        self.permission_authorization_status(request).await
    }

    async fn get_permission_authorization_statuses(
        &self,
        requests: Vec<PermissionAuthorizationRequest>,
    ) -> Result<Vec<PermissionAuthorizationStatus>, v01::GenericError> {
        self.permission_authorization_statuses(requests).await
    }

    async fn set_permission_authorization_status(
        &self,
        request: PermissionAuthorizationRequest,
        status: PermissionAuthorizationStatus,
    ) -> Result<(), v01::GenericError> {
        HostAdmin::set_permission_authorization_status(self, request, status).await
    }

    async fn get_session_chat_identity_key(&self) -> Result<Option<[u8; 32]>, v01::GenericError> {
        Ok(self
            .authority
            .session_state()
            .current()
            .and_then(|session| session.identity_chat_private_key))
    }

    async fn get_device_encryption_key(&self) -> Result<[u8; 32], v01::GenericError> {
        self.product_runtime
            .services()
            .device_encryption_secret()
            .await
            .map_err(|reason| v01::GenericError { reason })
    }

    async fn get_product_subtree_public_key(
        &self,
        product_id: String,
        timeout_ms: Option<u32>,
    ) -> Result<Option<[u8; 32]>, v01::GenericError> {
        product_subtree_public_key(self.authority.as_ref(), &product_id, timeout_ms).await
    }
}

/// Shared body of the two entry points that resolve a product subtree: the
/// `CoreAdmin` method native hosts call and the pairing-host runtime method the
/// wasm bridge wraps.
///
/// The identifier is normalized because the product path normalizes before it
/// populates the cache, so an unnormalized lookup would miss a key the core is
/// already holding.
///
/// The deadline is enforced by dropping the call rather than awaiting it after
/// cancelling. Only the SSO response wait observes the cancellation token; the
/// statement-store setup before it does not, so a call parked there ignores a
/// cancel and would outlive any deadline that waited for it to finish.
async fn product_subtree_public_key(
    authority: &(impl ProductAuthority + ?Sized),
    product_id: &str,
    timeout_ms: Option<u32>,
) -> Result<Option<[u8; 32]>, v01::GenericError> {
    let product_id =
        normalize_product_identifier(product_id).map_err(|reason| v01::GenericError {
            reason: reason.to_string(),
        })?;
    let Some(session) = authority.current_session() else {
        return Ok(None);
    };
    let timeout = timeout_ms
        .map(|timeout_ms| Duration::from_millis(u64::from(timeout_ms)))
        .unwrap_or(DEFAULT_REMOTE_AUTHORITY_RESPONSE_TIMEOUT);
    let mut cx = CallContext::default();
    cx.set_timeout(timeout);

    let call = authority
        .product_subtree_public_key(&cx, &session, product_id)
        .fuse();
    let deadline = futures_timer::Delay::new(timeout).fuse();
    pin_mut!(call, deadline);
    futures::select! {
        result = call => result.map(Some).map_err(|error| v01::GenericError {
            reason: error.to_string(),
        }),
        () = deadline => {
            let reason = CancellationReason::TimedOut { timeout };
            // Best effort for anything already watching the token. The call is
            // dropped on return either way, which is what actually ends it.
            cx.cancel().cancel_with_reason(reason.clone());
            Err(v01::GenericError {
                reason: format!("Product subtree request {reason}"),
            })
        }
    }
}

/// Target-neutral host runtime wrapper.
///
/// `ProductRuntime` is product-scoped. It owns the dispatcher core for one product
/// connection and handles byte-frame ingress, response/subscription egress, and
/// in-flight dispatch cancellation on dispose.
pub struct ProductRuntime {
    core: TrUApiCore,
    admin: HostAdmin,
    transport: Arc<SinkTransport>,
    host_subscriptions: Arc<HostInitiatedSubscriptionManager>,
    disposed: Arc<AtomicBool>,
    in_flight: Mutex<HashMap<u64, AbortHandle>>,
    next_dispatch_id: AtomicU64,
}

/// Host-facing control handle for pushing native events into one concrete
/// product connection.
#[derive(Clone)]
pub struct ProductRuntimeControl {
    runtime: Arc<ProductRuntimeHost>,
    transport: Arc<SinkTransport>,
    host_subscriptions: Arc<HostInitiatedSubscriptionManager>,
    disposed: Arc<AtomicBool>,
}

impl ProductRuntimeControl {
    fn runtime(&self) -> Result<&ProductRuntimeHost, ProductRuntimeError> {
        if self.disposed.load(Ordering::Acquire) {
            return Err(ProductRuntimeError::Closed);
        }
        Ok(&self.runtime)
    }

    /// Publish one host-authored Chat action into this connection's action
    /// stream, buffering it until the product subscribes.
    pub fn publish_chat_action(
        &self,
        action: v01::HostChatActionSubscribeItem,
    ) -> Result<(), ProductRuntimeError> {
        self.runtime()?.publish_chat_action(
            truapi::versioned::chat::HostChatActionSubscribeItem::V1(action),
        )
    }

    /// Request custom-message UI from this connection's product renderer.
    pub fn render_custom_message(
        &self,
        message_id: String,
        message_type: String,
        payload: Vec<u8>,
    ) -> Result<
        truapi::Subscription<Result<v01::CustomRendererNode, v01::GenericError>>,
        ProductRuntimeError,
    > {
        self.runtime()?.native_chat_platform()?;
        let request = truapi::versioned::chat::ProductChatCustomMessageRenderRequest::V1(
            v01::ProductChatCustomMessageRenderRequest {
                message_id,
                message_type,
                payload,
            },
        );
        let transport: Arc<dyn Transport> = self.transport.clone();
        let stream = crate::generated::dispatcher::chat_custom_message_render(
            &self.host_subscriptions,
            transport,
            request,
        )
        .map(|item| {
            item.map(|item| match item {
                truapi::versioned::chat::ProductChatCustomMessageRenderItem::V1(node) => node,
            })
        });
        Ok(truapi::Subscription::new(Box::pin(stream)))
    }
}

impl ProductRuntime {
    /// Build a product-facing host core around a platform implementation and
    /// outgoing frame sink.
    #[instrument(skip_all, fields(runtime.method = "product_runtime.from_platform_with_config"))]
    pub fn from_platform_with_config<P>(
        platform: Arc<P>,
        host_config: PairingHostConfig,
        product: ProductContext,
        spawner: Spawner,
        sink: Arc<dyn FrameSink>,
    ) -> Self
    where
        P: Platform + 'static,
    {
        Self::from_platform_with_chat_platform(platform, host_config, product, spawner, sink, None)
    }

    /// Same as [`Self::from_platform_with_config`], with the host's chat
    /// adapter installed.
    pub fn from_platform_with_chat_platform<P>(
        platform: Arc<P>,
        host_config: PairingHostConfig,
        product: ProductContext,
        spawner: Spawner,
        sink: Arc<dyn FrameSink>,
        chat_platform: Option<Arc<dyn ChatPlatform>>,
    ) -> Self
    where
        P: Platform + 'static,
    {
        let pairing =
            PairingHostRuntime::with_chat_platform(platform, host_config, spawner, chat_platform);
        pairing.product_runtime(product, sink)
    }

    /// Build a product-facing runtime from shared services and an authority.
    #[instrument(skip_all, fields(runtime.method = "product_runtime.new"))]
    pub(crate) fn new(
        services: Arc<RuntimeServices>,
        authority: Arc<dyn ProductAuthority>,
        product: ProductContext,
        adapters: ConnectionAdapters,
        sink: Arc<dyn FrameSink>,
    ) -> Self {
        let admin = HostAdmin::new(services.clone(), authority.clone(), product, adapters);
        let disposed = Arc::new(AtomicBool::new(false));
        let transport = Arc::new(SinkTransport {
            sink,
            disposed: disposed.clone(),
            has_debug: AtomicBool::new(false),
            debug: Mutex::new(None),
        });
        let host_subscriptions = Arc::new(HostInitiatedSubscriptionManager::new());
        Self {
            core: TrUApiCore::from_product_runtime(
                admin.product_runtime.clone(),
                services.spawner.clone(),
                authority.session_state(),
            ),
            admin,
            transport,
            host_subscriptions,
            disposed,
            in_flight: Mutex::new(HashMap::new()),
            next_dispatch_id: AtomicU64::new(0),
        }
    }

    /// Push one SCALE-encoded protocol frame into the dispatcher.
    ///
    /// Calls after [`Self::dispose`] are ignored and return `Ok(())` without
    /// decoding. If dispose happens while a dispatch is in flight, the dispatch
    /// is aborted and this method still returns `Ok(())`.
    #[instrument(skip_all, fields(runtime.method = "product_runtime.receive_frame"))]
    pub async fn receive_frame(&self, frame: Vec<u8>) -> Result<(), ProductRuntimeError> {
        if self.disposed.load(Ordering::Acquire) {
            return Ok(());
        }

        // Tap inbound before decode, so a corrupt frame is still observed.
        if let Some((channel_id, debug)) = self.transport.debug() {
            emit_debug(
                debug,
                DebugEvent::Frame {
                    channel_id,
                    dir: FrameDirection::In,
                    bytes: frame.clone(),
                },
            );
        }

        let message = ProtocolMessage::decode(&mut frame.as_slice()).map_err(|err| {
            ProductRuntimeError::InvalidFrame {
                reason: err.to_string(),
            }
        })?;
        let Some(message) = self.host_subscriptions.handle_message(message) else {
            return Ok(());
        };
        let dispatch_id = self.next_dispatch_id.fetch_add(1, Ordering::Relaxed);
        let (abort_handle, abort_registration) = AbortHandle::new_pair();
        // Same poison recovery as `self.debug`, and for a concrete reason rather than
        // symmetry: `dispose` below holds THIS guard across its whole drain loop and
        // calls `AbortHandle::abort()` inside it, which wakes the task's waker - i.e.
        // arbitrary out-of-repo executor code, under the lock. One panicking waker
        // would poison this mutex and every later `receive_frame` would then panic
        // here, which is exactly the production-host-killing shape the debug tap
        // above was fixed for.
        self.in_flight
            .lock()
            .unwrap_or_else(|poisoned| poisoned.into_inner())
            .insert(dispatch_id, abort_handle);

        let transport: Arc<dyn Transport> = self.transport.clone();
        let _ = Abortable::new(self.core.dispatch(message, transport), abort_registration).await;

        self.in_flight
            .lock()
            .unwrap_or_else(|poisoned| poisoned.into_inner())
            .remove(&dispatch_id);
        if self.disposed.load(Ordering::Acquire) {
            self.core.cancel_subscriptions();
        }
        Ok(())
    }

    /// Return a cloneable native control handle bound to this connection.
    pub fn control(&self) -> ProductRuntimeControl {
        ProductRuntimeControl {
            runtime: self.admin.product_runtime.clone(),
            transport: self.transport.clone(),
            host_subscriptions: self.host_subscriptions.clone(),
            disposed: self.disposed.clone(),
        }
    }

    /// Core-owned logout/disconnect. Best-effort notifies the SSO peer when
    /// the session has channel material, then clears in-memory and persisted
    /// session state.
    #[instrument(skip_all, fields(runtime.method = "product_runtime.disconnect_session"))]
    pub async fn disconnect_session(&self) {
        self.admin.disconnect_session().await;
    }

    /// Read a stored permission authorization status without prompting.
    ///
    /// A device capability also resolves the host application's OS gate, so an
    /// OS refusal reads as `Denied` whatever is stored. Remote,
    /// identity-disclosure and account-access decisions have no OS gate.
    #[instrument(skip_all, fields(runtime.method = "product_runtime.permission_authorization_status"))]
    pub async fn permission_authorization_status(
        &self,
        request: PermissionAuthorizationRequest,
    ) -> Result<PermissionAuthorizationStatus, v01::GenericError> {
        self.admin.permission_authorization_status(request).await
    }

    /// Read stored permission authorization statuses without prompting.
    ///
    /// A device capability also resolves the host application's OS gate, so an
    /// OS refusal reads as `Denied` whatever is stored. Remote,
    /// identity-disclosure and account-access decisions have no OS gate.
    #[instrument(skip_all, fields(runtime.method = "product_runtime.permission_authorization_statuses"))]
    pub async fn permission_authorization_statuses(
        &self,
        requests: Vec<PermissionAuthorizationRequest>,
    ) -> Result<Vec<PermissionAuthorizationStatus>, v01::GenericError> {
        self.admin.permission_authorization_statuses(requests).await
    }

    /// Update a stored permission authorization status. `NotDetermined`
    /// clears the stored value so the next product request prompts again.
    #[instrument(skip_all, fields(runtime.method = "product_runtime.set_permission_authorization_status"))]
    pub async fn set_permission_authorization_status(
        &self,
        request: PermissionAuthorizationRequest,
        status: PermissionAuthorizationStatus,
    ) -> Result<(), v01::GenericError> {
        self.admin
            .set_permission_authorization_status(request, status)
            .await
    }

    /// Install a dev-only [`DebugSink`] that observes every product frame in
    /// both directions for `channel_id`. Absent by default and inert in
    /// production.
    ///
    /// The sink cannot FAIL a dispatch - a panic is contained at both tap sites -
    /// but it can STALL one: `emit` is called synchronously on the frame path, and
    /// nothing here bounds how long it may take. Read [`DebugSink::emit`] before
    /// implementing one; a sink that may be slow must own its own queue and return
    /// immediately.
    pub fn set_debug_sink(&self, channel_id: ChannelId, sink: Arc<dyn DebugSink>) {
        self.transport.set_debug_sink(channel_id, sink);
    }

    /// Dispose this host core. Idempotent.
    ///
    /// Disposal suppresses future outgoing frames, aborts in-flight dispatch
    /// futures, and cancels active subscriptions.
    #[instrument(skip_all, fields(runtime.method = "product_runtime.dispose"))]
    pub fn dispose(&self) {
        if self.disposed.swap(true, Ordering::AcqRel) {
            return;
        }
        for (_, handle) in self
            .in_flight
            .lock()
            .unwrap_or_else(|poisoned| poisoned.into_inner())
            .drain()
        {
            handle.abort();
        }
        self.admin.product_runtime.detach_chat();
        self.host_subscriptions.close();
        self.core.cancel_subscriptions();
    }
}

struct SinkTransport {
    sink: Arc<dyn FrameSink>,
    disposed: Arc<AtomicBool>,
    /// Fast-path flag: `false` (the production default) lets the per-frame
    /// `debug()` return without touching the mutex. Set once when a sink is
    /// installed; a reader that races the install just misses one frame.
    has_debug: AtomicBool,
    debug: Mutex<Option<(ChannelId, Arc<dyn DebugSink>)>>,
}

impl SinkTransport {
    /// The installed debug sink and its channel, if any. Lock-free `None` on the
    /// production path (no sink installed); only locks once one is.
    fn debug(&self) -> Option<(ChannelId, Arc<dyn DebugSink>)> {
        if !self.has_debug.load(Ordering::Relaxed) {
            return None;
        }
        // Recover from poisoning rather than panicking. Of the fixes here, moving
        // the previous sink's `drop` out of `set_debug_sink`'s critical section
        // (below) is what removes the only reachable poisoner: nothing else run
        // under this guard can unwind, the body being an
        // `Option<(ChannelId, Arc<..>)>` clone.
        //
        // Two independent reasons that poisoner is already unreachable in what
        // ships, neither of them the profile. `wasm.rs` is the ONLY non-test
        // `set_debug_sink` caller in the repo (`truapi-host-cli` installs no sink
        // at all): the wasm32 target cannot unwind, AND that call site builds a
        // fresh `SinkTransport` per `product_runtime()` and installs at most once
        // on it, so `previous` is always `None` and there is no destructor to run
        // under the lock regardless of profile.
        //
        // The recovery is kept regardless, because this guard sits on the per-frame
        // path in both directions and outside `emit_debug`'s `catch_unwind`, so any
        // future in-guard work that can unwind would land in live dispatch.
        self.debug
            .lock()
            .unwrap_or_else(|poisoned| poisoned.into_inner())
            .clone()
    }

    fn set_debug_sink(&self, channel_id: ChannelId, sink: Arc<dyn DebugSink>) {
        // Take the previous sink out under the lock, then drop it AFTER releasing.
        // `*guard = Some(..)` would drop the old `Arc` in place, running an
        // out-of-repo destructor inside the critical section: a panic there
        // poisoned the mutex, and every subsequent frame then panicked on the
        // lock. Dropping outside keeps the destructor off the critical section.
        // It is not containment - this drop is not wrapped in `catch_unwind` - and
        // it is not necessarily the last reference either: a frame being tapped
        // concurrently holds its own clone and may be the one that drops it. That
        // is why `emit_debug` takes its clone by value and drops it inside the
        // guard, so the frame path never runs the destructor uncontained.
        let previous = self
            .debug
            .lock()
            .unwrap_or_else(|poisoned| poisoned.into_inner())
            .replace((channel_id, sink));
        self.has_debug.store(true, Ordering::Relaxed);
        drop(previous);
    }
}

impl Transport for SinkTransport {
    fn send(&self, message: ProtocolMessage) {
        if self.disposed.load(Ordering::Acquire) {
            return;
        }
        let encoded = message.encode();
        // Forward to the product first, then tap: the debugger is in the path
        // but never in the critical path for LATENCY - the product already has the
        // frame. That is not a claim about a hung sink: `emit_debug` runs
        // synchronously here, so a sink that never returns stalls this dispatch.
        // See `DebugSink::emit` for why that is caller-enforced.
        match self.debug() {
            Some((channel_id, debug)) => {
                self.sink.emit_frame(encoded.clone());
                emit_debug(
                    debug,
                    DebugEvent::Frame {
                        channel_id,
                        dir: FrameDirection::Out,
                        bytes: encoded,
                    },
                );
            }
            None => self.sink.emit_frame(encoded),
        }
    }

    fn on_message(
        &self,
        _handler: Box<dyn Fn(ProtocolMessage) + Send + Sync>,
    ) -> Box<dyn FnOnce()> {
        Box::new(|| {})
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::frame::{Payload, ProtocolMessage, subscription_ids};
    use crate::test_support::{StubPlatform, runtime_config, test_spawner};
    use parity_scale_codec::Encode;
    use std::sync::atomic::Ordering;

    #[derive(Default)]
    struct RecordingSink {
        frames: Mutex<Vec<Vec<u8>>>,
    }

    impl FrameSink for RecordingSink {
        fn emit_frame(&self, frame: Vec<u8>) {
            self.frames
                .lock()
                .expect("recording sink mutex poisoned")
                .push(frame);
        }
    }

    fn assert_send<T: Send>(_: T) {}

    fn assert_send_sync<T: Send + Sync>() {}

    #[test]
    fn a_cached_subtree_answers_without_reaching_the_wallet() {
        let platform = Arc::new(StubPlatform::default());
        let (host_config, _) = runtime_config("myapp.dot");
        let runtime = PairingHostRuntime::new(platform.clone(), host_config, test_spawner());
        let session = crate::test_support::sso_session_info();
        runtime
            .pairing_host
            .session_state()
            .set_session(session.clone());
        runtime
            .pairing_host
            .cache_product_subtree_for_test(&session, "myapp.dot", [9; 32]);

        let key =
            futures::executor::block_on(runtime.product_subtree_public_key("myapp.dot", Some(1)))
                .expect("a cached subtree resolves");
        assert_eq!(key, Some([9; 32]));

        // The cache comes before the wallet. A one-millisecond deadline means
        // anything that reached for the wallet here would time out instead of
        // answering, and no statement-store traffic says it did not try.
        assert!(
            platform
                .sent_rpc
                .lock()
                .expect("rpc list mutex poisoned")
                .is_empty()
        );
    }

    #[test]
    fn a_timeout_bounds_the_wait_for_the_account_holder() {
        let (host_config, _) = runtime_config("myapp.dot");
        let runtime = PairingHostRuntime::new(
            Arc::new(StubPlatform::default()),
            host_config,
            test_spawner(),
        );
        runtime
            .pairing_host
            .session_state()
            .set_session(crate::test_support::sso_session_info());

        // Nothing answers the wallet request, and wait_for_sso_remote_response exits
        // only on a peer answer, a disconnect, or the caller's token. Without
        // the timeout cancelling that token the call never returns, so this
        // test would hang rather than fail.
        let error =
            futures::executor::block_on(runtime.product_subtree_public_key("myapp.dot", Some(1)))
                .expect_err("an unanswered wallet request ends at its deadline");
        assert!(
            error.reason.contains("timed out"),
            "expected a timeout, got {}",
            error.reason
        );
    }

    #[test]
    fn product_runtime_and_dispatch_future_are_send() {
        assert_send_sync::<ProductRuntime>();
        let (host_config, product) = runtime_config("myapp.dot");
        let runtime = ProductRuntime::from_platform_with_config(
            Arc::new(StubPlatform::default()),
            host_config,
            product,
            test_spawner(),
            Arc::new(RecordingSink::default()),
        );

        assert_send(runtime.receive_frame(Vec::new()));
    }

    #[derive(Default)]
    struct RecordingDebugSink {
        events: Mutex<Vec<(ChannelId, FrameDirection, Vec<u8>)>>,
    }

    impl DebugSink for RecordingDebugSink {
        fn emit(&self, event: DebugEvent) {
            match event {
                DebugEvent::Frame {
                    channel_id,
                    dir,
                    bytes,
                } => self
                    .events
                    .lock()
                    .expect("debug events mutex poisoned")
                    .push((channel_id, dir, bytes)),
            }
        }
    }

    #[test]
    fn debug_sink_taps_frames_in_both_directions() {
        let platform = Arc::new(StubPlatform::default());
        let sink = Arc::new(RecordingSink::default());
        let debug = Arc::new(RecordingDebugSink::default());
        let (host_config, product) = runtime_config("myapp.dot");
        let runtime = ProductRuntime::from_platform_with_config(
            platform,
            host_config,
            product,
            test_spawner(),
            sink.clone(),
        );
        runtime.set_debug_sink(ChannelId("myapp.dot".to_string()), debug.clone());

        let ids = subscription_ids("theme_subscribe").expect("known subscription");
        let frame = ProtocolMessage {
            request_id: "theme:1".to_string(),
            payload: Payload {
                id: ids.start_id,
                value: Vec::new(),
            },
        };
        let raw = frame.encode();
        futures::executor::block_on(runtime.receive_frame(raw.clone())).unwrap();

        // The subscription's first item is emitted asynchronously; wait for it,
        // then let the tap (which runs right after delivery in `send`) settle.
        let deadline = std::time::Instant::now() + std::time::Duration::from_secs(2);
        while sink
            .frames
            .lock()
            .expect("recording sink mutex poisoned")
            .is_empty()
            && std::time::Instant::now() < deadline
        {
            std::thread::sleep(std::time::Duration::from_millis(5));
        }
        std::thread::sleep(std::time::Duration::from_millis(20));

        // Snapshot into owned vecs (never hold a lock across an assertion).
        let (inbound, outbound, channels): (Vec<Vec<u8>>, Vec<Vec<u8>>, Vec<ChannelId>) = {
            let events = debug.events.lock().expect("debug events mutex poisoned");
            (
                events
                    .iter()
                    .filter(|(_, dir, _)| *dir == FrameDirection::In)
                    .map(|(_, _, bytes)| bytes.clone())
                    .collect(),
                events
                    .iter()
                    .filter(|(_, dir, _)| *dir == FrameDirection::Out)
                    .map(|(_, _, bytes)| bytes.clone())
                    .collect(),
                events.iter().map(|(cid, _, _)| cid.clone()).collect(),
            )
        };
        let delivered = sink
            .frames
            .lock()
            .expect("recording sink mutex poisoned")
            .clone();

        // Every event carries the installed channel id.
        assert!(
            channels
                .iter()
                .all(|c| *c == ChannelId("myapp.dot".to_string())),
            "every event carries its channel id"
        );
        // Inbound tapped once, untouched, before decode.
        assert_eq!(
            inbound,
            vec![raw],
            "inbound frame tapped exactly once, untouched"
        );
        // Both directions fire, and every delivered outbound frame is tapped in
        // order: the tap is in the path, not a fabricated side channel.
        assert!(
            !outbound.is_empty(),
            "at least one outbound frame is tapped"
        );
        assert_eq!(
            outbound, delivered,
            "every delivered outbound frame is tapped, in order"
        );
    }

    /// A sink whose `Drop` panics. `emit` is a no-op: the point is the destructor,
    /// which `set_debug_sink` runs when it replaces this sink.
    struct PanicOnDropSink;

    impl DebugSink for PanicOnDropSink {
        fn emit(&self, _event: DebugEvent) {}
    }

    impl Drop for PanicOnDropSink {
        fn drop(&mut self) {
            panic!("out-of-repo sink destructor");
        }
    }

    /// Records how many frames the transport had already delivered at the moment
    /// each outbound tap fired, which is what pins the deliver-THEN-tap ordering.
    struct DeliveryOrderSink {
        transport: Arc<RecordingSink>,
        delivered_at_tap: Mutex<Vec<usize>>,
    }

    impl DebugSink for DeliveryOrderSink {
        fn emit(&self, event: DebugEvent) {
            let DebugEvent::Frame { dir, .. } = event;
            if dir != FrameDirection::Out {
                return;
            }
            let delivered = self
                .transport
                .frames
                .lock()
                .expect("recording sink mutex poisoned")
                .len();
            self.delivered_at_tap
                .lock()
                .expect("delivery order mutex poisoned")
                .push(delivered);
        }
    }

    #[test]
    fn a_panicking_sink_destructor_does_not_poison_the_tap_for_later_frames() {
        // `set_debug_sink` takes the previous sink out under the lock and drops it
        // after releasing. If it dropped in place instead, this destructor's unwind
        // would poison the debug mutex and - before the recovery below it - every
        // subsequent frame would panic on that lock, killing a live host over a
        // third-party sink's `Drop`. Both properties are asserted: the unwind
        // surfaces to whoever INSTALLS a sink, and the tap keeps working after.
        //
        // This pins the two fixes as a PAIR, not individually: reverting only the
        // drop-outside-the-guard change leaves the poison recovery to absorb it, and
        // reverting only the recovery leaves no poisoner to trip it. Restoring both
        // (the original code) fails here on the poisoned lock, which is the
        // production shape being guarded against.
        let platform = Arc::new(StubPlatform::default());
        let transport = Arc::new(RecordingSink::default());
        let (host_config, product) = runtime_config("myapp.dot");
        let runtime = ProductRuntime::from_platform_with_config(
            platform,
            host_config,
            product,
            test_spawner(),
            transport,
        );
        let channel = ChannelId("myapp.dot".to_string());
        runtime.set_debug_sink(channel.clone(), Arc::new(PanicOnDropSink));

        // Replacing it drops the panicking sink. The unwind lands HERE, on the
        // installer, not on a later frame.
        let replaced = Arc::new(RecordingDebugSink::default());
        let installed = std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| {
            runtime.set_debug_sink(channel.clone(), replaced.clone());
        }));
        assert!(
            installed.is_err(),
            "the destructor's panic should surface to the installer"
        );

        // The mutex must not be poisoned: the new sink is reachable and taps.
        let ids = subscription_ids("theme_subscribe").expect("known subscription");
        let frame = ProtocolMessage {
            request_id: "theme:1".to_string(),
            payload: Payload {
                id: ids.start_id,
                value: Vec::new(),
            },
        };
        futures::executor::block_on(runtime.receive_frame(frame.encode())).unwrap();
        let tapped = replaced
            .events
            .lock()
            .expect("debug events mutex poisoned")
            .len();
        assert!(
            tapped > 0,
            "the replacement sink should still receive frames after the panic"
        );
    }

    /// The inbound tap runs BEFORE decode, so a frame the codec rejects is still
    /// observed. Asserting a well-formed frame reaches the sink cannot see this -
    /// it arrives either way. Only an undecodable frame can: the call must fail AND
    /// the sink must still hold those exact bytes.
    #[test]
    fn a_corrupt_inbound_frame_is_tapped_even_though_decode_rejects_it() {
        let platform = Arc::new(StubPlatform::default());
        let transport = Arc::new(RecordingSink::default());
        let (host_config, product) = runtime_config("myapp.dot");
        let runtime = ProductRuntime::from_platform_with_config(
            platform,
            host_config,
            product,
            test_spawner(),
            transport,
        );
        let debug = Arc::new(RecordingDebugSink::default());
        runtime.set_debug_sink(ChannelId("myapp.dot".to_string()), debug.clone());

        // Not a `ProtocolMessage`: the leading compact length claims far more
        // bytes than follow, so decode fails before any field is read.
        let corrupt = vec![0xff, 0xff, 0xff, 0xff];
        let outcome = futures::executor::block_on(runtime.receive_frame(corrupt.clone()));
        assert!(
            matches!(outcome, Err(ProductRuntimeError::InvalidFrame { .. })),
            "expected decode to reject the frame, got {outcome:?}"
        );

        let events = debug.events.lock().expect("debug events mutex poisoned");
        assert_eq!(
            events.len(),
            1,
            "a frame rejected by decode must still be tapped"
        );
        assert_eq!(events[0].1, FrameDirection::In);
        assert_eq!(
            events[0].2, corrupt,
            "the tap must carry the original bytes, not a decoded form"
        );
    }

    /// A sink whose destructor panics must not unwind the FRAME path.
    ///
    /// `set_debug_sink` drops the previous sink outside the lock, which covers the
    /// case where the installer holds the last reference. It does not cover this
    /// one: the frame path clones its own `Arc` before tapping, so if the sink is
    /// replaced while that tap is in flight, the frame path holds the last
    /// reference and runs the destructor itself. `emit_debug` takes the clone by
    /// value so that drop lands inside its `catch_unwind`; with `&dyn DebugSink`
    /// the clone instead dies at the caller's scope end, outside the guard, and
    /// unwinds a live dispatch.
    #[test]
    fn a_panicking_sink_destructor_does_not_unwind_the_frame_path() {
        /// Blocks inside `emit` until the installer has released its reference, so
        /// the frame path is provably the one that drops this sink.
        struct HandoffSink {
            tapped: std::sync::mpsc::SyncSender<()>,
            release: Mutex<std::sync::mpsc::Receiver<()>>,
        }
        impl DebugSink for HandoffSink {
            fn emit(&self, _event: DebugEvent) {
                let _ = self.tapped.send(());
                let _ = self
                    .release
                    .lock()
                    .expect("release receiver poisoned")
                    .recv();
            }
        }
        impl Drop for HandoffSink {
            fn drop(&mut self) {
                panic!("out-of-repo sink destructor");
            }
        }

        let platform = Arc::new(StubPlatform::default());
        let transport = Arc::new(RecordingSink::default());
        let (host_config, product) = runtime_config("myapp.dot");
        let runtime = Arc::new(ProductRuntime::from_platform_with_config(
            platform,
            host_config,
            product,
            test_spawner(),
            transport,
        ));
        let channel = ChannelId("myapp.dot".to_string());

        let (tapped_tx, tapped_rx) = std::sync::mpsc::sync_channel(1);
        let (release_tx, release_rx) = std::sync::mpsc::sync_channel(1);
        runtime.set_debug_sink(
            channel.clone(),
            Arc::new(HandoffSink {
                tapped: tapped_tx,
                release: Mutex::new(release_rx),
            }),
        );

        let ids = subscription_ids("theme_subscribe").expect("known subscription");
        let frame = ProtocolMessage {
            request_id: "theme:1".to_string(),
            payload: Payload {
                id: ids.start_id,
                value: Vec::new(),
            },
        };
        let encoded = frame.encode();
        let frame_runtime = Arc::clone(&runtime);
        let frame_thread = std::thread::spawn(move || {
            futures::executor::block_on(frame_runtime.receive_frame(encoded))
        });

        // Wait until the tap is inside `emit`, holding its own clone.
        tapped_rx
            .recv_timeout(std::time::Duration::from_secs(5))
            .expect("tap never fired");
        // Replace the sink: the installer's reference goes, leaving the frame
        // path's clone as the last one.
        runtime.set_debug_sink(channel, Arc::new(RecordingDebugSink::default()));
        let _ = release_tx.send(());

        let outcome = frame_thread.join();
        assert!(
            outcome.is_ok(),
            "a panicking sink destructor unwound the frame path"
        );
    }

    #[test]
    fn outbound_frames_are_delivered_before_they_are_tapped() {
        // `send` hands the frame to the transport and taps afterwards, so no sink can
        // delay or drop THIS frame - it is already delivered. It says nothing about
        // the next one: `send` returns only after the tap, so a slow sink delays
        // every subsequent frame (see `DebugSink::emit`). Asserting the two lists
        // match cannot see the ordering at all - they are order-identical either way.
        // Counting deliveries AT TAP TIME can: tap N must observe N deliveries, and
        // tapping first would make it N-1.
        let platform = Arc::new(StubPlatform::default());
        let transport = Arc::new(RecordingSink::default());
        let (host_config, product) = runtime_config("myapp.dot");
        let runtime = ProductRuntime::from_platform_with_config(
            platform,
            host_config,
            product,
            test_spawner(),
            transport.clone(),
        );
        let debug = Arc::new(DeliveryOrderSink {
            transport: transport.clone(),
            delivered_at_tap: Mutex::new(Vec::new()),
        });
        runtime.set_debug_sink(ChannelId("myapp.dot".to_string()), debug.clone());

        let ids = subscription_ids("theme_subscribe").expect("known subscription");
        let frame = ProtocolMessage {
            request_id: "theme:1".to_string(),
            payload: Payload {
                id: ids.start_id,
                value: Vec::new(),
            },
        };
        futures::executor::block_on(runtime.receive_frame(frame.encode())).unwrap();

        let deadline = std::time::Instant::now() + std::time::Duration::from_secs(2);
        while debug
            .delivered_at_tap
            .lock()
            .expect("delivery order mutex poisoned")
            .is_empty()
            && std::time::Instant::now() < deadline
        {
            std::thread::sleep(std::time::Duration::from_millis(5));
        }
        std::thread::sleep(std::time::Duration::from_millis(20));

        let observed = debug
            .delivered_at_tap
            .lock()
            .expect("delivery order mutex poisoned")
            .clone();
        assert!(!observed.is_empty(), "expected at least one outbound tap");
        // Tap i (0-based) must see i+1 frames already delivered.
        let expected: Vec<usize> = (1..=observed.len()).collect();
        assert_eq!(
            observed, expected,
            "each outbound tap must run after its own frame was delivered"
        );
    }

    /// Every profile that ships a host aborts on panic, so [`emit_debug`]'s
    /// `catch_unwind` cannot fire in a shipping build - which is why
    /// [`DebugSink::emit`] documents its no-panic rule as caller-enforced. The
    /// guard still earns its keep everywhere else: `dev` inherits
    /// `panic = "unwind"` (the workspace defines no `[profile.dev]`), the Makefile
    /// builds `truapi-host-cli` without `--release`, and a downstream crate may
    /// compile this one under its own unwinding profile.
    ///
    /// No unit test can demonstrate the guard itself - Cargo ignores the `panic`
    /// setting for test profiles, so a "the guard protected dispatch" assertion
    /// passes with the guard removed. The premise is what is checkable, and this
    /// fails if a shipping profile stops aborting, at which point the reasoning on
    /// `DebugSink::emit` needs revisiting.
    #[test]
    fn shipping_profiles_abort_on_panic() {
        let workspace_manifest = std::path::Path::new(env!("CARGO_MANIFEST_DIR"))
            .ancestors()
            .nth(3)
            .expect("crate lives at <workspace>/rust/crates/truapi-server")
            .join("Cargo.toml");
        let manifest = std::fs::read_to_string(&workspace_manifest)
            .expect("workspace manifest is readable from the crate directory");
        let release = manifest
            .split("[profile.release]")
            .nth(1)
            .expect("workspace defines [profile.release]")
            .split("\n[")
            .next()
            .expect("release profile section");
        assert!(
            release.contains("panic = \"abort\""),
            "release no longer aborts on panic: revisit DebugSink::emit's contract docs"
        );
        assert!(
            manifest.contains("[profile.codegen]") && manifest.contains("inherits = \"release\""),
            "codegen no longer inherits release: recheck what the ws-bridge artifacts build with"
        );
    }

    #[test]
    fn frame_direction_wire_str_is_product_vantage() {
        // The wire string is product-vantage (what the debugger and design doc
        // use), the inverse of the enum's host-vantage names: a frame the host
        // tapped as `In` (product to core) *left the product*, so it serializes
        // as `"out"`. This pins the convention so a sink can't re-invert it.
        assert_eq!(FrameDirection::In.wire_str(), "out");
        assert_eq!(FrameDirection::Out.wire_str(), "in");
    }

    #[test]
    fn app_connection_rejects_custom_rendering() {
        let (host_config, product) = runtime_config("myapp.dot");
        let runtime = ProductRuntime::from_platform_with_config(
            Arc::new(StubPlatform::default()),
            host_config,
            product,
            test_spawner(),
            Arc::new(RecordingSink::default()),
        );

        assert!(matches!(
            runtime
                .control()
                .render_custom_message("message".into(), "vote".into(), vec![]),
            Err(ProductRuntimeError::Denied)
        ));
    }

    #[test]
    fn app_connection_rejects_publishing_a_chat_action() {
        let (host_config, product) = runtime_config("myapp.dot");
        let runtime = ProductRuntime::from_platform_with_config(
            Arc::new(StubPlatform::default()),
            host_config,
            product,
            test_spawner(),
            Arc::new(RecordingSink::default()),
        );

        assert!(matches!(
            runtime
                .control()
                .publish_chat_action(v01::HostChatActionSubscribeItem {
                    room_id: "support".into(),
                    peer: "myapp.dot".into(),
                    payload: v01::ChatActionPayload::ActionTriggered(v01::ActionTrigger {
                        message_id: "message".into(),
                        action_id: "vote".into(),
                        payload: None,
                    }),
                }),
            Err(ProductRuntimeError::Denied)
        ));
    }

    #[test]
    fn generated_filter_denies_chat_request_on_app_connection() {
        let sink = Arc::new(RecordingSink::default());
        let (host_config, product) = runtime_config("myapp.dot");
        let runtime = ProductRuntime::from_platform_with_config(
            Arc::new(StubPlatform::default()),
            host_config,
            product,
            test_spawner(),
            sink.clone(),
        );
        let ids = crate::frame::request_ids("chat_create_room").expect("known Chat request");
        let request = truapi::versioned::chat::HostChatCreateRoomRequest::V1(
            v01::HostChatCreateRoomRequest {
                room_id: "room".into(),
                name: "Room".into(),
                icon: String::new(),
            },
        );
        let frame = ProtocolMessage {
            request_id: "chat:1".into(),
            payload: Payload {
                id: ids.request_id,
                value: request.encode(),
            },
        };

        futures::executor::block_on(runtime.receive_frame(frame.encode())).unwrap();

        let frames = sink.frames.lock().unwrap();
        assert_eq!(frames.len(), 1);
        let response = ProtocolMessage::decode(&mut frames[0].as_slice()).unwrap();
        assert_eq!(response.payload.id, ids.response_id);
        let expected = crate::frame::encode_versioned_err_payload(
            truapi::CallError::<truapi::versioned::chat::HostChatCreateRoomError>::Denied,
            1,
        );
        assert_eq!(response.payload.value, expected);
    }

    #[test]
    fn generated_filter_denies_chat_register_bot_on_app_connection() {
        let sink = Arc::new(RecordingSink::default());
        let (host_config, product) = runtime_config("myapp.dot");
        let runtime = ProductRuntime::from_platform_with_config(
            Arc::new(StubPlatform::default()),
            host_config,
            product,
            test_spawner(),
            sink.clone(),
        );
        let ids = crate::frame::request_ids("chat_register_bot").expect("known Chat request");
        let request = truapi::versioned::chat::HostChatRegisterBotRequest::V1(
            v01::HostChatRegisterBotRequest {
                bot_id: "bot".into(),
                name: "Bot".into(),
                icon: String::new(),
            },
        );
        let frame = ProtocolMessage {
            request_id: "chat:bot".into(),
            payload: Payload {
                id: ids.request_id,
                value: request.encode(),
            },
        };

        futures::executor::block_on(runtime.receive_frame(frame.encode())).unwrap();

        let frames = sink.frames.lock().unwrap();
        assert_eq!(frames.len(), 1);
        let response = ProtocolMessage::decode(&mut frames[0].as_slice()).unwrap();
        assert_eq!(response.payload.id, ids.response_id);
        let expected = crate::frame::encode_versioned_err_payload(
            truapi::CallError::<truapi::versioned::chat::HostChatRegisterBotError>::Denied,
            1,
        );
        assert_eq!(response.payload.value, expected);
    }

    #[test]
    fn generated_filter_denies_chat_subscription_on_app_connection() {
        let sink = Arc::new(RecordingSink::default());
        let (host_config, product) = runtime_config("myapp.dot");
        let runtime = ProductRuntime::from_platform_with_config(
            Arc::new(StubPlatform::default()),
            host_config,
            product,
            test_spawner(),
            sink.clone(),
        );
        let ids = subscription_ids("chat_action_subscribe").expect("known Chat subscription");
        let frame = ProtocolMessage {
            request_id: "chat:actions".into(),
            payload: Payload {
                id: ids.start_id,
                value: Vec::new(),
            },
        };

        futures::executor::block_on(runtime.receive_frame(frame.encode())).unwrap();

        let frames = sink.frames.lock().unwrap();
        assert_eq!(frames.len(), 1);
        let response = ProtocolMessage::decode(&mut frames[0].as_slice()).unwrap();
        assert_eq!(response.request_id, "chat:actions");
        assert_eq!(response.payload.id, ids.interrupt_id);
        assert!(response.payload.value.is_empty());
    }

    #[test]
    fn dispose_cancels_active_subscriptions() {
        let theme_stream_dropped = Arc::new(AtomicBool::new(false));
        let platform = Arc::new(StubPlatform {
            theme_stream_pending: true,
            theme_stream_dropped: theme_stream_dropped.clone(),
            ..Default::default()
        });
        let sink = Arc::new(RecordingSink::default());
        let (host_config, product) = runtime_config("myapp.dot");
        let runtime = ProductRuntime::from_platform_with_config(
            platform,
            host_config,
            product,
            test_spawner(),
            sink,
        );

        let ids = subscription_ids("theme_subscribe").expect("known subscription");
        let frame = ProtocolMessage {
            request_id: "theme:1".to_string(),
            payload: Payload {
                id: ids.start_id,
                value: Vec::new(),
            },
        };
        futures::executor::block_on(runtime.receive_frame(frame.encode())).unwrap();

        runtime.dispose();

        let deadline = std::time::Instant::now() + std::time::Duration::from_secs(2);
        while !theme_stream_dropped.load(Ordering::SeqCst) {
            assert!(
                std::time::Instant::now() < deadline,
                "dispose did not drop the active theme subscription stream"
            );
            std::thread::sleep(std::time::Duration::from_millis(5));
        }
    }

    #[test]
    fn answer_sso_request_distinguishes_disconnect_from_ignorable_messages() {
        use crate::host_logic::sso::messages::{
            RemoteMessage, RemoteMessageData, SignRawLegacyResponse, v1,
        };
        use truapi_platform::{HostInfo, PlatformInfo, SigningHostConfig};

        const ENTROPY: [u8; 32] = [0xab; 32];

        let config = SigningHostConfig::new(
            HostInfo {
                name: "Polkadot Mobile".to_string(),
                icon: None,
                version: None,
                platform: truapi::latest::HostPlatform::Unknown,
            },
            PlatformInfo::default(),
            [0; 32],
            [0xbb; 32],
        )
        .expect("signing host config is valid");
        let runtime =
            SigningHostRuntime::new(Arc::new(StubPlatform::default()), config, test_spawner());
        futures::executor::block_on(runtime.activate_local_session(ENTROPY.to_vec()))
            .expect("activation succeeds");

        let disconnected = RemoteMessage {
            message_id: "m1".to_string(),
            data: RemoteMessageData::V1(v1::RemoteMessage::Disconnected),
        };
        let outcome = futures::executor::block_on(runtime.answer_sso_request(disconnected));
        assert!(matches!(outcome, SsoRequestOutcome::Disconnected));

        let response_variant = RemoteMessage {
            message_id: "m2".to_string(),
            data: RemoteMessageData::V1(v1::RemoteMessage::SignRawLegacyResponse(
                SignRawLegacyResponse {
                    responding_to: "m2".to_string(),
                    signature: Ok(vec![]),
                },
            )),
        };
        let outcome = futures::executor::block_on(runtime.answer_sso_request(response_variant));
        assert!(matches!(outcome, SsoRequestOutcome::Ignored));
    }

    #[test]
    fn answer_sso_request_returns_a_correlated_response() {
        use crate::host_logic::sso::messages::{
            ProductSubtreeRequest, RemoteMessage, RemoteMessageData, v1,
        };
        use truapi_platform::{HostInfo, PlatformInfo, SigningHostConfig};

        const ENTROPY: [u8; 32] = [0xab; 32];

        let config = SigningHostConfig::new(
            HostInfo {
                name: "Polkadot Mobile".to_string(),
                icon: None,
                version: None,
                platform: truapi::latest::HostPlatform::Unknown,
            },
            PlatformInfo::default(),
            [0; 32],
            [0xbb; 32],
        )
        .expect("signing host config is valid");
        let runtime =
            SigningHostRuntime::new(Arc::new(StubPlatform::default()), config, test_spawner());
        futures::executor::block_on(runtime.activate_local_session(ENTROPY.to_vec()))
            .expect("activation succeeds");

        let request = RemoteMessage {
            message_id: "m3".to_string(),
            data: RemoteMessageData::V1(v1::RemoteMessage::ProductSubtreeRequest(
                ProductSubtreeRequest {
                    product_id: "browse.dot".to_string(),
                },
            )),
        };
        let outcome = futures::executor::block_on(runtime.answer_sso_request(request));
        let SsoRequestOutcome::Response(response) = outcome else {
            panic!("expected a response outcome");
        };
        assert_eq!(response.message_id, "m3:response");
        let RemoteMessageData::V1(v1::RemoteMessage::ProductSubtreeResponse(payload)) =
            response.data
        else {
            panic!("expected a product subtree response payload");
        };
        assert_eq!(payload.responding_to, "m3");
        assert!(payload.product_public_key.is_ok());
    }
}
