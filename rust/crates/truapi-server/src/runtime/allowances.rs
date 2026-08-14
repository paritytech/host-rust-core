//! Persistent allowance-key repository for pairing-host SSO sessions.
//!
//! Implements the host-side allowance cache described in
//! `docs/rfcs/0010-allowance.md`.
//!
//! Keys are grouped by SSO session and then indexed by
//! `(product_id, artifact_identity, resource)`. The runtime keeps a short-lived
//! memory cache in `PairingHost`; this module owns the durable CoreStorage
//! encoding.

use parity_scale_codec::{Decode, Encode};
use truapi::latest::GenericError;
use truapi_platform::{CoreStorage, CoreStorageKey};
use zeroize::{Zeroize, ZeroizeOnDrop, Zeroizing};

use super::authority::AuthorityError;
use super::sso_remote::SsoSessionKey;
use crate::host_logic::session::{SessionInfo, SsoSessionInfo};
const ALLOWANCE_BLOB_PREFIX: &[u8] = b"truapi:allowances:v2\0";

/// Chain resource an allowance key grants access to.
#[derive(Clone, Copy, Debug, PartialEq, Eq, Hash, Encode, Decode, Zeroize)]
pub(super) enum AllowanceResource {
    /// Bulletin-chain transaction storage.
    Bulletin,
    /// People-chain statement store.
    StatementStore,
}

/// Memory-cache key: `(session, product_id, artifact_identity, resource)`.
#[derive(Clone, Debug, PartialEq, Eq, Hash)]
pub(super) struct AllowanceCacheKey {
    session: SsoSessionKey,
    product_id: String,
    artifact_identity: String,
    resource: AllowanceResource,
}

impl AllowanceCacheKey {
    /// Cache key for the session's SSO pair; fails when the session has none.
    pub(super) fn new(
        session: &SessionInfo,
        product_id: &str,
        artifact_identity: &str,
        resource: AllowanceResource,
    ) -> Result<Self, AuthorityError> {
        Ok(Self {
            session: sso_cache_key(session)?,
            product_id: product_id.to_string(),
            artifact_identity: artifact_identity.to_string(),
            resource,
        })
    }

    /// Whether this key belongs to the given SSO session.
    pub(super) fn is_for_session(&self, session: SsoSessionKey) -> bool {
        self.session == session
    }

    /// Whether this key belongs to the given product.
    pub(super) fn is_for_product(&self, product_id: &str) -> bool {
        self.product_id == product_id
    }
}

#[derive(Clone, PartialEq, Eq, Encode, Decode, Zeroize, ZeroizeOnDrop)]
struct StoredAllowanceEntry {
    product_id: String,
    artifact_identity: String,
    resource: AllowanceResource,
    slot_account_key: Vec<u8>,
}

/// Read the persisted allowance key for
/// `(product_id, artifact_identity, resource)`, if any.
pub(super) async fn read_allowance_key(
    storage: &(impl CoreStorage + ?Sized),
    session: &SessionInfo,
    product_id: &str,
    artifact_identity: &str,
    resource: AllowanceResource,
) -> Result<Option<Vec<u8>>, AuthorityError> {
    let entries = read_entries(storage, session).await?;
    Ok(entries
        .iter()
        .find(|entry| {
            entry.product_id == product_id
                && entry.artifact_identity == artifact_identity
                && entry.resource == resource
        })
        .map(|entry| entry.slot_account_key.clone()))
}

/// Persist an allowance key, replacing any prior key for the same
/// `(product_id, artifact_identity, resource)`.
pub(super) async fn write_allowance_key(
    storage: &(impl CoreStorage + ?Sized),
    session: &SessionInfo,
    product_id: &str,
    artifact_identity: &str,
    resource: AllowanceResource,
    slot_account_key: Vec<u8>,
) -> Result<(), AuthorityError> {
    let mut entries = read_entries(storage, session).await?;
    entries.retain(|entry| {
        !(entry.product_id == product_id
            && entry.artifact_identity == artifact_identity
            && entry.resource == resource)
    });
    entries.push(StoredAllowanceEntry {
        product_id: product_id.to_string(),
        artifact_identity: artifact_identity.to_string(),
        resource,
        slot_account_key,
    });
    let blob = encode_entries(&entries);
    storage
        .write_core_storage(storage_key(session)?, blob)
        .await
        .map_err(storage_error)
}

/// Remove the persisted allowance key for
/// `(product_id, artifact_identity, resource)`; a miss is not an error.
pub(super) async fn remove_allowance_key(
    storage: &(impl CoreStorage + ?Sized),
    session: &SessionInfo,
    product_id: &str,
    artifact_identity: &str,
    resource: AllowanceResource,
) -> Result<(), AuthorityError> {
    let mut entries = read_entries(storage, session).await?;
    let before = entries.len();
    entries.retain(|entry| {
        !(entry.product_id == product_id
            && entry.artifact_identity == artifact_identity
            && entry.resource == resource)
    });
    if entries.len() == before {
        return Ok(());
    }
    let blob = encode_entries(&entries);
    storage
        .write_core_storage(storage_key(session)?, blob)
        .await
        .map_err(storage_error)
}

/// Remove every persisted allowance key for `product_id` in the active SSO
/// session while preserving entries owned by other products.
pub(super) async fn clear_product_allowance_keys(
    storage: &(impl CoreStorage + ?Sized),
    session: &SessionInfo,
    product_id: &str,
) -> Result<(), AuthorityError> {
    let key = storage_key(session)?;
    let mut entries = read_entries(storage, session).await?;
    let before = entries.len();
    entries.retain(|entry| entry.product_id != product_id);
    if entries.len() == before {
        return Ok(());
    }
    if entries.is_empty() {
        storage.clear_core_storage(key).await.map_err(storage_error)
    } else {
        let blob = encode_entries(&entries);
        storage
            .write_core_storage(key, blob)
            .await
            .map_err(storage_error)
    }
}

/// Drop every persisted allowance key belonging to the session.
pub(super) async fn clear_session_allowance_keys(
    storage: &(impl CoreStorage + ?Sized),
    session: &SessionInfo,
) -> Result<(), AuthorityError> {
    storage
        .clear_core_storage(storage_key(session)?)
        .await
        .map_err(storage_error)
}

async fn read_entries(
    storage: &(impl CoreStorage + ?Sized),
    session: &SessionInfo,
) -> Result<Zeroizing<Vec<StoredAllowanceEntry>>, AuthorityError> {
    let key = storage_key(session)?;
    let Some(mut blob) = storage
        .read_core_storage(key.clone())
        .await
        .map_err(storage_error)?
    else {
        return Ok(Zeroizing::new(Vec::new()));
    };
    let decoded = decode_entries(&blob);
    blob.zeroize();
    match decoded {
        Ok(entries) => Ok(Zeroizing::new(entries)),
        Err(_) => {
            storage
                .clear_core_storage(key)
                .await
                .map_err(storage_error)?;
            Ok(Zeroizing::new(Vec::new()))
        }
    }
}

fn encode_entries(entries: &[StoredAllowanceEntry]) -> Vec<u8> {
    let mut blob = Vec::with_capacity(ALLOWANCE_BLOB_PREFIX.len() + entries.size_hint());
    blob.extend_from_slice(ALLOWANCE_BLOB_PREFIX);
    entries.encode_to(&mut blob);
    blob
}

fn decode_entries(blob: &[u8]) -> Result<Vec<StoredAllowanceEntry>, AuthorityError> {
    let Some(mut input) = blob.strip_prefix(ALLOWANCE_BLOB_PREFIX) else {
        return Err(AuthorityError::Unknown {
            reason: "invalid persisted allowance keys: unsupported legacy encoding".to_string(),
        });
    };
    let entries =
        Vec::<StoredAllowanceEntry>::decode(&mut input).map_err(|err| AuthorityError::Unknown {
            reason: format!("invalid persisted allowance keys: {err}"),
        })?;
    if !input.is_empty() {
        return Err(AuthorityError::Unknown {
            reason: "invalid persisted allowance keys: trailing bytes".to_string(),
        });
    }
    Ok(entries)
}

fn storage_key(session: &SessionInfo) -> Result<CoreStorageKey, AuthorityError> {
    Ok(CoreStorageKey::AllowanceKeys {
        session_id: session_storage_id(session.sso.as_ref().ok_or(AuthorityError::Disconnected)?),
    })
}

fn sso_cache_key(session: &SessionInfo) -> Result<SsoSessionKey, AuthorityError> {
    let sso = session.sso.as_ref().ok_or(AuthorityError::Disconnected)?;
    Ok(SsoSessionKey::from_session(sso))
}

fn session_storage_id(session: &SsoSessionInfo) -> String {
    let mut bytes = Vec::with_capacity(64);
    bytes.extend_from_slice(&session.session_id_own);
    bytes.extend_from_slice(&session.session_id_peer);
    hex::encode(bytes)
}

fn storage_error(err: GenericError) -> AuthorityError {
    AuthorityError::Unknown {
        reason: format!("allowance storage failed: {}", err.reason),
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::collections::HashMap;
    use std::sync::Mutex;

    use crate::test_support::sso_session_info;

    #[derive(Default)]
    struct MemStorage {
        inner: Mutex<HashMap<Vec<u8>, Vec<u8>>>,
    }

    #[truapi_platform::async_trait]
    impl CoreStorage for MemStorage {
        async fn read_core_storage(
            &self,
            key: CoreStorageKey,
        ) -> Result<Option<Vec<u8>>, GenericError> {
            Ok(self
                .inner
                .lock()
                .expect("storage mutex poisoned")
                .get(&key.encode())
                .cloned())
        }

        async fn write_core_storage(
            &self,
            key: CoreStorageKey,
            value: Vec<u8>,
        ) -> Result<(), GenericError> {
            self.inner
                .lock()
                .expect("storage mutex poisoned")
                .insert(key.encode(), value);
            Ok(())
        }

        async fn clear_core_storage(&self, key: CoreStorageKey) -> Result<(), GenericError> {
            self.inner
                .lock()
                .expect("storage mutex poisoned")
                .remove(&key.encode());
            Ok(())
        }
    }

    #[test]
    fn stores_allowance_keys_by_product_artifact_and_resource() {
        let storage = MemStorage::default();
        let session = sso_session_info();

        futures::executor::block_on(async {
            write_allowance_key(
                &storage,
                &session,
                "dotli.localhost",
                "sha256:artifact-a",
                AllowanceResource::Bulletin,
                vec![1; 64],
            )
            .await
            .unwrap();
            write_allowance_key(
                &storage,
                &session,
                "dotli.localhost",
                "sha256:artifact-a",
                AllowanceResource::StatementStore,
                vec![2; 64],
            )
            .await
            .unwrap();

            assert_eq!(
                read_allowance_key(
                    &storage,
                    &session,
                    "dotli.localhost",
                    "sha256:artifact-a",
                    AllowanceResource::Bulletin,
                )
                .await
                .unwrap(),
                Some(vec![1; 64])
            );
            assert_eq!(
                read_allowance_key(
                    &storage,
                    &session,
                    "dotli.localhost",
                    "sha256:artifact-b",
                    AllowanceResource::Bulletin,
                )
                .await
                .unwrap(),
                None
            );
            assert_eq!(
                read_allowance_key(
                    &storage,
                    &session,
                    "other.localhost",
                    "sha256:artifact-a",
                    AllowanceResource::Bulletin,
                )
                .await
                .unwrap(),
                None
            );
        });
    }

    #[test]
    fn clear_product_removes_every_artifact_but_preserves_other_products() {
        let storage = MemStorage::default();
        let session = sso_session_info();

        futures::executor::block_on(async {
            for (product_id, artifact_identity, value) in [
                ("dotli.localhost", "sha256:artifact-a", 1),
                ("dotli.localhost", "sha256:artifact-b", 2),
                ("other.localhost", "sha256:artifact-a", 3),
            ] {
                write_allowance_key(
                    &storage,
                    &session,
                    product_id,
                    artifact_identity,
                    AllowanceResource::Bulletin,
                    vec![value; 64],
                )
                .await
                .unwrap();
            }

            clear_product_allowance_keys(&storage, &session, "dotli.localhost")
                .await
                .unwrap();
            for artifact_identity in ["sha256:artifact-a", "sha256:artifact-b"] {
                assert_eq!(
                    read_allowance_key(
                        &storage,
                        &session,
                        "dotli.localhost",
                        artifact_identity,
                        AllowanceResource::Bulletin,
                    )
                    .await
                    .unwrap(),
                    None
                );
            }
            assert_eq!(
                read_allowance_key(
                    &storage,
                    &session,
                    "other.localhost",
                    "sha256:artifact-a",
                    AllowanceResource::Bulletin,
                )
                .await
                .unwrap(),
                Some(vec![3; 64])
            );
        });
    }

    #[test]
    fn legacy_product_only_blob_is_cleared_and_fails_closed() {
        #[derive(Encode)]
        struct LegacyStoredAllowanceEntry {
            product_id: String,
            resource: AllowanceResource,
            slot_account_key: Vec<u8>,
        }

        let storage = MemStorage::default();
        let session = sso_session_info();
        let legacy = vec![LegacyStoredAllowanceEntry {
            product_id: "dotli.localhost".to_string(),
            resource: AllowanceResource::Bulletin,
            slot_account_key: vec![1; 64],
        }]
        .encode();
        futures::executor::block_on(async {
            storage
                .write_core_storage(storage_key(&session).unwrap(), legacy)
                .await
                .unwrap();
            assert_eq!(
                read_allowance_key(
                    &storage,
                    &session,
                    "dotli.localhost",
                    "sha256:artifact-a",
                    AllowanceResource::Bulletin,
                )
                .await
                .unwrap(),
                None
            );
            assert!(
                storage
                    .read_core_storage(storage_key(&session).unwrap())
                    .await
                    .unwrap()
                    .is_none()
            );
        });
    }
}
