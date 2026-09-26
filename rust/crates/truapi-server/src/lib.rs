#![allow(
    clippy::double_must_use,
    reason = "async-trait generates must_use futures for async trait methods"
)]
// The pairing-flow future nests the chain, SSO and identity futures deeply
// enough that proving the tree's auto traits exceeds the default limit.
#![recursion_limit = "256"]

//! TrUAPI server runtime: dispatcher, frames, SCALE encoding, stream management.
//!
//! Hosts instantiate a role runtime around a [`platform::Platform`]
//! implementation, then create product-scoped [`ProductRuntime`] endpoints that
//! expose the stable byte-frame API used from WASM, native mobile, or desktop
//! shells.
//!
//! Host-facing bridges:
//! - `ws_bridge` (feature `ws-bridge`): localhost WebSocket bridge for
//!   native WebView hosts (Android/iOS).
//! - [`bootstrap`]: the JavaScript those hosts inject to reach that bridge.
//! - [`native`]: UniFFI surface exposing the native host runtime + callbacks.
//! - `wasm` (wasm32 only): wasm-bindgen surface exposing `WasmProductRuntime`.
//! - `native_debug` (non-wasm32 only): a loopback WebSocket [`DebugSink`] that
//!   streams tapped frames to the `@parity/truapi-debugger` app.

pub mod bootstrap;
mod chain_runtime;
mod core;
mod dispatcher;
mod dotns_views;
mod dynamic_vrf;
pub mod frame;
mod host_core;
mod host_internal;
pub mod host_logic;
mod host_rpc_client;
mod interrupt;
pub mod logging;
pub mod platform;
mod protocol_error;
mod runtime;
mod session_usernames;
pub mod subscription;
pub mod transport;

#[cfg(test)]
mod test_support;
mod unix_time;

// Dispatch must keep serving deprecated APIs while clients migrate.
#[allow(deprecated)]
pub mod generated;

#[cfg(all(not(target_arch = "wasm32"), feature = "ws-bridge"))]
mod ws_bridge;

#[cfg(not(target_arch = "wasm32"))]
pub mod native;

#[cfg(not(target_arch = "wasm32"))]
mod native_renderer;

#[cfg(target_arch = "wasm32")]
pub mod wasm;

#[cfg(all(not(target_arch = "wasm32"), feature = "debug-sink"))]
pub mod native_debug;

pub use core::TrUApiCore;
pub use host_core::{
    ChannelId, DebugEvent, DebugSink, FrameDirection, FrameSink, HostAdmin, PairingHostRuntime,
    ProductRuntime, ProductRuntimeControl, ProductRuntimeError, SigningHostRuntime,
};
pub use host_logic::session::{
    ExternalPairedSession, SsoSessionInfo, decode_persisted_session, encode_external_paired_session,
};
pub use host_logic::worker::{WorkerLedger, WorkerTransition};
#[cfg(all(not(target_arch = "wasm32"), feature = "debug-sink"))]
pub use native_debug::{DebugSinkError, WsDebugSink};
pub use platform::{
    CoreStorageKeyDescription, CoreStorageKeyDescriptionError, HostIdentity, PairingHostConfig,
    PermissionAuthorizationRequest, PermissionAuthorizationStatus, Platform, ProductContext,
    SigningHostConfig, describe_core_storage_key,
};
pub use runtime::StatementRenewalTarget;
pub use runtime::login_failure::reports_exhausted_period;
pub use runtime::product_manifest::{encode_cached_root_manifest, manifest_cache_key};
pub use runtime::statement_allowance;
pub use runtime::{
    AnnouncedPairing, DevicePairingObserver, MAX_PAIRING_METADATA_CHARS, PairedSsoPeer,
    PairingProposal, PairingProposalMetadata, ResponderExit,
};

#[cfg(all(not(target_arch = "wasm32"), feature = "ws-bridge"))]
pub use ws_bridge::{WsBridgeEndpoint, WsBridgeStartError};

#[cfg(not(target_arch = "wasm32"))]
pub use native_renderer::{NativeRendererObserver, NativeRendererSubscription};

#[cfg(all(target_arch = "wasm32", feature = "wasm-signing-host"))]
pub use wasm::WasmSigningHostRuntime;
#[cfg(target_arch = "wasm32")]
pub use wasm::{
    WasmPairingHostRuntime, WasmProductRuntime, WasmRendererSubscription,
    derive_product_account_public_key, describe_core_storage_key_for_wasm,
    has_trusted_remote_permissions_for_wasm, product_account_address, set_log_level,
    wire_schema_hash,
};

#[cfg(not(target_arch = "wasm32"))]
uniffi::setup_scaffolding!();

#[cfg(not(target_arch = "wasm32"))]
uniffi::use_remote_type!(truapi::Bytes32);

#[cfg(not(target_arch = "wasm32"))]
use truapi::Bytes32;

#[cfg(not(target_arch = "wasm32"))]
truapi::uniffi_reexport_scaffolding!();
