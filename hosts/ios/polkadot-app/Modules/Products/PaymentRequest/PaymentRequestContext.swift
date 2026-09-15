import Foundation
import Products
import SubstrateSdk

final class PaymentRequestContext {
    let productId: ProductId
    let amountInPlanks: Balance
    let destination: AccountId

    private var continuation: CheckedContinuation<Void, Error>?

    init(productId: ProductId, amountInPlanks: Balance, destination: AccountId) {
        self.productId = productId
        self.amountInPlanks = amountInPlanks
        self.destination = destination
    }

    func setContinuation(_ continuation: CheckedContinuation<Void, Error>) {
        self.continuation = continuation
    }

    func deliverApproved() {
        continuation?.resume()
        continuation = nil
    }

    func deliverRejected() {
        continuation?.resume(throwing: PaymentRequestError.rejected)
        continuation = nil
    }
}

enum PaymentRequestError: Error, LocalizedError {
    case rejected
    case insufficientBalance
    case presentationFailed

    var errorDescription: String? {
        switch self {
        case .rejected:
            "payment rejected"
        case .insufficientBalance:
            "insufficient balance"
        case .presentationFailed:
            "Failed to present the payment request sheet"
        }
    }
}
