//! Bandersnatch ring-VRF operations, from `truapi-verifiable`.
//!
//! Native builds link it. The browser core loads it as a WASM module of its
//! own, published beside the core's, once a pairing session connects or when
//! a call first needs a ring-VRF key, whichever comes first: it carries
//! `verifiable`, whose ring prover compiles in 4.5 MiB of powers of tau.

use parity_scale_codec::{Decode, DecodeAll};

use crate::host_logic::sso::messages::RingVrfError;

#[cfg(not(target_arch = "wasm32"))]
use truapi_verifiable as module;

/// Ring domain size for rings of up to 2^9 members.
pub(in crate::runtime) const DOMAIN_2E11: u32 = 1 << 11;
/// Ring domain size for rings of up to 2^10 members.
pub(in crate::runtime) const DOMAIN_2E12: u32 = 1 << 12;
/// Ring domain size for rings of up to 2^14 members.
pub(in crate::runtime) const DOMAIN_2E16: u32 = 1 << 16;

/// Ring-VRF operations, from [`load`].
pub(in crate::runtime) struct Vrf(());

/// Ring-VRF operations, which native builds link in.
#[cfg(not(target_arch = "wasm32"))]
pub(in crate::runtime) async fn load() -> Result<Vrf, RingVrfError> {
    Ok(Vrf(()))
}

/// Native builds link the operations in, so there is nothing to prefetch.
#[cfg(not(target_arch = "wasm32"))]
pub(in crate::runtime) fn prefetch(_spawner: &crate::subscription::Spawner) {}

#[cfg(target_arch = "wasm32")]
pub(in crate::runtime) use module::{load, prefetch};

/// The ring member for `entropy`, loading the operations first.
#[cfg(all(target_arch = "wasm32", feature = "test-host"))]
pub(crate) async fn ring_vrf_member(entropy: &[u8; 32]) -> Result<[u8; 32], RingVrfError> {
    load().await?.member(entropy)
}

impl Vrf {
    /// The ring member, a 32-byte public key, for `entropy`.
    pub(in crate::runtime) fn member(&self, entropy: &[u8; 32]) -> Result<[u8; 32], RingVrfError> {
        answer(&module::member(entropy))
    }

    /// A signature over `message` with the key for `entropy`.
    pub(in crate::runtime) fn sign(
        &self,
        entropy: &[u8; 32],
        message: &[u8],
    ) -> Result<Vec<u8>, RingVrfError> {
        answer(&module::sign(entropy, message))
    }

    /// The alias of the key for `entropy` in `context`.
    pub(in crate::runtime) fn alias(
        &self,
        entropy: &[u8; 32],
        context: &[u8],
    ) -> Result<[u8; 32], RingVrfError> {
        answer(&module::alias(entropy, context))
    }

    /// Prove, with the key for `entropy`, that `member` belongs to the ring
    /// `members` of the ring domain of size `domain`, in `context`. Returns the
    /// encoded proof and the member's alias in that context.
    pub(in crate::runtime) fn prove(
        &self,
        entropy: &[u8; 32],
        domain: u32,
        member: &[u8; 32],
        members: &[[u8; 32]],
        context: &[u8],
        message: &[u8],
    ) -> Result<(Vec<u8>, [u8; 32]), RingVrfError> {
        answer(&module::prove(
            entropy,
            domain,
            member,
            &members.concat(),
            context,
            message,
        ))
    }
}

/// A `truapi-verifiable` answer: `Result<T, String>`, SCALE-encoded.
fn answer<T: Decode>(encoded: &[u8]) -> Result<T, RingVrfError> {
    Result::<T, String>::decode_all(&mut &encoded[..])
        .map_err(|error| RingVrfError::Unknown {
            reason: format!("undecodable ring-VRF answer: {error}"),
        })?
        .map_err(|reason| RingVrfError::Unknown { reason })
}

#[cfg(target_arch = "wasm32")]
mod module {
    use super::Vrf;

    use futures::lock::Mutex;
    use js_sys::Uint8Array;
    use send_wrapper::SendWrapper;
    use sha2::{Digest, Sha256};
    use std::sync::OnceLock;
    use wasm_bindgen::JsCast;
    use wasm_bindgen::prelude::*;
    use wasm_bindgen_futures::JsFuture;

    use crate::host_logic::sso::messages::RingVrfError;

    // `make wasm` publishes the module under `verifiable/` in the core's own
    // output directory, two levels above this snippet.
    #[wasm_bindgen(inline_js = r#"
let module;
export async function read() {
  const url = new URL("../../verifiable/truapi_verifiable_bg.wasm", import.meta.url);
  const response = await fetch(url);
  if (!response.ok) throw new Error(`${url}: ${response.status} ${response.statusText}`);
  return new Uint8Array(await response.arrayBuffer());
}
export async function start(wasm) {
  const glue = await import(new URL("../../verifiable/truapi_verifiable.js", import.meta.url).href);
  await glue.default({ module_or_path: wasm });
  module = glue;
}
export const member = (...args) => module.member(...args);
export const sign = (...args) => module.sign(...args);
export const alias = (...args) => module.alias(...args);
export const prove = (...args) => module.prove(...args);
"#)]
    extern "C" {
        fn read() -> js_sys::Promise;
        fn start(wasm: &Uint8Array) -> js_sys::Promise;
        pub(super) fn member(entropy: &[u8]) -> Vec<u8>;
        pub(super) fn sign(entropy: &[u8], message: &[u8]) -> Vec<u8>;
        pub(super) fn alias(entropy: &[u8], context: &[u8]) -> Vec<u8>;
        pub(super) fn prove(
            entropy: &[u8],
            domain: u32,
            member: &[u8],
            members: &[u8],
            context: &[u8],
            message: &[u8],
        ) -> Vec<u8>;
    }

    /// SHA-256 of the module `make wasm` built beside this core, the only one
    /// it loads.
    const PINNED: Option<&str> = option_env!("TRUAPI_VERIFIABLE_SHA256");

    /// Whether the module has started, behind an async lock so concurrent
    /// calls wait on one load.
    static STARTED: OnceLock<Mutex<bool>> = OnceLock::new();

    /// Ring-VRF operations, loading the module on first use. A failed load is
    /// not remembered, so a later call tries again.
    pub(in crate::runtime) async fn load() -> Result<Vrf, RingVrfError> {
        let mut started = STARTED.get_or_init(|| Mutex::new(false)).lock().await;
        if !*started {
            SendWrapper::new(start_module())
                .await
                .map_err(|reason| RingVrfError::Unknown { reason })?;
            *started = true;
        }
        Ok(Vrf(()))
    }

    /// Load the module in the background, so a later call does not wait on
    /// it. A call made while it loads waits on this load instead of starting
    /// another.
    pub(in crate::runtime) fn prefetch(spawner: &crate::subscription::Spawner) {
        spawner(Box::pin(async {
            if let Err(error) = load().await {
                tracing::warn!(%error, "truapi-verifiable prefetch failed");
            }
        }));
    }

    async fn start_module() -> Result<(), String> {
        let pinned = PINNED.ok_or("this core was built without truapi-verifiable")?;
        let wasm: Uint8Array = JsFuture::from(read())
            .await
            .map_err(|error| format!("{error:?}"))?
            .unchecked_into();
        if hex::encode(Sha256::digest(wasm.to_vec())) != pinned {
            return Err("truapi-verifiable is not the build this core pins".to_owned());
        }
        JsFuture::from(start(&wasm))
            .await
            .map_err(|error| format!("{error:?}"))?;
        Ok(())
    }
}
