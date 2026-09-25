import Foundation
import Products
import Testing

@testable import polkadot_app

@Suite("AppPermissionsInteractor game reminder tests")
struct AppPermissionsGameReminderTests {
    private func makeInteractor(
        productId: ProductId,
        gameReminders: GameReminderScheduling
    ) -> AppPermissionsInteractor {
        let storageFacade = UserDataStorageTestFacade()

        return AppPermissionsInteractor(
            productId: productId,
            providerFactory: ProductPermissionDataProviderFactory(storageFacade: storageFacade),
            repository: ProductPermissionRepository(storageFacade: storageFacade),
            notificationScheduler: MockNotificationScheduler(),
            gameReminders: gameReminders
        )
    }

    @Test("revoking Alarm drops the product's game reminder")
    func revokeAlarmCancelsReminder() async {
        let reminders = MockGameReminderScheduling()
        let interactor = makeInteractor(productId: "jollity.dot", gameReminders: reminders)

        let cancelled = await withCheckedContinuation { continuation in
            reminders.onCancel = { continuation.resume(returning: $0) }
            interactor.revokeOnDisappear(permissions: [.deviceCapability(.alarm)])
        }

        #expect(cancelled == "jollity.dot")
    }

    @Test("revoking a non-alarm permission does not touch the game reminder")
    func revokeOtherPermissionLeavesReminderUntouched() async throws {
        let reminders = MockGameReminderScheduling()
        var cancelledCount = 0
        reminders.onCancel = { _ in cancelledCount += 1 }

        let interactor = makeInteractor(productId: "jollity.dot", gameReminders: reminders)
        interactor.revokeOnDisappear(permissions: [.deviceCapability(.camera)])

        try await Task.sleep(for: .milliseconds(50))

        #expect(cancelledCount == 0)
    }
}
