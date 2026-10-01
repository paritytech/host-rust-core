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

use crate::platform::{
    GAME_PRODUCT_LABEL, GamePlatform, PermissionAuthorizationStatus, dotns_product_label,
};
use crate::runtime::ProductRuntimeHost;
use crate::unix_time::current_unix_millis;

/// The Game API serves the game product alone.
fn is_game_product(product_id: &str) -> bool {
    dotns_product_label(product_id) == Some(GAME_PRODUCT_LABEL)
}

fn remind_error(error: latest::HostRemindNextGameError) -> CallError<HostRemindNextGameError> {
    CallError::Domain(HostRemindNextGameError::V1(error))
}

/// A withdrawn call shows no further prompt and schedules nothing. The
/// answers already given stay saved.
fn ensure_active(cx: &CallContext) -> Result<(), CallError<HostRemindNextGameError>> {
    if cx.cancel().is_cancelled() {
        Err(CallError::Cancelled)
    } else {
        Ok(())
    }
}

/// A reminder for a game that has begun brings nobody back.
fn ensure_upcoming(starts_at: u64) -> Result<(), CallError<HostRemindNextGameError>> {
    if starts_at > current_unix_millis() {
        Ok(())
    } else {
        Err(remind_error(latest::HostRemindNextGameError::StartsInPast))
    }
}

impl ProductRuntimeHost {
    /// The host's Game adapter, for the game product only. Any other product,
    /// or a host without an adapter, gets `Unsupported` before anything else
    /// runs.
    fn game_platform<E>(&self) -> Result<Arc<dyn GamePlatform>, CallError<E>> {
        if !is_game_product(self.product.product_id.as_str()) {
            return Err(CallError::Unsupported);
        }
        self.game_platform.clone().ok_or(CallError::Unsupported)
    }

    async fn is_device_authorized(
        &self,
        cx: &CallContext,
        request: latest::HostDevicePermissionRequest,
    ) -> Result<bool, CallError<HostRemindNextGameError>> {
        ensure_active(cx)?;
        self.permissions_service()
            .authorize_device(request)
            .await
            .map(|status| status == PermissionAuthorizationStatus::Authorized)
            .map_err(|error| CallError::HostFailure {
                reason: format!("permission storage failed: {error:?}"),
            })
    }

    /// Whether the reminder rings as an alarm. Without `Alarm` it falls back to
    /// an ordinary notification; without `Notifications` either, nothing can
    /// remind the user.
    async fn rings_alarm(
        &self,
        cx: &CallContext,
    ) -> Result<bool, CallError<HostRemindNextGameError>> {
        if self
            .is_device_authorized(cx, latest::HostDevicePermissionRequest::Alarm)
            .await?
        {
            return Ok(true);
        }
        if self
            .is_device_authorized(cx, latest::HostDevicePermissionRequest::Notifications)
            .await?
        {
            return Ok(false);
        }
        Err(remind_error(
            latest::HostRemindNextGameError::PermissionDenied,
        ))
    }

    /// Calendar is optional: without it the host still reminds the user and
    /// only leaves the calendar alone, so a storage failure counts as a refusal.
    async fn adds_calendar_event(
        &self,
        cx: &CallContext,
    ) -> Result<bool, CallError<HostRemindNextGameError>> {
        match self
            .is_device_authorized(cx, latest::HostDevicePermissionRequest::Calendar)
            .await
        {
            Err(CallError::HostFailure { reason }) => {
                tracing::warn!(%reason, "calendar permission unreadable; adding no calendar event");
                Ok(false)
            }
            other => other,
        }
    }
}

#[truapi::async_trait]
impl Game for ProductRuntimeHost {
    #[instrument(skip_all, fields(runtime.method = "game.remind_next_game"))]
    async fn remind_next_game(
        &self,
        cx: &CallContext,
        request: HostRemindNextGameRequest,
    ) -> Result<HostRemindNextGameResponse, CallError<HostRemindNextGameError>> {
        let platform = self.game_platform()?;
        let latest::HostRemindNextGameRequest { starts_at } = request.into_latest();
        ensure_upcoming(starts_at)?;
        let ring_alarm = self.rings_alarm(cx).await?;
        let add_calendar_event = self.adds_calendar_event(cx).await?;
        // The prompts can outlast both the start and the caller.
        ensure_upcoming(starts_at)?;
        ensure_active(cx)?;
        platform
            .schedule_game_reminder(&self.product, starts_at, ring_alarm, add_calendar_event)
            .await
            .map(|()| HostRemindNextGameResponse::V1)
            .map_err(|error| CallError::HostFailure {
                reason: error.reason,
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
