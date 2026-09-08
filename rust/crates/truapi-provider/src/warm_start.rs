//! Warm-start storage: the provider owns when a blob is read and written, the
//! host owns where it lives.
//!
//! A light client that starts from a stored finalized-database blob resumes
//! from that state instead of warp syncing from the chain-spec checkpoint. The
//! blob itself is opaque, so the only thing a host has to supply is somewhere
//! to keep it: [`FileWarmStore`] on native targets, or its own implementation
//! over whatever storage the platform offers.
//!
//! Reads and writes are explicit — [`warm_up`](crate::EmbeddedChainProvider::warm_up)
//! and [`persist`](crate::EmbeddedChainProvider::persist) — rather than hidden
//! inside `connect`. Connecting is a blocking call on the native bindings, and
//! awaiting a foreign callback underneath it would deadlock a host whose store
//! runs on the main thread.

use std::sync::Arc;

/// Failure reported by a [`WarmStore`] implementation.
#[derive(Debug, Clone, derive_more::Display)]
#[display("warm store: {reason}")]
pub struct WarmStoreError {
    /// What went wrong, for logs and error reports.
    pub reason: String,
}

impl WarmStoreError {
    /// Build an error from anything printable.
    pub fn new(reason: impl core::fmt::Display) -> Self {
        Self {
            reason: reason.to_string(),
        }
    }
}

impl std::error::Error for WarmStoreError {}

impl From<WarmStoreError> for truapi::latest::GenericError {
    fn from(error: WarmStoreError) -> Self {
        Self {
            reason: error.to_string(),
        }
    }
}

/// Where warm-start blobs are kept between runs.
///
/// A store that cannot answer must return `Err`, never `Ok(None)`: an empty
/// read is taken as "nothing stored yet" and lets a later
/// [`persist`](crate::EmbeddedChainProvider::persist) overwrite good state.
#[truapi_platform::async_trait]
pub trait WarmStore: Send + Sync {
    /// Read the blob stored for `genesis_hash`, if any.
    async fn load(&self, genesis_hash: [u8; 32]) -> Result<Option<String>, WarmStoreError>;

    /// Replace the blob stored for `genesis_hash`.
    async fn save(&self, genesis_hash: [u8; 32], blob: String) -> Result<(), WarmStoreError>;
}

/// Hex file name a blob is stored under.
#[cfg(not(target_arch = "wasm32"))]
fn blob_file_name(genesis_hash: [u8; 32]) -> String {
    format!("{}.json", hex::encode(genesis_hash))
}

/// A [`WarmStore`] keeping one file per chain under a directory the host owns.
///
/// The host picks the directory because only it knows a location the platform
/// will not evict: `applicationSupportDirectory` on iOS, `filesDir` on Android,
/// a state directory on desktop.
#[cfg(not(target_arch = "wasm32"))]
#[derive(Debug, Clone)]
pub struct FileWarmStore {
    directory: std::path::PathBuf,
}

#[cfg(not(target_arch = "wasm32"))]
impl FileWarmStore {
    /// Store blobs as files under `directory`, creating it if needed.
    pub fn new(directory: impl Into<std::path::PathBuf>) -> Result<Self, WarmStoreError> {
        let directory = directory.into();
        std::fs::create_dir_all(&directory).map_err(WarmStoreError::new)?;
        Ok(Self { directory })
    }
}

#[cfg(not(target_arch = "wasm32"))]
#[truapi_platform::async_trait]
impl WarmStore for FileWarmStore {
    async fn load(&self, genesis_hash: [u8; 32]) -> Result<Option<String>, WarmStoreError> {
        let path = self.directory.join(blob_file_name(genesis_hash));
        match std::fs::read_to_string(&path) {
            Ok(blob) => Ok(Some(blob)),
            Err(error) if error.kind() == std::io::ErrorKind::NotFound => Ok(None),
            Err(error) => Err(WarmStoreError::new(error)),
        }
    }

    async fn save(&self, genesis_hash: [u8; 32], blob: String) -> Result<(), WarmStoreError> {
        // Written beside the target and renamed, so a process killed mid-write
        // leaves the previous blob intact rather than a truncated one, which
        // smoldot would discard in silence.
        let path = self.directory.join(blob_file_name(genesis_hash));
        let temporary = path.with_extension("json.partial");
        std::fs::write(&temporary, blob).map_err(WarmStoreError::new)?;
        std::fs::rename(&temporary, &path).map_err(WarmStoreError::new)
    }
}

/// Whether a snapshot is worth storing.
///
/// smoldot answers `chainHead_unstable_finalizedDatabase` even when the chain
/// has finalized nothing yet, and that blob decodes to a database with no chain
/// information, which it then silently ignores on the next run. Saving one over
/// a good blob turns a warm start back into a cold one, so a blob only counts
/// once it carries chain information.
pub(crate) fn carries_chain_information(blob: &str) -> bool {
    serde_json::from_str::<serde_json::Value>(blob)
        .ok()
        .and_then(|value| value.get("chain").cloned())
        .is_some_and(|chain| !chain.is_null())
}

/// Shared handle to the store a provider was built with.
pub(crate) type SharedWarmStore = Arc<dyn WarmStore>;

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn a_blob_without_chain_information_is_not_worth_storing() {
        assert!(!carries_chain_information(r#"{"chain":null}"#));
        assert!(!carries_chain_information("{}"));
        assert!(!carries_chain_information("not json"));
        assert!(carries_chain_information(
            r#"{"chain":{"finalized_block_header":"0x00"},"genesisHash":"0x01"}"#
        ));
    }

    #[cfg(not(target_arch = "wasm32"))]
    #[test]
    fn a_file_store_round_trips_a_blob_and_reports_a_missing_one() {
        let directory = std::env::temp_dir().join("truapi-provider-warm-store-test");
        let _ = std::fs::remove_dir_all(&directory);
        let store = FileWarmStore::new(&directory).expect("the directory is creatable");

        let missing = futures::executor::block_on(store.load([7; 32])).expect("load succeeds");
        assert_eq!(missing, None);

        futures::executor::block_on(store.save([7; 32], "blob".to_owned())).expect("save succeeds");
        let found = futures::executor::block_on(store.load([7; 32])).expect("load succeeds");
        assert_eq!(found.as_deref(), Some("blob"));

        let _ = std::fs::remove_dir_all(&directory);
    }
}
