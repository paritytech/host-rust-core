import Foundation
import Products

enum ProductPermissionRequesterFactory {
    static func create(router: ProductPermissionRouting) -> ProductPermissionRequesting {
        #if FEATURE_PRODUCTS
            let allowedProducts: Set<String> = []
        #else
            let allowedProducts: Set<String> = [AppConfig.DotNs.dotNsGetSome]
        #endif

        let requester = ProductPermissionRequester(router: router)
        return AutoAllowProductPermissionRequester(
            allowedLabels: allowedProducts,
            wrapped: requester
        )
    }
}
