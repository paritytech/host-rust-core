import Foundation
import Products
@testable import polkadot_app

/// Resolves everything to the legacy shape unless a product is registered, which keeps SPA tests
/// on the base name exactly as they were before manifests existed.
final class StubProductResolver: ProductResolving, @unchecked Sendable {
    var products: [ProductId: ResolvedProduct] = [:]

    func resolve(_ productId: ProductId) async throws -> ResolvedProduct {
        products[productId] ?? .legacy(id: productId)
    }
}
