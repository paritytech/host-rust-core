//! Reference-counted demand on product workers.
//!
//! A product has one worker. The host keeps one reference count per worker:
//! the first reference starts it, and when the count returns to zero the host
//! may stop it. An acknowledgement grant is a reference the host takes and
//! releases on its own events. The ledger owns the counts; starting and
//! stopping the executable stays with the host.

use std::collections::HashMap;
use std::sync::{Mutex, MutexGuard};

/// What the host does with a product's worker after demand on it changed.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
#[cfg_attr(not(target_arch = "wasm32"), derive(uniffi::Enum))]
pub enum WorkerTransition {
    /// Demand went from none to some: the host starts the worker.
    Start,
    /// Demand went from some to none: the host may stop the worker.
    Stop,
}

/// Reference counts for every product worker the host tracks, keyed by
/// product id. A product with no references has no entry.
#[derive(Debug, Default)]
pub struct WorkerLedger {
    references: Mutex<HashMap<String, usize>>,
}

impl WorkerLedger {
    fn references(&self) -> MutexGuard<'_, HashMap<String, usize>> {
        self.references
            .lock()
            .expect("worker ledger mutex poisoned")
    }

    /// Take one reference on the product's worker. Returns
    /// [`WorkerTransition::Start`] when it is the first.
    pub fn acquire(&self, product_id: &str) -> Option<WorkerTransition> {
        let mut references = self.references();
        let count = references.entry(product_id.to_string()).or_insert(0);
        *count += 1;
        (*count == 1).then_some(WorkerTransition::Start)
    }

    /// Release one reference. Returns [`WorkerTransition::Stop`] when it was
    /// the last. Releasing a product with no reference is a no-op.
    pub fn release(&self, product_id: &str) -> Option<WorkerTransition> {
        let mut references = self.references();
        let count = references.get_mut(product_id)?;
        *count -= 1;
        if *count > 0 {
            return None;
        }
        references.remove(product_id);
        Some(WorkerTransition::Stop)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn first_reference_starts_and_last_release_stops() {
        let ledger = WorkerLedger::default();
        assert_eq!(ledger.acquire("a.dot"), Some(WorkerTransition::Start));
        assert_eq!(ledger.acquire("a.dot"), None);
        assert_eq!(ledger.release("a.dot"), None);
        assert_eq!(ledger.release("a.dot"), Some(WorkerTransition::Stop));
        assert_eq!(ledger.acquire("a.dot"), Some(WorkerTransition::Start));
    }

    #[test]
    fn releasing_without_a_reference_is_a_no_op() {
        let ledger = WorkerLedger::default();
        assert_eq!(ledger.release("a.dot"), None);
        ledger.acquire("a.dot");
        ledger.release("a.dot");
        assert_eq!(ledger.release("a.dot"), None);
    }

    #[test]
    fn products_are_counted_separately() {
        let ledger = WorkerLedger::default();
        ledger.acquire("a.dot");
        assert_eq!(ledger.acquire("b.dot"), Some(WorkerTransition::Start));
        assert_eq!(ledger.release("a.dot"), Some(WorkerTransition::Stop));
        assert_eq!(ledger.release("b.dot"), Some(WorkerTransition::Stop));
    }
}
