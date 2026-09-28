import Foundation
import Products
import TrUAPIHost

/// The worker reference a modality holder keeps for as long as it needs the
/// product's worker: a card on screen, a chat session while it is open. The
/// core counts these and starts or stops the worker on the transitions across
/// zero.
protocol TrUAPIWorkerReferencing: Sendable {
    func acquireWorker(productId: ProductId)

    func releaseWorker(productId: ProductId)
}

extension TrUAPIHostRuntime: TrUAPIWorkerReferencing {}
