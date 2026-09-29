import Foundation
import Products

final class SPAFlowState {
    let dotNsResolver: DotNsResolverProtocol
    let hostProvider: ProductHostProviding
    let productResolver: ProductResolving
    let iconViewModelFactory: ProductIconViewModelMaking

    init(
        dotNsResolver: DotNsResolverProtocol,
        hostProvider: ProductHostProviding,
        productResolver: ProductResolving,
        iconViewModelFactory: ProductIconViewModelMaking
    ) {
        self.dotNsResolver = dotNsResolver
        self.hostProvider = hostProvider
        self.productResolver = productResolver
        self.iconViewModelFactory = iconViewModelFactory
    }
}
