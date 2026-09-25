import Foundation
import Testing
@testable import Products

struct TrustedProductPermissionGuardTests {
    private enum StorageError: Error { case unavailable }

    private static let permissions: [ProductPermission] = [
        .networkAccess(domain: "example.com"),
        .webRtcAccess,
        .chainSubmitAccess,
        .preimageSubmitAccess,
        .statementSubmitAccess,
        .accountAccess(targetProductId: "peopl.dot"),
        .balanceAccess,
        .userIdentityAccess
    ]

    private func makeGuard(
        repository: MockProductPermissionRepository,
        requester: MockProductPermissionRequester
    ) -> ProductPermissionGuard {
        ProductPermissionGuard(
            networkHandler: NetworkAccessPermissionHandler(repository: repository, requester: requester),
            remoteHandler: RemotePermissionHandler(repository: repository, requester: requester),
            deviceHandler: DeviceCapabilityPermissionHandler(
                repository: repository, requester: requester, osAsker: MockOSPermissionAsker()
            ),
            accountHandler: AccountAccessPermissionHandler(repository: repository, requester: requester),
            repository: repository,
            requester: requester,
            isTrustedProduct: { $0 == "dim2.dot" }
        )
    }

    @Test(arguments: [false, true])
    func trustedPermissionsIgnoreDenialsAndUnavailableStorage(storageUnavailable: Bool) async throws {
        let repository = MockProductPermissionRepository()
        let requester = MockProductPermissionRequester()
        requester.decision = .deny
        let guardService = makeGuard(repository: repository, requester: requester)
        for permission in Self.permissions {
            repository.stubState(productId: "dim2.dot", permission: permission, state: .denied)
        }
        if storageUnavailable { repository.readError = StorageError.unavailable }

        for permission in Self.permissions {
            let grants = try await [
                guardService.check(productId: "dim2.dot", permission: permission),
                guardService.requestPermission(productId: "dim2.dot", permission: permission),
                guardService.consumePermission(productId: "dim2.dot", permission: permission)
            ]
            #expect(grants == [true, true, true])
        }
        let granted = try await guardService.requestPermissionsBatched(
            productId: "dim2.dot", permissions: Self.permissions
        )
        let decision = try await guardService.requestPermissionsDecision(
            productId: "dim2.dot", permissions: Self.permissions
        )

        #expect(granted)
        #expect(decision == .allowAlways)
        #expect([repository.accessCount, requester.promptCalls.count, requester.promptBatchedCalls.count] == [0, 0, 0])
    }

    @Test(arguments: ["ordinary.dot", "app.dim2.dot", "dim2evil.dot"])
    func ordinaryProductsStillHonorStoredDenials(productId: String) async throws {
        let repository = MockProductPermissionRepository()
        let requester = MockProductPermissionRequester()
        let guardService = makeGuard(repository: repository, requester: requester)
        let permission = ProductPermission.networkAccess(domain: "example.com")
        repository.stubState(productId: productId, permission: permission, state: .denied)

        let grants = try await [
            guardService.check(productId: productId, permission: permission),
            guardService.requestPermission(productId: productId, permission: permission)
        ]

        #expect(grants == [false, false])
        #expect([repository.accessCount, requester.promptCalls.count] == [2, 0])
    }

    @Test
    func mixedBatchOnlyRequestsDeviceConsent() async throws {
        let repository = MockProductPermissionRepository()
        let requester = MockProductPermissionRequester()
        requester.decision = .deny
        let guardService = makeGuard(repository: repository, requester: requester)
        let permissions = Self.permissions + [.deviceCapability(.camera)]

        let decision = try await guardService.requestPermissionsDecision(
            productId: "dim2.dot", permissions: permissions
        )

        #expect(decision == .deny)
        #expect(requester.promptBatchedCalls.map(\.permissions) == [[.deviceCapability(.camera)]])
        #expect(repository.accessCount > 0)
        #expect(repository.grantCalls.isEmpty)
    }
}
