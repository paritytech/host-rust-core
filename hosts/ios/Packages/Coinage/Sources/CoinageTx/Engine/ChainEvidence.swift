import Foundation

/// A three-valued on-chain read. `unknown` is a read that did not answer — a transport error, a key
/// missing from a batched response, an undecodable value — or an asset whose kind cannot establish
/// the fact at all. It is never a verdict: a rule that needs `present`/`absent` simply does not match.
public enum ChainPresence: Sendable, Equatable {
    case present
    case absent
    case unknown
}

/// What a voucher's recycler alias said, with the same three-valued reading as ``ChainPresence``.
public enum AliasRead: Sendable, Equatable {
    case unloaded
    case notUnloaded
    case unknown
}

/// Everything the rules may read about the chain, gathered for one entry against one pinned view.
///
/// Keyed by each asset's stable identifier; every asset of the entry appears in every map — a read
/// that did not establish a fact is ``ChainPresence/unknown`` rather than a missing key, so "we did
/// not find out" is a value you can see rather than an absence you infer. Every predicate over these
/// is positive-form and paired with its opposite, so an unknown read satisfies neither side.
public struct ChainEvidence: Sendable {
    public let finalized: BlockRef
    public let best: BlockRef
    public let presenceAtFinalized: [PublicKey: ChainPresence]
    public let presenceAtBest: [PublicKey: ChainPresence]
    public let aliasAtFinalized: [PublicKey: AliasRead]
    public let aliasAtBest: [PublicKey: AliasRead]
    /// Whether the block this entry recorded success at is still canonical. `nil` when the read
    /// failed; absent from the model when no success block is recorded.
    public let recordedBlockStillCanonical: Bool?

    public init(
        finalized: BlockRef,
        best: BlockRef,
        presenceAtFinalized: [PublicKey: ChainPresence],
        presenceAtBest: [PublicKey: ChainPresence],
        aliasAtFinalized: [PublicKey: AliasRead],
        aliasAtBest: [PublicKey: AliasRead],
        recordedBlockStillCanonical: Bool?
    ) {
        self.finalized = finalized
        self.best = best
        self.presenceAtFinalized = presenceAtFinalized
        self.presenceAtBest = presenceAtBest
        self.aliasAtFinalized = aliasAtFinalized
        self.aliasAtBest = aliasAtBest
        self.recordedBlockStillCanonical = recordedBlockStillCanonical
    }
}

// MARK: - Predicates

/// Positive-form, key-based reads over the evidence, each paired with its opposite so an `unknown`
/// read satisfies neither side.
public extension ChainEvidence {
    func exists(_ key: PublicKey, atFinalized: Bool) -> Bool {
        presence(atFinalized)[key] == .present
    }

    func absent(_ key: PublicKey, atFinalized: Bool) -> Bool {
        presence(atFinalized)[key] == .absent
    }

    func isUnloaded(_ key: PublicKey, atFinalized: Bool) -> Bool {
        alias(atFinalized)[key] == .unloaded
    }

    func isNotUnloaded(_ key: PublicKey, atFinalized: Bool) -> Bool {
        alias(atFinalized)[key] == .notUnloaded
    }

    /// This entry can no longer execute, so anything it did has already happened below finality.
    func windowClosed(_ entry: CoinageTxEntry) -> Bool {
        UInt64(finalized.number) > UInt64(entry.checkpoint.number) + UInt64(entry.mortality)
    }

    /// Execution is visible: an output appeared, or a voucher input was proven unloaded. A coin's
    /// absence is never proof here — `CoinsByOwner` being empty is necessary but not sufficient.
    func executed(_ entry: CoinageTxEntry, atFinalized: Bool) -> Bool {
        entry.outputs.contains { exists($0.publicKey, atFinalized: atFinalized) }
            || entry.inputs.contains { !$0.isCoin && isUnloaded($0.publicKey, atFinalized: atFinalized) }
    }

    private func presence(_ atFinalized: Bool) -> [PublicKey: ChainPresence] {
        atFinalized ? presenceAtFinalized : presenceAtBest
    }

    private func alias(_ atFinalized: Bool) -> [PublicKey: AliasRead] {
        atFinalized ? aliasAtFinalized : aliasAtBest
    }
}
