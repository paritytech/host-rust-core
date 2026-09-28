import Foundation
import Testing
import UIKit
import Keystore_iOS
import PolkadotUI
@testable import polkadot_app

@MainActor
@Suite("Product game reminder center")
struct ProductGameReminderCenterTests {
    private let productId = "jollity.dot"
    private let startsAt = Date(timeIntervalSince1970: 2_000_000_000)

    private func makeSUT(
        now: Date,
        alarmAuthorized: Bool = true,
        settings: SettingsManagerProtocol = InMemorySettingsManager()
    ) -> (center: ProductGameReminderCenter, fakes: Fakes) {
        let fakes = Fakes(now: now)
        fakes.alarmAuthorized = alarmAuthorized
        let center = ProductGameReminderCenter(
            alarm: fakes.alarm,
            notification: fakes.notification,
            isAlarmAuthorized: { fakes.alarmAuthorized },
            settingsManager: settings,
            applicationState: { fakes.applicationState },
            openProduct: { fakes.opened.append($0) },
            now: { fakes.now }
        )
        center.start(widgets: fakes.widgets)
        return (center, fakes)
    }

    @Test("A schedule rings an alarm at the native lead time when AlarmKit is authorized")
    func scheduleRingsAlarm() {
        let (center, fakes) = makeSUT(now: startsAt.addingTimeInterval(-3600))

        center.schedule(productId: productId, startsAt: startsAt)

        #expect(center.slot == .init(productId: productId, startsAt: startsAt))
        #expect(fakes.alarm.scheduled == [.init(gameDate: startsAt, target: .product(productId), timingSeconds: 20)])
        #expect(fakes.notification.scheduled.isEmpty)
    }

    @Test("Without AlarmKit the reminder is a notification")
    func scheduleFallsBackToNotification() {
        let (center, fakes) = makeSUT(now: startsAt.addingTimeInterval(-3600), alarmAuthorized: false)

        center.schedule(productId: productId, startsAt: startsAt)

        #expect(fakes.alarm.scheduled.isEmpty)
        #expect(fakes.notification.scheduled == [.init(gameDate: startsAt, target: .product(productId), timingSeconds: 20)])
    }

    @Test("One slot: a repeat keeps the reminder, another product replaces it, only the holder cancels it")
    func oneSlotForAllProducts() {
        let (center, fakes) = makeSUT(now: startsAt.addingTimeInterval(-3600))

        center.schedule(productId: productId, startsAt: startsAt)
        center.schedule(productId: productId, startsAt: startsAt)
        #expect(fakes.alarm.cancelCount == 0)

        center.schedule(productId: "other.dot", startsAt: startsAt)
        #expect(fakes.alarm.scheduled.last == .init(gameDate: startsAt, target: .product("other.dot"), timingSeconds: 20))
        center.cancel(productId: productId)
        #expect(center.slot == .init(productId: "other.dot", startsAt: startsAt))
        #expect(fakes.alarm.cancelCount == 1)

        center.cancel(productId: "other.dot")
        #expect(center.slot == nil)
        #expect(fakes.alarm.cancelCount == 2)
        #expect(fakes.notification.cancelCount == 4)
    }

    @Test("Once AlarmKit is authorized, rescheduling the same slot drops its notification")
    func alarmReplacesNotification() {
        let (center, fakes) = makeSUT(now: startsAt.addingTimeInterval(-3600), alarmAuthorized: false)
        center.schedule(productId: productId, startsAt: startsAt)
        let notificationCancels = fakes.notification.cancelCount

        fakes.alarmAuthorized = true
        center.schedule(productId: productId, startsAt: startsAt)

        #expect(fakes.notification.cancelCount == notificationCancels + 1)
        #expect(fakes.alarm.scheduled == [.init(gameDate: startsAt, target: .product(productId), timingSeconds: 20)])
    }

    @Test("The countdown pill shows only in the last five minutes")
    func pillInLastFiveMinutes() {
        let (center, fakes) = makeSUT(now: startsAt.addingTimeInterval(-6 * 60))
        let pillID = ProductGameReminderCenter.pillID(for: productId)

        center.schedule(productId: productId, startsAt: startsAt)
        #expect(fakes.widgets.attached.isEmpty)

        fakes.now = startsAt.addingTimeInterval(-4 * 60)
        center.refresh()
        #expect(fakes.widgets.attached[pillID]?.content == .waiting(gameDate: startsAt))

        center.cancel(productId: productId)
        #expect(fakes.widgets.attached.isEmpty)
    }

    @Test("The pill is hidden while its product is mounted and shown again after")
    func pillHiddenWhileMounted() {
        let (center, fakes) = makeSUT(now: startsAt.addingTimeInterval(-60))
        let pillID = ProductGameReminderCenter.pillID(for: productId)
        center.schedule(productId: productId, startsAt: startsAt)
        #expect(fakes.widgets.attached[pillID] != nil)

        center.mountedProductId = productId
        #expect(fakes.widgets.attached.isEmpty)

        center.mountedProductId = "other.dot"
        #expect(fakes.widgets.attached[pillID] != nil)
    }

    @Test(
        "At the start the product opens while the app is in the foreground, and the slot is dropped",
        arguments: [UIApplication.State.active, .inactive]
    )
    func opensAtStart(state: UIApplication.State) {
        let (center, fakes) = makeSUT(now: startsAt.addingTimeInterval(-60))
        center.schedule(productId: productId, startsAt: startsAt)

        fakes.applicationState = state
        fakes.now = startsAt.addingTimeInterval(1)
        center.refresh()

        #expect(fakes.opened == [productId])
        #expect(center.slot == nil)
        #expect(fakes.widgets.attached.isEmpty)
    }

    @Test(
        "In the background at the start, or back long after it, nothing opens and the slot is dropped",
        arguments: [(UIApplication.State.background, 1.0), (.active, 600.0)]
    )
    func noOpenInBackgroundOrLate(state: UIApplication.State, secondsAfterStart: TimeInterval) {
        let (center, fakes) = makeSUT(now: startsAt.addingTimeInterval(-60))
        center.schedule(productId: productId, startsAt: startsAt)

        fakes.applicationState = state
        fakes.now = startsAt.addingTimeInterval(secondsAfterStart)
        center.refresh()

        #expect(fakes.opened.isEmpty)
        #expect(center.slot == nil)
    }

    @Test("The slot survives a relaunch and its pill comes back")
    func restoresAfterRelaunch() {
        let settings = InMemorySettingsManager()
        let (first, _) = makeSUT(now: startsAt.addingTimeInterval(-3600), settings: settings)
        first.schedule(productId: productId, startsAt: startsAt)

        let (relaunched, fakes) = makeSUT(now: startsAt.addingTimeInterval(-60), settings: settings)

        #expect(relaunched.slot == .init(productId: productId, startsAt: startsAt))
        #expect(fakes.widgets.attached[ProductGameReminderCenter.pillID(for: productId)] != nil)
    }
}

// MARK: - Fakes

private final class Fakes {
    var now: Date
    var applicationState: UIApplication.State = .active
    var alarmAuthorized = true
    var opened: [String] = []
    let alarm = RecordingGameReminder()
    let notification = RecordingGameReminder()
    let widgets = RecordingWidgets()

    init(now: Date) {
        self.now = now
    }
}

private final class RecordingGameReminder: GameStartReminderServicing {
    struct Call: Equatable {
        let gameDate: Date
        let target: GameReminderTarget
        let timingSeconds: Int
    }

    private(set) var scheduled: [Call] = []
    private(set) var cancelCount = 0

    func scheduleReminder(gameDate: Date, target: GameReminderTarget, timingSeconds: Int) {
        scheduled.append(Call(gameDate: gameDate, target: target, timingSeconds: timingSeconds))
    }

    func cancelReminder() {
        cancelCount += 1
    }
}

private final class RecordingWidgets: AppWidgetManaging {
    private(set) var attached: [AppWidgetID: GameRoomPillConfiguration] = [:]

    func attachWidget(_ configuration: any HashableContentConfiguration, for id: AppWidgetID) {
        attached[id] = configuration as? GameRoomPillConfiguration
    }

    func detachWidget(for id: AppWidgetID) {
        attached[id] = nil
    }
}
