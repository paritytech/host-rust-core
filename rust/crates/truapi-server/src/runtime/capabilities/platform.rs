//! Product-facing platform capability adapters.

use futures::StreamExt;
use tracing::{instrument, warn};
use truapi::api::{LocalStorage, Locale, Notifications, Permissions, System, Theme};
use truapi::versioned::IntoLatest;
use truapi::versioned::local_storage::{
    HostLocalStorageClearError, HostLocalStorageClearRequest, HostLocalStorageClearResponse,
    HostLocalStorageReadError, HostLocalStorageReadRequest, HostLocalStorageReadResponse,
    HostLocalStorageWriteError, HostLocalStorageWriteRequest, HostLocalStorageWriteResponse,
};
use truapi::versioned::locale::HostLocaleSubscribeItem;
use truapi::versioned::notifications::{
    HostPushNotificationCancelError, HostPushNotificationCancelRequest,
    HostPushNotificationCancelResponse, HostPushNotificationError, HostPushNotificationRequest,
    HostPushNotificationResponse,
};
use truapi::versioned::permissions::{
    HostDevicePermissionError, HostDevicePermissionRequest, HostDevicePermissionResponse,
    RemotePermissionError, RemotePermissionRequest, RemotePermissionResponse,
};
use truapi::versioned::system::{
    HostFeatureSupportedError, HostFeatureSupportedRequest, HostFeatureSupportedResponse,
    HostGetProductContextError, HostGetProductContextRequest, HostGetProductContextResponse,
    HostInfoError, HostInfoRequest, HostInfoResponse, HostNavigateToError, HostNavigateToRequest,
    HostNavigateToResponse,
};
use truapi::versioned::theme::HostThemeSubscribeItem;
use truapi::{CallContext, CallError, Subscription, v01, v02};
use truapi_platform::PermissionAuthorizationStatus;

use crate::host_logic::dotns::{NavigateDecision, external_host, parse_navigate};
use crate::host_logic::features::feature_supported;
use crate::host_logic::product_manifest::Granted;
use crate::runtime::ProductRuntimeHost;

#[truapi::async_trait]
impl System for ProductRuntimeHost {
    #[instrument(skip_all, fields(runtime.method = "system.feature_supported"))]
    async fn feature_supported(
        &self,
        _cx: &CallContext,
        request: HostFeatureSupportedRequest,
    ) -> Result<HostFeatureSupportedResponse, CallError<HostFeatureSupportedError>> {
        let HostFeatureSupportedRequest::V1(inner) = request;
        feature_supported(self.platform.as_ref(), inner)
            .await
            .map(HostFeatureSupportedResponse::V1)
            .map_err(|err| CallError::Domain(HostFeatureSupportedError::V1(err)))
    }

    #[instrument(skip_all, fields(runtime.method = "system.host_info"))]
    async fn host_info(
        &self,
        _cx: &CallContext,
        request: HostInfoRequest,
    ) -> Result<HostInfoResponse, CallError<HostInfoError>> {
        let HostInfoRequest::V1 = request;
        let info = &self.services.host_info;
        Ok(HostInfoResponse::V1(v01::HostInfo {
            platform: info.platform.clone(),
            name: info.name.clone(),
            version: info.version.clone().unwrap_or_default(),
        }))
    }

    #[instrument(skip_all, fields(runtime.method = "system.navigate_to"))]
    async fn navigate_to(
        &self,
        _cx: &CallContext,
        request: HostNavigateToRequest,
    ) -> Result<HostNavigateToResponse, CallError<HostNavigateToError>> {
        let HostNavigateToRequest::V1(v01::HostNavigateToRequest { url }) = request;
        let resolved = match parse_navigate(&url) {
            NavigateDecision::Reject { reason } => {
                return Err(CallError::Domain(HostNavigateToError::V1(
                    v01::HostNavigateToError::Unknown { reason },
                )));
            }
            // dotNS and localhost resolve back into the host's own product
            // surface, which is already gated by the product sandbox. Neither
            // reaches an arbitrary internet host, so neither consumes a grant.
            NavigateDecision::DotName { canonical_url, .. }
            | NavigateDecision::Localhost { canonical_url, .. } => canonical_url,
            // An `http(s)` URL hands an arbitrary host the referrer, the shape
            // of the URL, and whatever the product put in it, so it needs the
            // same per-domain grant that gates outbound access to that host.
            // The other allowed schemes are app handoffs with no authorizable
            // domain (`external_host` returns `None`) and pass straight through.
            NavigateDecision::External { url } => {
                if let Some(host) = external_host(&url) {
                    self.require_remote_permission(
                        v01::RemotePermission::Remote {
                            domains: vec![host],
                        },
                        HostNavigateToError::V1(v01::HostNavigateToError::PermissionDenied),
                    )
                    .await?;
                }
                url
            }
        };
        self.platform
            .navigate_to(resolved)
            .await
            .map(|()| HostNavigateToResponse::V1)
            .map_err(|err| CallError::Domain(HostNavigateToError::V1(err)))
    }

    #[instrument(skip_all, fields(runtime.method = "system.get_product_context"))]
    async fn get_product_context(
        &self,
        _cx: &CallContext,
        _request: HostGetProductContextRequest,
    ) -> Result<HostGetProductContextResponse, CallError<HostGetProductContextError>> {
        Ok(HostGetProductContextResponse::V1(
            v01::HostGetProductContextResponse {
                product_id: self.product.product_id.clone(),
            },
        ))
    }
}

#[truapi::async_trait]
impl Permissions for ProductRuntimeHost {
    #[instrument(skip_all, fields(runtime.method = "permissions.request_device_permission"))]
    async fn request_device_permission(
        &self,
        _cx: &CallContext,
        request: HostDevicePermissionRequest,
    ) -> Result<HostDevicePermissionResponse, CallError<HostDevicePermissionError>> {
        let HostDevicePermissionRequest::V1(inner) = request;
        let product_id = self.product_id();
        let service = self.permissions_service(&product_id);
        match service.check_or_prompt_device(inner).await {
            Ok(decision) => Ok(HostDevicePermissionResponse::V1(
                v01::HostDevicePermissionResponse {
                    granted: decision == PermissionAuthorizationStatus::Authorized,
                },
            )),
            Err(err) => Err(CallError::HostFailure {
                reason: format!("permission storage failed: {err:?}"),
            }),
        }
    }

    #[instrument(skip_all, fields(runtime.method = "permissions.request_remote_permission"))]
    async fn request_remote_permission(
        &self,
        _cx: &CallContext,
        request: RemotePermissionRequest,
    ) -> Result<RemotePermissionResponse, CallError<RemotePermissionError>> {
        let RemotePermissionRequest::V1(inner) = request;
        let product_id = self.product_id();
        let service = self.permissions_service(&product_id);
        match service.check_or_prompt_remote(inner).await {
            Ok(decision) => Ok(RemotePermissionResponse::V1(
                v01::RemotePermissionResponse {
                    granted: decision == PermissionAuthorizationStatus::Authorized,
                },
            )),
            Err(err) => Err(CallError::HostFailure {
                reason: format!("permission storage failed: {err:?}"),
            }),
        }
    }
}

#[truapi::async_trait]
impl LocalStorage for ProductRuntimeHost {
    #[instrument(skip_all, fields(runtime.method = "local_storage.read"))]
    async fn read(
        &self,
        _cx: &CallContext,
        request: HostLocalStorageReadRequest,
    ) -> Result<HostLocalStorageReadResponse, CallError<HostLocalStorageReadError>> {
        let v02::HostLocalStorageReadRequest { product, key } = request.into_latest();

        // One refusal for every reason the grant is not held: telling them apart
        // would make this call a probe for which products exist and which hold
        // data. A prompt is not the fallback either, since stored values are
        // opaque bytes nobody could inspect to approve.
        let owner = match product {
            Some(target) => {
                match self
                    .cross_product_scope_target(&target, Granted::Storage)
                    .await
                {
                    Some(owner) => owner,
                    None => {
                        return Err(CallError::Domain(HostLocalStorageReadError::V2(
                            v02::HostLocalStorageReadError::AccessNotGranted,
                        )));
                    }
                }
            }
            None => self.product_id(),
        };

        self.platform
            .read(self.product_storage_key(&owner, key))
            .await
            .map(|value| {
                HostLocalStorageReadResponse::V2(v01::HostLocalStorageReadResponse { value })
            })
            .map_err(|err| {
                CallError::Domain(HostLocalStorageReadError::V2(
                    HostLocalStorageReadError::V1(err).into_latest(),
                ))
            })
    }

    #[instrument(skip_all, fields(runtime.method = "local_storage.write"))]
    async fn write(
        &self,
        _cx: &CallContext,
        request: HostLocalStorageWriteRequest,
    ) -> Result<HostLocalStorageWriteResponse, CallError<HostLocalStorageWriteError>> {
        let HostLocalStorageWriteRequest::V1(v01::HostLocalStorageWriteRequest { key, value }) =
            request;
        self.platform
            .write(self.product_storage_key(&self.product_id(), key), value)
            .await
            .map(|()| HostLocalStorageWriteResponse::V1)
            .map_err(|err| CallError::Domain(HostLocalStorageWriteError::V1(err)))
    }

    #[instrument(skip_all, fields(runtime.method = "local_storage.clear"))]
    async fn clear(
        &self,
        _cx: &CallContext,
        request: HostLocalStorageClearRequest,
    ) -> Result<HostLocalStorageClearResponse, CallError<HostLocalStorageClearError>> {
        let HostLocalStorageClearRequest::V1(v01::HostLocalStorageClearRequest { key }) = request;
        self.platform
            .clear(self.product_storage_key(&self.product_id(), key))
            .await
            .map(|()| HostLocalStorageClearResponse::V1)
            .map_err(|err| CallError::Domain(HostLocalStorageClearError::V1(err)))
    }
}

#[truapi::async_trait]
impl Theme for ProductRuntimeHost {
    #[instrument(skip_all, fields(runtime.method = "theme.subscribe"))]
    async fn subscribe(&self, _cx: &CallContext) -> Subscription<HostThemeSubscribeItem> {
        let stream = self.platform.subscribe_theme().filter_map(|item| async {
            // TODO: preserve platform stream errors as terminal
            // subscription interrupts once subscription items can carry
            // in-stream failures. Until then a dropped error freezes the
            // product's theme on its last value, so record why.
            match item {
                Ok(item) => Some(HostThemeSubscribeItem::V1(item)),
                Err(error) => {
                    warn!(reason = %error.reason, "theme platform stream failed");
                    None
                }
            }
        });
        Subscription::new(Box::pin(stream))
    }
}

#[truapi::async_trait]
impl Locale for ProductRuntimeHost {
    #[instrument(skip_all, fields(runtime.method = "locale.subscribe"))]
    async fn subscribe(&self, _cx: &CallContext) -> Subscription<HostLocaleSubscribeItem> {
        let stream = self.platform.subscribe_locale().filter_map(|item| async {
            match item {
                Ok(item) => Some(HostLocaleSubscribeItem::V1(item)),
                Err(error) => {
                    warn!(reason = %error.reason, "locale platform stream failed");
                    None
                }
            }
        });
        Subscription::new(Box::pin(stream))
    }
}

// `Notifications` delegates to the platform so hosts can own scheduling and
// cancellation while the core preserves the typed TrUAPI wire shape.

#[truapi::async_trait]
impl Notifications for ProductRuntimeHost {
    #[instrument(skip_all, fields(runtime.method = "notifications.send_push_notification"))]
    async fn send_push_notification(
        &self,
        _cx: &CallContext,
        request: HostPushNotificationRequest,
    ) -> Result<HostPushNotificationResponse, CallError<HostPushNotificationError>> {
        let HostPushNotificationRequest::V1(inner) = request;
        self.platform
            .push_notification(inner)
            .await
            .map(HostPushNotificationResponse::V1)
            .map_err(|err| {
                CallError::Domain(HostPushNotificationError::V1(
                    v01::HostPushNotificationError::Unknown { reason: err.reason },
                ))
            })
    }

    #[instrument(skip_all, fields(runtime.method = "notifications.cancel_push_notification"))]
    async fn cancel_push_notification(
        &self,
        _cx: &CallContext,
        request: HostPushNotificationCancelRequest,
    ) -> Result<HostPushNotificationCancelResponse, CallError<HostPushNotificationCancelError>>
    {
        let HostPushNotificationCancelRequest::V1(v01::HostPushNotificationCancelRequest { id }) =
            request;
        self.platform
            .cancel_notification(id)
            .await
            .map(|()| HostPushNotificationCancelResponse::V1)
            .map_err(|err| {
                CallError::Domain(HostPushNotificationCancelError::V1(v01::GenericError {
                    reason: err.reason,
                }))
            })
    }
}
