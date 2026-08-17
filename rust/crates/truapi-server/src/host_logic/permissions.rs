//! Permission authorization state machine (ask -> authorized | denied), backed
//! by the platform [`CoreStorage`] trait with typed [`CoreStorageKey`] slots.
//!
//! Device permissions (camera, mic, NFC, ...) are separate from remote
//! permissions (domain access, chain submit, ...), so this module exposes two
//! `check_or_prompt` entrypoints that route to the matching platform callback.
//! The cache layer is shared but keys are typed so a device grant cannot
//! authorize a remote operation by accident. Keys are also scoped by product id
//! so one product's authorization never grants another product's request.
//! Identity disclosure is also represented as a product-scoped authorization,
//! but the prompt itself is handled by the account runtime because it uses the
//! richer user-confirmation surface rather than the device/remote callbacks.
//!
//! Domain grants (`RemotePermission::Remote`) are the one request that does not
//! occupy a single slot. A product may ask for several domains at once, while
//! enforcement — outbound navigation, and any future outbound-request gate —
//! only ever asks about one host. So a bundle is stored as one authorization per
//! domain pattern, and a lookup for a concrete host resolves through the
//! RFC 0002 candidate list ([`remote_domain_candidates`]), letting the most
//! specific stored decision win.

use parity_scale_codec::{Decode, Encode};

use truapi::latest::{
    GenericError, HostDevicePermissionRequest, HostDevicePermissionResponse, RemotePermission,
    RemotePermissionRequest, RemotePermissionResponse,
};
use truapi_platform::{
    CoreStorage, CoreStorageKey, PermissionAuthorizationRequest, PermissionAuthorizationStatus,
    Permissions, remote_domain_candidates,
};

/// Persisted answer for a single permission request. Keep `Authorized` at
/// discriminant 0 and `Denied` at 1 to preserve the existing two-variant cache
/// encoding.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Encode, Decode)]
enum StoredAuthorizationStatus {
    /// User authorized the permission.
    Authorized,
    /// User denied the permission.
    Denied,
}

impl From<StoredAuthorizationStatus> for PermissionAuthorizationStatus {
    fn from(status: StoredAuthorizationStatus) -> Self {
        match status {
            StoredAuthorizationStatus::Authorized => PermissionAuthorizationStatus::Authorized,
            StoredAuthorizationStatus::Denied => PermissionAuthorizationStatus::Denied,
        }
    }
}

impl From<bool> for StoredAuthorizationStatus {
    fn from(granted: bool) -> Self {
        if granted {
            Self::Authorized
        } else {
            Self::Denied
        }
    }
}

/// Domain patterns a remote request covers, or `None` when the request is not a
/// domain grant and so occupies a single slot of its own.
fn requested_domains(request: &RemotePermissionRequest) -> Option<&[String]> {
    match &request.permission {
        RemotePermission::Remote { domains } => Some(domains),
        _ => None,
    }
}

/// Coordinator that inspects persisted state first, falls back to the
/// platform's prompt callback, and writes the authorization back so future
/// calls short-circuit.
pub struct PermissionsService<'a, S: CoreStorage + ?Sized, P: Permissions + ?Sized> {
    storage: &'a S,
    prompt: &'a P,
    product_id: &'a str,
}

impl<'a, S: CoreStorage + ?Sized, P: Permissions + ?Sized> PermissionsService<'a, S, P> {
    /// Construct a service backed by the given storage + prompt callbacks.
    pub fn new(storage: &'a S, prompt: &'a P, product_id: &'a str) -> Self {
        Self {
            storage,
            prompt,
            product_id,
        }
    }

    /// Returns the stored authorization status for a device permission without prompting.
    pub async fn peek_device(
        &self,
        permission: &HostDevicePermissionRequest,
    ) -> Result<PermissionAuthorizationStatus, GenericError> {
        authorization_status(
            self.storage,
            CoreStorageKey::device_permission_authorization(self.product_id, permission),
        )
        .await
    }

    /// Returns the stored authorization status for a remote permission without
    /// prompting.
    ///
    /// A domain bundle is authorized only when every domain in it is; a single
    /// denial denies the bundle, because the product asked to reach all of them.
    pub async fn peek_remote(
        &self,
        request: &RemotePermissionRequest,
    ) -> Result<PermissionAuthorizationStatus, GenericError> {
        let Some(domains) = requested_domains(request) else {
            return authorization_status(
                self.storage,
                CoreStorageKey::remote_permission_authorization(self.product_id, request),
            )
            .await;
        };
        // An empty bundle grants access to nothing. Reporting it as authorized
        // would let a malformed request read as a grant, so fail closed.
        if domains.is_empty() {
            return Ok(PermissionAuthorizationStatus::Denied);
        }
        let mut combined = PermissionAuthorizationStatus::Authorized;
        for domain in domains {
            match self.stored_domain_status(domain).await? {
                PermissionAuthorizationStatus::Denied => {
                    return Ok(PermissionAuthorizationStatus::Denied);
                }
                PermissionAuthorizationStatus::NotDetermined => {
                    combined = PermissionAuthorizationStatus::NotDetermined;
                }
                PermissionAuthorizationStatus::Authorized => {}
            }
        }
        Ok(combined)
    }

    /// Stored decision covering one concrete host or pattern.
    ///
    /// Walks [`remote_domain_candidates`] most-specific-first and returns the
    /// first stored decision, so an explicit grant for `api.example.com`
    /// survives a denial of `*.example.com` and vice versa.
    async fn stored_domain_status(
        &self,
        domain: &str,
    ) -> Result<PermissionAuthorizationStatus, GenericError> {
        for candidate in remote_domain_candidates(domain) {
            let key = CoreStorageKey::remote_domain_authorization(self.product_id, &candidate);
            if let Some(stored) = peek_stored(self.storage, key).await? {
                return Ok(stored.into());
            }
        }
        Ok(PermissionAuthorizationStatus::NotDetermined)
    }

    /// Returns the stored authorization status for a permission request
    /// without prompting.
    pub async fn authorization_status(
        &self,
        request: &PermissionAuthorizationRequest,
    ) -> Result<PermissionAuthorizationStatus, GenericError> {
        match request {
            PermissionAuthorizationRequest::Device(permission) => {
                self.peek_device(permission).await
            }
            PermissionAuthorizationRequest::Remote(request) => self.peek_remote(request).await,
            PermissionAuthorizationRequest::IdentityDisclosure => {
                authorization_status(
                    self.storage,
                    CoreStorageKey::identity_disclosure_authorization(self.product_id),
                )
                .await
            }
            PermissionAuthorizationRequest::AccountAccess { target_product_id } => {
                authorization_status(
                    self.storage,
                    CoreStorageKey::account_access_authorization(
                        self.product_id,
                        target_product_id,
                    ),
                )
                .await
            }
        }
    }

    /// Returns the stored authorization statuses for permission requests
    /// without prompting. Results follow the same order as `requests`.
    pub async fn authorization_statuses(
        &self,
        requests: &[PermissionAuthorizationRequest],
    ) -> Result<Vec<PermissionAuthorizationStatus>, GenericError> {
        let mut statuses = Vec::with_capacity(requests.len());
        for request in requests {
            statuses.push(self.authorization_status(request).await?);
        }
        Ok(statuses)
    }

    /// Update the stored authorization status for a permission request.
    ///
    /// Setting `NotDetermined` clears the stored value so the next product
    /// request prompts again.
    pub async fn set_authorization_status(
        &self,
        request: &PermissionAuthorizationRequest,
        status: PermissionAuthorizationStatus,
    ) -> Result<(), GenericError> {
        let key = match request {
            PermissionAuthorizationRequest::Device(permission) => {
                CoreStorageKey::device_permission_authorization(self.product_id, permission)
            }
            PermissionAuthorizationRequest::Remote(request) => {
                // Domain grants live one key per pattern, so a revocation has to
                // clear every pattern the request names. Writing a single bundle
                // slot would leave the per-domain grants enforcement reads intact.
                if let Some(domains) = requested_domains(request) {
                    for domain in domains {
                        set_authorization_status(
                            self.storage,
                            CoreStorageKey::remote_domain_authorization(self.product_id, domain),
                            status,
                        )
                        .await?;
                    }
                    return Ok(());
                }
                CoreStorageKey::remote_permission_authorization(self.product_id, request)
            }
            PermissionAuthorizationRequest::IdentityDisclosure => {
                CoreStorageKey::identity_disclosure_authorization(self.product_id)
            }
            PermissionAuthorizationRequest::AccountAccess { target_product_id } => {
                CoreStorageKey::account_access_authorization(self.product_id, target_product_id)
            }
        };
        set_authorization_status(self.storage, key, status).await
    }

    /// Returns the cached device authorization if any, otherwise prompts the
    /// platform's `device_permission` callback and persists the answer.
    pub async fn check_or_prompt_device(
        &self,
        permission: HostDevicePermissionRequest,
    ) -> Result<PermissionAuthorizationStatus, GenericError> {
        let key = CoreStorageKey::device_permission_authorization(self.product_id, &permission);
        if let Some(cached) = peek_stored(self.storage, key.clone()).await? {
            return Ok(cached.into());
        }
        // Only a genuine user authorization is persisted. A prompt-callback
        // error is transient (dismissed UI, unavailable UI, IPC timeout), not
        // a denial, so leave the authorization ask/default.
        let authorization = match self.prompt.device_permission(permission).await {
            Ok(HostDevicePermissionResponse { granted }) => granted.into(),
            Err(_) => return Ok(PermissionAuthorizationStatus::NotDetermined),
        };
        self.persist_decision(key, authorization).await
    }

    /// Returns the cached remote authorization if any, otherwise prompts the
    /// platform's `remote_permission` callback and persists the answer.
    ///
    /// For a domain bundle the prompt covers only the domains with no stored
    /// decision, and the answer is written to exactly those. Re-asking about an
    /// already-granted domain would let one denial revoke it, and re-asking
    /// about a denied one contradicts the prompt-once rule.
    pub async fn check_or_prompt_remote(
        &self,
        request: RemotePermissionRequest,
    ) -> Result<PermissionAuthorizationStatus, GenericError> {
        let Some(domains) = requested_domains(&request).map(<[String]>::to_vec) else {
            let key = CoreStorageKey::remote_permission_authorization(self.product_id, &request);
            if let Some(cached) = peek_stored(self.storage, key.clone()).await? {
                return Ok(cached.into());
            }
            // See `check_or_prompt_device`: persist only a genuine user decision;
            // transient callback errors leave the authorization ask/default.
            let authorization = match self.prompt.remote_permission(request).await {
                Ok(RemotePermissionResponse { granted }) => granted.into(),
                Err(_) => return Ok(PermissionAuthorizationStatus::NotDetermined),
            };
            return self.persist_decision(key, authorization).await;
        };

        if domains.is_empty() {
            return Ok(PermissionAuthorizationStatus::Denied);
        }

        let mut undetermined = Vec::new();
        for domain in &domains {
            match self.stored_domain_status(domain).await? {
                PermissionAuthorizationStatus::Denied => {
                    return Ok(PermissionAuthorizationStatus::Denied);
                }
                PermissionAuthorizationStatus::NotDetermined => undetermined.push(domain.clone()),
                PermissionAuthorizationStatus::Authorized => {}
            }
        }
        if undetermined.is_empty() {
            return Ok(PermissionAuthorizationStatus::Authorized);
        }

        let authorization = match self
            .prompt
            .remote_permission(RemotePermissionRequest {
                permission: RemotePermission::Remote {
                    domains: undetermined.clone(),
                },
            })
            .await
        {
            Ok(RemotePermissionResponse { granted }) => StoredAuthorizationStatus::from(granted),
            Err(_) => return Ok(PermissionAuthorizationStatus::NotDetermined),
        };
        for domain in &undetermined {
            self.persist_decision(
                CoreStorageKey::remote_domain_authorization(self.product_id, domain),
                authorization,
            )
            .await?;
        }
        Ok(authorization.into())
    }

    /// Persist a fresh user decision and return its public status.
    async fn persist_decision(
        &self,
        key: CoreStorageKey,
        authorization: StoredAuthorizationStatus,
    ) -> Result<PermissionAuthorizationStatus, GenericError> {
        self.storage
            .write_core_storage(key, authorization.encode())
            .await?;
        Ok(authorization.into())
    }
}

async fn authorization_status<S: CoreStorage + ?Sized>(
    storage: &S,
    key: CoreStorageKey,
) -> Result<PermissionAuthorizationStatus, GenericError> {
    Ok(peek_stored(storage, key)
        .await?
        .map(Into::into)
        .unwrap_or(PermissionAuthorizationStatus::NotDetermined))
}

async fn peek_stored<S: CoreStorage + ?Sized>(
    storage: &S,
    key: CoreStorageKey,
) -> Result<Option<StoredAuthorizationStatus>, GenericError> {
    let Some(raw) = storage.read_core_storage(key).await? else {
        return Ok(None);
    };
    Ok(StoredAuthorizationStatus::decode(&mut &*raw).ok())
}

async fn set_authorization_status<S: CoreStorage + ?Sized>(
    storage: &S,
    key: CoreStorageKey,
    status: PermissionAuthorizationStatus,
) -> Result<(), GenericError> {
    match status_into_stored(status) {
        Some(stored) => storage.write_core_storage(key, stored.encode()).await,
        None => storage.clear_core_storage(key).await,
    }
}

fn status_into_stored(status: PermissionAuthorizationStatus) -> Option<StoredAuthorizationStatus> {
    match status {
        PermissionAuthorizationStatus::NotDetermined => None,
        PermissionAuthorizationStatus::Denied => Some(StoredAuthorizationStatus::Denied),
        PermissionAuthorizationStatus::Authorized => Some(StoredAuthorizationStatus::Authorized),
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use futures::lock::Mutex;
    use std::collections::HashMap;
    use std::sync::atomic::{AtomicUsize, Ordering};
    use truapi::latest::RemotePermission;
    use truapi::v01;
    use truapi::v01::GenericError;

    #[derive(Default)]
    struct MemStorage {
        inner: Mutex<HashMap<String, Vec<u8>>>,
    }

    #[truapi_platform::async_trait]
    impl CoreStorage for MemStorage {
        async fn read_core_storage(
            &self,
            key: CoreStorageKey,
        ) -> Result<Option<Vec<u8>>, v01::GenericError> {
            Ok(self.inner.lock().await.get(&test_key(key)).cloned())
        }
        async fn write_core_storage(
            &self,
            key: CoreStorageKey,
            value: Vec<u8>,
        ) -> Result<(), v01::GenericError> {
            self.inner.lock().await.insert(test_key(key), value);
            Ok(())
        }
        async fn clear_core_storage(&self, key: CoreStorageKey) -> Result<(), v01::GenericError> {
            self.inner.lock().await.remove(&test_key(key));
            Ok(())
        }
    }

    fn test_key(key: CoreStorageKey) -> String {
        hex::encode(key.encode())
    }

    struct ScriptedPrompt {
        device_answers: Mutex<Vec<bool>>,
        remote_answers: Mutex<Vec<bool>>,
        device_calls: AtomicUsize,
        remote_calls: AtomicUsize,
        /// Domain bundles the remote callback was actually asked about, in call
        /// order, so a test can assert which subset reached the user.
        remote_domains_asked: Mutex<Vec<Vec<String>>>,
    }

    impl ScriptedPrompt {
        fn new(device_answers: Vec<bool>, remote_answers: Vec<bool>) -> Self {
            Self {
                device_answers: Mutex::new(device_answers),
                remote_answers: Mutex::new(remote_answers),
                device_calls: AtomicUsize::new(0),
                remote_calls: AtomicUsize::new(0),
                remote_domains_asked: Mutex::new(Vec::new()),
            }
        }

        fn domains_asked(&self) -> Vec<Vec<String>> {
            futures::executor::block_on(self.remote_domains_asked.lock()).clone()
        }
    }

    #[truapi_platform::async_trait]
    impl Permissions for ScriptedPrompt {
        async fn device_permission(
            &self,
            _request: HostDevicePermissionRequest,
        ) -> Result<HostDevicePermissionResponse, GenericError> {
            self.device_calls.fetch_add(1, Ordering::SeqCst);
            let granted = self
                .device_answers
                .lock()
                .await
                .pop()
                .expect("ScriptedPrompt ran out of device answers");
            Ok(v01::HostDevicePermissionResponse { granted })
        }

        async fn remote_permission(
            &self,
            request: RemotePermissionRequest,
        ) -> Result<RemotePermissionResponse, GenericError> {
            self.remote_calls.fetch_add(1, Ordering::SeqCst);
            if let RemotePermission::Remote { domains } = &request.permission {
                self.remote_domains_asked.lock().await.push(domains.clone());
            }
            let granted = self
                .remote_answers
                .lock()
                .await
                .pop()
                .expect("ScriptedPrompt ran out of remote answers");
            Ok(v01::RemotePermissionResponse { granted })
        }
    }

    fn remote_domains(domains: &[&str]) -> RemotePermissionRequest {
        RemotePermissionRequest {
            permission: RemotePermission::Remote {
                domains: domains.iter().map(|domain| domain.to_string()).collect(),
            },
        }
    }

    #[test]
    fn check_or_prompt_device_caches_grant() {
        let storage = MemStorage::default();
        let prompt = ScriptedPrompt::new(vec![true], vec![]);
        let service = PermissionsService::new(&storage, &prompt, "product.dot");

        let first = futures::executor::block_on(
            service.check_or_prompt_device(HostDevicePermissionRequest::Camera),
        )
        .unwrap();
        let second = futures::executor::block_on(
            service.check_or_prompt_device(HostDevicePermissionRequest::Camera),
        )
        .unwrap();

        assert_eq!(first, PermissionAuthorizationStatus::Authorized);
        assert_eq!(second, PermissionAuthorizationStatus::Authorized);
        assert_eq!(prompt.device_calls.load(Ordering::SeqCst), 1);
    }

    #[test]
    fn check_or_prompt_remote_caches_denial() {
        let storage = MemStorage::default();
        let prompt = ScriptedPrompt::new(vec![], vec![false]);
        let service = PermissionsService::new(&storage, &prompt, "product.dot");

        let request = RemotePermissionRequest {
            permission: RemotePermission::ChainSubmit,
        };
        let first =
            futures::executor::block_on(service.check_or_prompt_remote(request.clone())).unwrap();
        let second = futures::executor::block_on(service.check_or_prompt_remote(request)).unwrap();

        assert_eq!(first, PermissionAuthorizationStatus::Denied);
        assert_eq!(second, PermissionAuthorizationStatus::Denied);
        assert_eq!(prompt.remote_calls.load(Ordering::SeqCst), 1);
    }

    /// The defect this storage model exists to fix: a product grants a bundle,
    /// then enforcement asks about one host in it. Keying the bundle as a set
    /// made that lookup miss and re-prompt, so a granted domain read as
    /// undecided forever.
    #[test]
    fn a_bundle_grant_is_visible_to_a_single_domain_lookup() {
        let storage = MemStorage::default();
        let prompt = ScriptedPrompt::new(vec![], vec![true]);
        let service = PermissionsService::new(&storage, &prompt, "product.dot");

        let granted = futures::executor::block_on(
            service.check_or_prompt_remote(remote_domains(&["a.example.com", "b.example.com"])),
        )
        .unwrap();
        assert_eq!(granted, PermissionAuthorizationStatus::Authorized);

        for domain in ["a.example.com", "b.example.com"] {
            assert_eq!(
                futures::executor::block_on(service.peek_remote(&remote_domains(&[domain])))
                    .unwrap(),
                PermissionAuthorizationStatus::Authorized,
                "{domain} was granted as part of the bundle"
            );
            assert_eq!(
                futures::executor::block_on(
                    service.check_or_prompt_remote(remote_domains(&[domain]))
                )
                .unwrap(),
                PermissionAuthorizationStatus::Authorized,
            );
        }
        assert_eq!(
            prompt.remote_calls.load(Ordering::SeqCst),
            1,
            "a domain already covered by the bundle must not re-prompt"
        );
    }

    #[test]
    fn a_wildcard_grant_covers_one_subdomain_level_only() {
        let storage = MemStorage::default();
        let prompt = ScriptedPrompt::new(vec![], vec![true]);
        let service = PermissionsService::new(&storage, &prompt, "product.dot");

        futures::executor::block_on(
            service.check_or_prompt_remote(remote_domains(&["*.example.com"])),
        )
        .unwrap();

        assert_eq!(
            futures::executor::block_on(service.peek_remote(&remote_domains(&["api.example.com"])))
                .unwrap(),
            PermissionAuthorizationStatus::Authorized
        );
        // RFC 0002: a wildcard spans exactly one label, so a two-level host is
        // still undecided and the bare parent is not covered either.
        for uncovered in ["deep.api.example.com", "example.com"] {
            assert_eq!(
                futures::executor::block_on(service.peek_remote(&remote_domains(&[uncovered])))
                    .unwrap(),
                PermissionAuthorizationStatus::NotDetermined,
                "{uncovered} is outside a single-level wildcard"
            );
        }
    }

    #[test]
    fn the_most_specific_stored_decision_wins() {
        let storage = MemStorage::default();
        let prompt = ScriptedPrompt::new(vec![], vec![]);
        let service = PermissionsService::new(&storage, &prompt, "product.dot");

        // Deny the whole wildcard, then allow one host under it explicitly.
        futures::executor::block_on(service.set_authorization_status(
            &PermissionAuthorizationRequest::Remote(remote_domains(&["*.example.com"])),
            PermissionAuthorizationStatus::Denied,
        ))
        .unwrap();
        futures::executor::block_on(service.set_authorization_status(
            &PermissionAuthorizationRequest::Remote(remote_domains(&["api.example.com"])),
            PermissionAuthorizationStatus::Authorized,
        ))
        .unwrap();

        assert_eq!(
            futures::executor::block_on(service.peek_remote(&remote_domains(&["api.example.com"])))
                .unwrap(),
            PermissionAuthorizationStatus::Authorized,
            "an explicit host grant outranks a denied parent wildcard"
        );
        assert_eq!(
            futures::executor::block_on(
                service.peek_remote(&remote_domains(&["other.example.com"]))
            )
            .unwrap(),
            PermissionAuthorizationStatus::Denied,
            "a host with no decision of its own inherits the wildcard denial"
        );
    }

    #[test]
    fn a_prompt_covers_only_undetermined_domains_and_never_revokes_a_grant() {
        let storage = MemStorage::default();
        // Answers pop from the end: grant first, then deny.
        let prompt = ScriptedPrompt::new(vec![], vec![false, true]);
        let service = PermissionsService::new(&storage, &prompt, "product.dot");

        futures::executor::block_on(service.check_or_prompt_remote(remote_domains(&["a.com"])))
            .unwrap();
        let second = futures::executor::block_on(
            service.check_or_prompt_remote(remote_domains(&["a.com", "b.com"])),
        )
        .unwrap();

        assert_eq!(
            prompt.domains_asked(),
            vec![vec!["a.com".to_string()], vec!["b.com".to_string()]],
            "the second prompt must ask only about the undecided domain"
        );
        assert_eq!(
            second,
            PermissionAuthorizationStatus::Denied,
            "the bundle needs every domain, so one denial denies it"
        );
        assert_eq!(
            futures::executor::block_on(service.peek_remote(&remote_domains(&["a.com"]))).unwrap(),
            PermissionAuthorizationStatus::Authorized,
            "denying b.com must not revoke the existing a.com grant"
        );
    }

    #[test]
    fn a_denied_domain_short_circuits_the_bundle_without_prompting() {
        let storage = MemStorage::default();
        let prompt = ScriptedPrompt::new(vec![], vec![false]);
        let service = PermissionsService::new(&storage, &prompt, "product.dot");

        futures::executor::block_on(service.check_or_prompt_remote(remote_domains(&["a.com"])))
            .unwrap();
        let second = futures::executor::block_on(
            service.check_or_prompt_remote(remote_domains(&["a.com", "b.com"])),
        )
        .unwrap();

        assert_eq!(second, PermissionAuthorizationStatus::Denied);
        assert_eq!(
            prompt.remote_calls.load(Ordering::SeqCst),
            1,
            "a stored denial is not re-asked"
        );
    }

    #[test]
    fn an_empty_domain_bundle_is_denied_without_prompting() {
        let storage = MemStorage::default();
        let prompt = ScriptedPrompt::new(vec![], vec![]);
        let service = PermissionsService::new(&storage, &prompt, "product.dot");

        assert_eq!(
            futures::executor::block_on(service.check_or_prompt_remote(remote_domains(&[])))
                .unwrap(),
            PermissionAuthorizationStatus::Denied
        );
        assert_eq!(
            futures::executor::block_on(service.peek_remote(&remote_domains(&[]))).unwrap(),
            PermissionAuthorizationStatus::Denied
        );
        assert_eq!(prompt.remote_calls.load(Ordering::SeqCst), 0);
    }

    #[test]
    fn clearing_a_bundle_clears_each_domain_it_names() {
        let storage = MemStorage::default();
        let prompt = ScriptedPrompt::new(vec![], vec![true]);
        let service = PermissionsService::new(&storage, &prompt, "product.dot");

        futures::executor::block_on(
            service.check_or_prompt_remote(remote_domains(&["a.com", "b.com"])),
        )
        .unwrap();
        futures::executor::block_on(service.set_authorization_status(
            &PermissionAuthorizationRequest::Remote(remote_domains(&["a.com", "b.com"])),
            PermissionAuthorizationStatus::NotDetermined,
        ))
        .unwrap();

        for domain in ["a.com", "b.com"] {
            assert_eq!(
                futures::executor::block_on(service.peek_remote(&remote_domains(&[domain])))
                    .unwrap(),
                PermissionAuthorizationStatus::NotDetermined,
                "{domain} must be revocable through the bundle it was granted in"
            );
        }
    }

    #[test]
    fn remote_domain_grants_are_scoped_to_one_product() {
        let storage = MemStorage::default();
        let prompt = ScriptedPrompt::new(vec![], vec![true]);
        let service = PermissionsService::new(&storage, &prompt, "product.dot");
        futures::executor::block_on(service.check_or_prompt_remote(remote_domains(&["a.com"])))
            .unwrap();

        let other = PermissionsService::new(&storage, &prompt, "other.dot");
        assert_eq!(
            futures::executor::block_on(other.peek_remote(&remote_domains(&["a.com"]))).unwrap(),
            PermissionAuthorizationStatus::NotDetermined
        );
    }

    #[test]
    fn device_and_remote_caches_are_independent() {
        let storage = MemStorage::default();
        // Device denies, remote grants. If the caches collided we'd see the
        // same answer on the second call.
        let prompt = ScriptedPrompt::new(vec![false], vec![true]);
        let service = PermissionsService::new(&storage, &prompt, "product.dot");

        let device = futures::executor::block_on(
            service.check_or_prompt_device(HostDevicePermissionRequest::Camera),
        )
        .unwrap();
        let remote =
            futures::executor::block_on(service.check_or_prompt_remote(RemotePermissionRequest {
                permission: RemotePermission::ChainSubmit,
            }))
            .unwrap();

        assert_eq!(device, PermissionAuthorizationStatus::Denied);
        assert_eq!(remote, PermissionAuthorizationStatus::Authorized);
        assert_eq!(prompt.device_calls.load(Ordering::SeqCst), 1);
        assert_eq!(prompt.remote_calls.load(Ordering::SeqCst), 1);
    }

    #[test]
    fn device_prompt_does_not_invoke_remote_callback() {
        let storage = MemStorage::default();
        let prompt = ScriptedPrompt::new(vec![true], vec![]);
        let service = PermissionsService::new(&storage, &prompt, "product.dot");

        let _ = futures::executor::block_on(
            service.check_or_prompt_device(HostDevicePermissionRequest::Camera),
        )
        .unwrap();
        assert_eq!(prompt.device_calls.load(Ordering::SeqCst), 1);
        assert_eq!(prompt.remote_calls.load(Ordering::SeqCst), 0);
    }

    #[test]
    fn remote_prompt_does_not_invoke_device_callback() {
        let storage = MemStorage::default();
        let prompt = ScriptedPrompt::new(vec![], vec![true]);
        let service = PermissionsService::new(&storage, &prompt, "product.dot");

        let _ =
            futures::executor::block_on(service.check_or_prompt_remote(RemotePermissionRequest {
                permission: RemotePermission::WebRtc,
            }))
            .unwrap();
        assert_eq!(prompt.device_calls.load(Ordering::SeqCst), 0);
        assert_eq!(prompt.remote_calls.load(Ordering::SeqCst), 1);
    }

    #[test]
    fn peek_returns_not_determined_until_authorized() {
        let storage = MemStorage::default();
        let prompt = ScriptedPrompt::new(vec![true], vec![]);
        let service = PermissionsService::new(&storage, &prompt, "product.dot");

        let before =
            futures::executor::block_on(service.peek_device(&HostDevicePermissionRequest::Camera))
                .unwrap();
        assert_eq!(before, PermissionAuthorizationStatus::NotDetermined);

        futures::executor::block_on(
            service.check_or_prompt_device(HostDevicePermissionRequest::Camera),
        )
        .unwrap();

        let after =
            futures::executor::block_on(service.peek_device(&HostDevicePermissionRequest::Camera))
                .unwrap();
        assert_eq!(after, PermissionAuthorizationStatus::Authorized);
    }

    #[test]
    fn set_authorization_status_writes_and_clears() {
        let storage = MemStorage::default();
        let prompt = ScriptedPrompt::new(vec![], vec![]);
        let service = PermissionsService::new(&storage, &prompt, "product.dot");
        let request = PermissionAuthorizationRequest::Device(HostDevicePermissionRequest::Camera);

        futures::executor::block_on(
            service.set_authorization_status(&request, PermissionAuthorizationStatus::Authorized),
        )
        .unwrap();
        assert_eq!(
            futures::executor::block_on(service.authorization_status(&request)).unwrap(),
            PermissionAuthorizationStatus::Authorized
        );

        futures::executor::block_on(
            service
                .set_authorization_status(&request, PermissionAuthorizationStatus::NotDetermined),
        )
        .unwrap();
        assert_eq!(
            futures::executor::block_on(service.authorization_status(&request)).unwrap(),
            PermissionAuthorizationStatus::NotDetermined
        );
    }

    #[test]
    fn identity_disclosure_authorization_round_trips() {
        let storage = MemStorage::default();
        let prompt = ScriptedPrompt::new(vec![], vec![]);
        let service = PermissionsService::new(&storage, &prompt, "product.dot");
        let request = PermissionAuthorizationRequest::IdentityDisclosure;

        assert_eq!(
            futures::executor::block_on(service.authorization_status(&request)).unwrap(),
            PermissionAuthorizationStatus::NotDetermined
        );

        futures::executor::block_on(
            service.set_authorization_status(&request, PermissionAuthorizationStatus::Authorized),
        )
        .unwrap();
        assert_eq!(
            futures::executor::block_on(service.authorization_status(&request)).unwrap(),
            PermissionAuthorizationStatus::Authorized
        );

        let other_product_service = PermissionsService::new(&storage, &prompt, "other.dot");
        assert_eq!(
            futures::executor::block_on(other_product_service.authorization_status(&request))
                .unwrap(),
            PermissionAuthorizationStatus::NotDetermined
        );
    }

    #[test]
    fn account_access_authorization_is_scoped_by_requester_and_target() {
        let storage = MemStorage::default();
        let prompt = ScriptedPrompt::new(vec![], vec![]);
        let service = PermissionsService::new(&storage, &prompt, "product.dot");
        let request = PermissionAuthorizationRequest::AccountAccess {
            target_product_id: "target.dot".to_string(),
        };

        futures::executor::block_on(
            service.set_authorization_status(&request, PermissionAuthorizationStatus::Authorized),
        )
        .unwrap();
        assert_eq!(
            futures::executor::block_on(service.authorization_status(&request)).unwrap(),
            PermissionAuthorizationStatus::Authorized
        );
        assert_eq!(
            futures::executor::block_on(service.authorization_status(
                &PermissionAuthorizationRequest::AccountAccess {
                    target_product_id: "other.dot".to_string(),
                }
            ))
            .unwrap(),
            PermissionAuthorizationStatus::NotDetermined
        );

        let other_product_service = PermissionsService::new(&storage, &prompt, "other.dot");
        assert_eq!(
            futures::executor::block_on(other_product_service.authorization_status(&request))
                .unwrap(),
            PermissionAuthorizationStatus::NotDetermined
        );
    }

    /// Prompt callback that always errors, to exercise the transient-failure
    /// path (fail closed for the current call, but do not persist the error).
    struct FailingPrompt;

    #[truapi_platform::async_trait]
    impl Permissions for FailingPrompt {
        async fn device_permission(
            &self,
            _request: HostDevicePermissionRequest,
        ) -> Result<HostDevicePermissionResponse, GenericError> {
            Err(GenericError {
                reason: "boom".into(),
            })
        }

        async fn remote_permission(
            &self,
            _request: RemotePermissionRequest,
        ) -> Result<RemotePermissionResponse, GenericError> {
            Err(GenericError {
                reason: "boom".into(),
            })
        }
    }

    #[test]
    fn prompt_failure_stays_not_determined_without_persisting() {
        let storage = MemStorage::default();
        let prompt = FailingPrompt;
        let service = PermissionsService::new(&storage, &prompt, "product.dot");

        let device_decision = futures::executor::block_on(
            service.check_or_prompt_device(HostDevicePermissionRequest::Camera),
        )
        .unwrap();
        assert_eq!(
            device_decision,
            PermissionAuthorizationStatus::NotDetermined
        );

        let remote_request = RemotePermissionRequest {
            permission: RemotePermission::ChainSubmit,
        };
        let remote_decision =
            futures::executor::block_on(service.check_or_prompt_remote(remote_request.clone()))
                .unwrap();
        assert_eq!(
            remote_decision,
            PermissionAuthorizationStatus::NotDetermined
        );

        // A transient callback error is not cached, so peek still sees no
        // authorization and the next request re-prompts rather than
        // permanently locking out the capability.
        let cached_device =
            futures::executor::block_on(service.peek_device(&HostDevicePermissionRequest::Camera))
                .unwrap();
        assert_eq!(
            cached_device,
            PermissionAuthorizationStatus::NotDetermined,
            "a transient prompt error must not be persisted"
        );
        let cached_remote =
            futures::executor::block_on(service.peek_remote(&remote_request)).unwrap();
        assert_eq!(
            cached_remote,
            PermissionAuthorizationStatus::NotDetermined,
            "a transient prompt error must not be persisted"
        );
    }

    /// A corrupt SCALE-encoded cache entry must be treated as "no cache",
    /// not panic. The service falls back to prompting.
    #[test]
    fn corrupt_cache_entry_returns_none() {
        let storage = MemStorage::default();
        // Write garbage bytes under the canonical key.
        futures::executor::block_on(storage.write_core_storage(
            CoreStorageKey::device_permission_authorization(
                "product.dot",
                &HostDevicePermissionRequest::Camera,
            ),
            vec![0xff, 0xfe, 0xfd],
        ))
        .unwrap();

        let prompt = ScriptedPrompt::new(vec![true], vec![]);
        let service = PermissionsService::new(&storage, &prompt, "product.dot");

        let peeked =
            futures::executor::block_on(service.peek_device(&HostDevicePermissionRequest::Camera))
                .unwrap();
        assert_eq!(
            peeked,
            PermissionAuthorizationStatus::NotDetermined,
            "corrupt entry must decode as absent"
        );
    }

    /// Storage failures must propagate to the caller; the service must not
    /// swallow them by silently returning a default authorization.
    #[derive(Default)]
    struct FailingStorage;

    #[truapi_platform::async_trait]
    impl CoreStorage for FailingStorage {
        async fn read_core_storage(
            &self,
            _key: CoreStorageKey,
        ) -> Result<Option<Vec<u8>>, v01::GenericError> {
            Err(v01::GenericError {
                reason: "read failed".into(),
            })
        }
        async fn write_core_storage(
            &self,
            _key: CoreStorageKey,
            _value: Vec<u8>,
        ) -> Result<(), v01::GenericError> {
            Err(v01::GenericError {
                reason: "write failed".into(),
            })
        }
        async fn clear_core_storage(&self, _key: CoreStorageKey) -> Result<(), v01::GenericError> {
            Err(v01::GenericError {
                reason: "clear failed".into(),
            })
        }
    }

    #[test]
    fn storage_read_error_propagates() {
        let storage = FailingStorage;
        let prompt = ScriptedPrompt::new(vec![], vec![]);
        let service = PermissionsService::new(&storage, &prompt, "product.dot");

        let err = futures::executor::block_on(
            service.check_or_prompt_device(HostDevicePermissionRequest::Camera),
        )
        .expect_err("read failure must surface");
        assert!(matches!(err, v01::GenericError { .. }));
    }
}
