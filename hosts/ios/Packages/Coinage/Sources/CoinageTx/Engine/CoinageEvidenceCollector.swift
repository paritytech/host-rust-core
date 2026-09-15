import Foundation

/// Turns one entry plus a pinned view into the ``ChainEvidence`` the rules read, built on the chain
/// view's existing three-valued asset reads: a present voucher already carries its unload state,
/// which is the alias signal the rules need.
public struct CoinageEvidenceCollector: Sendable {
    public init() {}

    public func collect(entry: CoinageTxEntry, view: any CoinageChainViewProtocol) async -> ChainEvidence {
        let finalized = view.finalizedHead
        let best = view.bestHead

        async let inputsAtFinalized = view.readInputs(entry.inputs, at: finalized)
        async let inputsAtBest = view.readInputs(entry.inputs, at: best)
        async let outputsAtFinalized = view.readOutputs(entry.outputs, at: finalized)
        async let outputsAtBest = view.readOutputs(entry.outputs, at: best)

        let recordedStillCanonical = await recordedBlockStillCanonical(entry, view)

        let inputKeys = entry.inputs.map(\.publicKey)
        let outputKeys = entry.outputs.map(\.publicKey)

        let (presenceF, aliasF) = await maps(
            inputKeys: inputKeys, inputReads: inputsAtFinalized,
            outputKeys: outputKeys, outputReads: outputsAtFinalized
        )
        let (presenceB, aliasB) = await maps(
            inputKeys: inputKeys, inputReads: inputsAtBest,
            outputKeys: outputKeys, outputReads: outputsAtBest
        )

        return ChainEvidence(
            finalized: finalized,
            best: best,
            presenceAtFinalized: presenceF,
            presenceAtBest: presenceB,
            aliasAtFinalized: aliasF,
            aliasAtBest: aliasB,
            recordedBlockStillCanonical: recordedStillCanonical
        )
    }
}

private extension CoinageEvidenceCollector {
    func maps(
        inputKeys: [PublicKey],
        inputReads: [ReadResult<AssetPresence>],
        outputKeys: [PublicKey],
        outputReads: [ReadResult<AssetPresence>]
    ) -> (presence: [PublicKey: ChainPresence], alias: [PublicKey: AliasRead]) {
        var presence: [PublicKey: ChainPresence] = [:]
        var alias: [PublicKey: AliasRead] = [:]
        for (key, read) in Array(zip(inputKeys, inputReads)) + Array(zip(outputKeys, outputReads)) {
            presence[key] = Self.presence(read)
            alias[key] = Self.alias(read)
        }
        return (presence, alias)
    }

    /// `nil` when no success block is recorded; otherwise whether the canonical hash at that number
    /// still matches the recorded one. `nil` again when the read failed (the rule stays undecided).
    func recordedBlockStillCanonical(
        _ entry: CoinageTxEntry,
        _ view: any CoinageChainViewProtocol
    ) async -> Bool? {
        guard let recorded = entry.successDetectedAt else { return nil }

        switch await view.blockHash(at: recorded.number) {
        case let .present(hash): return hash == recorded.hash
        case .absent: return false
        case .failedRead: return nil
        }
    }

    static func presence(_ read: ReadResult<AssetPresence>) -> ChainPresence {
        switch read {
        case .present: .present
        case .absent: .absent
        case .failedRead: .unknown
        }
    }

    static func alias(_ read: ReadResult<AssetPresence>) -> AliasRead {
        switch read {
        case let .present(presence):
            switch presence.alias {
            case .unloaded: .unloaded
            case .notUnloaded: .notUnloaded
            case .unknown: .unknown
            }
        case .absent,
             .failedRead: .unknown
        }
    }
}
