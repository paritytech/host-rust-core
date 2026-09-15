import Foundation
import Products
@testable import polkadot_app

final class MockPermissionGuard: ProductPermissionGuarding, @unchecked Sendable {
    var requestedPermission: ProductPermission?
    var requestedProductId: String?
    var requestedBatchedPermissions: [ProductPermission]?
    var verdictToReturn: Bool = true

    func requestPermission(productId: String, permission: ProductPermission) async throws -> Bool {
        requestedProductId = productId
        requestedPermission = permission
        return verdictToReturn
    }

    func requestPermissionsBatched(
        productId: String,
        permissions: [ProductPermission]
    ) async throws -> Bool {
        requestedProductId = productId
        requestedBatchedPermissions = permissions
        return verdictToReturn
    }

    func consumePermission(productId _: String, permission _: ProductPermission) async throws -> Bool {
        verdictToReturn
    }

    func check(productId _: String, permission _: ProductPermission) async throws -> Bool {
        verdictToReturn
    }
}
