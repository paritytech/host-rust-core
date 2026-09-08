//! Browser-backed warm-start storage, used unless a host supplies its own.
//!
//! Blobs run to megabytes, which rules out `localStorage`, so they live in one
//! IndexedDB object store keyed by genesis hash. IndexedDB is event-driven
//! rather than promise-based, so each request is bridged to a future the same
//! way this crate bridges the browser's `WebSocket` in `ws_web`: the handlers
//! are `Closure`s held for exactly as long as the request is outstanding, and
//! the result crosses back on a channel.

use std::cell::RefCell;
use std::rc::Rc;

use futures::channel::oneshot;
use wasm_bindgen::JsCast;
use wasm_bindgen::closure::Closure;
use wasm_bindgen::prelude::*;
use web_sys::{IdbDatabase, IdbOpenDbRequest, IdbRequest, IdbTransactionMode};

use crate::warm_start::{WarmStore, WarmStoreError};

/// Database the blobs live in.
///
/// A persisted browser key: renaming it strands every blob already written, and
/// those chains warp sync again.
const DATABASE_NAME: &str = "truapi-provider-warm-start";

/// Object store holding one blob per chain.
const OBJECT_STORE: &str = "chain-databases";

/// Schema version. Raising it needs an upgrade path for stores already out
/// there, so the store is created on first open and never migrated.
const VERSION: u32 = 1;

/// The browser's own storage, used when the host names none.
pub(crate) struct IndexedDbWarmStore;

/// Key a chain's blob is stored under.
fn storage_key(genesis_hash: [u8; 32]) -> String {
    format!("0x{}", hex::encode(genesis_hash))
}

/// Render a JS error value for a message.
fn describe(error: &JsValue, fallback: &str) -> WarmStoreError {
    WarmStoreError::new(error.as_string().unwrap_or_else(|| fallback.to_owned()))
}

/// The environment's IndexedDB, in a page or a worker alike.
fn factory() -> Result<web_sys::IdbFactory, WarmStoreError> {
    js_sys::Reflect::get(&js_sys::global(), &JsValue::from_str("indexedDB"))
        .ok()
        .and_then(|value| value.dyn_into::<web_sys::IdbFactory>().ok())
        .ok_or_else(|| {
            WarmStoreError::new("IndexedDB is unavailable here, so blobs cannot be stored")
        })
}

/// Run the JS side on the event loop and report the outcome on a channel the
/// trait's `Send` future can hold.
///
/// Everything IndexedDB touches is `!Send`, so it stays inside the spawned task
/// and only the finished value crosses back.
fn on_event_loop<T: Send + 'static>(
    work: impl core::future::Future<Output = Result<T, WarmStoreError>> + 'static,
) -> oneshot::Receiver<Result<T, WarmStoreError>> {
    let (sender, receiver) = oneshot::channel();
    wasm_bindgen_futures::spawn_local(async move {
        let _ = sender.send(work.await);
    });
    receiver
}

/// Await one IndexedDB request, keeping its handlers alive until it settles.
///
/// `read` runs on success and turns the request into the value the caller
/// wants, so the JS value never has to cross the await point.
async fn await_request<T: 'static>(
    request: IdbRequest,
    failure: &'static str,
    read: impl FnOnce(&IdbRequest) -> Result<T, WarmStoreError> + 'static,
) -> Result<T, WarmStoreError> {
    let (sender, receiver) = oneshot::channel();
    let sender = Rc::new(RefCell::new(Some(sender)));

    let on_success = {
        let sender = Rc::clone(&sender);
        let request = request.clone();
        Closure::once(move |_event: web_sys::Event| {
            if let Some(sender) = sender.borrow_mut().take() {
                let _ = sender.send(read(&request));
            }
        })
    };
    let on_error = {
        let sender = Rc::clone(&sender);
        Closure::once(move |_event: web_sys::Event| {
            if let Some(sender) = sender.borrow_mut().take() {
                let _ = sender.send(Err(WarmStoreError::new(failure)));
            }
        })
    };
    request.set_onsuccess(Some(on_success.as_ref().unchecked_ref()));
    request.set_onerror(Some(on_error.as_ref().unchecked_ref()));

    let outcome = receiver.await;
    // Held until here so a handler cannot fire against a freed closure.
    drop(on_success);
    drop(on_error);
    outcome.map_err(|_| WarmStoreError::new("the browser database never answered"))?
}

/// Open the database, creating the object store on first use.
async fn open() -> Result<IdbDatabase, WarmStoreError> {
    let request: IdbOpenDbRequest = factory()?
        .open_with_u32(DATABASE_NAME, VERSION)
        .map_err(|error| describe(&error, "could not open the browser database"))?;

    let on_upgrade = Closure::once(move |event: web_sys::IdbVersionChangeEvent| {
        let Some(target) = event.target() else { return };
        let Ok(request) = target.dyn_into::<IdbRequest>() else {
            return;
        };
        let Ok(result) = request.result() else { return };
        let Ok(database) = result.dyn_into::<IdbDatabase>() else {
            return;
        };
        // Creating a store that already exists throws, and the upgrade only
        // runs when the version rises, so the miss is the expected case.
        let _ = database.create_object_store(OBJECT_STORE);
    });
    request.set_onupgradeneeded(Some(on_upgrade.as_ref().unchecked_ref()));

    let database = await_request(
        request.clone().into(),
        "could not open the browser database",
        {
            move |request| {
                request
                    .result()
                    .ok()
                    .and_then(|value| value.dyn_into::<IdbDatabase>().ok())
                    .ok_or_else(|| {
                        WarmStoreError::new("the browser database opened with no handle")
                    })
            }
        },
    )
    .await;
    drop(on_upgrade);
    database
}

#[truapi_platform::async_trait]
impl WarmStore for IndexedDbWarmStore {
    async fn load(&self, genesis_hash: [u8; 32]) -> Result<Option<String>, WarmStoreError> {
        let receiver = on_event_loop(load_blob(genesis_hash));
        receiver.await.map_err(|_| lost())?
    }

    async fn save(&self, genesis_hash: [u8; 32], blob: String) -> Result<(), WarmStoreError> {
        let receiver = on_event_loop(save_blob(genesis_hash, blob));
        receiver.await.map_err(|_| lost())?
    }
}

/// Report a task dropped before it answered.
fn lost() -> WarmStoreError {
    WarmStoreError::new("the browser database never answered")
}

/// Read one chain's blob, entirely on the JS event loop.
async fn load_blob(genesis_hash: [u8; 32]) -> Result<Option<String>, WarmStoreError> {
    let key = storage_key(genesis_hash);
    let database = open().await?;
    let request = {
        let store = database
            .transaction_with_str_and_mode(OBJECT_STORE, IdbTransactionMode::Readonly)
            .and_then(|transaction| transaction.object_store(OBJECT_STORE))
            .map_err(|error| describe(&error, "could not read the browser database"))?;
        store
            .get(&JsValue::from_str(&key))
            .map_err(|error| describe(&error, "could not read the browser database"))?
    };
    let blob = await_request(request, "could not read the browser database", |request| {
        Ok(request.result().ok().and_then(|value| value.as_string()))
    })
    .await?;
    database.close();
    Ok(blob)
}

/// Write one chain's blob, entirely on the JS event loop.
async fn save_blob(genesis_hash: [u8; 32], blob: String) -> Result<(), WarmStoreError> {
    let key = storage_key(genesis_hash);
    let database = open().await?;
    let request = {
        let store = database
            .transaction_with_str_and_mode(OBJECT_STORE, IdbTransactionMode::Readwrite)
            .and_then(|transaction| transaction.object_store(OBJECT_STORE))
            .map_err(|error| describe(&error, "could not write the browser database"))?;
        store
            .put_with_key(&JsValue::from_str(&blob), &JsValue::from_str(&key))
            .map_err(|error| describe(&error, "could not write the browser database"))?
    };
    await_request(request, "could not write the browser database", |_| Ok(())).await?;
    database.close();
    Ok(())
}

#[cfg(test)]
mod tests {
    use wasm_bindgen_test::{wasm_bindgen_test, wasm_bindgen_test_configure};

    use super::*;

    wasm_bindgen_test_configure!(run_in_browser);

    /// The point of the whole feature: what one run stored, the next run reads.
    #[wasm_bindgen_test]
    async fn a_blob_survives_a_fresh_store() {
        let genesis = [0x11; 32];
        IndexedDbWarmStore
            .save(genesis, "finalized-state".to_owned())
            .await
            .expect("the browser database accepts a blob");

        let found = IndexedDbWarmStore
            .load(genesis)
            .await
            .expect("the browser database answers");
        assert_eq!(found.as_deref(), Some("finalized-state"));
    }

    /// An unknown chain reads as absent. It must not read as a failure, and it
    /// must not fail: `warm_up` treats an error as a broken store.
    #[wasm_bindgen_test]
    async fn an_unknown_chain_reads_as_absent() {
        let found = IndexedDbWarmStore
            .load([0x22; 32])
            .await
            .expect("a missing key is not a failure");
        assert_eq!(found, None);
    }

    /// Blobs are keyed per chain, so one chain's state cannot seed another.
    #[wasm_bindgen_test]
    async fn blobs_are_kept_per_chain() {
        let first = [0x33; 32];
        let second = [0x44; 32];
        IndexedDbWarmStore
            .save(first, "one".to_owned())
            .await
            .expect("save");
        IndexedDbWarmStore
            .save(second, "two".to_owned())
            .await
            .expect("save");

        assert_eq!(
            IndexedDbWarmStore
                .load(first)
                .await
                .expect("load")
                .as_deref(),
            Some("one")
        );
        assert_eq!(
            IndexedDbWarmStore
                .load(second)
                .await
                .expect("load")
                .as_deref(),
            Some("two")
        );
    }

    /// A later snapshot replaces the earlier one rather than accumulating.
    #[wasm_bindgen_test]
    async fn a_later_save_replaces_the_blob() {
        let genesis = [0x55; 32];
        IndexedDbWarmStore
            .save(genesis, "older".to_owned())
            .await
            .expect("save");
        IndexedDbWarmStore
            .save(genesis, "newer".to_owned())
            .await
            .expect("save");
        assert_eq!(
            IndexedDbWarmStore
                .load(genesis)
                .await
                .expect("load")
                .as_deref(),
            Some("newer")
        );
    }
}
