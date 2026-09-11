import Foundation

/// The finalized and best heads a single recovery pass evaluates against.
///
/// Both heads are pinned once, from one connection, before the pass reads anything, so every
/// rule in the pass sees the same chain. Freshness comes from re-pinning a new view each pass,
/// not from tracking the connection: a read is addressed by block hash, so a swapped connection
/// yields a failed read rather than a wrong verdict.
public struct ChainView: Sendable, Equatable {
    public let finalized: BlockRef
    public let best: BlockRef

    public init(finalized: BlockRef, best: BlockRef) {
        self.finalized = finalized
        self.best = best
    }
}
