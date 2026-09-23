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
        var task: Task<Void, Never>?
    }

    private let builder: any PocketWorkerBuilding
    private let pocket: PocketFacade
    private let logger: LoggerProtocol

    private var running: [ProductId: Running] = [:]
    private let executionSubject = AsyncCurrentValueSubject<[ProductId: TrUAPIProductExecutionProtocol]>([:])

    init(builder: any PocketWorkerBuilding, pocket: PocketFacade = .shared, logger: LoggerProtocol = Logger.shared) {
        self.builder = builder
        self.pocket = pocket
        self.logger = logger

        Task { await self.followCollection() }
    }

    /// A card added or removed anywhere changes what every running worker is
    /// told it holds, so each bridge re-reads its own slice and tells the core
    /// only if that slice moved.
    private func followCollection() async {
        do {
            for try await _ in pocket.changes() {
                for held in running.values {
                    await held.pocket.refresh()
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
        guard running[productId] == nil else { return }

        guard let store = await pocket.store() else {
            logger.error("[pocket] no collection to serve \(productId)'s worker from")
            return
        }

        let bridge = ProductPocketHostBridge(productId: productId, collection: store)

        do {
            let runtime = try await builder.makeRuntime(productId: productId, pocket: bridge)
            running[productId] = Running(runtime: runtime, pocket: bridge)

            try await runtime.start()
            bridge.start { [weak self] cards in
                self?.publishCards(cards, of: productId)
            }
            await bridge.refresh()

            executionSubject.send(executionSubject.value.merging([productId: runtime.execution]) { _, new in new })
        } catch {
            logger.error("[pocket] \(productId)'s worker failed to start: \(error)")
            // A failed boot left in the map would swallow every later start,
            // while the core keeps counting the reference the card holds and
            // so never sends another stop to clear it.
            await stop(productId)
        }
    }

    private func stop(_ productId: ProductId) async {
        guard let held = running.removeValue(forKey: productId) else { return }

        held.pocket.stop()
        var executions = executionSubject.value
        executions[productId] = nil
        executionSubject.send(executions)

        await held.runtime.dispose()
    }

    private nonisolated func publishCards(_ cards: [PocketCard], of productId: ProductId) {
        executionSubject.value[productId]?.notifyPocketCardsChanged(cards: cards)
    }
}
