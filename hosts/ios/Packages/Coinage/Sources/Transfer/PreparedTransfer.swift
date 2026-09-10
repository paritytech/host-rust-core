import Foundation

/// The result of preparing a transfer: the memo to hand to the transport, and a provisional handoff
/// to commit once that memo is durable.
///
/// Commit the handle after the memo has durably left toward the recipient (e.g. the chat message
/// row is written). Leaving it uncommitted is safe — a relaunch releases the reservation and the
/// coins return — so a payment that fails before its keys leave never freezes them.
public struct PreparedTransfer {
    public let memo: TransferMemo
    public let handoffCommit: any CoinageHandoffCommit

    public init(memo: TransferMemo, handoffCommit: any CoinageHandoffCommit) {
        self.memo = memo
        self.handoffCommit = handoffCommit
    }
}
