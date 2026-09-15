import Foundation

/// A block identified by number and hash together, so the two can never drift apart.
///
/// Used for an entry's checkpoint and for the block where its execution was first
/// observed.
public struct BlockRef: Hashable, Sendable {
    public let number: UInt32
    public let hash: Data

    public init(number: UInt32, hash: Data) {
        self.number = number
        self.hash = hash
    }
}
