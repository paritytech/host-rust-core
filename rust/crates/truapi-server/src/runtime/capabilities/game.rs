//! Product-facing Game capability adapter.

use std::sync::Arc;

use tracing::instrument;
use truapi::api::Game;
use truapi::latest;
use truapi::versioned::IntoLatest;
use truapi::versioned::game::{
    HostCancelNextGameError, HostCancelNextGameRequest, HostCancelNextGameResponse,
    HostRemindNextGameError, HostRemindNextGameRequest, HostRemindNextGameResponse,
};
use truapi::{CallContext, CallError};
use truapi_platform::{GamePlatform, PermissionAuthorizationStatus};

use crate::runtime::ProductRuntimeHost;

/// The device clock in Unix milliseconds, which is what `starts_at` is
/// measured against.
fn now_ms() -> u64 {
    #[cfg(not(target_arch = "wasm32"))]
    use std::time::{SystemTime, UNIX_EPOCH};
    #[cfg(target_arch = "wasm32")]
    use web_time::{SystemTime, UNIX_EPOCH};

    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|elapsed| u64::try_from(elapsed.as_millis()).unwrap_or(u64::MAX))
        .unwrap_or_default()
}

fn remind_error(error: latest::HostRemindNextGameError) -> CallError<HostRemindNextGameError> {
    CallError::Domain(HostRemindNextGameError::V1(error))
}

impl ProductRuntimeHost {
    /// The host's Game adapter. A host without one has no way to remind the
    /// user, so both methods answer `Unsupported` before anything else runs.
    fn game_platform<E>(&self) -> Result<Arc<dyn GamePlatform>, CallError<E>> {
        self.game_platform.clone().ok_or(CallError::Unsupported)
    }
}

#[truapi::async_trait]
impl Game for ProductRuntimeHost {
    #[instrument(skip_all, fields(runtime.method = "game.remind_next_game"))]
    async fn remind_next_game(
        &self,
        _cx: &CallContext,
        request: HostRemindNextGameRequest,
    ) -> Result<HostRemindNextGameResponse, CallError<HostRemindNextGameError>> {
        let platform = self.game_platform()?;
        let latest::HostRemindNextGameRequest { starts_at } = request.into_latest();
        if starts_at <= now_ms() {
            return Err(remind_error(latest::HostRemindNextGameError::StartsInPast));
        }
        let product_id = self.product_id();
        let status = self
            .permissions_service(&product_id)
            .authorize_device(latest::HostDevicePermissionRequest::Alarm)
            .await
            .map_err(|error| CallError::HostFailure {
                reason: format!("permission storage failed: {error:?}"),
            })?;
        if status != PermissionAuthorizationStatus::Authorized {
            return Err(remind_error(
                latest::HostRemindNextGameError::PermissionDenied,
            ));
        }
        // The prompt can outlast the start, and a reminder for a game that
        // has begun brings nobody back.
        if starts_at <= now_ms() {
            return Err(remind_error(latest::HostRemindNextGameError::StartsInPast));
        }
        platform
            .schedule_game_reminder(&self.product, starts_at)
            .await
            .map(|()| HostRemindNextGameResponse::V1)
            .map_err(|error| {
                remind_error(latest::HostRemindNextGameError::Unknown {
                    reason: error.reason,
                })
            })
    }

    #[instrument(skip_all, fields(runtime.method = "game.cancel_next_game"))]
    async fn cancel_next_game(
        &self,
        _cx: &CallContext,
        request: HostCancelNextGameRequest,
    ) -> Result<HostCancelNextGameResponse, CallError<HostCancelNextGameError>> {
        let platform = self.game_platform()?;
        let latest::HostCancelNextGameRequest {} = request.into_latest();
        platform
            .cancel_game_reminder(&self.product)
            .await
            .map(|()| HostCancelNextGameResponse::V1)
            .map_err(|error| CallError::Domain(HostCancelNextGameError::V1(error)))
    }
}
