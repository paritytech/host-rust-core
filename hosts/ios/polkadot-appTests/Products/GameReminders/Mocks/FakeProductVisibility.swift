import Foundation

@testable import polkadot_app

@MainActor
final class FakeProductVisibility: ProductVisibilityReporting {
    var current = ProductVisibility(productId: nil, isAppActive: true)
    func changes() -> AsyncStream<ProductVisibility> { AsyncStream { $0.finish() } }
}
