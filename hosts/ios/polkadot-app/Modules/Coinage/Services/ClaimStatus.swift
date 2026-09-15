import BigInt
import Foundation
import SubstrateSdk

/// Rich lifecycle status for UI publishing via ``ClaimStatusPublishing``.
///
/// An ephemeral in-memory projection of the durability-derived transfer status — carries associated
/// data and supports fine-grained UI states. Nothing here is persisted.
public enum ClaimStatus: Sendable, Equatable {
    /// Waiting for coins to appear on-chain (subscription active).
    case detecting
    /// Claim extrinsic submitted, waiting for confirmation.
    case claiming
    /// Some coins received; the rest are being retried. Carries the amount claimed so far.
    case partiallyClaimed(claimed: Balance)
    /// Outgoing transfer intermediate: coins appeared on-chain, awaiting recipient claim. Carries no
    /// amount by design, the mid-flight sender bubble shows the full total, and only a
    /// finished claim can be short (see ``finished``).
    case sent
    /// Operation completed. Carries the actual claimed amount in planks.
    case finished(claimedAmount: Balance)
    /// Operation failed (timeout, RPC error, etc.).
    case error
}

/// Broadcasts claim/send status updates to in-memory observers (e.g. chat extensions).
public protocol ClaimStatusPublishing: Sendable {
    func updateStatus(_ status: ClaimStatus, forMessageId messageId: String) async
}
