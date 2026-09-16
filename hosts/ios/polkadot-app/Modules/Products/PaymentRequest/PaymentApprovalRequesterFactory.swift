import Foundation
import Products

enum PaymentApprovalRequesterFactory {
    static func create(router: ProductsRouting) -> PaymentApprovalRequesting {
        AutoAllowPaymentApprovalRequester(
            allowedLabels: ProductAutoAllowList.labels,
            wrapped: PaymentApprovalRequester(router: router)
        )
    }
}
