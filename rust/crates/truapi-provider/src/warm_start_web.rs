//! Browser-backed warm-start storage, used unless a host supplies its own.
//!
//! Blobs run to megabytes, which rules out `localStorage`, so they live in one
//! IndexedDB object store keyed by genesis hash. The database work is a small
//! JS module rather than `web-sys` calls: IndexedDB is event-driven, and a
//! promise per operation keeps the request and transaction handlers alive
//! without hand-managing closures across every await.

use futures::channel::oneshot;
use wasm_bindgen::prelude::*;

use crate::warm_start::{WarmStore, WarmStoreError};

/// Database the blobs live in.
///
/// A persisted browser key: renaming it strands every blob already written, and
/// those chains warp sync again.
const DATABASE_NAME: &str = "truapi-provider-warm-start";

#[wasm_bindgen(inline_js = r#"
const STORE = "chain-databases";
const VERSION = 1;

function open(name) {
  return new Promise((resolve, reject) => {
    const request = indexedDB.open(name, VERSION);
    request.onupgradeneeded = () => {
      const db = request.result;
      if (!db.objectStoreNames.contains(STORE)) db.createObjectStore(STORE);
    };
    // An upgrade held open by another tab would otherwise never settle.
    request.onblocked = () =>
      reject(new Error(`another connection is holding "${name}" open`));
    request.onerror = () =>
      reject(request.error ?? new Error(`could not open "${name}"`));
    request.onsuccess = () => resolve(request.result);
  });
}

export async function warmStoreLoad(name, key) {
  const db = await open(name);
  try {
    return await new Promise((resolve, reject) => {
      const tx = db.transaction(STORE, "readonly");
      const request = tx.objectStore(STORE).get(key);
      request.onsuccess = () =>
        resolve(typeof request.result === "string" ? request.result : null);
      tx.onerror = () => reject(tx.error ?? new Error("read failed"));
      tx.onabort = () => reject(tx.error ?? new Error("read aborted"));
    });
  } finally {
    db.close();
  }
}

export async function warmStoreSave(name, key, blob) {
  const db = await open(name);
  try {
    await new Promise((resolve, reject) => {
      const tx = db.transaction(STORE, "readwrite");
      tx.objectStore(STORE).put(blob, key);
      tx.oncomplete = () => resolve();
      tx.onerror = () => reject(tx.error ?? new Error("write failed"));
      tx.onabort = () => reject(tx.error ?? new Error("write aborted"));
    });
  } finally {
    db.close();
  }
}
"#)]
extern "C" {
    #[wasm_bindgen(js_name = warmStoreLoad, catch)]
    async fn warm_store_load(name: String, key: String) -> Result<JsValue, JsValue>;

    #[wasm_bindgen(js_name = warmStoreSave, catch)]
    async fn warm_store_save(name: String, key: String, blob: String) -> Result<(), JsValue>;
}

/// The browser's own storage, used when the host names none.
pub(crate) struct IndexedDbWarmStore;

/// Key a chain's blob is stored under.
fn storage_key(genesis_hash: [u8; 32]) -> String {
    format!("0x{}", hex::encode(genesis_hash))
}

/// Render a rejected JS value for an error message.
fn describe(error: JsValue) -> WarmStoreError {
    WarmStoreError::new(
        error
            .as_string()
            .or_else(|| {
                js_sys::Reflect::get(&error, &JsValue::from_str("message"))
                    .ok()?
                    .as_string()
            })
            .unwrap_or_else(|| "the browser database failed".to_owned()),
    )
}

/// Run a JS database call to completion on the event loop, reporting the
/// outcome through a channel the caller can hold across its own await.
///
/// The trait's futures are `Send` and a `JsFuture` is not, so the JS side runs
/// in its own task rather than being awaited in place.
fn on_event_loop<F>(work: F) -> oneshot::Receiver<Result<Option<String>, WarmStoreError>>
where
    F: core::future::Future<Output = Result<Option<String>, WarmStoreError>> + 'static,
{
    let (sender, receiver) = oneshot::channel();
    wasm_bindgen_futures::spawn_local(async move {
        let _ = sender.send(work.await);
    });
    receiver
}

/// Report a task that was dropped before it answered.
fn lost() -> WarmStoreError {
    WarmStoreError::new("the browser database never answered")
}

#[truapi_platform::async_trait]
impl WarmStore for IndexedDbWarmStore {
    async fn load(&self, genesis_hash: [u8; 32]) -> Result<Option<String>, WarmStoreError> {
        let key = storage_key(genesis_hash);
        let receiver = on_event_loop(async move {
            match warm_store_load(DATABASE_NAME.to_owned(), key).await {
                Ok(value) => Ok(value.as_string()),
                Err(error) => Err(describe(error)),
            }
        });
        receiver.await.map_err(|_| lost())?
    }

    async fn save(&self, genesis_hash: [u8; 32], blob: String) -> Result<(), WarmStoreError> {
        let key = storage_key(genesis_hash);
        let receiver = on_event_loop(async move {
            match warm_store_save(DATABASE_NAME.to_owned(), key, blob).await {
                Ok(()) => Ok(None),
                Err(error) => Err(describe(error)),
            }
        });
        receiver.await.map_err(|_| lost())?.map(|_| ())
    }
}
