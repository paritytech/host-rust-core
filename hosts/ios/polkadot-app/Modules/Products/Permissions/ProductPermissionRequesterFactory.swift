import Foundation
import Products

enum ProductPermissionRequesterFactory {
    static func create(
        router: ProductPermissionRouting,
        fundingProvider: FundingDomainProviding
    ) -> ProductPermissionRequesting {
        let requester = ProductPermissionRequester(router: router)
        return AutoAllowProductPermissionRequester(
            allowedLabels: ProductAutoAllowList.labels(fundingProvider: fundingProvider),
            wrapped: requester
        )
    }
}
