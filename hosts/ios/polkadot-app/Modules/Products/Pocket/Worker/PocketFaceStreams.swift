import Foundation
import Products
import TrUAPIHost

/// The live side of a face: the product's render stream, and the actions going
/// back to it.
protocol PocketFaceStreaming: Sendable {
    /// Faces the product draws for `key`, each replacing the last. Iterating
    /// holds one worker reference for the card's product, and the stream stays
    /// silent while the worker is unavailable.
    func renderFaces(for key: PocketCardKey) -> AsyncThrowingStream<RendererNode, Error>

    func send(action: String, payload: Data, for key: PocketCardKey)
}

/// Faces over the core: one worker reference is taken for as long as the card
/// is on screen, the product's worker is awaited, and `render` is opened on the
/// card's own context.
///
/// A render stream that ends or fails leaves the last face on screen and is
/// opened again; a worker that restarts gets a fresh stream.
struct TrUAPIPocketFaceStreams: PocketFaceStreaming {
    private enum Retry {
        /// A worker that has just booted is not yet listening, so the first
        /// renders are expected to be refused.
        static let connectAttempts = 40
        static let connectDelay = Duration.milliseconds(250)

        /// Doubling from a second up to half a minute: a worker that is simply
        /// slow is picked up at once, and a broken one is not asked on a loop
        /// for as long as its card is on screen.
        static let reopenDelay = Duration.seconds(1)
        static let maxReopenDelay = Duration.seconds(30)
        static let maxBackoffDoublings = 5
    }

    private let runtime: @Sendable () throws -> TrUAPIHostRuntime
    private let workers: any PocketWorkerSupervising
    private let publishedCards: any PublishedPocketCardsResolving
    private let logger: LoggerProtocol

    init(
        runtime: @escaping @Sendable () throws -> TrUAPIHostRuntime,
        workers: any PocketWorkerSupervising,
        publishedCards: any PublishedPocketCardsResolving,
        logger: LoggerProtocol = Logger.shared
    ) {
        self.runtime = runtime
        self.workers = workers
        self.publishedCards = publishedCards
        self.logger = logger
    }

    func renderFaces(for key: PocketCardKey) -> AsyncThrowingStream<RendererNode, Error> {
        AsyncThrowingStream { continuation in
            let task = Task { await stream(key, into: continuation) }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    func send(action: String, payload: Data, for key: PocketCardKey) {
        guard let execution = workers.currentExecution(of: key.productId) else { return }

        do {
            try execution.publishRendererAction(
                HostRendererActionSubscribeItem(
                    context: .pocketCard(cardId: key.cardId.value),
                    actionId: action,
                    payload: payload
                )
            )
        } catch {
            logger.error("[pocket] action '\(action)' for \(key.cardId.value) was not delivered: \(error)")
        }
    }
}

private extension TrUAPIPocketFaceStreams {
    func stream(_ key: PocketCardKey, into continuation: AsyncThrowingStream<RendererNode, Error>.Continuation) async {
        // A card whose product publishes no Pocket worker has nothing to
        // stream, and the reference below is what starts one: taking it
        // regardless would boot a worker for the personhood product every time
        // the default tab is opened.
        guard await isStreamable(key) else {
            continuation.finish()
            return
        }

        guard let runtime = try? runtime() else {
            logger.error("[pocket] no runtime; \(key.cardId.value) keeps the face it has")
            continuation.finish()
            return
        }

        runtime.acquireWorker(productId: key.productId)
        defer { runtime.releaseWorker(productId: key.productId) }

        await followExecutions(of: key, into: continuation)
        continuation.finish()
    }

    /// One render per execution the supervisor publishes: a worker that
    /// restarts is picked up as a new execution, and its stream replaces the
    /// one before it.
    func followExecutions(
        of key: PocketCardKey,
        into continuation: AsyncThrowingStream<RendererNode, Error>.Continuation
    ) async {
        var opened: Task<Void, Never>?
        defer { opened?.cancel() }

        do {
            for try await execution in workers.executions(of: key.productId) {
                opened?.cancel()
                guard let execution else { continue }

                opened = Task { await reopening(execution, for: key, into: continuation) }
            }
        } catch {
            logger.error("[pocket] the worker stream for \(key.cardId.value) ended: \(error)")
        }
    }

    /// A render that fails is opened again on the same worker. Ending here
    /// instead would leave the card static for the worker's whole life: a new
    /// render is only opened when a different execution is published, and a
    /// stop publishes none.
    func reopening(
        _ execution: TrUAPIProductExecutionProtocol,
        for key: PocketCardKey,
        into continuation: AsyncThrowingStream<RendererNode, Error>.Continuation
    ) async {
        var attempt = 0
        while !Task.isCancelled {
            do {
                try await drain(execution, for: key, into: continuation)
                attempt = 0
            } catch is CancellationError {
                return
            } catch {
                logger.warning("[pocket] the face stream for \(key.cardId.value) ended, reopening: \(error)")
            }

            try? await Task.sleep(for: reopenDelay(after: attempt))
            attempt += 1
        }
    }

    func drain(
        _ execution: TrUAPIProductExecutionProtocol,
        for key: PocketCardKey,
        into continuation: AsyncThrowingStream<RendererNode, Error>.Continuation
    ) async throws {
        for try await face in try await connect(execution, for: key) {
            try Task.checkCancellation()
            continuation.yield(face)
        }
    }

    /// The worker registers its handler after it connects, so the first renders
    /// are refused rather than answered; they are retried at a fixed short
    /// interval instead of backing off, because the wait is a boot, not a fault.
    func connect(
        _ execution: TrUAPIProductExecutionProtocol,
        for key: PocketCardKey
    ) async throws -> AsyncThrowingStream<RendererNode, Error> {
        let request = ProductRendererRenderRequest(context: .pocketCard(cardId: key.cardId.value), payload: Data())

        for _ in 0 ..< Retry.connectAttempts {
            try Task.checkCancellation()
            if let stream = try? execution.render(request) { return stream }
            try await Task.sleep(for: Retry.connectDelay)
        }

        return try execution.render(request)
    }

    func reopenDelay(after attempt: Int) -> Duration {
        let doublings = min(attempt, Retry.maxBackoffDoublings)

        return min(Retry.reopenDelay * (1 << doublings), Retry.maxReopenDelay)
    }

    func isStreamable(_ key: PocketCardKey) async -> Bool {
        do {
            _ = try await publishedCards.find(productId: key.productId, cardId: key.cardId)
            return true
        } catch {
            logger.debug("[pocket] \(key.cardId.value) has no published card; it keeps the face it has")
            return false
        }
    }
}
