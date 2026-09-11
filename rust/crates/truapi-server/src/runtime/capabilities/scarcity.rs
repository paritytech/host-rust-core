//! Product-facing `Scarcity` (NFT pocket) capability adapter.
//!
//! Every method resolves the calling product from the runtime, never from
//! the request, checks the persisted grant, and delegates to the account
//! authority, which alone holds the purse keys. Hosts without purses answer
//! `Unsupported` before any session is consulted.

use core::time::Duration;
use std::sync::Arc;

use tracing::instrument;
use truapi::api::Scarcity;
use truapi::versioned::scarcity::{
    HostScarcityListError, HostScarcityListRequest, HostScarcityListResponse,
    HostScarcityListSubscribeError, HostScarcityListSubscribeItem,
    HostScarcityListSubscribeRequest, HostScarcityRequestReceiveAddressError,
    HostScarcityRequestReceiveAddressRequest, HostScarcityRequestReceiveAddressResponse,
    HostScarcityTransferError, HostScarcityTransferItem, HostScarcityTransferRequest,
};
use truapi::{CallContext, CallError, Subscription, v01};
use truapi_platform::{
    PermissionAuthorizationRequest, PermissionAuthorizationStatus, Platform, ScarcityAccessReview,
    ScarcityReceiveForReview, ScarcityTransferReview, UserConfirmationReview,
};

use crate::host_logic::permissions::PermissionsService;
use crate::runtime::authority::AuthoritySession;
use crate::runtime::scarcity::{PocketAuthorityError, PocketError};
use crate::runtime::{AccountAccessAuthorizationError, AuthorityError, ProductRuntimeHost};

/// Interval between purse re-reads while a `list_subscribe` stream is open.
/// The chain is not observed reactively yet; this is the honest pull that
/// keeps a live view live.
const SCARCITY_LIST_POLL_INTERVAL: Duration = Duration::from_secs(12);

/// Map a pocket failure onto the service's error, with `wrap` naming the
/// method's versioned envelope.
fn scarcity_call_error<E>(
    err: PocketAuthorityError,
    wrap: impl Fn(v01::ScarcityError) -> E,
) -> CallError<E> {
    let domain = match err {
        PocketAuthorityError::Authority(AuthorityError::Disconnected) => {
            v01::ScarcityError::NotConnected
        }
        PocketAuthorityError::Authority(AuthorityError::Rejected) => v01::ScarcityError::Rejected,
        PocketAuthorityError::Authority(AuthorityError::NotSupported { .. }) => {
            return CallError::Unsupported;
        }
        PocketAuthorityError::Authority(other) => v01::ScarcityError::Unknown {
            reason: other.to_string(),
        },
        PocketAuthorityError::Pocket(PocketError::ChainNotServed) => {
            v01::ScarcityError::ChainNotServed
        }
        PocketAuthorityError::Pocket(PocketError::Derivation(_)) => {
            v01::ScarcityError::UnknownTarget
        }
        PocketAuthorityError::Pocket(other) => v01::ScarcityError::Unknown {
            reason: other.to_string(),
        },
    };
    CallError::Domain(wrap(domain))
}

/// Persist a yes/no answer the way every product-scoped grant is stored.
async fn persist_grant(
    platform: &dyn Platform,
    product_id: &str,
    request: PermissionAuthorizationRequest,
    review: UserConfirmationReview,
) -> Result<PermissionAuthorizationStatus, AccountAccessAuthorizationError> {
    let service = PermissionsService::new(platform, platform, product_id);
    let cached = service
        .authorization_status(&request)
        .await
        .map_err(AccountAccessAuthorizationError::PermissionStorage)?;
    if cached != PermissionAuthorizationStatus::NotDetermined {
        return Ok(cached);
    }
    let confirmed = platform
        .confirm_user_action(review)
        .await
        .map_err(AccountAccessAuthorizationError::Confirmation)?;
    let status = if confirmed {
        PermissionAuthorizationStatus::Authorized
    } else {
        PermissionAuthorizationStatus::Denied
    };
    service
        .set_authorization_status(&request, status)
        .await
        .map_err(AccountAccessAuthorizationError::PermissionStorage)?;
    Ok(status)
}

/// Once per product: may it list its own purse and allocate keys in it?
async fn scarcity_access_authorization(
    platform: &dyn Platform,
    product_id: &str,
    collections: Option<Vec<u32>>,
) -> Result<PermissionAuthorizationStatus, AccountAccessAuthorizationError> {
    persist_grant(
        platform,
        product_id,
        PermissionAuthorizationRequest::ScarcityAccess,
        UserConfirmationReview::ScarcityAccess(ScarcityAccessReview {
            product_id: product_id.to_string(),
            collections,
        }),
    )
    .await
}

/// Once per caller and target: may `product_id` allocate receive keys in
/// `target_product_id`'s purse?
async fn scarcity_receive_for_authorization(
    platform: &dyn Platform,
    product_id: &str,
    target_product_id: &str,
) -> Result<PermissionAuthorizationStatus, AccountAccessAuthorizationError> {
    persist_grant(
        platform,
        product_id,
        PermissionAuthorizationRequest::ScarcityReceiveFor {
            target_product_id: target_product_id.to_string(),
        },
        UserConfirmationReview::ScarcityReceiveFor(ScarcityReceiveForReview {
            product_id: product_id.to_string(),
            target_product_id: target_product_id.to_string(),
        }),
    )
    .await
}

impl ProductRuntimeHost {
    /// The active authority session, or `Unsupported` on a host without
    /// purses and the service's `NotConnected` on one without a session.
    fn scarcity_session<E>(
        &self,
        wrap: impl Fn(v01::ScarcityError) -> E,
    ) -> Result<AuthoritySession, CallError<E>> {
        if !self.authority.supports_scarcity() {
            return Err(CallError::Unsupported);
        }
        self.authority
            .current_session()
            .ok_or_else(|| CallError::Domain(wrap(v01::ScarcityError::NotConnected)))
    }

    /// Resolve a grant outcome into the service's error space.
    fn scarcity_grant<E>(
        outcome: Result<PermissionAuthorizationStatus, AccountAccessAuthorizationError>,
        wrap: impl Fn(v01::ScarcityError) -> E,
    ) -> Result<(), CallError<E>> {
        match outcome {
            Ok(PermissionAuthorizationStatus::Authorized) => Ok(()),
            Ok(_) => Err(CallError::Domain(wrap(v01::ScarcityError::Rejected))),
            Err(err) => Err(CallError::Domain(wrap(v01::ScarcityError::Unknown {
                reason: err.to_string(),
            }))),
        }
    }
}

#[truapi::async_trait]
impl Scarcity for ProductRuntimeHost {
    #[instrument(skip_all, fields(runtime.method = "scarcity.list"))]
    async fn list(
        &self,
        cx: &CallContext,
        request: HostScarcityListRequest,
    ) -> Result<HostScarcityListResponse, CallError<HostScarcityListError>> {
        let HostScarcityListRequest::V1(v01::HostScarcityListRequest { collections }) = request;
        let wrap = HostScarcityListError::V1;
        let session = self.scarcity_session(wrap)?;
        let product_id = self.product_id();
        Self::scarcity_grant(
            scarcity_access_authorization(self.platform.as_ref(), &product_id, collections.clone())
                .await,
            wrap,
        )?;
        let items = self
            .authority
            .scarcity_list(cx, &session, product_id, collections)
            .await
            .map_err(|err| scarcity_call_error(err, wrap))?;
        Ok(HostScarcityListResponse::V1(
            v01::HostScarcityListResponse { items },
        ))
    }

    #[instrument(skip_all, fields(runtime.method = "scarcity.request_receive_address"))]
    async fn request_receive_address(
        &self,
        cx: &CallContext,
        request: HostScarcityRequestReceiveAddressRequest,
    ) -> Result<
        HostScarcityRequestReceiveAddressResponse,
        CallError<HostScarcityRequestReceiveAddressError>,
    > {
        let HostScarcityRequestReceiveAddressRequest::V1(
            v01::HostScarcityRequestReceiveAddressRequest {
                idempotency_key,
                target,
            },
        ) = request;
        let wrap = HostScarcityRequestReceiveAddressError::V1;
        let session = self.scarcity_session(wrap)?;
        let product_id = self.product_id();
        let target = match target {
            Some(target) if target != product_id => {
                Self::scarcity_grant(
                    scarcity_receive_for_authorization(
                        self.platform.as_ref(),
                        &product_id,
                        &target,
                    )
                    .await,
                    wrap,
                )?;
                target
            }
            _ => {
                Self::scarcity_grant(
                    scarcity_access_authorization(self.platform.as_ref(), &product_id, None).await,
                    wrap,
                )?;
                product_id.clone()
            }
        };
        let address = self
            .authority
            .scarcity_request_receive_address(cx, &session, target, product_id, idempotency_key)
            .await
            .map_err(|err| scarcity_call_error(err, wrap))?;
        Ok(HostScarcityRequestReceiveAddressResponse::V1(
            v01::HostScarcityRequestReceiveAddressResponse { address },
        ))
    }

    #[instrument(skip_all, fields(runtime.method = "scarcity.transfer"))]
    async fn transfer(
        &self,
        cx: &CallContext,
        request: HostScarcityTransferRequest,
    ) -> Result<Subscription<HostScarcityTransferItem>, CallError<HostScarcityTransferError>> {
        let HostScarcityTransferRequest::V1(v01::HostScarcityTransferRequest { instance, to }) =
            request;
        let wrap = HostScarcityTransferError::V1;
        let session = self.scarcity_session(wrap)?;
        let product_id = self.product_id();
        Self::scarcity_grant(
            scarcity_access_authorization(self.platform.as_ref(), &product_id, None).await,
            wrap,
        )?;
        // The sheet names the item, so it has to be in the caller's purse first.
        let held = self
            .authority
            .scarcity_list(cx, &session, product_id.clone(), None)
            .await
            .map_err(|err| scarcity_call_error(err, wrap))?;
        let item = held
            .into_iter()
            .find(|item| item.instance == instance)
            .ok_or_else(|| CallError::Domain(wrap(v01::ScarcityError::NotFound)))?;
        let to_product_id = self
            .authority
            .scarcity_purse_of(cx, &session, to)
            .await
            .map_err(|err| scarcity_call_error(err, wrap))?;
        // Every move asks; a stored grant never covers a transfer.
        let approved = self
            .platform
            .confirm_user_action(UserConfirmationReview::ScarcityTransfer(
                ScarcityTransferReview {
                    product_id: product_id.clone(),
                    instance,
                    collection: item.collection,
                    item: item.item,
                    to,
                    to_product_id,
                },
            ))
            .await
            .map_err(|err| {
                CallError::Domain(wrap(v01::ScarcityError::Unknown { reason: err.reason }))
            })?;
        if !approved {
            return Err(CallError::Domain(wrap(v01::ScarcityError::Rejected)));
        }

        let (sender, receiver) = futures::channel::mpsc::unbounded();
        let progress_sender = sender.clone();
        let progress: Arc<dyn Fn(v01::ScarcityTransferStatus) + Send + Sync> =
            Arc::new(move |status| {
                let _ = progress_sender.unbounded_send(HostScarcityTransferItem::V1(status));
            });
        let authority = self.authority.clone();
        let cx = CallContext::with_request_id(cx.request_id().to_string());
        (self.services.spawner)(Box::pin(async move {
            let outcome = authority
                .scarcity_transfer(&cx, &session, product_id, instance, to, progress)
                .await;
            let terminal = match outcome {
                Ok(_) => v01::ScarcityTransferStatus::Landed,
                Err(err) => v01::ScarcityTransferStatus::Failed {
                    error: err.to_service_error(),
                },
            };
            let _ = sender.unbounded_send(HostScarcityTransferItem::V1(terminal));
            // Dropping the sender closes the stream after the terminal item.
        }));
        Ok(Subscription::new(Box::pin(receiver)))
    }

    #[instrument(skip_all, fields(runtime.method = "scarcity.list_subscribe"))]
    async fn list_subscribe(
        &self,
        cx: &CallContext,
        request: HostScarcityListSubscribeRequest,
    ) -> Result<
        Subscription<HostScarcityListSubscribeItem>,
        CallError<HostScarcityListSubscribeError>,
    > {
        let HostScarcityListSubscribeRequest::V1(v01::HostScarcityListSubscribeRequest {
            collections,
        }) = request;
        let wrap = HostScarcityListSubscribeError::V1;
        let session = self.scarcity_session(wrap)?;
        let product_id = self.product_id();
        Self::scarcity_grant(
            scarcity_access_authorization(self.platform.as_ref(), &product_id, collections.clone())
                .await,
            wrap,
        )?;
        let first = self
            .authority
            .scarcity_list(cx, &session, product_id.clone(), collections.clone())
            .await
            .map_err(|err| scarcity_call_error(err, wrap))?;

        let (sender, receiver) = futures::channel::mpsc::unbounded();
        let item = |items: Vec<truapi::latest::ScarcityItem>| {
            HostScarcityListSubscribeItem::V1(v01::HostScarcityListSubscribeItem { items })
        };
        let _ = sender.unbounded_send(item(first.clone()));
        let authority = self.authority.clone();
        let cx = CallContext::with_request_id(cx.request_id().to_string());
        (self.services.spawner)(Box::pin(async move {
            let mut last = first;
            loop {
                futures_timer::Delay::new(SCARCITY_LIST_POLL_INTERVAL).await;
                if sender.is_closed() {
                    break;
                }
                match authority
                    .scarcity_list(&cx, &session, product_id.clone(), collections.clone())
                    .await
                {
                    Ok(items) => {
                        if items != last && sender.unbounded_send(item(items.clone())).is_err() {
                            break;
                        }
                        last = items;
                    }
                    // A failed read ends the stream; the product re-subscribes
                    // and sees the error on its next call.
                    Err(_) => break,
                }
            }
        }));
        Ok(Subscription::new(Box::pin(receiver)))
    }
}
