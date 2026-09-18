import Foundation

/// A transaction's status write, applied atomically by
/// ``DurableTxRepositoryProtocol/updateTxStatus(for:expectedCurrentStatus:verdict:)``.
///
/// The status to write and the block where execution was observed (`nil` clears it). A verdict that
/// keeps the existing record simply re-states the same block, so the write is skipped only when both
/// `status` and `successDetectedAt` already match the entry.
public struct Verdict: Sendable, Equatable {
    public let status: DurableTxStatus
    public let successDetectedAt: BlockRef?

    public init(status: DurableTxStatus, successDetectedAt: BlockRef?) {
        self.status = status
        self.successDetectedAt = successDetectedAt
    }
}

/// What the ladder decided for one transaction this pass.
public enum RuleOutcome: Sendable, Equatable {
    /// Write this verdict (a compare-and-set against the status the rules were evaluated from).
    case decided(Verdict)
    /// A read this transaction depended on failed. It keeps its status and its locks, and is retried.
    case undecided
}

public extension RuleOutcome {
    var verdict: Verdict? {
        if case let .decided(verdict) = self { verdict } else { nil }
    }
}
