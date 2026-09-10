import AsyncExtensions
import BigInt
import Foundation
import SubstrateSdk

/// Public interface for previewing, initiating and monitoring external payments.
public protocol ExternalPaymentServicing {
    func previewPayment(
        for amount: Balance,
        context: DenominationBreakdownContext
    ) async throws -> ExternalPaymentPreview

    func initiatePayment(
        origin: String,
        amountInPlanks: Balance,
        destination: AccountId
    ) async throws -> String

    func subscribePaymentStatus(paymentId: String) throws -> AnyAsyncSequence<ExternalPaymentStatus>

    func setup(with context: DenominationBreakdownContext)
    func throttle()
}

public enum ExternalPaymentStatus: Sendable, Equatable {
    case processing
    case completed
    case failed(reason: String)
}
