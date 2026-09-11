import AsyncExtensions
import Foundation
import SubstrateSdk
import BigInt

public struct PaymentBalance: Encodable {
    @StringCodable public var available: Balance

    public init(available: Balance) {
        self.available = available
    }
}

/// Payment status as seen by product scripts.
public enum HostPaymentStatus: Sendable, Equatable {
    case processing
    case completed
    case failed(reason: String)
}

/// Receipt returned to the product after initiating a payment.
public struct PaymentReceipt: Sendable {
    public let paymentId: String

    public init(paymentId: String) {
        self.paymentId = paymentId
    }
}
