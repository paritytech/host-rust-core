import AsyncExtensions
import Foundation
@preconcurrency import ExtrinsicService
import ExtrinsicServiceExt
import SubstrateSdk
@preconcurrency import SDKLogger
import BackgroundExecution
import StructuredConcurrency
import os

/// Follows one already-built extrinsic from submission to a terminal outcome.
///
/// It proposes; it does not decide unilaterally. Every status change goes through the same
/// compare-and-set (`updateTxStatus`) the recovery pass uses, so the guards apply uniformly and a
/// status that moved underneath costs a proposal, nothing more.
///
/// It owns the entries it watches, and ownership is one-shot: released exactly once, never taken
/// back — not on a resubmission (the injected `submitter` owns that), not on anything. Release drops
/// the entry; `onRecovery` then fires only if the entry is still undecided, so the happy path never
/// schedules a pass to re-derive an answer that already exists.
final class CoinageTxTracker: Sendable {
    private let submitter: any ExtrinsicSubmitting
    private let store: any CoinageTxRepositoryProtocol
    private let chainFactory: any CoinageChainViewFactoryProtocol
    private let watched: CoinageTrackingTxSet
    private let backgroundExecutor: any BackgroundExecuting
    private let logger: SDKLoggerProtocol?

    /// Longest gap between status updates before the entry is handed back to the pass. About fifteen
    /// blocks against a mortality window, so it always fires while the extrinsic can still execute.
    private static let silenceTimeout: Duration = .seconds(30)

    /// The queue the submitter delivers status callbacks on.
    private static let submissionQueue = DispatchQueue(label: "com.novawallet.coinage.tx.submission")

    init(
        submitter: any ExtrinsicSubmitting,
        store: any CoinageTxRepositoryProtocol,
        chainFactory: any CoinageChainViewFactoryProtocol,
        watched: CoinageTrackingTxSet,
        backgroundExecutor: any BackgroundExecuting,
        logger: SDKLoggerProtocol?
    ) {
        self.submitter = submitter
        self.store = store
        self.chainFactory = chainFactory
        self.watched = watched
        self.backgroundExecutor = backgroundExecutor
        self.logger = logger
    }

    /// Submits `model` and tracks it to a terminal outcome in a detached task, holding a
    /// background-task assertion so tracking survives the app being folded. Fire-and-forget: the
    /// caller has already registered the entry (with its `txHash`) and taken ownership.
    ///
    /// On release, `onRecovery` runs only when the entry is still live — a watch that wrote a
    /// terminal verdict has already decided it, so no pass is scheduled to re-derive it.
    func trackTransaction(
        _ model: ExtrinsicBuiltModel,
        transactionId: CoinageTxId,
        onRecovery: @escaping @Sendable () -> Void
    ) {
        Task { [self] in
            await runFollow(model: model, transactionId: transactionId)

            guard watched.release(transactionId) else { return }

            if await needsRecovery(transactionId) {
                onRecovery()
            }
        }
    }
}

// MARK: - Follow

private extension CoinageTxTracker {
    /// One tracked event: a chain status, or a terminal submission failure the submitter reported
    /// after it declined to resubmit.
    enum TrackEvent {
        case status(ExtrinsicStatusUpdate)
        case submissionFailed(Error)
    }

    func runFollow(model: ExtrinsicBuiltModel, transactionId: CoinageTxId) async {
        do {
            try await backgroundExecutor.execute {
                await self.follow(model: model, transactionId: transactionId)
            }
        } catch {
            logger?.error("Submission watch failed for \(transactionId): \(error)")
        }
    }

    /// Recovery is for entries nobody has decided. Keyed on what the entry now says rather than on
    /// why the watch ended: an unreadable finalized outcome or a refused proposal both leave it live
    /// and genuinely needing the pass. Unreadable status counts as needing recovery.
    func needsRecovery(_ id: CoinageTxId) async -> Bool {
        guard let status = try? await store.getStatus(id) else { return true }
        return status.isLive
    }

    func follow(model: ExtrinsicBuiltModel, transactionId: CoinageTxId) async {
        guard let view = try? await chainFactory.pin() else {
            logger?.debug("Couldn't pin view for submission watch")
            return
        }

        // A buffered channel the submitter's callbacks feed. `send`/`finish` are non-blocking;
        // `next()` is cancellation-safe, so a timed-out receive drops no buffered element.
        let events = AsyncBufferedChannel<TrackEvent>()
        let subscriptionId = OSAllocatedUnfairLock<UInt16?>(initialState: nil)

        logger?.debug("Submitting transaction: \(transactionId)")

        submitter.submitAndSubscribe(
            builtExtrinsic: model,
            runningIn: Self.submissionQueue,
            subscriptionIdClosure: { id in
                subscriptionId.withLock { $0 = id }
                return true
            },
            notificationClosure: { result in
                switch result {
                case let .success(status):
                    events.send(.status(status.statusUpdate))
                case let .failure(error):
                    events.send(.submissionFailed(error))
                    events.finish()
                }
            }
        )

        // Receive each event under a per-element silence timeout; a timeout or the channel finishing
        // ends following and hands the entry back to the pass.
        let iterator = events.makeAsyncIterator()
        while true {
            let received = try? await withTimeout(Self.silenceTimeout) { await iterator.next() }
            guard let event = received.flatMap({ $0 }) else {
                logger?.warning("Transaction tracking timeout: \(transactionId)")
                break
            }

            logger?.debug("New event is proposed: \(transactionId)")

            let isComplete = await handle(event, transactionId: transactionId, using: view)

            if isComplete {
                logger?.debug("Terminal event for: \(transactionId)")
                break
            }
        }
        events.finish()

        // Stop the underlying watch if it is still open — a silence timeout ended following before
        // the submitter reached a terminal. A no-op if the watch already finished.
        if let id = subscriptionId.withLock({ $0 }) {
            submitter.cancelExtrinsicWatch(for: id)
        }
    }

    /// Maps one event onto a proposed verdict. Returns true when the entry is done being watched.
    func handle(
        _ event: TrackEvent,
        transactionId id: CoinageTxId,
        using view: CoinageChainViewProtocol
    ) async -> Bool {
        logger?.debug("Handling event: \(event) transaction: \(id)")

        switch event {
        case let .submissionFailed(error):
            return await handleSubmissionFailed(id, error: error)
        case let .status(update):
            return await handleStatus(update, transactionId: id, using: view)
        }
    }

    /// `.submissionFailed` covers two situations that differ only in whether the bytes reached the
    /// node. A `PreSubmissionValidationFailedError` means the submitter refused to broadcast — the
    /// extrinsic was never sent, so its inputs are untouched and a terminal `FAILURE` is justified
    /// immediately. Any other error is a submission/pool failure raised *after* the
    /// bytes may already have reached the node, where the extrinsic can still be included: a terminal
    /// `FAILURE` must rest on finalized evidence (spec — Justified failure), so we propose nothing and
    /// let the recovery pass decide from chain state.
    func handleSubmissionFailed(_ id: CoinageTxId, error: Error) async -> Bool {
        if error is PreSubmissionValidationFailedError {
            await propose(id, Verdict(status: .failure, successDetectedAt: nil))
        }
        return true
    }

    /// Maps a chain status update onto a proposed verdict. Returns true when watching is done.
    func handleStatus(
        _ update: ExtrinsicStatusUpdate,
        transactionId id: CoinageTxId,
        using view: CoinageChainViewProtocol
    ) async -> Bool {
        guard case let .onChain(remote) = update.extrinsicStatus else {
            // `.created` carries no chain information.
            return false
        }

        switch remote {
        case .future,
             .ready,
             .broadcast:
            // Pre-inclusion states carry no evidence; they must not lower an entry that already has
            // some (a resubmission can put one behind an inclusion).
            return false

        case let .inBlock(blockHash):
            await handleInBlock(blockHash: blockHash, entryId: id, using: view)
            return false

        case let .retracted(blockHash):
            await clearRecordIfItNames(id, blockHash: blockHash)
            return false

        case let .finalized(blockHash):
            await handleFinalized(blockHash: blockHash, entryId: id, using: view)
            return true

        case .dropped,
             .invalid,
             .unsurped,
             .finalityTimeout,
             .other:
            // Recovery has already had its chance to resubmit by the time these surface; the pass
            // decides from state.
            return true
        }
    }
}

// MARK: - Verdicts

private extension CoinageTxTracker {
    /// Not finalized, so a terminal verdict must not rest on it: success is recorded as
    /// `pendingSuccess` for the pass to finalize; a failure here proposes nothing.
    func handleInBlock(
        blockHash: String,
        entryId: CoinageTxId,
        using view: CoinageChainViewProtocol
    ) async {
        guard let block = await blockOf(blockHash, using: view) else {
            return
        }

        let outcome = await dispatchOutcome(blockHash: blockHash, entryId: entryId, using: view)

        switch outcome {
        case .present(true):
            await propose(entryId, Verdict(status: .pendingSuccess, successDetectedAt: block))
        case .present(false),
             .absent,
             .failedRead:
            break
        }
    }

    func handleFinalized(blockHash: String, entryId: CoinageTxId, using view: CoinageChainViewProtocol) async {
        switch await dispatchOutcome(blockHash: blockHash, entryId: entryId, using: view) {
        case .present(true):
            let block = await blockOf(blockHash, using: view)
            await propose(entryId, Verdict(status: .finalizedSuccess, successDetectedAt: block))
        case .present(false):
            await propose(entryId, Verdict(status: .failure, successDetectedAt: nil))
        case .absent,
             .failedRead:
            // Unreadable outcome: record nothing and let the pass decide from state.
            break
        }
    }

    /// The record is cleared only when it names the retracted block; the status is lowered with it,
    /// because leaving `pendingSuccess` on a block that no longer exists would keep the outputs
    /// spendable for a whole mortality window on nothing.
    func clearRecordIfItNames(_ id: CoinageTxId, blockHash: String) async {
        guard let hash = try? Data(hexString: blockHash),
              let entry = try? await store.getEntry(id: id),
              entry.successDetectedAt?.hash == hash
        else { return }

        await propose(id, Verdict(status: .pending, successDetectedAt: nil))
    }

    /// A terminal entry is never rewritten, so a late event cannot un-fail a failed transaction; the
    /// compare-and-set then covers a status that moved since it was read.
    func propose(_ id: CoinageTxId, _ verdict: Verdict) async {
        guard let observed = try? await store.getStatus(id), observed.isLive else { return }

        do {
            logger?.debug("Proposing \(verdict.status) for id: \(id)")
            try await store.updateTxStatus(for: id, expectedCurrentStatus: observed, verdict: verdict)
        } catch {
            logger?.error("Proposal write failed for \(id) to \(verdict.status): \(error)")
        }
    }

    func dispatchOutcome(
        blockHash: String,
        entryId: CoinageTxId,
        using view: CoinageChainViewProtocol
    ) async -> ReadResult<Bool> {
        guard
            let entry = try? await store.getEntry(id: entryId),
            let block = await blockOf(blockHash, using: view)
        else { return .failedRead }

        return await view.dispatchOutcome(txHash: entry.txHash, at: block)
    }

    func blockOf(_ blockHash: String, using view: CoinageChainViewProtocol) async -> BlockRef? {
        guard let hash = try? Data(hexString: blockHash) else { return nil }
        return await view.blockRef(forHash: hash).value
    }
}
