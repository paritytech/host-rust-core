import Foundation
import AsyncExtensions
import Products
import TrUAPIHost

/// Runs product workers for as long as the core's reference ledger wants them.
///
/// The core counts the references its modality holders take — a card on screen
/// takes one — and reports only the transitions across zero. A `.start` boots
/// the product's worker behind a Worker execution; a `.stop` tears it down.
protocol PocketWorkerSupervising: AnyObject, Sendable {
    /// May arrive on any thread, including re-entrantly from inside
    /// `acquireWorker`, so the work is handed off rather than done here.
    func demandChanged(productId: ProductId, transition: WorkerTransition)

    /// The product's worker execution while it runs, and nil while it does not.
    func executions(of productId: ProductId) -> AnyAsyncSequence<TrUAPIProductExecutionProtocol?>

    func currentExecution(of productId: ProductId) -> TrUAPIProductExecutionProtocol?

    /// Stops every worker this supervisor is running and gives up following the
    /// collection. Called when the session it was built for ends.
    func shutdown() async
}

/// Builds the pieces one product's worker needs: its archive, its execution and
/// the engine its script runs in.
protocol PocketWorkerBuilding: Sendable {
    func makeRuntime(productId: ProductId, pocket: ProductPocketHostBridge) async throws -> PocketWorkerRuntime
}

actor PocketWorkerSupervisor: PocketWorkerSupervising {
    private struct Running {
        let runtime: PocketWorkerRuntime
        let pocket: ProductPocketHostBridge
    }

    /// What the supervisor holds for one product. A boot claims the product
    /// before its first await: actors are reentrant, so two starts that overlap
    /// would otherwise both pass the guard and build a worker, and a stop that
    /// landed mid-boot would find nothing to remove and leave the worker
    /// running with no way back to it.
    private enum Held {
        case booting
        case running(Running)
    }

    private let builder: any PocketWorkerBuilding
    private let pocket: PocketFacade
    private let logger: LoggerProtocol

    private var held: [ProductId: Held] = [:]
    private var following: Task<Void, Never>?
    private let executionSubject = AsyncCurrentValueSubject<[ProductId: TrUAPIProductExecutionProtocol]>([:])

    init(builder: any PocketWorkerBuilding, pocket: PocketFacade = .shared, logger: LoggerProtocol = Logger.shared) {
        self.builder = builder
        self.pocket = pocket
        self.logger = logger

        following = Task { await self.followCollection() }
    }

    /// The workers outlive every screen, so nothing else ever tears them down:
    /// a supervisor dropped without this leaves a headless web view and its
    /// chain connections running for the rest of the process.
    func shutdown() async {
        following?.cancel()
        following = nil

        // Over a snapshot: `stop` takes each product out of the map it would
        // otherwise be iterating, and awaits inside it let more land.
        for productId in Array(held.keys) {
            await stop(productId)
        }
    }

    /// A card added or removed anywhere changes what every running worker is
    /// told it holds, so each bridge re-reads its own slice and tells the core
    /// only if that slice moved.
    private func followCollection() async {
        do {
            for try await _ in pocket.changes() {
                for case let .running(worker) in held.values {
                    await worker.pocket.refresh()
                }
            }
        } catch {
            logger.error("[pocket] the collection change stream ended: \(error)")
        }
    }

    nonisolated func demandChanged(productId: ProductId, transition: WorkerTransition) {
        Task { await apply(transition, to: productId) }
    }

    nonisolated func executions(of productId: ProductId) -> AnyAsyncSequence<TrUAPIProductExecutionProtocol?> {
        executionSubject
            .map { $0[productId] }
            .eraseToAnyAsyncSequence()
    }

    nonisolated func currentExecution(of productId: ProductId) -> TrUAPIProductExecutionProtocol? {
        executionSubject.value[productId]
    }

    private func apply(_ transition: WorkerTransition, to productId: ProductId) async {
        switch transition {
        case .start: await start(productId)
        case .stop: await stop(productId)
        }
    }

    private func start(_ productId: ProductId) async {
        guard held[productId] == nil else { return }
        held[productId] = .booting

        guard let store = await pocket.store() else {
            held[productId] = nil
            logger.error("[pocket] no collection to serve \(productId)'s worker from")
            return
        }

        let bridge = ProductPocketHostBridge(productId: productId, collection: store)

        do {
            let runtime = try await builder.makeRuntime(productId: productId, pocket: bridge)
            guard case .booting = held[productId] else {
                await runtime.dispose()
                return
            }
            held[productId] = .running(Running(runtime: runtime, pocket: bridge))

            // The worker's card list is served from the bridge's snapshot, and
            // the script that subscribes to it comes up inside `start()`.
            await bridge.refresh()
            try await runtime.start()

            guard case let .running(worker) = held[productId], worker.runtime === runtime else { return }

            // Published before the bridge republishes, because republishing
            // reads the execution back out of this map.
            executionSubject.send(executionSubject.value.merging([productId: runtime.execution]) { _, new in new })
            bridge.start { [weak self] cards in
                self?.publishCards(cards, of: productId)
            }
        } catch {
            logger.error("[pocket] \(productId)'s worker failed to start: \(error)")
            // A failed boot left in the map would swallow every later start,
            // while the core keeps counting the reference the card holds and
            // so never sends another stop to clear it.
            await stop(productId)
        }
    }

    private func stop(_ productId: ProductId) async {
        // A boot in flight is cleared here and disposes what it built when it
        // finds its claim gone, so there is nothing else to tear down yet.
        guard case let .running(worker)? = held.removeValue(forKey: productId) else { return }

        worker.pocket.stop()
        var executions = executionSubject.value
        executions[productId] = nil
        executionSubject.send(executions)

        await worker.runtime.dispose()
    }

    private nonisolated func publishCards(_ cards: [PocketCard], of productId: ProductId) {
        executionSubject.value[productId]?.notifyPocketCardsChanged(cards: cards)
    }
}
