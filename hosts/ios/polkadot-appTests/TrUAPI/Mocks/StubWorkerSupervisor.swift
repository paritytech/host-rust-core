import Foundation
import os
import AsyncExtensions
import Products
import TrUAPIHost
@testable import polkadot_app

/// Publishes executions the way the supervisor does: one value carrying every
/// product, re-sent whenever any of them moves.
final class StubWorkerSupervisor: TrUAPIWorkerSupervising, @unchecked Sendable {
    private let subject = AsyncCurrentValueSubject<[ProductId: TrUAPIProductExecutionProtocol]>([:])
    private let openSeams = OSAllocatedUnfairLock<[ProductId: TrUAPIWorkerSeams]>(initialState: [:])

    private(set) var demands: [(productId: ProductId, transition: WorkerTransition)] = []

    func publish(_ executions: [ProductId: TrUAPIProductExecutionProtocol]) {
        subject.send(executions)
    }

    func demandChanged(productId: ProductId, transition: WorkerTransition) {
        demands.append((productId, transition))
    }

    func seams(of productId: ProductId) -> TrUAPIWorkerSeams {
        openSeams.withLock { open in
            if let seams = open[productId] { return seams }

            let seams = TrUAPIWorkerSeams()
            open[productId] = seams
            return seams
        }
    }

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

/// The references a modality holder takes, recorded rather than counted by the
/// core.
final class StubWorkerReferences: TrUAPIWorkerReferencing, @unchecked Sendable {
    private(set) var acquired: [ProductId] = []
    private(set) var released: [ProductId] = []

    func acquireWorker(productId: ProductId) {
        acquired.append(productId)
    }

    func releaseWorker(productId: ProductId) {
        released.append(productId)
    }
}
