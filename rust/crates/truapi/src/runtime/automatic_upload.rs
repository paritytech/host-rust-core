//! Limits on preimage uploads made under an automatic-upload consent.

use std::collections::{HashMap, VecDeque};
use std::sync::Mutex;
#[cfg(not(target_arch = "wasm32"))]
use std::time::Instant;

use core::time::Duration;
#[cfg(target_arch = "wasm32")]
use web_time::Instant;

/// Largest preimage an automatic-upload consent covers. A larger one still asks the user.
const MAX_BYTES: u64 = 256 * 1024;

/// Unprompted uploads one product may make for one account per [`WINDOW`].
const MAX_UPLOADS_PER_WINDOW: usize = 4;

/// Sliding window [`MAX_UPLOADS_PER_WINDOW`] is counted over.
const WINDOW: Duration = Duration::from_secs(60 * 60);

/// Unprompted uploads per product and account, shared by every product
/// runtime of one host so that reconnecting does not reset the count.
#[derive(Default)]
pub struct AutomaticUploadLedger {
    uploads: Mutex<HashMap<Grantee, VecDeque<Instant>>>,
}

/// The product and account one consent was granted for.
#[derive(PartialEq, Eq, Hash)]
struct Grantee {
    product_id: String,
    root_public_key: [u8; 32],
}

impl AutomaticUploadLedger {
    /// Reserve one unprompted upload of `size` bytes, or return `false` when it
    /// is over the size or frequency limit and the user has to confirm it.
    ///
    /// A reservation counts whether or not the upload then succeeds, so a
    /// failing upload cannot retry past the limit without the user.
    pub fn try_reserve(&self, product_id: &str, root_public_key: [u8; 32], size: u64) -> bool {
        self.try_reserve_at(product_id, root_public_key, size, Instant::now())
    }

    fn try_reserve_at(
        &self,
        product_id: &str,
        root_public_key: [u8; 32],
        size: u64,
        now: Instant,
    ) -> bool {
        if size > MAX_BYTES {
            return false;
        }
        let mut uploads = self
            .uploads
            .lock()
            .expect("automatic upload ledger mutex poisoned");
        let recent = uploads
            .entry(Grantee {
                product_id: product_id.to_string(),
                root_public_key,
            })
            .or_default();
        while recent
            .front()
            .is_some_and(|reserved_at| now.duration_since(*reserved_at) >= WINDOW)
        {
            recent.pop_front();
        }
        if recent.len() >= MAX_UPLOADS_PER_WINDOW {
            return false;
        }
        recent.push_back(now);
        true
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    const PRODUCT: &str = "t3ams.dot";
    const ACCOUNT: [u8; 32] = [7; 32];

    #[test]
    fn uploads_over_the_size_limit_always_ask() {
        let ledger = AutomaticUploadLedger::default();
        assert!(ledger.try_reserve(PRODUCT, ACCOUNT, MAX_BYTES));
        assert!(!ledger.try_reserve(PRODUCT, ACCOUNT, MAX_BYTES + 1));
    }

    /// A background task that uploads on a timer must not be able to turn the
    /// consent into unlimited silent uploads, but the window has to slide so
    /// a steady 15-minute backup keeps running unprompted.
    #[test]
    fn frequency_limit_slides_with_the_window() {
        let ledger = AutomaticUploadLedger::default();
        let start = Instant::now();
        let quarter = WINDOW / 4;
        let reserve = |offset: Duration| ledger.try_reserve_at(PRODUCT, ACCOUNT, 1, start + offset);

        let outcomes: Vec<bool> = [
            Duration::ZERO,
            quarter,
            quarter * 2,
            quarter * 3,
            quarter * 3 + Duration::from_secs(1),
            WINDOW,
        ]
        .into_iter()
        .map(reserve)
        .collect();

        assert_eq!(outcomes, [true, true, true, true, false, true]);
    }

    #[test]
    fn limits_are_counted_per_product_and_account() {
        let ledger = AutomaticUploadLedger::default();
        let now = Instant::now();
        for _ in 0..MAX_UPLOADS_PER_WINDOW {
            assert!(ledger.try_reserve_at(PRODUCT, ACCOUNT, 1, now));
        }

        assert_eq!(
            [
                ledger.try_reserve_at(PRODUCT, ACCOUNT, 1, now),
                ledger.try_reserve_at("other.dot", ACCOUNT, 1, now),
                ledger.try_reserve_at(PRODUCT, [8; 32], 1, now),
            ],
            [false, true, true]
        );
    }
}
