import Foundation

/// Products that never see a permission or payment prompt. Builds without an Apps settings screen
/// cannot let the user review a grant, so the shipped funding product is allowlisted there.
enum ProductAutoAllowList {
    static var labels: Set<String> {
        #if FEATURE_PRODUCTS
            []
        #else
            [AppConfig.DotNs.dotNsGetSome]
        #endif
    }
}
