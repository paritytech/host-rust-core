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
    crate::js::hex0x(&genesis_hash)
}

/// Render a JS error value for a message.
///
/// Every failure here arrives as a `DOMException`, which is an object rather
/// than a string, so its `name` and `message` are read off it directly. Losing
/// them would hide the one failure an 8 MB write will really produce,
/// `QuotaExceededError`, and Safari's private-browsing block with it.
fn describe(error: &JsValue, fallback: &str) -> WarmStoreError {
    let field = |name: &str| {
        js_sys::Reflect::get(error, &JsValue::from_str(name))
            .ok()
            .and_then(|value| value.as_string())
            .filter(|value| !value.is_empty())
    };
    let detail = match (field("name"), field("message")) {
        (Some(name), Some(message)) => Some(format!("{name}: {message}")),
        (Some(only), None) | (None, Some(only)) => Some(only),
        (None, None) => error.as_string(),
    };
    match detail {
        Some(detail) => WarmStoreError::new(format!("{fallback}: {detail}")),
        None => WarmStoreError::new(fallback),
    }
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

/// Await an IndexedDB transaction's commit, which is the durable signal. A
/// request succeeds before its transaction commits, so reporting on the request
/// alone would call an aborted write a stored blob.
async fn await_commit(
    transaction: web_sys::IdbTransaction,
    failure: &'static str,
) -> Result<(), WarmStoreError> {
    let (sender, receiver) = oneshot::channel();
    let sender = Rc::new(RefCell::new(Some(sender)));

    let on_complete = {
        let sender = Rc::clone(&sender);
        Closure::once(move |_event: web_sys::Event| {
            if let Some(sender) = sender.borrow_mut().take() {
                let _ = sender.send(Ok(()));
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
    let on_abort = {
        let sender = Rc::clone(&sender);
        Closure::once(move |_event: web_sys::Event| {
            if let Some(sender) = sender.borrow_mut().take() {
                let _ = sender.send(Err(WarmStoreError::new(failure)));
            }
        })
    };
    transaction.set_oncomplete(Some(on_complete.as_ref().unchecked_ref()));
    transaction.set_onerror(Some(on_error.as_ref().unchecked_ref()));
    transaction.set_onabort(Some(on_abort.as_ref().unchecked_ref()));

    let outcome = receiver.await;
    drop(on_complete);
    drop(on_error);
    drop(on_abort);
    outcome.map_err(|_| lost())?
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
    let outcome = read(&database, &key).await;
    // Closed on every path, so a failed read leaks no handle.
    database.close();
    outcome
}

/// Read one chain's blob out of an open database.
async fn read(database: &IdbDatabase, key: &str) -> Result<Option<String>, WarmStoreError> {
    const FAILURE: &str = "could not read the browser database";
    let request = {
        let store = database
            .transaction_with_str_and_mode(OBJECT_STORE, IdbTransactionMode::Readonly)
            .and_then(|transaction| transaction.object_store(OBJECT_STORE))
            .map_err(|error| describe(&error, FAILURE))?;
        store
            .get(&JsValue::from_str(key))
            .map_err(|error| describe(&error, FAILURE))?
    };
    await_request(request, FAILURE, |request| {
        Ok(request.result().ok().and_then(|value| value.as_string()))
    })
    .await
}

/// Write one chain's blob, entirely on the JS event loop.
async fn save_blob(genesis_hash: [u8; 32], blob: String) -> Result<(), WarmStoreError> {
    let key = storage_key(genesis_hash);
    let database = open().await?;
    let outcome = write(&database, &key, blob).await;
    // Closed on every path: a `?` return would otherwise leak a handle, once
    // per snapshot.
    database.close();
    outcome
}

/// Put the blob and wait for its transaction to commit.
async fn write(database: &IdbDatabase, key: &str, blob: String) -> Result<(), WarmStoreError> {
    const FAILURE: &str = "could not write the browser database";
    let transaction = database
        .transaction_with_str_and_mode(OBJECT_STORE, IdbTransactionMode::Readwrite)
        .map_err(|error| describe(&error, FAILURE))?;
    {
        let store = transaction
            .object_store(OBJECT_STORE)
            .map_err(|error| describe(&error, FAILURE))?;
        let value = JsValue::from_str(&blob);
        // `put` structured-clones the value, so the Rust copy is dead here and
        // megabytes need not sit in the future's state across the await below.
        drop(blob);
        store
            .put_with_key(&value, &JsValue::from_str(key))
            .map_err(|error| describe(&error, FAILURE))?;
    }
    // The commit, not the request: a request succeeds inside its transaction,
    // so a transaction that aborts afterwards would be reported as a stored
    // blob, and the next snapshot would decline to replace it.
    await_commit(transaction, FAILURE).await
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
