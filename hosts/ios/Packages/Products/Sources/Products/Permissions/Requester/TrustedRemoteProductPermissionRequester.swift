import Foundation

/// Grants remote requests for trusted products and delegates other requests.
/// `ProductPermissionGuard` applies trusted policy before reading stored decisions.
public struct TrustedRemoteProductPermissionRequester: ProductPermissionRequesting {
    private let isTrustedForRemoteAccess: @Sendable (String) -> Bool
    private let wrapped: ProductPermissionRequesting

    public init(
        isTrustedForRemoteAccess: @escaping @Sendable (String) -> Bool,
        wrapped: ProductPermissionRequesting
    ) {
        self.isTrustedForRemoteAccess = isTrustedForRemoteAccess
        self.wrapped = wrapped
    }

    public func prompt(
        productId: String,
        permission: ProductPermission
    ) async -> PermissionDecision {
        guard !grantsWithoutPrompting(productId: productId, permissions: [permission]) else {
            return .allowAlways
        }

        return await wrapped.prompt(productId: productId, permission: permission)
    }

    public func promptBatched(
        productId: String,
        permissions: [ProductPermission]
    ) async -> PermissionDecision {
        guard !grantsWithoutPrompting(productId: productId, permissions: permissions) else {
            return .allowAlways
        }

        return await wrapped.promptBatched(productId: productId, permissions: permissions)
    }
}

private extension TrustedRemoteProductPermissionRequester {
    /// A batch is granted only when every permission in it is remote access.
    ///
    /// One decision answers the whole batch, so a batch mixing remote access
    /// with a device capability has to reach the user: granting it here would
    /// hand over the camera on the strength of a network grant. An empty batch
    /// asks for nothing and is not something to grant.
    func grantsWithoutPrompting(productId: String, permissions: [ProductPermission]) -> Bool {
        guard !permissions.isEmpty, permissions.allSatisfy(\.isRemoteAccess) else { return false }

        return isTrustedForRemoteAccess(productId)
    }
}
