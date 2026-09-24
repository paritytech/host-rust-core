import Foundation
import AsyncExtensions
import Products
import Testing
import TrUAPIHost
@testable import polkadot_app

/// The render stream is what makes a card live, and iterating it is what holds
/// the worker reference the core counts. Both ways it goes wrong are invisible
/// on screen: a stream nothing reopens, and a stream torn down for a worker
/// that never moved.
struct PocketFaceStreamsTests {
    /// The supervisor publishes every product's execution in one value, so it
    /// re-sends whenever any worker starts or stops. Reopening on those would
    /// drop a live render and pay the connect retries again, for a worker this
    /// card's product never moved.
    @Test
    func doesNotReopenTheRenderWhenAnotherProductsWorkerMoves() async throws {
        let workers = StubWorkers()
        let execution = MockProductExecution()
        execution.keepsRenderStreamOpen = true
        let streams = makeStreams(workers: workers)

        let drawing = Task { for try await _ in streams.renderFaces(for: loyalty) {} }
        try await settle()

        workers.publish(["game.paseo": execution])
        try await settle()
        workers.publish(["game.paseo": execution, "shop.paseo": MockProductExecution()])
        try await settle()
        workers.publish(["game.paseo": execution])
        try await settle()
        drawing.cancel()

        #expect(execution.renderRequests.count == 1)
    }

    /// Looking a card up is a chain read. A card view re-runs its stream only
    /// when the card's identity changes, so a stream ended on a read that did
    /// not land leaves the card frozen on its cached face with nothing left to
    /// retry it.
    @Test
    func asksAgainWhenTheCardLookupDidNotLand() async throws {
        let published = StubPublishedCards()
        published.failures = [URLError(.notConnectedToInternet)]
        let workers = StubWorkers()
        let execution = MockProductExecution()
        workers.publish(["game.paseo": execution])

        execution.keepsRenderStreamOpen = true
        let streams = makeStreams(workers: workers, published: published)
        let drawing = Task { for try await _ in streams.renderFaces(for: loyalty) {} }

        try await waitUntil { published.lookups == 2 && !execution.renderRequests.isEmpty }
        drawing.cancel()

        #expect(published.lookups == 2)
        #expect(execution.renderRequests.count == 1)
    }

    /// A product that publishes no such card has nothing to draw, and the
    /// reference the stream would take is what boots a worker: asking again
    /// would keep one alive for a card that will never draw.
    @Test
    func stopsAskingWhenTheProductPublishesNoSuchCard() async throws {
        let published = StubPublishedCards()
        published.failures = [PocketPublishError.noPocket]
        let workers = StubWorkers()
        workers.publish(["game.paseo": MockProductExecution()])
        let references = StubWorkerReferences()

        let streams = makeStreams(workers: workers, published: published, references: references)
        for try await _ in streams.renderFaces(for: loyalty) {}

        #expect(published.lookups == 1)
        #expect(references.acquired.isEmpty)
    }
}

// MARK: - Fixtures

private let loyalty = PocketCardKey(productId: "game.paseo", cardId: PocketCardId(value: "loyalty"))

/// The streams hand their work to tasks, so the assertions wait for them rather
/// than for a fixed time.
private func settle() async throws {
    for _ in 0 ..< 20 {
        await Task.yield()
    }
    try await Task.sleep(for: .milliseconds(20))
}

/// Waits on what the streams did rather than on the clock: the retry between
/// two lookups is a wall-clock delay, and a fixed sleep either flakes under a
/// loaded machine or makes every run pay the worst case.
private func waitUntil(_ condition: () -> Bool) async throws {
    for _ in 0 ..< 60 {
        if condition() { return }
        try await Task.sleep(for: .milliseconds(100))
    }
}

private func makeStreams(
    workers: StubWorkers,
    published: StubPublishedCards = StubPublishedCards(),
    references: StubWorkerReferences = StubWorkerReferences()
) -> TrUAPIPocketFaceStreams {
    TrUAPIPocketFaceStreams(
        runtime: { references },
        workers: workers,
        publishedCards: published
    )
}

/// Publishes executions the way the supervisor does: one value carrying every
/// product, re-sent whenever any of them moves.
private final class StubWorkers: PocketWorkerSupervising, @unchecked Sendable {
    private let subject = AsyncCurrentValueSubject<[ProductId: TrUAPIProductExecutionProtocol]>([:])

    func publish(_ executions: [ProductId: TrUAPIProductExecutionProtocol]) {
        subject.send(executions)
    }

    func demandChanged(productId _: ProductId, transition _: WorkerTransition) {}

    func executions(of productId: ProductId) -> AnyAsyncSequence<TrUAPIProductExecutionProtocol?> {
        subject
            .map { $0[productId] }
            .eraseToAnyAsyncSequence()
    }

    func currentExecution(of productId: ProductId) -> TrUAPIProductExecutionProtocol? {
        subject.value[productId]
    }

    func shutdown() async {}
}

private final class StubPublishedCards: PublishedPocketCardsResolving, @unchecked Sendable {
    /// Errors thrown by successive lookups, consumed in order; once empty the
    /// lookup succeeds.
    var failures: [any Error] = []
    private(set) var lookups = 0

    func find(productId: ProductId, cardId: PocketCardId) async throws -> PublishedPocketCard {
        lookups += 1
        if !failures.isEmpty { throw failures.removeFirst() }

        return PublishedPocketCard(
            productId: productId,
            productName: productId,
            workerContentId: productId,
            definition: PocketCardDefinition(id: cardId, title: "Loyalty", preview: .archive(path: "face.json"))
        )
    }
}

private final class StubWorkerReferences: PocketWorkerReferencing, @unchecked Sendable {
    private(set) var acquired: [ProductId] = []

    func acquireWorker(productId: ProductId) {
        acquired.append(productId)
    }

    func releaseWorker(productId _: ProductId) {}
}
