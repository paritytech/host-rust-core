import Foundation

/// The outcome of a strategy's foreground preparation.
///
/// `prepare` does everything that must complete before the memo — the keys — can leave the device:
/// register entries, insert projected outputs, and pre-commit the handoff. It returns the handoff
/// handle, committed once the memo is durable, and the background work that submits the on-chain
/// extrinsic(s).
struct PreparedStrategy {
    /// Memo entries for the coins the recipient receives — built from what `prepare` minted.
    let memoEntries: [PlannedMemoEntry]
    let handoffCommit: any CoinageHandoffCommit
}

/// Protocol for transfer execution strategies. Each strategy mints its outputs, fires the
/// (background-tracked) submission, and pre-commits the handoff — all in one `prepare`.
protocol TransferStrategy {
    /// Mints outputs (persisted by the allocator), submits the extrinsic(s) fire-and-forget under
    /// `groupId` (the transfer's message id, or `nil` when ungrouped), and pre-commits the handoff.
    /// Returns the memo entries and the handoff handle.
    func prepare(groupId: CoinageTxGroupId?) async throws -> PreparedStrategy
}
