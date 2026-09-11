//! Purse keys served by the paired signing host over SSO.
//!
//! A pairing host holds no root entropy, and every purse junction is hard, so
//! it cannot derive even a purse public key. It asks the Account Holder for
//! key ranges and caches them per SSO session; allocation and signing are
//! relayed one request at a time. The cache holds public material only and
//! is cleared with the session so a later pairing never serves stale keys.

use async_trait::async_trait;
use truapi::CallContext;

use super::PairingHost;
use crate::host_logic::session::SessionInfo;
use crate::host_logic::sso::messages::{PurseAllocateRequest, PurseKeysRequest};
use crate::runtime::authority::AuthoritySession;
use crate::runtime::scarcity::keys::{
    PURSE_KEYS_MAX_COUNT, PurseKeys, PurseTransfer, SignedTransfer,
};
use crate::runtime::scarcity::{PocketError, SCAN_MAX};
use crate::runtime::sso_remote::SsoSessionKey;

/// Keys fetched on a cache miss, so a ten-key scan batch costs one round trip
/// and a small purse is read in one.
const PURSE_KEYS_PREFETCH: u32 = 50;

/// One purse public key's cache slot: SSO session, purse, index.
pub(super) type PurseKeyCacheKey = (SsoSessionKey, String, u32);

/// The paired Account Holder as a purse key source for one call.
pub(super) struct RemotePurseKeys<'a> {
    host: &'a PairingHost,
    cx: &'a CallContext,
}

impl<'a> RemotePurseKeys<'a> {
    /// A source relaying `cx`'s call to the host's paired signing host.
    pub(super) fn new(host: &'a PairingHost, cx: &'a CallContext) -> Self {
        Self { host, cx }
    }

    fn session_info(&self, session: &AuthoritySession) -> Result<SessionInfo, PocketError> {
        Ok(self.host.current_private_session(session)?)
    }

    fn cached(&self, key: &PurseKeyCacheKey) -> Option<[u8; 32]> {
        self.host
            .purse_keys
            .lock()
            .expect("purse key cache mutex poisoned")
            .get(key)
            .copied()
    }
}

#[async_trait]
impl PurseKeys for RemotePurseKeys<'_> {
    async fn public_keys(
        &self,
        session: &AuthoritySession,
        product_id: &str,
        start: u32,
        count: u32,
    ) -> Result<Vec<[u8; 32]>, PocketError> {
        let info = self.session_info(session)?;
        let sso = info.sso.as_ref().ok_or(PocketError::Authority(
            crate::runtime::authority::AuthorityError::Disconnected,
        ))?;
        let session_key = SsoSessionKey::from_session(sso);
        let end = start.saturating_add(count);
        let cache_key = |index: u32| (session_key, product_id.to_string(), index);
        let first_miss = (start..end).find(|index| self.cached(&cache_key(*index)).is_none());
        if let Some(first_miss) = first_miss {
            let lifecycle_epoch = self.host.current_session_lifecycle_epoch();
            let fetch = (end - first_miss)
                .clamp(PURSE_KEYS_PREFETCH, PURSE_KEYS_MAX_COUNT)
                .min(SCAN_MAX.saturating_sub(first_miss));
            let fetched = self
                .host
                .remote_purse_keys(
                    self.cx,
                    &info,
                    PurseKeysRequest {
                        product_id: product_id.to_string(),
                        start: first_miss,
                        count: fetch,
                    },
                )
                .await?;
            if fetched.len() != fetch as usize {
                return Err(PocketError::Unknown {
                    reason: format!(
                        "the Account Holder returned {} purse keys for {fetch} indices",
                        fetched.len()
                    ),
                });
            }
            let cached = self.host.cache_purse_keys_if_current(
                &info,
                lifecycle_epoch,
                fetched
                    .into_iter()
                    .enumerate()
                    .map(|(offset, key)| (cache_key(first_miss + offset as u32), key)),
            );
            if !cached {
                return Err(PocketError::Authority(
                    crate::runtime::authority::AuthorityError::Disconnected,
                ));
            }
        }
        (start..end)
            .map(|index| {
                self.cached(&cache_key(index))
                    .ok_or_else(|| PocketError::Unknown {
                        reason: format!("purse key {index} of {product_id} is missing"),
                    })
            })
            .collect()
    }

    async fn allocate_receive_key(
        &self,
        session: &AuthoritySession,
        target_product_id: &str,
        requested_by: &str,
        idempotency_key: &str,
    ) -> Result<(u32, [u8; 32]), PocketError> {
        let info = self.session_info(session)?;
        let sso = info.sso.as_ref().ok_or(PocketError::Authority(
            crate::runtime::authority::AuthorityError::Disconnected,
        ))?;
        let session_key = SsoSessionKey::from_session(sso);
        let lifecycle_epoch = self.host.current_session_lifecycle_epoch();
        let (index, key) = self
            .host
            .remote_purse_allocate(
                self.cx,
                &info,
                PurseAllocateRequest {
                    target_product_id: target_product_id.to_string(),
                    requested_by: requested_by.to_string(),
                    idempotency_key: idempotency_key.to_string(),
                },
            )
            .await?;
        // The desktop's own store only learns the purse exists and how far it
        // reaches; it never allocates.
        self.host
            .pocket
            .store()
            .observe_allocated(session.public_key, target_product_id, index)
            .await?;
        self.host.cache_purse_keys_if_current(
            &info,
            lifecycle_epoch,
            core::iter::once(((session_key, target_product_id.to_string(), index), key)),
        );
        Ok((index, key))
    }

    async fn sign_transfer(
        &self,
        session: &AuthoritySession,
        request: PurseTransfer,
    ) -> Result<SignedTransfer, PocketError> {
        let info = self.session_info(session)?;
        Ok(self
            .host
            .remote_purse_sign(self.cx, &info, request.into())
            .await?
            .into())
    }
}
