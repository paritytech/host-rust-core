import Foundation

/// What the ladder decided for one entry this pass.
public enum RuleOutcome: Sendable, Equatable {
    /// Write this verdict (a compare-and-set against the status the rules were evaluated from).
    case decided(Verdict)
    /// A read this entry depended on failed. It keeps its status and its locks, and is retried.
    case undecided
}

/// The rule table, evaluated in the spec's order — 0, 1, 2, 3, 4, 5, 6, 3b, 4b, 7 — first match
/// decides. Impure: Rule 7 searches block bodies through the pinned ``CoinageChainViewProtocol``.
public struct RuleEvaluator: Sendable {
    public init() {}

    public func evaluate(
        entry: CoinageTxEntry,
        dag: CoinageEntryDag,
        evidence: ChainEvidence,
        view: any CoinageChainViewProtocol
    ) async -> RuleOutcome {
        if let outcome = recordedInclusion(entry, evidence) {
            return outcome
        }

        // Rule 1 — execution is visible at the finalized head.
        if evidence.executed(entry, atFinalized: true) {
            return .decided(Verdict(status: .finalizedSuccess, successDetectedAt: entry.successDetectedAt))
        }

        // Rule 2 — execution is visible at the best head; recording the block lets Rule 0 decide later.
        if evidence.executed(entry, atFinalized: false) {
            return .decided(Verdict(status: .pendingSuccess, successDetectedAt: evidence.best))
        }

        let windowClosed = evidence.windowClosed(entry)

        // Rule 3 — an output nothing could have removed is definitely not there.
        if windowClosed,
           entry.outputs.contains(where: {
               noPotentialConsumers($0, dag, evidence) && evidence.absent($0.publicKey, atFinalized: true)
           }) {
            return .decided(Verdict(status: .failure, successDetectedAt: nil))
        }

        // Rule 4 — an input is definitely still there to be spent.
        if windowClosed, entry.inputs.contains(where: { available($0, evidence, atFinalized: true) }) {
            return .decided(Verdict(status: .failure, successDetectedAt: nil))
        }

        let provenOwnCoins = hasOnlyProvenOwnCoinInputs(entry, dag, evidence)

        // Rule 5 — every input is a proven-minted coin of ours and all are gone at finality.
        if provenOwnCoins, entry.inputs.allSatisfy({ evidence.absent($0.publicKey, atFinalized: true) }) {
            return .decided(Verdict(status: .finalizedSuccess, successDetectedAt: entry.successDetectedAt))
        }

        // Rule 6 — the same, except one input survives at finality, so consumption is only best-chain.
        if provenOwnCoins,
           entry.inputs.contains(where: { evidence.exists($0.publicKey, atFinalized: true) }),
           entry.inputs.allSatisfy({ evidence.absent($0.publicKey, atFinalized: false) }) {
            return .decided(Verdict(status: .pendingSuccess, successDetectedAt: evidence.best))
        }

        // Rules 3b / 4b — short-circuit an entry with no positive evidence so it does not run a body
        // search on every head; they stop at mortality, past which only the search can decide it.
        if !windowClosed,
           entry.outputs.contains(where: {
               noPotentialConsumers($0, dag, evidence) && evidence.absent($0.publicKey, atFinalized: false)
           }) {
            return .decided(Verdict(status: .pending, successDetectedAt: nil))
        }

        if !windowClosed, entry.inputs.contains(where: { available($0, evidence, atFinalized: false) }) {
            return .decided(Verdict(status: .pending, successDetectedAt: nil))
        }

        return await searchForTransaction(entry, evidence, view, windowClosed: windowClosed)
    }
}

// MARK: - Rule 0

private extension RuleEvaluator {
    /// Rule 0 — recorded inclusion. Returns `nil` when no success block is recorded, letting
    /// evaluation fall through to Rule 1.
    func recordedInclusion(_ entry: CoinageTxEntry, _ evidence: ChainEvidence) -> RuleOutcome? {
        guard let recorded = entry.successDetectedAt else { return nil }

        guard let stillCanonical = evidence.recordedBlockStillCanonical else {
            // The record's canonicality could not be read — keep it, decide nothing.
            return .undecided
        }

        if !stillCanonical {
            // The recorded block was reorged out. Re-derive from live evidence rather than trust it.
            if evidence.executed(entry, atFinalized: true) {
                return .decided(Verdict(status: .finalizedSuccess, successDetectedAt: evidence.finalized))
            }
            if evidence.executed(entry, atFinalized: false) {
                return .decided(Verdict(status: .pendingSuccess, successDetectedAt: evidence.best))
            }
            // Demote to PENDING and clear: leaving PENDING_SUCCESS with no evidence would keep the
            // outputs spendable for a full mortality window on the strength of a vanished block.
            return .decided(Verdict(status: .pending, successDetectedAt: nil))
        }

        return recorded.number <= evidence.finalized.number
            ? .decided(Verdict(status: .finalizedSuccess, successDetectedAt: recorded))
            : .decided(Verdict(status: .pendingSuccess, successDetectedAt: recorded))
    }
}

// MARK: - Rule 7

private extension RuleEvaluator {
    /// Nothing above could decide it, so look for the transaction itself. The window ends at the
    /// finalized head, so both terminal verdicts rest on a finalized fact.
    func searchForTransaction(
        _ entry: CoinageTxEntry,
        _ evidence: ChainEvidence,
        _ view: any CoinageChainViewProtocol,
        windowClosed: Bool
    ) async -> RuleOutcome {
        // No search window means there is nothing to read yet; decide by mortality.
        guard let window = searchWindow(entry, evidence) else {
            return .decided(Verdict(status: windowClosed ? .failure : .pending, successDetectedAt: nil))
        }

        switch await view.searchBodies(for: entry.txHash, in: window) {
        case let .foundSucceeded(block):
            return .decided(Verdict(status: .finalizedSuccess, successDetectedAt: block))
        case .foundFailed:
            return .decided(Verdict(status: .failure, successDetectedAt: nil))
        case .foundOutcomeUnreadable:
            return .decided(Verdict(status: .pending, successDetectedAt: nil))
        case .notFoundWindowComplete:
            return .decided(Verdict(status: windowClosed ? .failure : .pending, successDetectedAt: nil))
        case .incomplete:
            return .decided(Verdict(status: .pending, successDetectedAt: nil))
        }
    }

    func searchWindow(_ entry: CoinageTxEntry, _ evidence: ChainEvidence) -> ClosedRange<UInt32>? {
        let from = entry.checkpoint.number
        let to = min(entry.checkpoint.number + entry.mortality, evidence.finalized.number)
        return from <= to ? from ... to : nil
    }
}

// MARK: - Graph facts

private extension RuleEvaluator {
    /// The asset is still there to be spent.
    func available(_ input: CoinageTxInput, _ evidence: ChainEvidence, atFinalized: Bool) -> Bool {
        if input.isCoin {
            return evidence.exists(input.publicKey, atFinalized: atFinalized)
        }
        return evidence.exists(input.publicKey, atFinalized: atFinalized)
            && evidence.isNotUnloaded(input.publicKey, atFinalized: atFinalized)
    }

    /// Nothing could have removed this output, so its absence is meaningful.
    func noPotentialConsumers(_ output: OwnAsset, _ dag: CoinageEntryDag, _ evidence: ChainEvidence) -> Bool {
        if dag.isHandedOff(output.publicKey) { return false }
        if spent(output, dag, evidence) { return false }
        return dag.consumers(output.publicKey).allSatisfy { $0.status == .failure }
    }

    /// Once established this is permanent: a terminal status never changes, and a coin absent at a
    /// finalized head can never come back, because addresses are never reused.
    func spent(_ output: OwnAsset, _ dag: CoinageEntryDag, _ evidence: ChainEvidence) -> Bool {
        let consumedByFinalized = dag.consumers(output.publicKey).contains { $0.status == .finalizedSuccess }
        let provenConsumed = !output.isCoin && evidence.isUnloaded(output.publicKey, atFinalized: true)
        return consumedByFinalized || provenConsumed || spentByAbsence(output, dag, evidence)
    }

    /// Absence read as consumption, guarded by `isCoin` (a voucher's disappearance may be ring
    /// cleaning) and the minter's window having closed (a coin minted above a shallow finalized head
    /// reads absent simply because it does not exist there yet).
    func spentByAbsence(_ output: OwnAsset, _ dag: CoinageEntryDag, _ evidence: ChainEvidence) -> Bool {
        guard output.isCoin, let minter = dag.minter(output.publicKey) else { return false }
        return minter.status == .finalizedSuccess
            && evidence.absent(output.publicKey, atFinalized: true)
            && evidence.windowClosed(minter)
    }

    /// Every input is a coin we minted ourselves, proven to have existed and old enough that its
    /// absence now is meaningful — what resolves the ambiguity in Rules 5 and 6.
    func hasOnlyProvenOwnCoinInputs(
        _ entry: CoinageTxEntry,
        _ dag: CoinageEntryDag,
        _ evidence: ChainEvidence
    ) -> Bool {
        guard !entry.inputs.isEmpty else { return false }

        return entry.inputs.allSatisfy { input in
            guard input.isCoin, input.isOwn, !dag.isHandedOff(input.publicKey),
                  let minter = dag.minter(input.publicKey), minter.status == .finalizedSuccess
            else { return false }
            return evidence.windowClosed(minter)
        }
    }
}
