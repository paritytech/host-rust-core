//! Warm-start storage: the provider owns when a blob is read and written, the
//! host owns where it lives.
//!
//! A light client that starts from a stored finalized-database blob resumes
//! from that state instead of warp syncing from the chain-spec checkpoint. The
//! blob itself is opaque, so the only thing a host has to supply is somewhere
//! to keep it: [`FileWarmStore`] on native targets, or its own implementation
//! over whatever storage the platform offers.
//!
//! Reads and writes are explicit — [`load_database`](crate::EmbeddedChainProvider::load_database)
//! and [`save_database`](crate::EmbeddedChainProvider::save_database) — rather than hidden
//! inside `connect`. Connecting is a blocking call on the native bindings, and
//! awaiting a foreign callback underneath it would deadlock a host whose store
//! runs on the main thread.

/// Failure reported by a [`WarmStore`] implementation.
///
/// An enum with one variant rather than a struct because the native bindings
/// export this type, and uniffi errors must be enums.
#[derive(Debug, Clone, derive_more::Display)]
#[cfg_attr(
    all(feature = "uniffi", not(target_arch = "wasm32")),
    derive(uniffi::Error)
)]
pub enum WarmStoreError {
    /// The store could not read or write the blob.
    #[display("warm store: {reason}")]
    Failed {
        /// What went wrong, for logs and error reports.
        reason: String,
    },
}

impl WarmStoreError {
    /// Build an error from anything printable.
    pub fn new(reason: impl core::fmt::Display) -> Self {
        Self::Failed {
            reason: reason.to_string(),
        }
    }

    /// What went wrong.
    pub fn reason(&self) -> &str {
        let Self::Failed { reason } = self;
        reason
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
/// [`save_database`](crate::EmbeddedChainProvider::save_database) overwrite good state.
///
/// A loaded blob is trusted input: it goes to the light client as the finalized
/// state to resume from, so whatever can write to the store can steer the
/// client's view of the chain. Keep the store no more writable than the source
/// the chain specification itself came from.
#[cfg_attr(
    all(feature = "uniffi", not(target_arch = "wasm32")),
    uniffi::export(with_foreign)
)]
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
pub(crate) fn carries_runtime_code(blob: &str) -> bool {
    // smoldot serialises the runtime code as `runtimeCode` and omits the key
    // when it has none, and its shrink ladder drops that field first when a
    // snapshot is over the size cap. A blob without it still skips the warp
    // sync, since the database's chain information is chosen on finalized block
    // number alone, but it costs a runtime download on the next start.
    blob.contains("\"runtimeCode\":")
}

/// Whether `blob` is worth storing over `stored`.
///
/// A snapshot taken early, or shrunk to fit the size cap, can carry chain
/// information without the runtime code. That is still usable, so it is worth
/// keeping when nothing is stored, but it must not replace a blob that has the
/// code: doing so trades a warm start for a runtime download every run.
pub(crate) fn is_worth_storing(blob: &str, stored: Option<&str>) -> bool {
    if !carries_chain_information(blob) {
        return false;
    }
    match stored {
        Some(stored) => carries_runtime_code(blob) || !carries_runtime_code(stored),
        None => true,
    }
}

pub(crate) fn carries_chain_information(blob: &str) -> bool {
    // A substring test rather than a parse: this runs on every snapshot against
    // a blob of up to 8 MB, and smoldot's encoder omits the key entirely when
    // there is no chain information and writes it as an object when there is
    // (`skip_serializing_if` on `SerdeDatabase::chain`). The truncation
    // sentinels it can return instead, `"<too-large>"` and the empty string,
    // carry no key at all.
    blob.contains("\"chain\":{")
}

/// Genesis hash of the chain a blob belongs to.
pub type GenesisHash = [u8; 32];

// Bridged for the native bindings the way `truapi` bridges its own 32-byte
// values: uniffi has no fixed-size array type, so the hash crosses as bytes and
// converts back here. Lowering only, since the provider validates the length
// before a store ever sees one.
#[cfg(all(feature = "uniffi", not(target_arch = "wasm32")))]
uniffi::custom_type!(GenesisHash, Vec<u8>, {
    remote,
    lower: |hash| hash.to_vec(),
    try_lift: |bytes| Ok(bytes.as_slice().try_into()?),
});

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn a_blob_without_chain_information_is_not_worth_storing() {
        assert!(!carries_chain_information(r#"{"chain":null}"#));
        assert!(!carries_chain_information("{}"));
        assert!(!carries_chain_information("not json"));
        assert!(!carries_chain_information("<too-large>"));
        assert!(!carries_chain_information(""));
        assert!(carries_chain_information(
            r#"{"chain":{"finalized_block_header":"0x00"},"genesisHash":"0x01"}"#
        ));
    }

    #[test]
    fn a_blob_without_runtime_code_never_replaces_one_that_has_it() {
        const WITH_CODE: &str = r#"{"chain":{"a":1},"runtimeCode":"AAAA"}"#;
        const WITHOUT_CODE: &str = r#"{"chain":{"a":1}}"#;

        assert!(
            is_worth_storing(WITHOUT_CODE, None),
            "a blob with no runtime code still beats nothing stored"
        );
        assert!(
            is_worth_storing(WITH_CODE, Some(WITHOUT_CODE)),
            "gaining the runtime code is an improvement"
        );
        assert!(
            !is_worth_storing(WITHOUT_CODE, Some(WITH_CODE)),
            "losing the runtime code would cost a runtime download every run"
        );
        assert!(
            is_worth_storing(WITH_CODE, Some(WITH_CODE)),
            "a fresher blob of the same quality is still worth storing"
        );
        assert!(
            !is_worth_storing(r#"{"genesisHash":"0x01"}"#, None),
            "a blob with no chain information is worth nothing"
        );
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
