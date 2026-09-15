import BigInt
import Foundation
import SubstrateSdk

/// Plans how to fulfill an external payment from available coins and vouchers.
public protocol ExternalPaymentPlanning {
    func plan(
        amount: Balance,
        context: DenominationBreakdownContext
    ) async throws -> ExternalPaymentPreview
}
