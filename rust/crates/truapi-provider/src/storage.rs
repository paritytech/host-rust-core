//! Warm-start storage: the provider owns when a blob is read and written, the
//! host owns where it lives.
//!
//! A light client that starts from a stored finalized-database blob resumes
//! from that state instead of warp syncing from the chain-spec checkpoint. The
//! blob itself is opaque, so the only thing a host has to supply is somewhere
//! to keep it: an implementation of [`StorageClient`] over whatever storage the
//! platform already offers. The crate stores nothing itself, so it never
//! competes with the host for the same quota and never decides on its behalf
//! whether the bytes are backed up or encrypted.
//!
//! Reads and writes are explicit, through
//! [`load_database`](crate::EmbeddedChainProvider::load_database) and
//! [`save_database`](crate::EmbeddedChainProvider::save_database), rather than
//! hidden inside `connect`. Connecting is a blocking call on the native
//! bindings. Awaiting a foreign callback underneath it would deadlock a host
//! whose client runs on the main thread.

/// Failure reported by a [`StorageClient`] implementation.
///
/// An enum with one variant rather than a struct because the native bindings
/// export this type, and uniffi errors must be enums.
#[derive(Debug, Clone, derive_more::Display)]
#[cfg_attr(
    all(feature = "uniffi", not(target_arch = "wasm32")),
    derive(uniffi::Error)
)]
pub enum StorageClientError {
    /// The store could not read or write the blob.
    #[display("warm store: {reason}")]
    Failed {
        /// What went wrong, for logs and error reports.
        reason: String,
    },
}

impl StorageClientError {
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

impl std::error::Error for StorageClientError {}

impl From<StorageClientError> for truapi::latest::GenericError {
    fn from(error: StorageClientError) -> Self {
        Self {
            reason: error.to_string(),
        }
    }
}

/// Where warm-start blobs are kept between runs.
///
/// A client that cannot answer must return `Err`, never `Ok(None)`: an empty
/// read is taken as nothing being stored for that chain yet, and lets a later
/// [`save_database`](crate::EmbeddedChainProvider::save_database) overwrite good state.
///
/// A loaded blob is trusted input: it goes to the light client as the finalized
/// state to resume from, so whatever can write to the store can steer the
/// view the client has of the chain. Keep storage no more writable than the source
/// the chain specification itself came from.
#[cfg_attr(
    all(feature = "uniffi", not(target_arch = "wasm32")),
    uniffi::export(with_foreign)
)]
#[truapi_platform::async_trait]
pub trait StorageClient: Send + Sync {
    /// Read the blob stored for `genesis_hash`, if any.
    async fn load(&self, genesis_hash: [u8; 32]) -> Result<Option<String>, StorageClientError>;

    /// Replace the blob stored for `genesis_hash`.
    async fn save(&self, genesis_hash: [u8; 32], blob: String) -> Result<(), StorageClientError>;
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
    // sync, since the chain information in the database is chosen on finalized block
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
    // a blob of up to 8 MB, and the encoder in smoldot omits the key entirely when
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
}
