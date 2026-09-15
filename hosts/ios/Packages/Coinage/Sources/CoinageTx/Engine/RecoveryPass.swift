import Foundation
import SDKLogger

/// One bounded sweep over the live entry set.
///
/// Builds a ``CoinageEntryDag`` once, evaluates every live entry that submission tracking does not
/// own, then propagates finalized success along the graph. Never awaited by startup: a single
/// unresolvable entry must not hold the app for a mortality window.
///
/// Rules run entirely outside any database transaction — the body search can span a whole mortality
/// window — and the write is a compare-and-set against the status the rules were evaluated from, so
/// a status that moved underneath costs that entry a pass and nothing else.
actor RecoveryPass {
    private let store: any CoinageTxRepositoryProtocol
    private let chainFactory: any CoinageChainViewFactoryProtocol
    private let watched: CoinageTrackingTxSet
    private let evaluator = RuleEvaluator()
    private let collector = CoinageEvidenceCollector()
    private let logger: SDKLoggerProtocol?

    private var isRunning = false
    private var rerunRequested = false

    private static let maxCoalescedPasses = 2

    init(
        store: any CoinageTxRepositoryProtocol,
        chainFactory: any CoinageChainViewFactoryProtocol,
        watched: CoinageTrackingTxSet,
        logger: SDKLoggerProtocol?
    ) {
        self.store = store
        self.chainFactory = chainFactory
        self.watched = watched
        self.logger = logger
    }

    /// Runs one pass. At most one runs at a time; a request arriving during a pass causes one
    /// additional pass afterwards rather than being dropped, capped to prevent unbounded spinning.
    func run() async {
        guard !isRunning else {
            rerunRequested = true
            return
        }
        isRunning = true
        defer { isRunning = false }

        var iterations = 0
        repeat {
            rerunRequested = false
            do {
                try await performPass()
            } catch {
                logger?.error("Recovery pass failed: \(error)")
            }
            iterations += 1
        } while rerunRequested && iterations < Self.maxCoalescedPasses
    }
}

// MARK: - Pass

private extension RecoveryPass {
    func performPass() async throws {
        logger?.debug("Starting recovery pass")

        let dag = try await loadDag()
        let decidable = dag.entries.filter { $0.status.isLive && !watched.isWatched($0.id) }

        // Nothing to decide means nothing to propagate — propagation walks the same set — so the
        // pass ends before pinning a view, which would be a chain read with nothing to read it for.
        guard !decidable.isEmpty else { return }

        logger?.debug("Found needs to be decided: \(decidable.count)")

        let view = try await chainFactory.pin()

        logger?.debug("Pinning view at finalized: \(view.finalizedHead.number) \(view.finalizedHead.hash.toHex())")
        logger?.debug("Pinning view at best: \(view.bestHead.number) \(view.bestHead.hash.toHex())")

        var written = 0
        for entry in decidable {
            let evidence = await collector.collect(entry: entry, view: view)
            if await decide(entry, dag: dag, evidence: evidence, view: view) {
                written += 1
            }
        }

        logger?.debug("Updated \(written) entries")

        // Propagation reads statuses, so it needs the ones this pass just wrote: an entry promoted
        // above is exactly the successor that lets its predecessor be promoted too.
        let propagationDag = written > 0 ? try await loadDag() : dag

        logger?.debug("Propagating...")

        try await propagate(propagationDag)

        logger?.debug("Propagated")
    }

    func loadDag() async throws -> CoinageEntryDag {
        async let entries = store.getAllEntries()
        async let handedOff = store.getHandoffKeys()
        return try await CoinageEntryDag(entries: entries, handedOff: handedOff)
    }

    /// Returns whether it wrote.
    func decide(
        _ entry: CoinageTxEntry,
        dag: CoinageEntryDag,
        evidence: ChainEvidence,
        view: any CoinageChainViewProtocol
    ) async -> Bool {
        switch await evaluator.evaluate(entry: entry, dag: dag, evidence: evidence, view: view) {
        case .undecided:
            // A failed read: keep the status and the locks, retry next pass.
            false
        case let .decided(verdict):
            await write(entry, verdict)
        }
    }

    /// A successor that consumed our output proves the output existed, and an output exists only if
    /// the entry minting it executed — positive evidence that arrives before the entry's own window
    /// closes. The opposite direction needs no rule: a failed entry's outputs never existed, so its
    /// successors are decided by their own mortality, in parallel.
    func propagate(_ dag: CoinageEntryDag) async throws {
        for entry in dag.entries where entry.status.isLive && !watched.isWatched(entry.id) {
            guard dag.successors(entry).contains(where: { $0.status == .finalizedSuccess }) else {
                continue
            }
            _ = await write(entry, Verdict(status: .finalizedSuccess, successDetectedAt: entry.successDetectedAt))
        }
    }

    /// Compare-and-set against the status the verdict was formed from. Skips a write that would
    /// change nothing.
    func write(_ entry: CoinageTxEntry, _ verdict: Verdict) async -> Bool {
        guard verdict.status != entry.status || verdict.successDetectedAt != entry.successDetectedAt else {
            return false
        }
        do {
            logger?.debug("Updating status: \(verdict.status) transaction: \(entry.id)")
            return try await store.updateTxStatus(
                for: entry.id,
                expectedCurrentStatus: entry.status,
                verdict: verdict
            )
        } catch {
            logger?.error("Verdict write failed for \(entry.id): \(error)")
            return false
        }
    }
}
