import Foundation
import Products

enum ProductPermissionRequesterFactory {
    static func create(router: ProductPermissionRouting) -> ProductPermissionRequesting {
        let requester = ProductPermissionRequester(router: router)
        return AutoAllowProductPermissionRequester(
            allowedLabels: ProductAutoAllowList.labels,
            wrapped: requester
        )
    }
}
