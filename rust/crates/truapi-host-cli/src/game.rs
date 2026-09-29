//! Logging Game host for the CLI.
//!
//! Reminders are accepted and logged but never held or fired: this exists to
//! make a Game product runnable headlessly, not to ring anything.

use truapi::latest::{GenericError, HostRemindNextGameError};
use truapi::platform::{GamePlatform, ProductContext, async_trait};

/// A Game host that accepts every reminder and cancel.
pub struct CliGameHost;

#[async_trait]
impl GamePlatform for CliGameHost {
    async fn schedule_game_reminder(
        &self,
        product: &ProductContext,
        starts_at: u64,
        ring_alarm: bool,
        add_calendar_event: bool,
    ) -> Result<(), HostRemindNextGameError> {
        tracing::info!(
            product = %product.product_id,
            starts_at,
            ring_alarm,
            add_calendar_event,
            "game reminder accepted"
        );
        Ok(())
    }

    async fn cancel_game_reminder(&self, product: &ProductContext) -> Result<(), GenericError> {
        tracing::info!(product = %product.product_id, "game reminder cancelled");
        Ok(())
    }
}
