import Coinage
import Foundation
import Products
import SubstrateSdk
import UIKitExt

/// Presents the top-up request sheets. Resolves the bridge continuation with a
/// failure when no view is attached so JS never hangs.
extension ProductsRouting {
    func showTopUpError(context: TopUpRequestContext, error: Error) {
        let view = TopUpRequestViewFactory.createErrorView(context: context, error: error)

        if !present(view: view) {
            context.deliverFailed(error)
        }
    }

    func showTopUpMismatch(
        context: TopUpRequestContext,
        claimedAmount: Balance,
        requestedAmount: Balance
    ) {
        guard let view = TopUpRequestViewFactory.createMismatchView(
            context: context,
            claimedAmount: claimedAmount,
            requestedAmount: requestedAmount
        ) else {
            context.deliverFailed(PaymentTopUpError.partialPayment(amount: claimedAmount))
            return
        }

        if !present(view: view) {
            context.deliverFailed(PaymentTopUpError.partialPayment(amount: claimedAmount))
        }
    }
}

enum TopUpRequestRouterError: Error, LocalizedError {
    case presentationFailed

    var errorDescription: String? {
        switch self {
        case .presentationFailed:
            "Failed to present the top-up sheet"
        }
    }
}
