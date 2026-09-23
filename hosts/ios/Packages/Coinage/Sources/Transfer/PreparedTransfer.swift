import Foundation

/// The memo to hand to the transport and its idempotent handoff commit handle.
///
/// Ordinary transfers reserve provisionally: commit after the carrying payload is durable, or a
/// relaunch releases the reservation. Native-custody transfers have already committed their marks
/// and derivation journal atomically before returning; their keys remain recoverable across relaunch.
public struct PreparedTransfer {
    public let memo: TransferMemo
    public let handoffCommit: any CoinageHandoffCommit

    public init(memo: TransferMemo, handoffCommit: any CoinageHandoffCommit) {
        self.memo = memo
        self.handoffCommit = handoffCommit
    }
}
