//! In-memory Game host for the CLI.
//!
//! Reminders are held in memory for the length of the process and never fire:
//! this exists to make a Game product runnable headlessly, not to ring
//! anything.

use std::collections::BTreeMap;
use std::sync::{Arc, Mutex};

use truapi::latest::GenericError;
use truapi_platform::{GamePlatform, ProductContext, async_trait};

/// A Game host that keeps one reminder per product in memory.
pub struct CliGameHost {
    /// Product id to the start it holds, in Unix milliseconds.
    reminders: Mutex<BTreeMap<String, u64>>,
}

impl CliGameHost {
    /// Build an empty Game host.
    pub fn new() -> Arc<Self> {
        Arc::new(Self {
            reminders: Mutex::new(BTreeMap::new()),
        })
    }

    #[cfg(test)]
    fn reminder(&self, product_id: &str) -> Option<u64> {
        self.reminders
            .lock()
            .expect("game reminders mutex poisoned")
            .get(product_id)
            .copied()
    }
}

#[async_trait]
impl GamePlatform for CliGameHost {
    async fn schedule_game_reminder(
        &self,
        product: &ProductContext,
        starts_at: u64,
    ) -> Result<(), GenericError> {
        tracing::info!(product = %product.product_id, starts_at, "game reminder held");
        self.reminders
            .lock()
            .expect("game reminders mutex poisoned")
            .insert(product.product_id.clone(), starts_at);
        Ok(())
    }

    async fn cancel_game_reminder(&self, product: &ProductContext) -> Result<(), GenericError> {
        tracing::info!(product = %product.product_id, "game reminder dropped");
        self.reminders
            .lock()
            .expect("game reminders mutex poisoned")
            .remove(&product.product_id);
        Ok(())
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn product(id: &str) -> ProductContext {
        ProductContext::new(id.to_string()).expect("valid product id")
    }

    fn schedule(host: &CliGameHost, product_id: &str, starts_at: u64) {
        futures::executor::block_on(host.schedule_game_reminder(&product(product_id), starts_at))
            .expect("schedule succeeds");
    }

    fn cancel(host: &CliGameHost, product_id: &str) {
        futures::executor::block_on(host.cancel_game_reminder(&product(product_id)))
            .expect("cancel succeeds");
    }

    /// The CLI serves every product from one process, and a `/product` switch
    /// reuses the same host, so reminders are keyed by product.
    #[test]
    fn one_product_cannot_see_or_cancel_another_products_reminder() {
        let host = CliGameHost::new();
        schedule(&host, "mine.dot", 10);
        cancel(&host, "theirs.dot");

        assert_eq!(host.reminder("mine.dot"), Some(10));
        assert_eq!(host.reminder("theirs.dot"), None);
    }

    #[test]
    fn a_schedule_replaces_the_previous_reminder_and_cancel_is_idempotent() {
        let host = CliGameHost::new();
        schedule(&host, "mine.dot", 10);
        schedule(&host, "mine.dot", 20);
        assert_eq!(host.reminder("mine.dot"), Some(20));

        cancel(&host, "mine.dot");
        cancel(&host, "mine.dot");
        assert_eq!(host.reminder("mine.dot"), None);
    }
}
