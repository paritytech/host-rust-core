import Foundation
import KeyDerivation
import Products
import SubstrateSdk

final class TopUpRequestContext {
    enum Source {
        case wallet(any WalletManaging)
        case coins(secretKeys: [Data])
    }

    let productId: ProductId
    let amount: Balance
    let source: Source

    private var continuation: CheckedContinuation<Void, Error>?

    init(productId: ProductId, amount: Balance, source: Source) {
        self.productId = productId
        self.amount = amount
        self.source = source
    }

    func setContinuation(_ continuation: CheckedContinuation<Void, Error>) {
        self.continuation = continuation
    }

    func deliverClaimed() {
        continuation?.resume()
        continuation = nil
    }

    func deliverFailed(_ error: Error) {
        continuation?.resume(throwing: error)
        continuation = nil
    }
}
