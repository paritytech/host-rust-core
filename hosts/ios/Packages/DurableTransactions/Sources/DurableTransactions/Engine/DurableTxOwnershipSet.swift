import Foundation
import os

/// The set of transactions a live submission currently owns, so the recovery pass skips exactly those
/// and each transaction has one writer at a time.
///
/// Ownership is one-shot because there is exactly one acquisition site — ``DurableTxRegistrar``, which
/// takes a freshly minted id inside the registration transaction — and no path anywhere re-takes an id
/// after release, including after a resubmission. A pass reads this per transaction so one registered
/// mid-pass is skipped rather than judged on a chain view older than it is.
///
/// Deliberately volatile: a crash takes the set with it, and an empty set after restart is the correct
/// answer — a durable set would strand transactions behind a watcher that no longer exists.
///
/// Synchronous by design: the pass must test membership without suspending between the test and the
/// read it guards.
public final class DurableTxOwnershipSet: Sendable {
    private let lock = OSAllocatedUnfairLock(initialState: Set<DurableTxId>())

    public init() {}

    /// Takes ownership of a transaction.
    public func take(_ id: DurableTxId) {
        _ = lock.withLock { owned in
            owned.insert(id)
        }
    }

    /// Releases ownership. Returns false if the transaction was already released, so a caller can keep
    /// release side effects one-shot.
    @discardableResult
    public func release(_ id: DurableTxId) -> Bool {
        lock.withLock { owned in
            owned.remove(id) != nil
        }
    }

    public func isOwned(_ id: DurableTxId) -> Bool {
        lock.withLock { owned in owned.contains(id) }
    }
}
