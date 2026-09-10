import Foundation

/// A durability entry's status write, applied atomically by
/// ``CoinageTxRepositoryProtocol/updateTxStatus(for:expectedCurrentStatus:verdict:)``.
///
/// The status to write and the block where execution was observed (`nil` clears it). A verdict that
/// keeps the existing record simply re-states the same block, so the write is skipped only when both
/// `status` and `successDetectedAt` already match the entry.
public struct Verdict: Sendable, Equatable {
    public let status: CoinageTxStatus
    public let successDetectedAt: BlockRef?

    public init(status: CoinageTxStatus, successDetectedAt: BlockRef?) {
        self.status = status
        self.successDetectedAt = successDetectedAt
    }
}
